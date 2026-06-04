"""
Combined KB + CF recommendation demo over the shipped Flutter SQLite asset
(`assets/fridge_app.db`).

Output style matches `test_kb_recommendations.py` and `test_ml_recommendations.py`
(Turkish headers, emojis, `━`/`─` separators). All algorithm code is imported
verbatim from those two files; this driver only:
  - swaps data sources (CSV/JSON → SQLite),
  - feeds `consumption_logs` into the existing tracker,
  - presents both pipelines back-to-back.

Recipes are loaded via `test_kb_recommendations.load_recipes()` — that function
now reads from the SQLite asset itself (ORDER BY id ASC, bulk ingredient join,
falls back to CSV only if the DB file is missing), producing the same dict
shape the KB scorer expects. We import it instead of reimplementing it here.

Shared infrastructure with `inspect_app_state.py` (imported, not duplicated):
  - `_open()`            : read-only `mode=ro` SQLite connection with
                           WAL-safe busy_timeout
  - `_DEFAULT_KCAL`,
    `_DEFAULT_MEALS`     : per-profile defaults mirroring UserProfile in
                           lib/models/user_profile.dart
  - `_ingredient_match`  : loose bidirectional substring matcher — verbatim
                           port of `test_kb_recommendations.calc_ingredient_match`,
                           which itself mirrors `KbRecommenderService.ingredientMatch`
                           in lib/services/kb_recommender_service.dart. We
                           monkey-patch it into test_kb_recommendations so
                           the inspector remains the single source of truth
                           for matching, even though the two implementations
                           are currently equivalent.

The synthetic users in `user_interactions` are training corpus for CF only; the
real `users` row drives KB. They never mix.

Usage (from repo root):
    python3 datasets_to_use/combined_recommender_demo.py
    python3 datasets_to_use/combined_recommender_demo.py --user 1 --cf-synth 1
"""

from __future__ import annotations

import argparse
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

sys.path.insert(0, SCRIPT_DIR)
import test_kb_recommendations  # noqa: E402
from test_kb_recommendations import (  # noqa: E402
    DV_REF,
    MEAL_PLANS,
    NUTR_KEYS,
    PROFILE_SCORING,
    DailyMealTracker,
    VirtualUser,
    load_recipes,
    recommend_5,
)
from test_ml_recommendations import MLRecommender  # noqa: E402
import inspect_app_state  # noqa: E402
from inspect_app_state import (  # noqa: E402
    _DEFAULT_KCAL,
    _DEFAULT_MEALS,
    _ingredient_match,
    _open,
)

# Route test_kb_recommendations.calc_ingredient_match through the inspector's
# `_ingredient_match`. Both are currently loose bidirectional substring matchers
# (the inspector says it mirrors `KbRecommenderService.ingredientMatch` in
# lib/services/kb_recommender_service.dart), so this assignment is a no-op
# today. We keep it so the inspector remains the single source of truth — if
# its matcher gains plural/token rules later, recommend_5 will follow without
# any change to its body (it resolves calc_ingredient_match in module globals
# at call time).
test_kb_recommendations.calc_ingredient_match = _ingredient_match


# ───────────────────────── helpers ─────────────────────────

DIET_PREFS = {"vegan", "vegetarian", "pescatarian"}


def _parse_json_list(value) -> list[str]:
    if not value:
        return []
    try:
        parsed = json.loads(value)
        return [str(x).strip() for x in parsed] if isinstance(parsed, list) else []
    except (json.JSONDecodeError, TypeError):
        return []


# ───────────────────────── data loaders ─────────────────────────

def load_real_user(con: sqlite3.Connection, user_id: int | None) -> VirtualUser:
    if user_id is None:
        row = con.execute("SELECT * FROM users ORDER BY id ASC LIMIT 1").fetchone()
    else:
        row = con.execute("SELECT * FROM users WHERE id = ?", (user_id,)).fetchone()
    if row is None:
        raise SystemExit("👤 `users` tablosu boş veya verilen id bulunamadı.")

    u = dict(row)
    raw_restrictions = _parse_json_list(u["dietary_restrictions"])
    raw_avoid = _parse_json_list(u["avoid_ingredients"])

    diet_pref = ""
    allergies = []
    for token in raw_restrictions:
        t = token.lower()
        if t in DIET_PREFS:
            diet_pref = t
        else:
            allergies.append(t)

    is_athlete = u["profile_key"] == "athlete_bodybuilder"
    is_pregnant = u["profile_key"] == "pregnant_lactating"

    if u["profile_key"] not in PROFILE_SCORING:
        raise SystemExit(
            f"❌ Bilinmeyen profile_key={u['profile_key']!r}. "
            f"Mevcut profiller: {list(PROFILE_SCORING.keys())}"
        )

    daily_cal = _DEFAULT_KCAL.get((u["profile_key"], u["sex"]), 2200)
    meals = _DEFAULT_MEALS.get(u["profile_key"], 3)

    vu = VirtualUser(
        name=f"user_{u['id']}",
        age=u["age"],
        gender=u["sex"],
        profile_key=u["profile_key"],
        daily_calories=daily_cal,
        meals_per_day=meals,
        is_athlete=is_athlete,
        is_pregnant=is_pregnant,
        diet_preference=diet_pref,
        allergies=allergies,
        avoid_ingredients=[a.lower() for a in raw_avoid],
    )
    vu._db_id = u["id"]  # type: ignore[attr-defined]
    vu._defaults_used = True  # type: ignore[attr-defined]
    return vu


def load_fridge_into_user(con: sqlite3.Connection, vu: VirtualUser) -> list[sqlite3.Row]:
    rows = con.execute(
        "SELECT name, category, amount, unit FROM fridge_items ORDER BY category, name"
    ).fetchall()
    vu.fridge = [r["name"].lower() for r in rows]
    return rows


def replay_consumption_logs(
    con: sqlite3.Connection, vu: VirtualUser, tracker: DailyMealTracker
) -> int:
    rows = con.execute(
        """
        SELECT cl.id, cl.item_name, cl.category, cl.amount, cl.unit, cl.is_from_fridge, cl.date,
               fi.calories, fi.protein, fi.carbs, fi.fat, fi.sugars, fi.sodium
        FROM consumption_logs cl
        LEFT JOIN food_items fi ON fi.name = cl.item_name
        ORDER BY cl.date ASC
        """
    ).fetchall()

    if not rows:
        print("   📭 consumption_logs boş — tracker temiz başlıyor, tüm günlük bütçe açık.")
        return 0

    print(f"   📋 {len(rows)} adet geçmiş tüketim kaydı bulundu.")
    print("       Her kayıt food_items'tan eşleştirilip DV_REF ile %DV vektörüne çevriliyor.")
    print("       (food_items'ta saturated_fat sütunu olmadığı için satfat%DV=0 alınır.)")

    fed = 0
    meal_name = MEAL_PLANS.get(vu.meals_per_day, ["Öğün 1"])[0]
    for r in rows:
        when = datetime.fromtimestamp(r["date"] / 1000).strftime("%Y-%m-%d %H:%M") if r["date"] else "?"
        if r["calories"] is None:
            print(f"       ⚠️  {r['item_name']!r} food_items'ta bulunamadı, atlanıyor.")
            continue
        amt = r["amount"] or 1.0
        cal = (r["calories"] or 0) * amt
        fat_g = (r["fat"] or 0) * amt
        sugar_g = (r["sugars"] or 0) * amt
        sodium_mg = (r["sodium"] or 0) * amt
        protein_g = (r["protein"] or 0) * amt
        carbs_g = (r["carbs"] or 0) * amt
        nutrition = [
            cal,
            fat_g / DV_REF["total_fat_g"] * 100,
            sugar_g / DV_REF["sugar_g"] * 100,
            sodium_mg / DV_REF["sodium_mg"] * 100,
            protein_g / DV_REF["protein_g"] * 100,
            0.0,
            carbs_g / DV_REF["carbs_g"] * 100,
        ]
        tracker.record_meal(meal_name, {
            "name": f"[Geçmiş] {r['item_name']}",
            "nutrition": nutrition,
            "ingredients": [],
            "tags": [],
        })
        fed += 1
        print(
            f"       + {r['item_name']} (×{amt}, {when}) → "
            f"Cal:{cal:.0f} Prot:{nutrition[4]:.0f}%DV "
            f"Şeker:{nutrition[2]:.0f}%DV Na:{nutrition[3]:.0f}%DV"
        )
    return fed


# ───────────────────────── KB driver ─────────────────────────

def run_kb_pipeline(vu: VirtualUser, recipes: list[dict], tracker: DailyMealTracker) -> list[dict]:
    print("=" * 90)
    print("🍽️  KB ÖNERİ SİSTEMİ — Buzdolabı + 5'li Öneri + Adaptif Besin Takibi")
    print("=" * 90)
    print(f"\n📦 {len(recipes)} tarif yüklendi.\n")

    extras = []
    if vu.diet_preference: extras.append(f"Diyet:{vu.diet_preference}")
    if vu.allergies: extras.append(f"Alerji:{','.join(vu.allergies)}")
    if vu.avoid_ingredients: extras.append(f"Kaçın:{','.join(vu.avoid_ingredients)}")

    print("━" * 90)
    print(f"👤 {vu.name} (DB id={vu._db_id}) | {vu.profile_key} "  # type: ignore[attr-defined]
          f"| {vu.age}{vu.gender}")
    print(f"   ⚙️  daily_calories={vu.daily_calories} kcal, meals_per_day={vu.meals_per_day} "
          f"(inspect_app_state._DEFAULT_KCAL/_DEFAULT_MEALS — Flutter UserProfile defaults)")
    if extras:
        print(f"   {' | '.join(extras)}")
    ps = PROFILE_SCORING[vu.profile_key]
    pw, bw = ps["penalty_weights"], ps["bonus_weights"]
    print(f"   📐 Puanlama: {ps['description']} | Prot ceza ×{pw['protein_low']} "
          f"| Prot bonus ×{bw['protein_recovery']} | Şeker ceza ×{pw['sugar_pdv']} "
          f"| Na ceza ×{pw['sodium_pdv']}")
    print(f"   🎯 Günlük limit (%DV): "
          + " | ".join(f"{k.replace('_pdv','')}:{v:.0f}" for k, v in vu.daily_limits.items()))

    if vu.fridge:
        print(f"   🧊 Buzdolabı ({len(vu.fridge)} ürün): {', '.join(vu.fridge[:10])}"
              + ("…" if len(vu.fridge) > 10 else ""))
    else:
        print("   🧊 Buzdolabı: BOŞ — match_ratio her tarif için 0% olacak, "
              "kısmi eşik 0.3'ü de geçemez → recommend_5 boş dönecek.")

    print("\n   🔁 Geçmiş tüketim (consumption_logs) tracker'a yükleniyor:")
    fed = replay_consumption_logs_redirected(vu, tracker)

    meals = MEAL_PLANS.get(vu.meals_per_day, [f"Öğün {i+1}" for i in range(vu.meals_per_day)])
    start_idx = len(tracker.meals_eaten)
    print(f"\n   📅 Öğün planı: {meals}")
    print(f"   ✅ Hesaplanan/atlanan öğün: {start_idx}  |  🔮 Önerilecek öğün: {len(meals)-start_idx}")

    kb_picks = []
    for mi in range(start_idx, len(meals)):
        meal_name = meals[mi]
        n_remaining = tracker.meals_remaining
        adaptive = tracker.get_adaptive_meal_limits()
        deficits = tracker.get_deficits()

        icon = '🍳' if mi == 0 else '🌙' if mi == len(meals) - 1 else '🍽️'
        print(f"\n   {icon} {meal_name}")
        print(f"      Kalan öğün: {n_remaining}  →  "
              "adaptif limit = (günlük − tüketilen) ÷ kalan_öğün")
        print("      Bu öğün için limit (%DV): "
              + " | ".join(f"{k.replace('_pdv','')}:{adaptive[k]:.0f}" for k in NUTR_KEYS))
        if deficits:
            print("      ⚖️  Telafi gerekiyor: " + ", ".join(
                f"{k}:{v:+.1f}" for k, v in deficits.items()
            ))

        top5 = recommend_5(vu, recipes, tracker)
        if not top5:
            print("      ⚠️  Uygun öneri bulunamadı (diskalifiye + eşleşme filtresinden hiçbir tarif geçemedi).")
            continue

        full_count = sum(1 for r in top5 if r["match_ratio"] >= 0.8)
        partial_count = len(top5) - full_count
        print(f"      5 Öneri (🟢{full_count} tam + 🟡{partial_count} kısmi):")

        for j, r in enumerate(top5, 1):
            n = r["nutrition"]
            tag = "🟢" if r["match_ratio"] >= 0.8 else "🟡"
            star = " ⭐" if j == 1 else ""
            print(f"        {j}. {tag} [{r['score']:.0f}p] {r['name'][:50]}{star}")
            print(f"           Cal:{n[0]:.0f} Prot:{n[4]:.0f}%DV "
                  f"| Eşleşme:{r['match_ratio']*100:.0f}%", end="")
            if r["missing_ings"]:
                print(f" | Eksik: {', '.join(r['missing_ings'][:3])}", end="")
            print()
            if r["reasons"]:
                print(f"           ↳ {' | '.join(r['reasons'][:4])}")

        chosen = top5[0]
        tracker.record_meal(meal_name, chosen)
        kb_picks.append({"meal": meal_name, "top5": top5, "chosen": chosen})

    consumed, limits, pct = tracker.summary()
    print(f"\n   📊 GÜN SONU (KB)")
    print(f"      Cal:{pct['calories']:.0f}% | Yağ:{pct['total_fat_pdv']:.0f}% "
          f"| Şeker:{pct['sugar_pdv']:.0f}% | Prot:{pct['protein_pdv']:.0f}% "
          f"| Na:{pct['sodium_pdv']:.0f}%")
    return kb_picks


def replay_consumption_logs_redirected(vu: VirtualUser, tracker: DailyMealTracker) -> int:
    """Wrapper so the KB pipeline section owns the log replay output."""
    con = _open()
    try:
        return replay_consumption_logs(con, vu, tracker)
    finally:
        con.close()


# ───────────────────────── CF driver ─────────────────────────

class MLRecommenderFromDB(MLRecommender):
    """Subclasses verbatim CF logic, swaps only `load_data()` to read SQLite.
    Adds one helper, `add_real_user_profile`, that injects a real app user's
    taste vector into `user_profiles` so the original `find_similar_users` and
    `predict_rating_and_serendipity` can score for them without any change to
    those methods. The taste vector is built the same way the original
    `build_user_profiles` builds synthetic ones: weighted average TF-IDF of
    'liked recipes' — for the real user, that's the KB-picked recipes
    (weighted by KB score). Falls back to the fridge as a pseudo-document if
    KB picked nothing."""

    def __init__(self, db_path: str):
        super().__init__()
        self.db_path = db_path

    def load_data(self):  # type: ignore[override]
        print(f"1. Veriler yükleniyor (SQLite: {os.path.basename(self.db_path)})...")
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

    def add_real_user_profile(self, key, vu: VirtualUser, kb_picks: list[dict]) -> str:
        """Inject a real user into `user_profiles` so the inherited CF methods
        can produce per-real-user predictions.

        Source of the taste vector (in priority order):
          1. KB-picked recipes for this user (weighted by KB score) — direct
             analog of `build_user_profiles`' 'liked recipes ≥3.0' bootstrap.
          2. Fridge contents as a pseudo-document run through the trained
             TfidfVectorizer — fallback when KB picked nothing.
          3. Zero vector — last resort (empty fridge AND no KB picks).

        Returns a short string describing which source was used (for logging).
        We deliberately do NOT touch `user_item_matrix` or `user_content_matrix`:
        - `find_similar_users` compares `user_profiles[key]` against
          `user_content_matrix` (synthetic-only). The real user is excluded
          from the similarity ranking because they're not in
          `user_item_matrix.index`, which is exactly what we want.
        - `predict_rating_and_serendipity` only needs `user_profiles[key]`
          (for the serendipity familiarity check) and the synthetic ratings
          in `user_item_matrix.loc[sim_user_id, r_id]` (looked up by id).
        """
        recipe_id_to_idx = {rid: idx for idx, rid in enumerate(self.df_recipes["id"])}
        chosen = [
            pick["chosen"] for pick in kb_picks
            if pick["chosen"]["id"] in recipe_id_to_idx
        ]
        if chosen:
            idxs = [recipe_id_to_idx[r["id"]] for r in chosen]
            rows = self.tfidf_matrix[idxs].toarray()
            weights = np.array([float(r["score"]) for r in chosen])
            if weights.sum() > 0:
                vec = np.average(rows, axis=0, weights=weights)
            else:
                vec = np.mean(rows, axis=0)
            self.user_profiles[key] = vec
            return f"KB picks ({len(chosen)} chosen recipes, weighted by KB score)"

        if vu.fridge:
            doc = " ".join(x.replace(" ", "_") for x in vu.fridge)
            vec = self.vectorizer.transform([doc]).toarray()[0]
            self.user_profiles[key] = vec
            return f"fridge pseudo-document ({len(vu.fridge)} items, vectorizer.transform)"

        self.user_profiles[key] = np.zeros(self.tfidf_matrix.shape[1])
        return "zero vector (no KB picks, empty fridge)"


def cf_train(db_path: str) -> MLRecommenderFromDB:
    """Train CF infrastructure once — load data, build TF-IDF, build synthetic
    user taste vectors. This is shared across all real users; the per-real-user
    serendipity pass reuses these matrices."""
    print("\n" + "=" * 90)
    print("🧠 CF EĞİTİMİ — Sentetik korpus üzerinden TF-IDF + komşuluk altyapısı")
    print("=" * 90)
    print("ℹ️  Sentetik `user_interactions` SADECE CF için kullanılır. Gerçek app")
    print("    kullanıcıları KB ile beslenir; CF'de yalnızca komşuluk sinyali (oyları)")
    print("    katkı sağlarlar — kimlikleri karıştırılmaz.\n")

    rec = MLRecommenderFromDB(db_path)
    rec.load_data()
    rec.prepare_matrices()
    rec.build_user_profiles()

    print(f"   📦 TF-IDF matrisi: {rec.tfidf_matrix.shape} (tarif × benzersiz malzeme token)")
    print(f"   📦 user-item matrisi: {rec.user_item_matrix.shape} (sentetik kullanıcı × tarif)")
    print(f"   📦 Sentetik kullanıcı zevk vektörleri hazır: {len(rec.user_profiles)}")
    return rec


def cf_serendipity_for_real_user(
    rec: MLRecommenderFromDB, vu: VirtualUser, kb_picks: list[dict]
) -> pd.DataFrame:
    """Per-real-user CF pass following the original test_ml_recommendations
    flow: build a taste vector → find K-NN synthetic neighbours → predict +
    serendipity for unseen recipes. The serendipity output is the diet-
    diversity layer the user asked for (recipes whose key ingredients are
    absent from the real user's current taste vector)."""
    print("\n" + "=" * 90)
    print(f"✨ CF SERENDİPİTY — diyet çeşitliliği için (gerçek user_id={vu._db_id})")  # type: ignore[attr-defined]
    print("=" * 90)

    key = f"real_user_{vu._db_id}"  # type: ignore[attr-defined]
    src = rec.add_real_user_profile(key, vu, kb_picks)
    print(f"🎯 Hedef: {key}  |  zevk vektörü kaynağı: {src}")
    print("   (Orijinal CF'deki 'rating ≥ 3.0 liked recipes' yerine bu kullanıcı için")
    print("    KB'nin seçtiği tarifler kullanılır; KB puanı = ağırlık. Synthetic users")
    print("    sadece komşu olarak kullanılır, kimlikleri gerçek kullanıcıyla karışmaz.)")

    print("\n🔍 K-NN ile en benzer 5 sentetik komşu (cosine on TF-IDF taste vector):")
    similar = rec.find_similar_users(key, k=5)
    if not similar:
        print("   (Taste vector boş — sıfır vektör; komşu bulunamadı.)")
        return pd.DataFrame()
    for u_id, sim in similar:
        neighbor_top = rec.df_interactions[
            (rec.df_interactions["user_id"] == u_id) & (rec.df_interactions["rating"] == 5)
        ]
        n_rec = "-"
        if not neighbor_top.empty:
            r_id = neighbor_top.iloc[0]["recipe_id"]
            row = rec.df_recipes[rec.df_recipes["id"] == r_id]
            if not row.empty:
                n_rec = row["name"].iloc[0]
        print(f"   > Sentetik kullanıcı {u_id} (Benzerlik: {sim:.2f}) → Örn sevdiği: {n_rec[:35]}")

    # The real user has no synthetic ratings of their own, so all recipes are
    # 'unseen' from the CF perspective. We exclude the recipes KB already
    # picked so serendipity surfaces genuine alternatives, not duplicates.
    all_r = set(rec.recipe_ids)
    kb_pick_ids = {p["chosen"]["id"] for p in kb_picks}
    unseen = list(all_r - kb_pick_ids)[:1000]
    print(f"\n🔮 Puan tahmini + sürpriz hesabı — {len(unseen)} tarif değerlendiriliyor")
    print(f"   (KB'nin zaten seçtiği {len(kb_pick_ids)} tarif hariç tutuldu; "
          "orijinal betikteki gibi 1000 ile sınırlı.)")
    preds = rec.predict_rating_and_serendipity(key, unseen)

    print("\n📈 [Normal CF] Komşuların en çok sevdiği 5 tarif:")
    for _, row in preds.sort_values("cf_score", ascending=False).head(5).iterrows():
        name_row = rec.df_recipes[rec.df_recipes["id"] == row["recipe_id"]]
        name = name_row["name"].iloc[0] if not name_row.empty else "?"
        print(f"   - {name[:45]:<45} | Tahmini Puan: {row['cf_score']:.2f}")

    print("\n✨ [Serendipity] Diyet çeşitliliği için 5 sürpriz tarif:")
    print("   (Komşular sevmiş + ana malzemeler gerçek kullanıcının zevkinde yok)")
    top_s = (
        preds[preds["serendipity_score"] > 0]
        .sort_values("serendipity_score", ascending=False)
        .head(5)
    )
    if top_s.empty:
        print("   (Bu kullanıcı için sürpriz tarif çıkmadı — zevk vektörü zaten geniş.)")
    for _, row in top_s.iterrows():
        name_row = rec.df_recipes[rec.df_recipes["id"] == row["recipe_id"]]
        name = name_row["name"].iloc[0] if not name_row.empty else "?"
        ings = name_row["ingredients_list"].iloc[0] if not name_row.empty else []
        print(f"   - {name[:40]:<40} | Sürpriz: {row['serendipity_score']:.2f} "
              f"| Yabancı Malzeme: {', '.join(ings[:3])}…")
    return preds


# ───────────────────────── combination ─────────────────────────

def combine_kb_plus_cf(
    vu: VirtualUser, kb_picks: list[dict], cf_preds: pd.DataFrame,
    cf_rec: MLRecommenderFromDB,
) -> None:
    """KB and CF are complementary, not redundant: KB picks the meals the
    user can cook NOW from their fridge; CF surfaces what to TRY NEXT to
    broaden their diet. This view shows both sides for one real user."""
    print("\n" + "=" * 90)
    print(f"🔗 BİRLEŞİK GÖRÜNÜM — KB (bugün) + CF (çeşitlilik) — user_id={vu._db_id}")  # type: ignore[attr-defined]
    print("=" * 90)
    print("ℹ️  KB ve CF puanları KARIŞTIRILMAZ; iki sütun olarak gösterilir.")
    print("    KB ⭐ pick = bugün önerilen öğün. CF sürpriz = yarın denenebilecek tarif.")

    print("\n   🍽️  KB — bugünkü plan:")
    if not kb_picks:
        print("      (KB hiç öneri üretmedi — buzdolabı boş veya diskalifiye.)")
    else:
        for pick in kb_picks:
            r = pick["chosen"]
            tag = "🟢" if r["match_ratio"] >= 0.8 else "🟡"
            print(f"      {tag} [{pick['meal']:<14}] {r['name'][:55]:<55} "
                  f"KB:{r['score']:.0f}p  match:{r['match_ratio']*100:.0f}%")

    print("\n   ✨ CF — diyet çeşitliliği için 3 sürpriz öneri:")
    if cf_preds.empty:
        print("      (CF serendipity boş — taste vector kurulamadı.)")
        return
    top_s = (
        cf_preds[cf_preds["serendipity_score"] > 0]
        .sort_values("serendipity_score", ascending=False)
        .head(3)
    )
    if top_s.empty:
        print("      (Sürpriz tarif yok — komşular kullanıcının zaten bildiği şeyleri sevmiş.)")
        return
    for _, row in top_s.iterrows():
        name_row = cf_rec.df_recipes[cf_rec.df_recipes["id"] == row["recipe_id"]]
        name = name_row["name"].iloc[0] if not name_row.empty else f"recipe_id={int(row['recipe_id'])}"
        print(f"      ✨ {name[:55]:<55} "
              f"serendipity:{row['serendipity_score']:.2f}  cf:{row['cf_score']:.2f}")


# ───────────────────────── main ─────────────────────────

def parse_args():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--db", default=DEFAULT_DB_PATH)
    ap.add_argument("--user", type=int, default=None,
                    help="Real users.id. If omitted, runs KB+CF for ALL rows in `users`.")
    return ap.parse_args()


def _user_ids_to_run(con: sqlite3.Connection, user_arg: int | None) -> list[int]:
    if user_arg is not None:
        return [user_arg]
    return [r["id"] for r in con.execute("SELECT id FROM users ORDER BY id ASC").fetchall()]


def main():
    args = parse_args()
    # Redirect inspect_app_state's hard-coded DB_PATH so its _open() honours --db.
    inspect_app_state.DB_PATH = args.db
    if not os.path.exists(args.db):
        raise SystemExit(f"❌ DB bulunamadı: {args.db}")

    con = _open()
    try:
        user_ids = _user_ids_to_run(con, args.user)
        if not user_ids:
            raise SystemExit("❌ `users` tablosu boş — Flutter uygulamasında profil oluşturun.")
    finally:
        con.close()

    # Recipes are user-independent; load them once via the canonical loader in
    # test_kb_recommendations.load_recipes (now SQLite-backed, ORDER BY id ASC
    # to match Dart KbRecommenderService.scoreAll iteration order).
    recipes = load_recipes()
    print(f"\n📦 {len(recipes)} tarif yüklendi (test_kb_recommendations.load_recipes).")

    print(f"\n🚀 KB pipeline çalıştırılacak kullanıcı sayısı: {len(user_ids)} "
          f"(ids={user_ids})\n")

    # CF training is shared across all real users — the TF-IDF matrix and
    # synthetic user_profiles depend only on the recipe corpus and the
    # user_interactions table, both of which are user-independent.
    cf_rec = cf_train(args.db)

    # Per real user: KB → CF serendipity (built from KB picks) → combined view.
    all_results = []
    for uid in user_ids:
        con = _open()
        try:
            vu = load_real_user(con, uid)
            load_fridge_into_user(con, vu)
        finally:
            con.close()
        tracker = DailyMealTracker(vu)
        kb_picks = run_kb_pipeline(vu, recipes, tracker)
        cf_preds = cf_serendipity_for_real_user(cf_rec, vu, kb_picks)
        combine_kb_plus_cf(vu, kb_picks, cf_preds, cf_rec)
        all_results.append((vu, kb_picks, tracker))

    # Multi-user summary table.
    if len(all_results) > 1:
        print("\n" + "━" * 90)
        print("📊 TÜM KULLANICILAR — KB GÜN SONU ÖZETİ")
        print("━" * 90)
        print(f"{'id':>3} {'Profil':<22} {'Yaş/Cins':<9} {'Diyet/Alerji':<22} "
              f"{'Cal%':>5} {'Yağ%':>5} {'Şeker%':>6} {'Prot%':>6} {'Na%':>5}  Öğün")
        print("─" * 90)
        for vu, kb_picks, tracker in all_results:
            _, _, pct = tracker.summary()
            extras = []
            if vu.diet_preference: extras.append(vu.diet_preference)
            extras += vu.allergies
            extras_s = ",".join(extras) if extras else "-"
            print(f"{vu._db_id:>3} {vu.profile_key:<22} "  # type: ignore[attr-defined]
                  f"{vu.age}{vu.gender:<7} {extras_s[:22]:<22} "
                  f"{pct['calories']:>4.0f}% {pct['total_fat_pdv']:>4.0f}% "
                  f"{pct['sugar_pdv']:>5.0f}% {pct['protein_pdv']:>5.0f}% "
                  f"{pct['sodium_pdv']:>4.0f}%  {len(kb_picks)}/{vu.meals_per_day}")

    print("\n" + "━" * 90)
    print("✅ Demo tamamlandı. KB → gerçek `users` satırları | CF → sentetik `user_interactions`.")
    print("━" * 90)


if __name__ == "__main__":
    main()
