"""
FastAPI service exposing the CF recommender from
datasets_to_use/test_ml_recommendations.py to the Flutter app.

Endpoints:
  GET  /health                          → {"ok": true, "recipes": N, "users": M}
  POST /recommend                       → see RecommendRequest below

Run locally:
  pip install -r requirements.txt
  uvicorn server:app --host 0.0.0.0 --port 8000 --reload
"""
from __future__ import annotations

import ast
import os
import threading
from typing import List, Optional

import numpy as np
import pandas as pd
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.metrics.pairwise import cosine_similarity

# ── Paths ───────────────────────────────────────────────────────────
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
DATA_DIR = os.path.normpath(os.path.join(SCRIPT_DIR, "..", "datasets_to_use"))
RECIPES_PATH = os.path.join(DATA_DIR, "RAW_recipes_filtered.csv")
INTERACTIONS_PATH = os.path.join(DATA_DIR, "synthetic_interactions.csv")


class MLRecommender:
    """Direct port of MLRecommender from test_ml_recommendations.py."""

    def __init__(self) -> None:
        self.df_recipes: Optional[pd.DataFrame] = None
        self.df_interactions: Optional[pd.DataFrame] = None
        self.user_item_matrix: Optional[pd.DataFrame] = None
        self.tfidf_matrix = None
        self.recipe_id_to_idx: dict = {}
        self.user_profiles: dict = {}
        self.user_content_matrix: Optional[np.ndarray] = None
        self.synthetic_user_by_profile: dict = {}

    def load(self) -> None:
        self.df_recipes = pd.read_csv(RECIPES_PATH)
        self.df_interactions = pd.read_csv(INTERACTIONS_PATH)

        self.df_recipes["ingredients_list"] = self.df_recipes["ingredients"].apply(
            lambda x: ast.literal_eval(x) if isinstance(x, str) and x.startswith("[") else str(x).split(",")
        )
        self.df_recipes["ingredients_text"] = self.df_recipes["ingredients_list"].apply(
            lambda lst: " ".join(i.replace(" ", "_") for i in lst)
        )

        vectorizer = TfidfVectorizer(max_df=0.85, min_df=2)
        self.tfidf_matrix = vectorizer.fit_transform(self.df_recipes["ingredients_text"])
        self.recipe_id_to_idx = {rid: i for i, rid in enumerate(self.df_recipes["id"])}

        self.user_item_matrix = (
            self.df_interactions.pivot(index="user_id", columns="recipe_id", values="rating").fillna(0)
        )
        self._build_user_profiles()
        self._pick_synthetic_user_per_profile()

    def _build_user_profiles(self) -> None:
        feature_dim = self.tfidf_matrix.shape[1]
        rows = []
        for user_id in self.user_item_matrix.index.tolist():
            ratings = self.df_interactions[self.df_interactions["user_id"] == user_id]
            liked = ratings[ratings["rating"] >= 3.0]
            if liked.empty:
                vec = np.zeros(feature_dim)
            else:
                idxs = [self.recipe_id_to_idx[r] for r in liked["recipe_id"] if r in self.recipe_id_to_idx]
                if not idxs:
                    vec = np.zeros(feature_dim)
                else:
                    sub = self.tfidf_matrix[idxs].toarray()
                    weights = liked["rating"].values
                    if len(weights) == len(sub):
                        vec = np.average(sub, axis=0, weights=weights)
                    else:
                        vec = sub.mean(axis=0)
            self.user_profiles[user_id] = vec
            rows.append(vec)
        self.user_content_matrix = np.array(rows)

    def _pick_synthetic_user_per_profile(self) -> None:
        """Map each profile_tag → one representative synthetic user_id (the one
        whose tag-tagged interactions are richest). Used so the Flutter app can
        request 'recommend me as a meat_lover' without us actually owning a
        synthetic user account."""
        if "profile_tag" not in self.df_interactions.columns:
            return
        counts = (
            self.df_interactions.groupby(["profile_tag", "user_id"]).size().reset_index(name="n")
        )
        for tag, group in counts.groupby("profile_tag"):
            best = group.sort_values("n", ascending=False).iloc[0]
            self.synthetic_user_by_profile[str(tag).lower()] = int(best["user_id"])

    # ── Recommendation API ──────────────────────────────────────────

    def find_similar_users(self, profile_vec: np.ndarray, k: int = 20):
        sims = cosine_similarity(profile_vec.reshape(1, -1), self.user_content_matrix)[0]
        user_ids = self.user_item_matrix.index.tolist()
        ranked = sorted(zip(user_ids, sims), key=lambda x: x[1], reverse=True)
        return ranked[:k]

    def profile_vec_from_history(self, recipe_ids: List[int]) -> np.ndarray:
        """Build a TF-IDF profile vector from a list of liked recipe ids."""
        feature_dim = self.tfidf_matrix.shape[1]
        idxs = [self.recipe_id_to_idx[r] for r in recipe_ids if r in self.recipe_id_to_idx]
        if not idxs:
            return np.zeros(feature_dim)
        sub = self.tfidf_matrix[idxs].toarray()
        return sub.mean(axis=0)

    def recommend(
        self,
        profile_vec: np.ndarray,
        seen_recipe_ids: set,
        candidate_limit: int = 2000,
        top_n: int = 5,
    ):
        neighbors = self.find_similar_users(profile_vec, k=20)

        all_ids = set(self.recipe_ids)
        unseen = [r for r in (all_ids - seen_recipe_ids)][:candidate_limit]

        results = []
        for rid in unseen:
            if rid not in self.recipe_id_to_idx:
                continue
            r_idx = self.recipe_id_to_idx[rid]

            weighted = 0.0
            total_sim = 0.0
            if rid in self.user_item_matrix.columns:
                for u_id, sim in neighbors:
                    rating = self.user_item_matrix.loc[u_id, rid]
                    if rating > 0:
                        weighted += sim * rating
                        total_sim += sim
            pred = (weighted / total_sim) if total_sim > 0 else 2.5

            serendipity = 0.0
            if pred > 3.5:
                recipe_tfidf = self.tfidf_matrix[r_idx].toarray().flatten()
                significant = np.where(recipe_tfidf > 0.1)[0]
                if significant.size:
                    familiarity = float(np.mean(profile_vec[significant]))
                    if familiarity < 0.05:
                        serendipity = pred * (1.0 - familiarity)

            results.append((rid, float(pred), float(serendipity)))

        results.sort(key=lambda r: (r[1] + r[2]), reverse=True)
        top = results[:top_n]
        return [
            {
                "recipe_id": rid,
                "cf_score": round(score, 3),
                "serendipity": round(ser, 3),
                "name": str(self.df_recipes.loc[self.df_recipes["id"] == rid, "name"].values[0]),
            }
            for rid, score, ser in top
        ]

    @property
    def recipe_ids(self):
        return list(self.recipe_id_to_idx.keys())


# ── App & lazy loader ───────────────────────────────────────────────
app = FastAPI(title="Fridge CF Recommender", version="1.0.0")
_rec: Optional[MLRecommender] = None
_lock = threading.Lock()


def get_recommender() -> MLRecommender:
    global _rec
    if _rec is None:
        with _lock:
            if _rec is None:
                rec = MLRecommender()
                rec.load()
                _rec = rec
    return _rec


class RecommendRequest(BaseModel):
    profile_tag: Optional[str] = Field(
        None,
        description="Synthetic profile tag (meat_lover, vegetarian, pescatarian, sweet_tooth, healthy_eater, spicy_lover). Used to derive a starting profile vector when no consumption history is supplied.",
    )
    liked_recipe_ids: List[int] = Field(
        default_factory=list,
        description="DB recipe ids the user has liked / consumed. Builds a TF-IDF taste profile.",
    )
    exclude_recipe_ids: List[int] = Field(
        default_factory=list,
        description="Recipe ids to exclude (e.g. already shown).",
    )
    top_n: int = Field(5, ge=1, le=50)


class RecommendResponse(BaseModel):
    recipes: list


@app.get("/health")
def health():
    rec = get_recommender()
    return {
        "ok": True,
        "recipes": len(rec.recipe_ids),
        "users": int(rec.user_content_matrix.shape[0]) if rec.user_content_matrix is not None else 0,
        "profile_tags": sorted(rec.synthetic_user_by_profile.keys()),
    }


@app.post("/recommend", response_model=RecommendResponse)
def recommend(req: RecommendRequest):
    rec = get_recommender()

    # Build a profile vector. Priority: liked recipes > profile_tag > zero.
    if req.liked_recipe_ids:
        profile_vec = rec.profile_vec_from_history(req.liked_recipe_ids)
    elif req.profile_tag and req.profile_tag.lower() in rec.synthetic_user_by_profile:
        synth_uid = rec.synthetic_user_by_profile[req.profile_tag.lower()]
        profile_vec = rec.user_profiles[synth_uid]
    else:
        profile_vec = np.zeros(rec.tfidf_matrix.shape[1])

    if not np.any(profile_vec):
        raise HTTPException(
            status_code=400,
            detail="Cannot build a taste profile. Supply liked_recipe_ids or a known profile_tag.",
        )

    seen = set(req.exclude_recipe_ids) | set(req.liked_recipe_ids)
    recipes = rec.recommend(profile_vec=profile_vec, seen_recipe_ids=seen, top_n=req.top_n)
    return RecommendResponse(recipes=recipes)


if __name__ == "__main__":
    import uvicorn
    uvicorn.run("server:app", host="0.0.0.0", port=8000, reload=True)
