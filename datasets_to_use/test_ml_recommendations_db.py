"""ML recommendation demo that pulls data from the shipped Flutter SQLite asset
(`assets/fridge_app.db`) instead of the raw CSV files.

Mirrors the algorithm in `test_ml_recommendations.py` so the results are the
same ones the Flutter app would see if it ran the same model against its
on-device database.

Usage (from repo root):
    python3 datasets_to_use/test_ml_recommendations_db.py [--user 1] [--db assets/fridge_app.db]
"""

import argparse
import os
import sqlite3

import numpy as np
import pandas as pd
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.metrics.pairwise import cosine_similarity

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.abspath(os.path.join(SCRIPT_DIR, os.pardir))
DEFAULT_DB_PATH = os.path.join(REPO_ROOT, "assets", "fridge_app.db")


class MLRecommenderDB:
    def __init__(self, db_path: str):
        self.db_path = db_path
        self.df_recipes = None
        self.df_interactions = None
        self.user_item_matrix = None
        self.tfidf_matrix = None
        self.vectorizer = None
        self.recipe_ids = []
        self.user_profiles = {}
        self.user_content_matrix = None

    def load_data(self):
        print(f"1. Veriler SQLite'tan yukleniyor: {self.db_path}")
        if not os.path.exists(self.db_path):
            raise FileNotFoundError(
                f"Database not found at {self.db_path}. "
                "Run `dart run scripts/build_db.dart` first."
            )

        conn = sqlite3.connect(self.db_path)
        try:
            # Recipes: reconstruct an ingredients list by joining recipe_ingredients
            recipes_sql = """
                SELECT r.id, r.name,
                       GROUP_CONCAT(ri.name, '||') AS ingredients_joined
                FROM recipes r
                LEFT JOIN recipe_ingredients ri ON ri.recipe_id = r.id
                GROUP BY r.id, r.name
            """
            self.df_recipes = pd.read_sql_query(recipes_sql, conn)

            interactions_sql = """
                SELECT user_id, recipe_id, rating, profile_tag
                FROM user_interactions
            """
            self.df_interactions = pd.read_sql_query(interactions_sql, conn)
        finally:
            conn.close()

        # Split the joined ingredients back into a list (same shape the CSV
        # version produced via ast.literal_eval).
        self.df_recipes["ingredients_list"] = self.df_recipes["ingredients_joined"].apply(
            lambda x: x.split("||") if isinstance(x, str) and x else []
        )
        # Drop recipes with no ingredients — they cannot contribute to TF-IDF.
        self.df_recipes = self.df_recipes[
            self.df_recipes["ingredients_list"].map(len) > 0
        ].reset_index(drop=True)

        self.recipe_ids = self.df_recipes["id"].tolist()
        print(
            f"   -> {len(self.df_recipes)} recipe, "
            f"{self.df_interactions['user_id'].nunique()} user, "
            f"{len(self.df_interactions)} interaction"
        )

    def prepare_matrices(self):
        print("2. Matrisler hazirlaniyor (TF-IDF & User-Item)...")

        # TF-IDF over the ingredient bag-of-words. Multi-word ingredients are
        # collapsed into a single token via underscore so the vectorizer treats
        # them as one feature.
        self.df_recipes["ingredients_text"] = self.df_recipes["ingredients_list"].apply(
            lambda x: " ".join(i.replace(" ", "_") for i in x)
        )

        self.vectorizer = TfidfVectorizer(max_df=0.85, min_df=2)
        self.tfidf_matrix = self.vectorizer.fit_transform(
            self.df_recipes["ingredients_text"]
        )

        self.user_item_matrix = self.df_interactions.pivot_table(
            index="user_id", columns="recipe_id", values="rating", aggfunc="mean"
        ).fillna(0)

    def build_user_profiles(self):
        print("3. Kullanicilarin Icerik Zevk Vektorleri hesaplaniyor...")
        recipe_id_to_idx = {
            r_id: idx for idx, r_id in enumerate(self.df_recipes["id"])
        }

        user_profiles_list = []
        user_ids = self.user_item_matrix.index.tolist()

        for user_id in user_ids:
            user_ratings = self.df_interactions[
                self.df_interactions["user_id"] == user_id
            ]
            liked_recipes = user_ratings[user_ratings["rating"] >= 3.0]

            if liked_recipes.empty:
                user_prof = np.zeros((1, self.tfidf_matrix.shape[1]))
            else:
                liked_idxs = [
                    recipe_id_to_idx[r_id]
                    for r_id in liked_recipes["recipe_id"]
                    if r_id in recipe_id_to_idx
                ]
                if liked_idxs:
                    liked_tfidf = self.tfidf_matrix[liked_idxs].toarray()
                    # Align weights with the rows we actually kept (some recipe
                    # ids in interactions may not exist in the recipes table).
                    aligned_weights = liked_recipes[
                        liked_recipes["recipe_id"].isin(recipe_id_to_idx)
                    ]["rating"].values
                    if len(aligned_weights) == len(liked_tfidf) and aligned_weights.sum() > 0:
                        user_prof = np.average(
                            liked_tfidf, axis=0, weights=aligned_weights
                        ).reshape(1, -1)
                    else:
                        user_prof = np.mean(liked_tfidf, axis=0).reshape(1, -1)
                else:
                    user_prof = np.zeros((1, self.tfidf_matrix.shape[1]))

            self.user_profiles[user_id] = user_prof.flatten()
            user_profiles_list.append(user_prof.flatten())

        self.user_content_matrix = np.array(user_profiles_list)

    def find_similar_users(self, target_user_id, k=10):
        if target_user_id not in self.user_profiles:
            return []

        target_profile = self.user_profiles[target_user_id].reshape(1, -1)
        similarities = cosine_similarity(target_profile, self.user_content_matrix)[0]

        user_ids = self.user_item_matrix.index.tolist()
        sim_scores = list(zip(user_ids, similarities))
        sim_scores = sorted(
            [s for s in sim_scores if s[0] != target_user_id],
            key=lambda x: x[1],
            reverse=True,
        )
        return sim_scores[:k]

    def predict_rating_and_serendipity(self, target_user_id, recipe_ids_to_predict):
        similar_users = self.find_similar_users(target_user_id, k=20)
        target_profile = self.user_profiles.get(
            target_user_id, np.zeros(self.tfidf_matrix.shape[1])
        )
        recipe_id_to_idx = {
            r_id: idx for idx, r_id in enumerate(self.df_recipes["id"])
        }

        predictions = []
        for r_id in recipe_ids_to_predict:
            if r_id not in recipe_id_to_idx:
                continue

            total_sim = 0.0
            weighted_rating = 0.0

            if r_id in self.user_item_matrix.columns:
                for sim_user_id, sim_score in similar_users:
                    rating = self.user_item_matrix.loc[sim_user_id, r_id]
                    if rating > 0:
                        weighted_rating += sim_score * rating
                        total_sim += sim_score

            pred_rating = (weighted_rating / total_sim) if total_sim > 0 else 2.5

            serendipity_score = 0.0
            if pred_rating > 3.5:
                r_idx = recipe_id_to_idx[r_id]
                recipe_tfidf = self.tfidf_matrix[r_idx].toarray().flatten()
                significant_features = np.where(recipe_tfidf > 0.1)[0]
                if len(significant_features) > 0:
                    user_familiarity = float(np.mean(target_profile[significant_features]))
                    if user_familiarity < 0.05:
                        serendipity_score = pred_rating * (1.0 - user_familiarity)

            predictions.append(
                {
                    "recipe_id": r_id,
                    "cf_score": pred_rating,
                    "serendipity_score": serendipity_score,
                }
            )

        return pd.DataFrame(predictions)


def _recipe_name(df_recipes, r_id):
    row = df_recipes[df_recipes["id"] == r_id]
    return row["name"].values[0] if not row.empty else f"<unknown:{r_id}>"


def _recipe_ings(df_recipes, r_id):
    row = df_recipes[df_recipes["id"] == r_id]
    return row["ingredients_list"].values[0] if not row.empty else []


def run_demo(db_path: str, target_user: int):
    rec = MLRecommenderDB(db_path)
    rec.load_data()
    rec.prepare_matrices()
    rec.build_user_profiles()

    if target_user not in rec.user_profiles:
        available = sorted(rec.user_profiles.keys())[:10]
        raise SystemExit(
            f"User {target_user} not found in DB. Sample available ids: {available}"
        )

    print(f"\nHEDEF KULLANICI: {target_user}")
    user_past = rec.df_interactions[
        (rec.df_interactions["user_id"] == target_user)
        & (rec.df_interactions["rating"] >= 4.0)
    ]
    liked_r_ids = user_past["recipe_id"].tolist()

    print("Bu kullanicinin gecmiste sevdigi bazi tariflerin icerikleri:")
    for r in liked_r_ids[:3]:
        ings = _recipe_ings(rec.df_recipes, r)
        print(f"  - {_recipe_name(rec.df_recipes, r)} | Malzemeler: {', '.join(ings[:4])}...")

    print("\nK-NN (Benzer Kullanicilar) araniyor...")
    for u_id, sim in rec.find_similar_users(target_user, k=5):
        neighbor_liked = rec.df_interactions[
            (rec.df_interactions["user_id"] == u_id)
            & (rec.df_interactions["rating"] == 5)
        ]
        n_rec = "-"
        if not neighbor_liked.empty:
            n_rec = _recipe_name(rec.df_recipes, neighbor_liked.iloc[0]["recipe_id"])
        print(f"  > Kullanici {u_id} (Benzerlik: {sim:.2f}) -> Orn sevdigi: {n_rec[:30]}")

    print("\nPuan tahmini (Prediction) ve surpriz (Serendipity) hesaplaniyor...")
    all_r_ids = set(rec.recipe_ids)
    past_r_ids = set(
        rec.df_interactions[rec.df_interactions["user_id"] == target_user][
            "recipe_id"
        ].tolist()
    )
    unseen_r_ids = list(all_r_ids - past_r_ids)[:1000]

    preds_df = rec.predict_rating_and_serendipity(target_user, unseen_r_ids)

    print("\n[Normal CF] Komsularin en cok sevdigi 3 tarif:")
    for _, row in preds_df.sort_values("cf_score", ascending=False).head(3).iterrows():
        name = _recipe_name(rec.df_recipes, row["recipe_id"])
        print(f"  - {name[:40]:<40} | Tahmini Puan: {row['cf_score']:.2f}")

    print("\n[Serendipity] Kullanicinin hic denemedigi ama komsularin sevdigi 3 surpriz tarif:")
    top_serendipity = (
        preds_df[preds_df["serendipity_score"] > 0]
        .sort_values("serendipity_score", ascending=False)
        .head(3)
    )
    for _, row in top_serendipity.iterrows():
        name = _recipe_name(rec.df_recipes, row["recipe_id"])
        ings = _recipe_ings(rec.df_recipes, row["recipe_id"])
        print(
            f"  - {name[:40]:<40} | Surpriz Skoru: {row['serendipity_score']:.2f} "
            f"| Yabanci Malzemeler: {', '.join(ings[:4])}..."
        )


def parse_args():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--db", default=DEFAULT_DB_PATH, help="Path to fridge_app.db")
    ap.add_argument("--user", type=int, default=1, help="Target user_id")
    return ap.parse_args()


if __name__ == "__main__":
    args = parse_args()
    run_demo(args.db, args.user)
