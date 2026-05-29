"""
Combined KB + CF recommendation demo over the shipped Flutter SQLite asset
(`assets/fridge_app.db`).

Output style matches `test_kb_recommendations.py` and `test_ml_recommendations.py`
(Turkish headers, emojis, `━`/`─` separators). All algorithm code is imported
verbatim from those two files; this driver only:
  - swaps data sources (CSV/JSON → SQLite),
  - feeds `consumption_logs` into the existing tracker,
  - presents both pipelines back-to-back.

The synthetic users in `user_interactions` are training corpus for CF only; the
real `users` row drives KB. They never mix.

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

import pandas as pd

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.abspath(os.path.join(SCRIPT_DIR, os.pardir))
DEFAULT_DB_PATH = os.path.join(REPO_ROOT, "assets", "fridge_app.db")

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

DIET_PREFS = {"vegan", "vegetarian", "pescatarian"}

# The `users` table only stores profile_key/age/sex/restrictions now. KB needs
# `daily_calories` and `meals_per_day`, so we pick sensible defaults per
# (profile_key, sex). These mirror the prototypes in test_kb_recommendations.py's
# VIRTUAL_USERS list (e.g. Ozan athlete_bodybuilder M = 3200 kcal/6 meals,
# Seda pregnant_lactating F = 2400 kcal/4 meals).
PROFILE_DEFAULTS = {
    ("general_adult",       "M"): (2400, 3),
    ("general_adult",       "F"): (1900, 3),
    ("athlete_bodybuilder", "M"): (3200, 5),
    ("athlete_bodybuilder", "F"): (2600, 5),
    ("pregnant_lactating",  "F"): (2300, 4),
    ("pregnant_lactating",  "M"): (2300, 4),  # rare row, keep KB callable
    ("adolescent",          "M"): (2700, 4),
    ("adolescent",          "F"): (2100, 4),
}


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

    daily_cal, meals = PROFILE_DEFAULTS.get(
        (u["profile_key"], u["sex"]), (2200, 3)
    )

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


def load_recipes(con: sqlite3.Connection) -> tuple[list[dict], int, int]:
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
            "id": r["id"], "name": r["name"], "nutrition": nutrition,
            "ingredients": ingredients, "tags": tags, "minutes": r["minutes"] or 0,
        })
    return recipes, skipped_nutr, skipped_no_ings


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
          f"(users tablosunda yok → ({vu.profile_key},{vu.gender}) için varsayılan)")
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
    con = sqlite3.connect(DEFAULT_DB_PATH)
    con.row_factory = sqlite3.Row
    try:
        return replay_consumption_logs(con, vu, tracker)
    finally:
        con.close()


# ───────────────────────── CF driver ─────────────────────────

class MLRecommenderFromDB(MLRecommender):
    """Subclasses verbatim CF logic, swaps only `load_data()` to read SQLite."""

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


def run_cf_pipeline(db_path: str, synthetic_user_id: int) -> tuple[pd.DataFrame, MLRecommenderFromDB]:
    print("\n" + "=" * 90)
    print("🧠 CF ÖNERİ SİSTEMİ — Sentetik Kullanıcı Korpusu (yalnız CF için)")
    print("=" * 90)
    print("ℹ️  Aşağıdaki user_id, `user_interactions` içindeki SENTETİK bir kullanıcıdır.")
    print("   Gerçek app kullanıcısı ile aynı kişi DEĞİLDİR; sadece id uzayını paylaşıyorlar.\n")

    rec = MLRecommenderFromDB(db_path)
    rec.load_data()
    rec.prepare_matrices()
    rec.build_user_profiles()

    print(f"   📦 TF-IDF matrisi: {rec.tfidf_matrix.shape} (tarif × benzersiz malzeme token)")
    print(f"   📦 user-item matrisi: {rec.user_item_matrix.shape} (sentetik kullanıcı × tarif)")

    profile_tag = "?"
    sub = rec.df_interactions[rec.df_interactions["user_id"] == synthetic_user_id]
    if not sub.empty:
        profile_tag = sub["profile_tag"].iloc[0]

    print(f"\n🎯 HEDEF SENTETİK KULLANICI: {synthetic_user_id} (profile_tag={profile_tag!r})")
    user_past = rec.df_interactions[
        (rec.df_interactions["user_id"] == synthetic_user_id)
        & (rec.df_interactions["rating"] >= 4.0)
    ]
    if not user_past.empty:
        print("   Geçmişte sevdiği bazı tarifler:")
        for r_id in user_past["recipe_id"].tolist()[:3]:
            row = rec.df_recipes[rec.df_recipes["id"] == r_id]
            if not row.empty:
                name = row["name"].iloc[0]
                ings = row["ingredients_list"].iloc[0]
                print(f"      - {name} | Malzemeler: {', '.join(ings[:4])}…")

    print("\n🔍 K-NN ile benzer kullanıcılar (cosine on TF-IDF taste vector):")
    similar = rec.find_similar_users(synthetic_user_id, k=5)
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
        print(f"   > Kullanıcı {u_id} (Benzerlik: {sim:.2f}) → Örn sevdiği: {n_rec[:35]}")

    print("\n🔮 Puan tahmini (komşuların ağırlıklı puanları) ve sürpriz hesabı yapılıyor…")
    all_r = set(rec.recipe_ids)
    seen = set(rec.df_interactions[rec.df_interactions["user_id"] == synthetic_user_id][
        "recipe_id"
    ].tolist())
    unseen = list(all_r - seen)[:1000]
    print(f"   (Henüz puanlamadığı {len(unseen)} tarif değerlendiriliyor — orijinal "
          "betikteki gibi 1000 ile sınırlı.)")
    preds = rec.predict_rating_and_serendipity(synthetic_user_id, unseen)

    print("\n📈 [Normal CF] Komşuların en çok sevdiği 5 tarif:")
    for _, row in preds.sort_values("cf_score", ascending=False).head(5).iterrows():
        name_row = rec.df_recipes[rec.df_recipes["id"] == row["recipe_id"]]
        name = name_row["name"].iloc[0] if not name_row.empty else "?"
        print(f"   - {name[:45]:<45} | Tahmini Puan: {row['cf_score']:.2f}")

    print("\n✨ [Serendipity] Hedefin denemediği ama komşuların sevdiği 5 sürpriz tarif:")
    top_s = (
        preds[preds["serendipity_score"] > 0]
        .sort_values("serendipity_score", ascending=False)
        .head(5)
    )
    for _, row in top_s.iterrows():
        name_row = rec.df_recipes[rec.df_recipes["id"] == row["recipe_id"]]
        name = name_row["name"].iloc[0] if not name_row.empty else "?"
        ings = name_row["ingredients_list"].iloc[0] if not name_row.empty else []
        print(f"   - {name[:40]:<40} | Sürpriz: {row['serendipity_score']:.2f} "
              f"| Yabancı Malzeme: {', '.join(ings[:3])}…")

    return preds, rec


# ───────────────────────── combination ─────────────────────────

def combine(kb_picks: list[dict], cf_preds: pd.DataFrame, cf_rec: MLRecommenderFromDB) -> None:
    print("\n" + "=" * 90)
    print("🔗 BİRLEŞİK GÖRÜNÜM — KB ve CF kesişimi (yalnız sunum katmanı)")
    print("=" * 90)
    print("ℹ️  KB ve CF puanları KARIŞTIRILMAZ. Aşağıda her iki listede de geçen tarifler "
          "öne çıkarılır (yüksek güven).\n")

    if not kb_picks:
        print("   ⚠️  KB hiç öneri üretmedi (buzdolabı boş veya tüm tarifler diskalifiye). "
              "Birleşik görünüm üretilemez.")
        return

    kb_ids_all = {r["id"] for pick in kb_picks for r in pick["top5"]}
    print(f"   📦 KB'nin tüm öğünlerde döndürdüğü tekil tarif sayısı: {len(kb_ids_all)}")

    cf_top = cf_preds.sort_values("cf_score", ascending=False).head(100)
    cf_ids = set(cf_top["recipe_id"].tolist())
    print(f"   📦 CF'nin top-100 (cf_score) tarif kümesi: {len(cf_ids)}")

    intersection = kb_ids_all & cf_ids
    print(f"   🤝 Kesişim: {len(intersection)} tarif iki listede de var.")
    if not intersection:
        print("      Çoğu durumda kesişim çıkmaz: gerçek kullanıcının diyet/alerji profili "
              "ile sentetik kullanıcının cohort'u birbirinden farklı olur.")
        return

    print("   🏆 Yüksek güvenli ortak öneriler:")
    for pick in kb_picks:
        for r in pick["top5"]:
            if r["id"] in intersection:
                cf_row = cf_top[cf_top["recipe_id"] == r["id"]].iloc[0]
                print(f"      - [{pick['meal']}] {r['name'][:55]:<55} "
                      f"KB:{r['score']:.0f}p  CF:{cf_row['cf_score']:.2f}")


# ───────────────────────── main ─────────────────────────

def parse_args():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--db", default=DEFAULT_DB_PATH)
    ap.add_argument("--user", type=int, default=None,
                    help="Real users.id. If omitted, runs KB for ALL rows in `users`.")
    ap.add_argument("--cf-synth", type=int, default=1,
                    help="Synthetic user_id for the CF demo (default: 1)")
    return ap.parse_args()


def _user_ids_to_run(con: sqlite3.Connection, user_arg: int | None) -> list[int]:
    if user_arg is not None:
        return [user_arg]
    return [r["id"] for r in con.execute("SELECT id FROM users ORDER BY id ASC").fetchall()]


def main():
    args = parse_args()
    if not os.path.exists(args.db):
        raise SystemExit(f"❌ DB bulunamadı: {args.db}")

    con = sqlite3.connect(args.db)
    con.row_factory = sqlite3.Row
    try:
        user_ids = _user_ids_to_run(con, args.user)
        if not user_ids:
            raise SystemExit("❌ `users` tablosu boş — Flutter uygulamasında profil oluşturun.")
        # Recipes and fridge are shared across all users, load them once.
        recipes, skipped_nutr, skipped_no_ings = load_recipes(con)
    finally:
        con.close()

    if skipped_nutr or skipped_no_ings:
        print(f"   (Atlanan tarifler — nutrition bozuk:{skipped_nutr}, "
              f"malzemesiz:{skipped_no_ings})")

    print(f"\n🚀 KB pipeline çalıştırılacak kullanıcı sayısı: {len(user_ids)} "
          f"(ids={user_ids})\n")

    # CF runs once — it doesn't depend on the real user; the synthetic corpus is
    # the same regardless of which real user we're scoring.
    cf_preds, cf_rec = run_cf_pipeline(args.db, args.cf_synth)

    # KB per real user (each gets its own VirtualUser and DailyMealTracker).
    all_results = []
    for uid in user_ids:
        con = sqlite3.connect(args.db)
        con.row_factory = sqlite3.Row
        try:
            vu = load_real_user(con, uid)
            load_fridge_into_user(con, vu)
        finally:
            con.close()
        tracker = DailyMealTracker(vu)
        kb_picks = run_kb_pipeline(vu, recipes, tracker)
        combine(kb_picks, cf_preds, cf_rec)
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
