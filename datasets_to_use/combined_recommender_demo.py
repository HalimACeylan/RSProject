"""
Combined KB + CF recommendation demo over the shipped Flutter SQLite asset
(`assets/fridge_app.db`).

Two separate algorithms run on two separate user concepts and meet only at
presentation time:

  KB (Knowledge-Based, the main app recommender)
    user      : single real row from the `users` table
    inputs    : `users`, `fridge_items`, `consumption_logs`, `food_items`,
                `recipes` + `recipe_ingredients`
    algorithm : adaptive macro tracking + ingredient match + profile-weighted
                scoring (imported verbatim from test_kb_recommendations.py)

  CF (Collaborative Filtering, the optional cohort signal)
    user      : one synthetic user_id from `user_interactions` (training corpus only)
    inputs    : `user_interactions`, `recipes` + `recipe_ingredients`
    algorithm : TF-IDF over ingredients + cosine-similarity K-NN + serendipity
                (imported verbatim from test_ml_recommendations.py)

The synthetic CF users are NOT the real app user — they share an id space by
accident, but represent different humans. This demo never lets one's data leak
into the other's pipeline.

The KB and CF algorithm code is reused as-is via Python imports; the only new
code here is (a) sourcing data from SQLite instead of CSV/JSON and (b) verbose
[LOG] lines explaining every decision.

Usage (from repo root):
    python3 datasets_to_use/combined_recommender_demo.py
    python3 datasets_to_use/combined_recommender_demo.py --user 1 --cf-synth 1
"""

from __future__ import annotations

import argparse
import ast
import json
import os
import sqlite3
import sys
from datetime import datetime

import numpy as np
import pandas as pd

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.abspath(os.path.join(SCRIPT_DIR, os.pardir))
DEFAULT_DB_PATH = os.path.join(REPO_ROOT, "assets", "fridge_app.db")

# Reuse the verbatim KB + CF logic. These modules sit next to this file.
sys.path.insert(0, SCRIPT_DIR)
from test_kb_recommendations import (  # noqa: E402
    DV_REF,
    MEAL_PLANS,
    NUTR_KEYS,
    PROFILE_SCORING,
    DailyMealTracker,
    VirtualUser,
    recommend_5,
)
from test_ml_recommendations import MLRecommender  # noqa: E402


# ───────────────────────── helpers ─────────────────────────

def log(msg: str) -> None:
    """Print a decision-explaining log line. All explanatory output flows
    through here so it's easy to grep / silence later."""
    print(f"[LOG] {msg}")


def section(title: str) -> None:
    bar = "=" * 88
    print(f"\n{bar}\n  {title}\n{bar}")


def _parse_json_list(value) -> list[str]:
    """`users.dietary_restrictions` / `avoid_ingredients` are stored as JSON
    text. Empty / null comes through as None or '[]'."""
    if not value:
        return []
    try:
        parsed = json.loads(value)
        return [str(x).strip() for x in parsed] if isinstance(parsed, list) else []
    except (json.JSONDecodeError, TypeError):
        return []


# ───────────────────────── data loaders ─────────────────────────

DIET_PREFS = {"vegan", "vegetarian", "pescatarian"}


def load_real_user(con: sqlite3.Connection, user_id: int | None) -> VirtualUser:
    section("1. Loading real app user from `users` table")
    if user_id is None:
        row = con.execute("SELECT * FROM users ORDER BY id ASC LIMIT 1").fetchone()
        log("No --user flag provided → using the first row in `users` (lowest id).")
    else:
        row = con.execute("SELECT * FROM users WHERE id = ?", (user_id,)).fetchone()
        log(f"--user {user_id} → fetching that row from `users`.")

    if row is None:
        raise SystemExit(
            "No row found in `users`. Open the Flutter app once to complete onboarding, "
            "or pass --user N for an existing id."
        )

    u = dict(row)
    log(
        f"Real user: id={u['id']} profile_key={u['profile_key']} "
        f"age={u['age']} sex={u['sex']} weight={u['weight_kg']}kg height={u['height_cm']}cm"
    )
    log(
        f"  activity={u['activity_level']} meals_per_day={u['meals_per_day']} "
        f"daily_calories={u['daily_calories']}"
    )

    raw_restrictions = _parse_json_list(u["dietary_restrictions"])
    raw_avoid = _parse_json_list(u["avoid_ingredients"])
    log(f"  dietary_restrictions(raw)={raw_restrictions}  avoid_ingredients(raw)={raw_avoid}")

    # The schema stores diet preference (vegan/vegetarian/pescatarian) and
    # allergies mixed in the same `dietary_restrictions` column. Split them so
    # the KB algorithm (which expects them as separate fields on VirtualUser)
    # behaves correctly.
    diet_pref = ""
    allergies = []
    for token in raw_restrictions:
        t = token.lower()
        if t in DIET_PREFS:
            diet_pref = t
            log(f"  → '{token}' classified as diet_preference (KB will disqualify "
                f"recipes containing animal/meat ingredients)")
        else:
            allergies.append(t)
            log(f"  → '{token}' classified as allergy (KB will disqualify recipes "
                f"matching ALLERGY_GROUPS['{t}'])")
    if not allergies and not diet_pref:
        log("  → no allergies or diet preference detected")

    if raw_avoid:
        log(f"  avoid_ingredients={raw_avoid} (KB disqualifies recipes whose ingredients "
            f"substring-match any of these)")

    is_athlete = (u["profile_key"] == "athlete_bodybuilder") or (u["activity_level"] == "very_active")
    is_pregnant = u["profile_key"] == "pregnant_lactating"
    log(f"  derived flags: is_athlete={is_athlete} is_pregnant={is_pregnant} "
        f"(display-only, not used in scoring)")

    if u["profile_key"] not in PROFILE_SCORING:
        raise SystemExit(
            f"Unknown profile_key={u['profile_key']!r}. KB only knows about "
            f"{list(PROFILE_SCORING.keys())}."
        )
    log(f"  profile_key={u['profile_key']} → using PROFILE_SCORING['{u['profile_key']}'] "
        f"({PROFILE_SCORING[u['profile_key']]['description']})")

    vu = VirtualUser(
        name=f"user_{u['id']}",
        age=u["age"],
        gender=u["sex"],
        profile_key=u["profile_key"],
        daily_calories=u["daily_calories"],
        meals_per_day=u["meals_per_day"],
        is_athlete=is_athlete,
        is_pregnant=is_pregnant,
        diet_preference=diet_pref,
        allergies=allergies,
        avoid_ingredients=[a.lower() for a in raw_avoid],
    )

    log(f"  computed daily_limits (PDV %): " + ", ".join(
        f"{k}={v:.0f}" for k, v in vu.daily_limits.items()
    ))
    return vu


def load_fridge_into_user(con: sqlite3.Connection, vu: VirtualUser) -> None:
    section("2. Loading current fridge from `fridge_items` table")
    rows = con.execute(
        "SELECT name, category, amount, unit FROM fridge_items ORDER BY category, name"
    ).fetchall()
    if not rows:
        log("Fridge is empty → KB will fall back to partial matches only "
            "(every recipe will have 0% match ratio).")
        vu.fridge = []
        return

    log(f"Fridge has {len(rows)} items:")
    for r in rows:
        log(f"  - [{r['category'] or '—':<12}] {r['name']} ({r['amount']} {r['unit']})")

    # Lowercase to match the KB's substring matcher, which is case-sensitive.
    vu.fridge = [r["name"].lower() for r in rows]
    log("Fridge ingredients are lowercased to match KB's substring matcher "
        "(fridge_name in recipe_ing OR recipe_ing in fridge_name).")


def replay_consumption_logs(
    con: sqlite3.Connection, vu: VirtualUser, tracker: DailyMealTracker
) -> None:
    section("3. Replaying past consumption from `consumption_logs` into tracker")

    rows = con.execute(
        """
        SELECT cl.id, cl.item_name, cl.category, cl.amount, cl.unit, cl.is_from_fridge,
               cl.date,
               fi.calories, fi.protein, fi.carbs, fi.fat, fi.fiber, fi.sugars,
               fi.sodium, fi.cholesterol
        FROM consumption_logs cl
        LEFT JOIN food_items fi ON fi.name = cl.item_name
        ORDER BY cl.date ASC
        """
    ).fetchall()

    if not rows:
        log("No consumption_logs rows → tracker starts empty, all meals still "
            "open, full daily macro budget available.")
        return

    log(f"Found {len(rows)} consumption_log entries. Each is converted to a 7-element "
        "nutrient vector matching the recipe schema using DV_REF from "
        "who_daily_nutrient_guidelines.json:")
    log("  vector = [calories, fat%DV, sugar%DV, sodium%DV, protein%DV, satfat%DV, carbs%DV]")
    log("  (food_items has no saturated_fat column → satfat%DV is set to 0; "
        "this is a known data gap, not a logic change.)")

    fed = 0
    for r in rows:
        when = datetime.fromtimestamp(r["date"] / 1000).strftime("%Y-%m-%d %H:%M") if r["date"] else "?"
        amt = r["amount"] or 1.0  # `amount` is portion count; food_items values are per-portion

        if r["calories"] is None:
            log(f"  - {r['item_name']!r} (logged {when}): NOT FOUND in food_items → "
                "skipped (would otherwise count as 0 calories).")
            continue

        # Raw per-portion values (already 1 portion in food_items), scaled by `amount`.
        cal = (r["calories"] or 0) * amt
        fat_g = (r["fat"] or 0) * amt
        sugar_g = (r["sugars"] or 0) * amt
        sodium_mg = (r["sodium"] or 0) * amt
        protein_g = (r["protein"] or 0) * amt
        carbs_g = (r["carbs"] or 0) * amt

        # Convert to %DV using the same constants the KB uses for recipes.
        nutrition = [
            cal,
            fat_g / DV_REF["total_fat_g"] * 100,
            sugar_g / DV_REF["sugar_g"] * 100,
            sodium_mg / DV_REF["sodium_mg"] * 100,
            protein_g / DV_REF["protein_g"] * 100,
            0.0,  # saturated_fat_pdv — not in food_items
            carbs_g / DV_REF["carbs_g"] * 100,
        ]

        synthetic_recipe = {
            "name": f"[Logged] {r['item_name']}",
            "nutrition": nutrition,
            "ingredients": [],
            "tags": [],
        }
        # Charge this against the tracker as if it were a meal already consumed.
        # We label it under the user's first meal slot to keep the existing
        # tracker semantics (record_meal expects a meal name string).
        meal_name = MEAL_PLANS.get(vu.meals_per_day, ["Meal 1"])[0]
        tracker.record_meal(meal_name, synthetic_recipe)
        fed += 1
        log(
            f"  + {r['item_name']} (×{amt}) → "
            f"cal={cal:.0f} protein={protein_g:.1f}g({nutrition[4]:.0f}%DV) "
            f"sugar={sugar_g:.1f}g({nutrition[2]:.0f}%DV) sodium={sodium_mg:.0f}mg({nutrition[3]:.0f}%DV)"
        )

    log(f"Replayed {fed}/{len(rows)} log entries into the tracker.")
    log(f"After replay: meals_eaten={len(tracker.meals_eaten)} / {tracker.total_meals} planned")
    consumed_pct = {
        k: (tracker.consumed[k] / tracker.daily_limits[k] * 100) if tracker.daily_limits[k] > 0 else 0
        for k in NUTR_KEYS
    }
    log("  consumed so far (% of daily limit): " + ", ".join(
        f"{k.replace('_pdv','').replace('_',' ')}={consumed_pct[k]:.0f}%" for k in NUTR_KEYS
    ))


def load_recipes(con: sqlite3.Connection) -> list[dict]:
    section("4. Loading recipe pool (KB + CF share this table)")
    rows = con.execute(
        """
        SELECT r.id, r.name, r.nutrition, r.tags, r.minutes,
               GROUP_CONCAT(ri.name, '||') AS ings
        FROM recipes r
        LEFT JOIN recipe_ingredients ri ON ri.recipe_id = r.id
        GROUP BY r.id
        """
    ).fetchall()

    recipes = []
    skipped_nutr = 0
    skipped_no_ings = 0
    for r in rows:
        try:
            nutrition = ast.literal_eval(r["nutrition"]) if r["nutrition"] else None
        except (ValueError, SyntaxError):
            nutrition = None
        if not nutrition or len(nutrition) != 7:
            skipped_nutr += 1
            continue

        ings_raw = r["ings"]
        if not ings_raw:
            skipped_no_ings += 1
            continue
        ingredients = [x.lower().strip() for x in ings_raw.split("||") if x.strip()]

        try:
            tags = [x.lower().strip() for x in ast.literal_eval(r["tags"] or "[]")]
        except (ValueError, SyntaxError):
            tags = []

        recipes.append({
            "id": r["id"],
            "name": r["name"],
            "nutrition": nutrition,
            "ingredients": ingredients,
            "tags": tags,
            "minutes": r["minutes"] or 0,
        })

    log(f"Loaded {len(recipes)} usable recipes (joined recipes ⋈ recipe_ingredients).")
    if skipped_nutr:
        log(f"  Skipped {skipped_nutr} recipes with missing/malformed nutrition vector.")
    if skipped_no_ings:
        log(f"  Skipped {skipped_no_ings} recipes with no ingredients (KB needs them "
            "for substring match; CF needs them for TF-IDF).")
    return recipes


# ───────────────────────── KB driver ─────────────────────────

def run_kb_pipeline(vu: VirtualUser, recipes: list[dict], tracker: DailyMealTracker) -> list[dict]:
    section("5. KB recommendation pipeline (real user only)")
    meals = MEAL_PLANS.get(vu.meals_per_day, [f"Meal {i+1}" for i in range(vu.meals_per_day)])
    log(f"Meal plan template for meals_per_day={vu.meals_per_day}: {meals}")
    log(f"  meals already accounted for (from consumption_logs replay): {len(tracker.meals_eaten)}")
    log(f"  meals still to recommend: {vu.meals_per_day - len(tracker.meals_eaten)}")

    kb_picks = []
    start_idx = len(tracker.meals_eaten)
    for mi in range(start_idx, len(meals)):
        meal_name = meals[mi]
        n_remaining = tracker.meals_remaining
        adaptive = tracker.get_adaptive_meal_limits()
        deficits = tracker.get_deficits()

        print()
        log(f"--- {meal_name} ---")
        log(f"  meals_remaining={n_remaining} → adaptive per-meal limit = "
            "(daily_limit − already_consumed) / meals_remaining")
        log("  adaptive limits this meal: " + ", ".join(
            f"{k.replace('_pdv','')}={adaptive[k]:.0f}" for k in NUTR_KEYS
        ))
        if deficits:
            log("  deficits triggering bonuses this meal: " + ", ".join(
                f"{k}={v:+.1f}" for k, v in deficits.items()
            ))
        else:
            log("  no deficits yet (first scored meal of the day or fully on-pace).")

        top5 = recommend_5(vu, recipes, tracker)
        if not top5:
            log("  recommend_5 returned 0 candidates → likely too many disqualifications. "
                "Skipping meal.")
            continue

        full_count = sum(1 for r in top5 if r["match_ratio"] >= 0.8)
        partial_count = len(top5) - full_count
        log(f"  recommend_5 returned {len(top5)} picks: {full_count} full-match "
            f"(≥80% ingredients in fridge) + {partial_count} partial (30–80%).")
        log("  Slot policy: top-3 full + top-2 partial, ordered by (kb_score, match_ratio).")

        for j, r in enumerate(top5, 1):
            n = r["nutrition"]
            tag = "FULL" if r["match_ratio"] >= 0.8 else "PART"
            print(
                f"    {j}. [{tag}] score={r['score']:5.1f}  match={r['match_ratio']*100:3.0f}%  "
                f"cal={n[0]:.0f} prot%DV={n[4]:.0f}  {r['name'][:55]}"
            )
            if r["missing_ings"]:
                print(f"        missing: {', '.join(r['missing_ings'][:4])}")
            if r["reasons"]:
                # Show the top 4 scoring reasons (penalties/bonuses) so the user
                # sees WHY this score came out where it did.
                print(f"        reasons: {' | '.join(r['reasons'][:4])}")

        chosen = top5[0]
        log(f"  Chose #1 ({chosen['name'][:50]}) — highest score+match. "
            "Tracker is updated so the next meal's adaptive limits reflect this.")
        tracker.record_meal(meal_name, chosen)
        kb_picks.append({"meal": meal_name, "top5": top5, "chosen": chosen})

    section("6. KB day-end summary")
    consumed, limits, pct = tracker.summary()
    log("Final %DV vs daily limit: " + ", ".join(
        f"{k.replace('_pdv','')}={pct[k]:.0f}%" for k in NUTR_KEYS
    ))
    return kb_picks


# ───────────────────────── CF driver ─────────────────────────

class MLRecommenderFromDB(MLRecommender):
    """Subclasses the verbatim CF logic and swaps only the data loader. Every
    other method (prepare_matrices, build_user_profiles, find_similar_users,
    predict_rating_and_serendipity) is inherited unchanged."""

    def __init__(self, db_path: str):
        super().__init__()
        self.db_path = db_path

    def load_data(self):  # type: ignore[override]
        log(f"CF load_data: reading user_interactions + recipes from {self.db_path}")
        con = sqlite3.connect(self.db_path)
        try:
            self.df_recipes = pd.read_sql_query(
                """
                SELECT r.id, r.name,
                       GROUP_CONCAT(ri.name, '||') AS ingredients_joined
                FROM recipes r
                LEFT JOIN recipe_ingredients ri ON ri.recipe_id = r.id
                GROUP BY r.id, r.name
                """,
                con,
            )
            self.df_interactions = pd.read_sql_query(
                "SELECT user_id, recipe_id, rating, profile_tag FROM user_interactions",
                con,
            )
        finally:
            con.close()

        self.df_recipes["ingredients_list"] = self.df_recipes["ingredients_joined"].apply(
            lambda x: x.split("||") if isinstance(x, str) and x else []
        )
        self.df_recipes = self.df_recipes[
            self.df_recipes["ingredients_list"].map(len) > 0
        ].reset_index(drop=True)
        self.recipe_ids = self.df_recipes["id"].tolist()
        log(f"  CF corpus: {len(self.df_recipes)} recipes, "
            f"{self.df_interactions['user_id'].nunique()} synthetic users, "
            f"{len(self.df_interactions)} ratings")


def run_cf_pipeline(db_path: str, synthetic_user_id: int) -> pd.DataFrame:
    section("7. CF recommendation pipeline (synthetic training corpus only)")
    log("Important: the user_id below is a SYNTHETIC user from user_interactions, NOT "
        "the real app user. They share an id space by coincidence but represent "
        "different humans. CF and KB never mix users.")

    rec = MLRecommenderFromDB(db_path)
    rec.load_data()

    log("Step 1/3: TF-IDF over recipe ingredients (max_df=0.85, min_df=2). "
        "Multi-word ingredients are joined with '_' so they tokenize as one feature.")
    rec.prepare_matrices()
    log(f"  TF-IDF matrix shape: {rec.tfidf_matrix.shape} "
        f"(recipes × distinct ingredient tokens)")
    log(f"  user_item_matrix shape: {rec.user_item_matrix.shape} "
        f"(synthetic users × recipes they rated)")

    log("Step 2/3: build each synthetic user's taste vector as the weighted "
        "average TF-IDF of recipes they rated ≥ 3.0 (weight = their rating).")
    rec.build_user_profiles()

    profile_tag = rec.df_interactions[rec.df_interactions["user_id"] == synthetic_user_id][
        "profile_tag"
    ].iloc[0] if (rec.df_interactions["user_id"] == synthetic_user_id).any() else "?"
    log(f"Step 3/3: predict for synthetic user_id={synthetic_user_id} "
        f"(profile_tag={profile_tag!r}).")

    similar = rec.find_similar_users(synthetic_user_id, k=5)
    log(f"  Top-5 nearest synthetic neighbours by cosine similarity on taste vectors:")
    for u_id, sim in similar:
        log(f"    - user {u_id} (sim={sim:.3f})")

    all_r = set(rec.recipe_ids)
    seen = set(rec.df_interactions[rec.df_interactions["user_id"] == synthetic_user_id][
        "recipe_id"
    ].tolist())
    unseen = list(all_r - seen)[:1000]
    log(f"  Scoring {len(unseen)} unseen recipes (out of {len(all_r)} total — capped at 1000 "
        "to keep the demo fast, matching the original script).")
    preds = rec.predict_rating_and_serendipity(synthetic_user_id, unseen)

    top_cf = preds.sort_values("cf_score", ascending=False).head(5)
    print()
    log("CF top-5 (neighbours' weighted ratings):")
    for _, row in top_cf.iterrows():
        name = rec.df_recipes[rec.df_recipes["id"] == row["recipe_id"]]["name"].iloc[0]
        print(f"    cf={row['cf_score']:.2f}  {name[:70]}")

    top_serendipity = (
        preds[preds["serendipity_score"] > 0]
        .sort_values("serendipity_score", ascending=False)
        .head(5)
    )
    log("CF serendipity top-5 (neighbours loved it, but its key ingredients are "
        "absent from this synthetic user's taste vector — i.e. 'surprise me'):")
    for _, row in top_serendipity.iterrows():
        name = rec.df_recipes[rec.df_recipes["id"] == row["recipe_id"]]["name"].iloc[0]
        print(f"    s={row['serendipity_score']:.2f}  cf={row['cf_score']:.2f}  {name[:60]}")

    return preds


# ───────────────────────── combination ─────────────────────────

def combine(kb_picks: list[dict], cf_preds: pd.DataFrame) -> None:
    section("8. Combined view (no logic merge — presentation overlap only)")
    log("Per the constraint: KB and CF are kept independent. We DO NOT mix scores "
        "or feed one's output into the other's algorithm. The 'combination' below "
        "is purely a presentation overlay — which recipes appear in BOTH top lists.")

    if not kb_picks:
        log("KB produced no picks; nothing to overlay.")
        return

    kb_recipe_ids = {pick["chosen"]["id"] for pick in kb_picks} | {
        r["id"] for pick in kb_picks for r in pick["top5"]
    }
    log(f"KB surfaced {len(kb_recipe_ids)} distinct recipe ids across all meals.")

    cf_top = cf_preds.sort_values("cf_score", ascending=False).head(100)
    cf_set = set(cf_top["recipe_id"].tolist())
    log(f"CF top-100 (by cf_score) contains {len(cf_set)} recipe ids.")

    intersection = kb_recipe_ids & cf_set
    log(f"Intersection: {len(intersection)} recipes appear in BOTH lists.")
    if intersection:
        log("  → These are 'high-confidence' picks: the real user's KB profile and the "
            "synthetic cohort's CF signal independently agree.")
        for pick in kb_picks:
            for r in pick["top5"]:
                if r["id"] in intersection:
                    cf_row = cf_top[cf_top["recipe_id"] == r["id"]].iloc[0]
                    print(f"    - {r['name'][:60]:60} "
                          f"kb={r['score']:.0f} cf={cf_row['cf_score']:.2f} "
                          f"meal={pick['meal']}")
    else:
        log("  → No overlap. Expected when the real user and the chosen synthetic "
            "user have very different profiles (e.g. athlete_bodybuilder vs meat_lover).")


# ───────────────────────── main ─────────────────────────

def parse_args():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--db", default=DEFAULT_DB_PATH, help="Path to fridge_app.db")
    ap.add_argument("--user", type=int, default=None,
                    help="Real users.id (default: lowest id in `users`)")
    ap.add_argument("--cf-synth", type=int, default=1,
                    help="Synthetic user_id used for the CF demo (default: 1)")
    return ap.parse_args()


def main():
    args = parse_args()
    section("0. Opening database")
    log(f"DB path: {args.db}")
    if not os.path.exists(args.db):
        raise SystemExit(f"DB not found at {args.db}. Run `dart run scripts/build_db.dart` first.")

    con = sqlite3.connect(args.db)
    con.row_factory = sqlite3.Row
    log("Opened SQLite connection (read-only intent — this demo never writes).")

    try:
        vu = load_real_user(con, args.user)
        load_fridge_into_user(con, vu)

        tracker = DailyMealTracker(vu)
        log("Initialised DailyMealTracker with the user's profile-derived daily_limits.")
        replay_consumption_logs(con, vu, tracker)

        recipes = load_recipes(con)
    finally:
        con.close()

    kb_picks = run_kb_pipeline(vu, recipes, tracker)
    cf_preds = run_cf_pipeline(args.db, args.cf_synth)
    combine(kb_picks, cf_preds)

    print()
    log("Demo complete. KB pipeline ran on the real `users` row; CF pipeline ran on "
        "synthetic `user_interactions` data. They never shared a user identity.")


if __name__ == "__main__":
    main()
