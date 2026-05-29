"""
Quick inspector for the live app DB (assets/fridge_app.db).

Run while the Flutter app is using the same file (start the app with
`--dart-define=DB_FILE=$(pwd)/assets/fridge_app.db` from the repo root, then
this script can read everything the user has done).

Usage:
    python3 datasets_to_use/inspect_app_state.py
    python3 datasets_to_use/inspect_app_state.py --recs   # also rank top KB recipes for the saved user

Notes:
- SQLite reads are safe to do concurrently with the app, but try not to write
  from two processes at once.
- The KB ranking here is a small Python port of the same algorithm in
  test_kb_recommendations.py, narrowed to the columns the app stores.
"""
from __future__ import annotations

import argparse
import json
import os
import sqlite3
import sys
from datetime import datetime
from typing import Any

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
DB_PATH = os.path.normpath(os.path.join(SCRIPT_DIR, "..", "assets", "fridge_app.db"))


def _open() -> sqlite3.Connection:
    if not os.path.exists(DB_PATH):
        sys.exit(f"DB not found at {DB_PATH}. Did you rebuild it via `dart run scripts/build_db.dart`?")
    # mode=ro guarantees no writes from this process; the app enables WAL so
    # this open never blocks even if a fridge add is mid-flight. The 5 s
    # busy_timeout is belt-and-suspenders for the brief window before WAL is
    # negotiated on the very first run.
    con = sqlite3.connect(f"file:{DB_PATH}?mode=ro", uri=True, timeout=5.0)
    con.row_factory = sqlite3.Row
    con.execute("PRAGMA busy_timeout = 5000")
    return con


def _ms_to_str(ms: int | None) -> str:
    if ms is None:
        return "—"
    return datetime.fromtimestamp(ms / 1000).strftime("%Y-%m-%d %H:%M")


def print_user_profile(con: sqlite3.Connection) -> dict[str, Any] | None:
    rows = list(con.execute("SELECT * FROM users ORDER BY id ASC LIMIT 1"))
    if not rows:
        print("USER PROFILE: (none — first launch not completed)\n")
        return None
    u = dict(rows[0])
    print("USER PROFILE")
    print(f"  profile_key       : {u['profile_key']}")
    print(f"  age / sex         : {u['age']} / {u['sex']}")
    print(f"  restrictions      : {u['dietary_restrictions']}")
    print(f"  avoid_ingredients : {u['avoid_ingredients']}")
    print(f"  created_at        : {_ms_to_str(u['created_at'])}\n")
    return u


def print_fridge(con: sqlite3.Connection) -> list[str]:
    rows = list(con.execute(
        "SELECT id, name, category, amount, unit, expiry_date, added_date "
        "FROM fridge_items ORDER BY category, name"
    ))
    print(f"FRIDGE ({len(rows)} items)")
    if not rows:
        print("  (empty)\n")
        return []
    by_cat: dict[str, list[sqlite3.Row]] = {}
    for r in rows:
        by_cat.setdefault(r["category"] or "—", []).append(r)
    for cat, items in by_cat.items():
        print(f"  [{cat}]")
        for r in items:
            exp = _ms_to_str(r["expiry_date"])
            print(f"    - {r['name']:<28} {r['amount']:>6} {r['unit']:<8} exp:{exp}")
    print()
    return [r["name"].lower() for r in rows]


def print_cooked(con: sqlite3.Connection, days: int = 14) -> None:
    try:
        cutoff_ms = int((datetime.now().timestamp() - days * 86400) * 1000)
        rows = list(con.execute(
            "SELECT recipe_id, recipe_name, cooked_at FROM cooked_recipes "
            "WHERE cooked_at >= ? ORDER BY cooked_at DESC", (cutoff_ms,),
        ))
    except sqlite3.OperationalError:
        # Table may not exist on an older DB; silently skip.
        return
    print(f"COOKED RECIPES (last {days} days, {len(rows)} entries)")
    if not rows:
        print("  (none)\n")
        return
    for r in rows:
        print(f"  {_ms_to_str(r['cooked_at'])}  #{r['recipe_id']:<8} {r['recipe_name']}")
    print()


def print_consumption(con: sqlite3.Connection, days: int = 7) -> None:
    cutoff_ms = int((datetime.now().timestamp() - days * 86400) * 1000)
    rows = list(con.execute(
        "SELECT item_name, category, amount, unit, is_from_fridge, date "
        "FROM consumption_logs WHERE date >= ? ORDER BY date DESC", (cutoff_ms,),
    ))
    print(f"CONSUMPTION (last {days} days, {len(rows)} entries)")
    if not rows:
        print("  (empty)\n")
        return
    for r in rows:
        src = "fridge" if r["is_from_fridge"] else "external"
        print(f"  {_ms_to_str(r['date'])}  {r['item_name']:<24} {r['amount']:>5} {r['unit']:<6} ({src})")
    print()


# ── KB scoring (slim port of test_kb_recommendations.py) ─────────────────

GUIDE_PATH = os.path.join(SCRIPT_DIR, "who_daily_nutrient_guidelines.json")
with open(GUIDE_PATH) as f:
    GUIDE = json.load(f)
DV_REF = GUIDE["engine_constants"]["dv_references"]
PROFILES = GUIDE["recommendation_profiles"]
NUTR_KEYS = [
    "calories", "total_fat_pdv", "sugar_pdv", "sodium_pdv",
    "protein_pdv", "saturated_fat_pdv", "carbs_pdv",
]


# Per-profile defaults (mirror UserProfile.dailyCalories / mealsPerDay in
# lib/models/user_profile.dart so the Python KB ranks against the same numbers
# the app uses).
_DEFAULT_KCAL = {
    ("athlete_bodybuilder", "M"): 3000, ("athlete_bodybuilder", "F"): 2500,
    ("adolescent", "M"): 2800,         ("adolescent", "F"): 2200,
    ("pregnant_lactating", "M"): 2300, ("pregnant_lactating", "F"): 2300,
    ("general_adult", "M"): 2400,      ("general_adult", "F"): 2000,
}
_DEFAULT_MEALS = {
    "athlete_bodybuilder": 5, "pregnant_lactating": 5,
    "adolescent": 4,          "general_adult": 3,
}


def _daily_calories(user: dict[str, Any]) -> int:
    return _DEFAULT_KCAL.get((user["profile_key"], user["sex"]), 2200)


def _meals_per_day(user: dict[str, Any]) -> int:
    return _DEFAULT_MEALS.get(user["profile_key"], 3)


def _daily_limits(user: dict[str, Any]) -> dict[str, float]:
    rules = PROFILES[user["profile_key"]]["macronutrient_rules"]
    e = float(_daily_calories(user))
    return {
        "calories": e,
        "total_fat_pdv": (e * rules["fat_pct_max"] / 100 / 9) / DV_REF["total_fat_g"] * 100,
        "sugar_pdv": (e * rules["sugar_pct_max"] / 100 / 4) / DV_REF["sugar_g"] * 100,
        "sodium_pdv": rules["sodium_max_mg"] / DV_REF["sodium_mg"] * 100,
        "protein_pdv": (e * rules["protein_pct_min"] / 100 / 4) / DV_REF["protein_g"] * 100,
        "saturated_fat_pdv": (e * rules["sat_fat_pct_max"] / 100 / 9) / DV_REF["saturated_fat_g"] * 100,
        "carbs_pdv": (e * rules["carbs_pct_max"] / 100 / 4) / DV_REF["carbs_g"] * 100,
    }


def _ingredient_match(fridge: list[str], ings: list[str]) -> tuple[float, list[str], list[str]]:
    if not ings:
        return 0.0, [], []
    matched, missing = [], []
    for ing in ings:
        if any(f in ing or ing in f for f in fridge):
            matched.append(ing)
        else:
            missing.append(ing)
    return len(matched) / len(ings), matched, missing


def print_kb_top(con: sqlite3.Connection, user: dict[str, Any], fridge: list[str], limit: int = 5) -> None:
    print(f"KB TOP {limit} (mirroring app's KbRecommenderService)")
    limits = _daily_limits(user)
    recipes = list(con.execute("SELECT id, name, nutrition FROM recipes"))
    print(f"  scanning {len(recipes)} recipes against fridge ({len(fridge)} items)...")

    ings_by_recipe: dict[int, list[str]] = {}
    for r in con.execute("SELECT recipe_id, name FROM recipe_ingredients"):
        ings_by_recipe.setdefault(r["recipe_id"], []).append((r["name"] or "").lower())

    full, partial = [], []
    for r in recipes:
        rid = r["id"]
        ings = ings_by_recipe.get(rid, [])
        if not ings:
            continue
        try:
            nutr = [float(x) for x in r["nutrition"].strip("[]").split(",")]
        except Exception:
            continue
        if len(nutr) < 7:
            continue

        score = 100.0
        for key, idx, base in [
            ("calories", 0, 25), ("total_fat_pdv", 1, 20), ("sugar_pdv", 2, 20),
            ("sodium_pdv", 3, 15), ("saturated_fat_pdv", 5, 15), ("carbs_pdv", 6, 10),
        ]:
            lim = limits[key] / max(1, _meals_per_day(user))
            if lim > 0 and nutr[idx] > lim:
                score -= min(base, (nutr[idx] - lim) / lim * base * 2)
        pl = limits["protein_pdv"] / max(1, _meals_per_day(user))
        if nutr[4] < pl and pl > 0:
            score -= min(15, (pl - nutr[4]) / pl * 30)
        score = max(0.0, min(130.0, score))

        ratio, matched, missing = _ingredient_match(fridge, ings)
        entry = (score, ratio, r["name"], matched, missing)
        if ratio >= 0.8:
            full.append(entry)
        elif ratio >= 0.3:
            partial.append(entry)

    full.sort(key=lambda x: (x[0], x[1]), reverse=True)
    partial.sort(key=lambda x: (x[0], x[1]), reverse=True)
    picks = full[:3] + partial[: max(0, limit - min(3, len(full)))]
    picks = picks[:limit]

    if not picks:
        print("  No matches (try adding common ingredients to the fridge).\n")
        return
    for i, (score, ratio, name, matched, missing) in enumerate(picks, 1):
        tag = "FULL " if ratio >= 0.8 else "PART "
        miss = ", ".join(missing[:3]) if missing else "—"
        print(f"  {i}. [{tag}] {score:5.1f}p  match {ratio * 100:3.0f}%  {name[:46]:<46}  miss: {miss}")
    print()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--recs", action="store_true",
                        help="Also rank top-5 KB recipes for the saved user.")
    parser.add_argument("--days", type=int, default=7, help="Days of consumption history to show (default 7).")
    args = parser.parse_args()

    con = _open()
    print(f"DB: {DB_PATH}\n")
    user = print_user_profile(con)
    fridge = print_fridge(con)
    print_cooked(con, days=args.days)
    print_consumption(con, days=args.days)
    if args.recs:
        if user is None:
            print("Cannot rank recipes — no user profile saved.\n")
        else:
            print_kb_top(con, user, fridge)
    con.close()


if __name__ == "__main__":
    main()
