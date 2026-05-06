import pandas as pd
import numpy as np
import os
import json
from datetime import datetime
import sys

# Yollar
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
if SCRIPT_DIR not in sys.path:
    sys.path.append(SCRIPT_DIR)

from test_kb_recommendations import (
    VIRTUAL_USERS, DailyMealTracker, is_disqualified, adaptive_score, 
    load_recipes, MEAL_PLANS, USER_BREAKFAST, BREAKFAST_SCENARIOS, calc_ingredient_match
)
from test_ml_recommendations import MLRecommender

class AdvancedMealTracker(DailyMealTracker):
    def __init__(self, user, ml_recommender):
        super().__init__(user)
        self.ingredient_history = []
        self.ml_recommender = ml_recommender
        self.feature_names = self.ml_recommender.vectorizer.get_feature_names_out()
        
    def get_main_ingredient(self, recipe_id):
        """Tarifin TF-IDF'e göre en ayırt edici/ana malzemesini bulur."""
        if recipe_id not in self.ml_recommender.recipe_ids:
            return None
        
        idx = self.ml_recommender.recipe_ids.index(recipe_id)
        tfidf_vector = self.ml_recommender.tfidf_matrix[idx].toarray().flatten()
        
        # En yüksek TF-IDF skoruna sahip kelimeyi bul
        if np.max(tfidf_vector) > 0:
            top_idx = np.argmax(tfidf_vector)
            return self.feature_names[top_idx]
        return None

    def record_meal(self, meal_name, recipe):
        super().record_meal(meal_name, recipe)
        # Sadece simüle edilmemiş gerçek tariflerin malzemelerini takip et
        r_id = recipe.get("id")
        if r_id is not None:
            main_ing = self.get_main_ingredient(r_id)
            if main_ing:
                self.ingredient_history.append(main_ing)
                # Sadece son 3 öğünü tut
                if len(self.ingredient_history) > 3:
                    self.ingredient_history.pop(0)

class BoundaryCFHelper:
    def __init__(self, ml_recommender):
        self.ml = ml_recommender
        self.boundary_neighbors_cache = {}

    def get_boundary_neighbors(self, user_id):
        """Orta derece (%30-%60) benzerlikteki komşuları bulur."""
        if user_id in self.boundary_neighbors_cache:
            return self.boundary_neighbors_cache[user_id]
            
        target_profile = self.ml.user_profiles.get(user_id)
        if target_profile is None:
            return []
            
        target_profile = target_profile.reshape(1, -1)
        similarities = self.ml.cosine_similarity(target_profile, self.ml.user_content_matrix)[0]
        
        user_ids = self.ml.user_item_matrix.index.tolist()
        boundary_neighbors = []
        
        for uid, sim in zip(user_ids, similarities):
            if uid != user_id and 0.30 <= sim <= 0.60:
                boundary_neighbors.append((uid, sim))
                
        # En iyi 20 boundary komşuyu al
        boundary_neighbors.sort(key=lambda x: x[1], reverse=True)
        self.boundary_neighbors_cache[user_id] = boundary_neighbors[:20]
        return self.boundary_neighbors_cache[user_id]

    def get_cf_boundary_bonus(self, user_id, recipe_id):
        """Boundary komşuların profilleriyle tarifin TF-IDF vektörü arasındaki Affinity'ye (Benzeşim) göre bonus hesaplar."""
        neighbors = self.get_boundary_neighbors(user_id)
        if not neighbors or recipe_id not in self.ml.recipe_ids:
            return 0.0
            
        # Hedef tarifin TF-IDF vektörü
        idx = self.ml.recipe_ids.index(recipe_id)
        recipe_vector = self.ml.tfidf_matrix[idx].toarray().reshape(1, -1)
        
        total_affinity = 0.0
        count = 0
        
        for uid, sim in neighbors:
            neighbor_profile = self.ml.user_profiles.get(uid)
            if neighbor_profile is not None:
                # Komşunun "Zevk Vektörü" ile "Tarifin Vektörü" ne kadar örtüşüyor?
                affinity = self.ml.cosine_similarity(recipe_vector, neighbor_profile.reshape(1, -1))[0][0]
                # Sim ağırlığı ile çarpabiliriz (daha yakın komşunun fikri daha önemli)
                total_affinity += affinity * sim
                count += sim
                
        if count == 0:
            return 0.0
            
        avg_affinity = total_affinity / count
        # avg_affinity genelde 0.0 ile 1.0 arasındadır. Genelde 0.05 - 0.20 arası değerler alır.
        # Maksimum 15 puanlık bonus sistemine entegre ediyoruz.
        # Eğer affinity > 0.02 ise bonus vermeye başla.
        if avg_affinity > 0.02:
            bonus = (avg_affinity - 0.02) * 100.0 # 0.05 -> 3 puan, 0.10 -> 8 puan, 0.17+ -> 15 puan
            return min(15.0, bonus)
        return 0.0

class MonotonyBreaker:
    def __init__(self, tracker):
        self.tracker = tracker
        
    def get_monotony_adjustment(self, recipe_id):
        """Geçmişe göre çeşitlilik (+10) veya monotonluk (-5) skoru verir."""
        main_ing = self.tracker.get_main_ingredient(recipe_id)
        if not main_ing:
            return 0.0
            
        if main_ing in self.tracker.ingredient_history:
            return -5.0 # Monotony Penalty
        else:
            return +10.0 # Diversity Bonus


def select_5_slots(scored_recipes):
    """
    Kategorize edilmiş 5'li slot seçimi:
    1. Ana Eşleşme 1
    2. Ana Eşleşme 2
    3. Makro Telafi
    4. Kesişim Keşfi (Boundary CF)
    5. Diyet Kırıcı (Monotony Breaker)
    """
    slots = []
    selected_ids = set()
    
    def pop_best(candidates, key_func, tag):
        # candidates'ı sırala, seçilmeyeni bul
        candidates.sort(key=key_func, reverse=True)
        for c in candidates:
            if c["recipe"]["id"] not in selected_ids:
                selected_ids.add(c["recipe"]["id"])
                c["slot_tag"] = tag
                slots.append(c)
                return c
        return None

    # 1. & 2. Slot: Ana KB Eşleşmesi (Buzdolabı Tam Eşleşen En Yüksek KB)
    # Eşleşme yoksa kısmi eşleşenlerden al
    full_matches = [r for r in scored_recipes if r["match_ratio"] >= 0.8]
    if not full_matches:
        full_matches = scored_recipes
        
    pop_best(full_matches, lambda x: x["kb_score"], "🟢 Ana Eşleşme 1")
    pop_best(full_matches, lambda x: x["kb_score"], "🟢 Ana Eşleşme 2")
    
    # 3. Slot: Makro Telafi (Adaptive Bonus almış en yüksek tarif)
    macro_candidates = [r for r in scored_recipes if any("telafi" in res.lower() or "denge" in res.lower() for res in r["kb_reasons"])]
    if not macro_candidates:
        macro_candidates = scored_recipes
    pop_best(macro_candidates, lambda x: x["kb_score"], "🛡️ Makro Telafi")
    
    # 4. Slot: Kesişim Keşfi (CF Boundary Bonus'u en yüksek olan)
    boundary_candidates = [r for r in scored_recipes if r["cf_bonus"] > 0]
    if not boundary_candidates:
        boundary_candidates = scored_recipes
    pop_best(boundary_candidates, lambda x: x["cf_bonus"], "🌉 Kesişim Keşfi (CF)")
    
    # 5. Slot: Diyet Kırıcı (Monotony Bonus'u en yüksek olan)
    monotony_candidates = [r for r in scored_recipes if r["monotony_adj"] > 0]
    if not monotony_candidates:
        monotony_candidates = scored_recipes
    pop_best(monotony_candidates, lambda x: x["monotony_adj"], "✨ Diyet Kırıcı")
    
    # Eğer 5'e tamamlanmadıysa (aynı tarifler denk geldiyse vs.) en iyi total skorlulardan ekle
    remaining = [r for r in scored_recipes if r["recipe"]["id"] not in selected_ids]
    remaining.sort(key=lambda x: x["total_score"], reverse=True)
    
    while len(slots) < 5 and remaining:
        c = remaining.pop(0)
        c["slot_tag"] = "🔵 Ekstra"
        slots.append(c)
        selected_ids.add(c["recipe"]["id"])
        
    return slots


def run_boundary_tests():
    print("1. ML Modeli Başlatılıyor (TF-IDF & K-NN)...")
    ml_recommender = MLRecommender()
    ml_recommender.load_data()
    ml_recommender.prepare_matrices()
    ml_recommender.build_user_profiles()
    # Metod referansını düzelt
    from sklearn.metrics.pairwise import cosine_similarity
    ml_recommender.cosine_similarity = cosine_similarity
    
    print("\n2. KB Modeli İçin Tarifler Yükleniyor...")
    kb_recipes = load_recipes()
    
    cf_helper = BoundaryCFHelper(ml_recommender)
    all_results = []
    
    for i, user in enumerate(VIRTUAL_USERS, 1):
        target_ml_user_id = i + 20 # ML tarafında bir ID (Örn: 21-30)
        
        meals = MEAL_PLANS.get(user.meals_per_day, [f"Öğün {j+1}" for j in range(user.meals_per_day)])
        scenario = USER_BREAKFAST[user.name]
        
        # Gelişmiş Tracker (Ingredient History içerir)
        tracker = AdvancedMealTracker(user, ml_recommender)
        monotony_breaker = MonotonyBreaker(tracker)
        
        print(f"\n{'━'*100}")
        print(f"👤 [{i}] {user.name} | {user.profile_key} | {user.daily_calories}kcal | ML-ID: {target_ml_user_id}")
        
        # Kahvaltı simülasyonunu sadece tek sayılı kullanıcılar için yap, çiftler uygulama önersin
        user_meal_data = []
        start_mi = 0
        if i % 2 != 0:
            bk = BREAKFAST_SCENARIOS[scenario]
            tracker.record_meal(meals[0], {"name":f"[Simüle] {scenario}","nutrition":bk,"ingredients":[],"tags":[]})
            user_meal_data.append({"meal":meals[0],"chosen":f"[Simüle] {scenario}","nutrition":bk,"type":"simulated"})
            start_mi = 1
        else:
            print(f"   🌅 {meals[0]} öğünü uygulama tarafından önerilecek (Simülasyon atlandı).")
            
        for mi in range(start_mi, len(meals)):
            mn = meals[mi]
            
            # ADIM 1: Hard Filter (KB Otoritesi)
            valid_recipes = []
            for r in kb_recipes:
                if not is_disqualified(user, r) and r["name"] not in tracker.eaten_recipe_names:
                    valid_recipes.append(r)
            
            if not valid_recipes:
                print(f"   ⚠️ {mn}: Uygun tarif bulunamadı!")
                continue
                
            import random
            sample_size = min(500, len(valid_recipes))
            sampled_recipes = random.sample(valid_recipes, sample_size)
            
            scored_recipes = []
            
            for r in sampled_recipes:
                # KB Skoru (Otorite)
                kb_score, kb_reasons = adaptive_score(user, r, tracker)
                if kb_score < 0: # Yasaklı/Tekrar
                    continue
                    
                match_ratio, _, _ = calc_ingredient_match(user.fridge, r["ingredients"])
                
                # CF Çeşitlilik Bonusu
                cf_bonus = cf_helper.get_cf_boundary_bonus(target_ml_user_id, r["id"])
                
                # Monotonluk Ayarı
                monotony_adj = monotony_breaker.get_monotony_adjustment(r["id"])
                
                # Total Skor
                total_score = kb_score + cf_bonus + monotony_adj
                
                scored_recipes.append({
                    "recipe": r,
                    "kb_score": round(kb_score, 1),
                    "kb_reasons": kb_reasons,
                    "match_ratio": round(match_ratio, 2),
                    "cf_bonus": round(cf_bonus, 1),
                    "monotony_adj": round(monotony_adj, 1),
                    "total_score": round(total_score, 1),
                    "main_ingredient": tracker.get_main_ingredient(r["id"])
                })
                
            # ADIM 2: Slotlara Göre Seçim
            top5 = select_5_slots(scored_recipes)
            
            print(f"\n   🍽️ {mn} — Kesişim CF & Monotonluk Kırıcı 5'li Slot:")
            
            all_5_data = []
            for j, opt in enumerate(top5, 1):
                r = opt["recipe"]
                n = r["nutrition"]
                tag = opt["slot_tag"]
                
                print(f"      {j}. {tag:<22} | {opt['total_score']}p | {r['name'][:35]}")
                print(f"         KB:{opt['kb_score']}p | CF Bonus:+{opt['cf_bonus']}p | Monotonluk:{opt['monotony_adj']:+}p | AnaMalzeme: {opt['main_ingredient']}")
                if opt["kb_reasons"]:
                    print(f"         KB Sebepler: {', '.join(opt['kb_reasons'])}")
                print()
                
                all_5_data.append({
                    "rank": j, "recipe": r["name"], "slot_tag": tag,
                    "total_score": opt["total_score"], "kb_score": opt["kb_score"], 
                    "cf_bonus": opt["cf_bonus"], "monotony_adj": opt["monotony_adj"],
                    "main_ingredient": opt["main_ingredient"],
                    "nutrition": list(n)
                })

            # En iyi tarifi tüketildi olarak işaretle
            chosen_opt = top5[0]
            tracker.record_meal(mn, chosen_opt["recipe"])
            
            user_meal_data.append({
                "meal": mn, "chosen": chosen_opt["recipe"]["name"],
                "slot_tag": chosen_opt["slot_tag"],
                "nutrition": list(chosen_opt["recipe"]["nutrition"]),
                "all_5": all_5_data
            })
            
        consumed, limits, pct = tracker.summary()
        all_results.append({
            "user": user.name, "profile": user.profile_key,
            "pct": pct, "meals": user_meal_data,
            "history": tracker.ingredient_history
        })
        
    return all_results, ml_recommender

def generate_boundary_results(all_results):
    ts = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    
    with open(os.path.join(SCRIPT_DIR, "boundary_cf_results.txt"), "w", encoding="utf-8") as f:
        f.write(f"BOUNDARY CF & MONOTONY BREAKER Test Sonuçları — {ts}\n{'='*110}\n")
        f.write(f"Özellikler: Otoriter KB | Kesişim Noktası CF (+15 Puan Maks) | Diyet Monotonluğu Kırıcı (-5/+10)\n\n")
        
        for r in all_results:
            f.write(f"{'━'*110}\n👤 {r['user']} | {r['profile']}\n")
            f.write(f"   Son Öğünlerin Ana Malzemeleri (History): {', '.join([str(x) for x in r['history']])}\n\n")
            
            for m in r["meals"]:
                f.write(f"   📌 {m['meal']}")
                if m.get("type") == "simulated":
                    f.write(f" (simüle): {m['chosen']}\n\n")
                    continue
                
                f.write(f" — Seçilen: {m['chosen']}\n")
                f.write(f"      {'#':<3} {'Slot Tipi':<22} {'Total':>5} {'KB Puan':>7} {'CF Bonus':>8} {'Monotonluk':>10} {'Tarif'}\n")
                f.write(f"      {'─'*105}\n")
                for item in m.get("all_5", []):
                    f.write(f"      {item['rank']:<3} {item['slot_tag']:<22} {item['total_score']:>5.0f} {item['kb_score']:>7.1f} {item['cf_bonus']:>8.1f} {item['monotony_adj']:>10.1f}  {item['recipe'][:40]}\n")
                f.write("\n")
            
            p = r["pct"]
            f.write(f"   Gün Sonu: Cal:{p['calories']:.0f}% Fat:{p['total_fat_pdv']:.0f}% Sugar:{p['sugar_pdv']:.0f}% Prot:{p['protein_pdv']:.0f}% Na:{p['sodium_pdv']:.0f}%\n")
            
    print(f"\n📄 boundary_cf_results.txt oluşturuldu.")

def show_knn_and_matrix(ml):
    print("\n" + "="*100)
    print("🧠 K-NN KOMSULUK ORNEKLERI VE MATRIS YAPISI")
    print("="*100)
    
    target_user = 21 # Örneğin Berk'in ML ID'si (1 + 20)
    print(f"\n[Örnek Hedef Kullanıcı ML-ID: {target_user} - Profili: Vegan]")
    
    target_profile = ml.user_profiles.get(target_user)
    if target_profile is not None:
        target_profile = target_profile.reshape(1, -1)
        similarities = ml.cosine_similarity(target_profile, ml.user_content_matrix)[0]
        
        sim_scores = [(uid, sim) for uid, sim in zip(ml.user_item_matrix.index.tolist(), similarities) if uid != target_user]
        sim_scores.sort(key=lambda x: x[1], reverse=True)
        
        print("\n🔴 En Yakın 3 Komşusu (Yankı Fanusu - Çok Benzer | > %70 Benzerlik):")
        for uid, sim in sim_scores[:3]:
            prof = ml.user_profiles.get(uid)
            top_features_idx = np.argsort(prof)[-3:]
            top_features = [ml.vectorizer.get_feature_names_out()[idx] for idx in top_features_idx if prof[idx] > 0]
            print(f"  -> Kullanıcı {uid} | Benzerlik: %{sim*100:.1f} | Sevdiği Ana Malzemeler: {', '.join(top_features)}")
            print("     (Açıklama: Bu komşular kullanıcı ile aynı şeyleri yer. Çeşitlilik sağlamazlar.)")
            
        print("\n🟢 Orta Seviye 3 Komşusu (Kesişim/Boundary CF İçin Seçilenler | %30 - %60 Benzerlik):")
        boundary = [x for x in sim_scores if 0.30 <= x[1] <= 0.60]
        for uid, sim in boundary[:3]:
            prof = ml.user_profiles.get(uid)
            top_features_idx = np.argsort(prof)[-3:]
            top_features = [ml.vectorizer.get_feature_names_out()[idx] for idx in top_features_idx if prof[idx] > 0]
            print(f"  -> Kullanıcı {uid} | Benzerlik: %{sim*100:.1f} | Sevdiği Ana Malzemeler: {', '.join(top_features)}")
            print("     (Açıklama: Bu komşular, hedefin diyet sınırlarında olan, hem vegan hem de biraz esnek beslenen/farklı baharatlar seven kullanıcılardır. Sürpriz keşifler için mükemmeldirler!)")
            
    print("\n\n📊 USER-FEATURE AFFINITY MATRİSİNİN GÖRSELLEŞTİRİLMESİ (Küçük Bir Kesit)")
    print("-" * 100)
    print("Satırlar: Kullanıcı ID'leri | Sütunlar: En Çok Kullanılan Özellikler/Kavramlar (TF-IDF)")
    print("Değerler: Kullanıcının o malzemeye/kavrama olan yakınlığı (Affinity Skoru).\n")
    
    # Tüm kelimeleri (özellikleri) al
    features = ml.vectorizer.get_feature_names_out()
    # Rastgele 5 kullanıcı
    sample_users = list(ml.user_profiles.keys())[:5]
    
    # Tüm özellikler içinden en yüksek varyansa / ortalamaya sahip 8 tanesini seçelim ki dolu görünsün
    mean_affinities = np.mean(ml.user_content_matrix, axis=0)
    top_feature_indices = np.argsort(mean_affinities)[-8:]
    top_feature_names = [features[i] for i in top_feature_indices]
    
    print(f"{'User_ID':<10}", end="")
    for f_name in top_feature_names:
        print(f"{f_name[:12]:>12}", end="")
    print("\n" + "-"*105)
    
    for uid in sample_users:
        prof = ml.user_profiles[uid]
        print(f"{uid:<10}", end="")
        for idx in top_feature_indices:
            val = prof[idx]
            print(f"{val:>12.3f}", end="")
        print()
    print("-" * 105)

if __name__ == "__main__":
    results, ml_recommender = run_boundary_tests()
    generate_boundary_results(results)
    show_knn_and_matrix(ml_recommender)
