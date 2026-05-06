import pandas as pd
import numpy as np
import random
import os
import ast

# Yollar
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
RECIPES_PATH = os.path.join(SCRIPT_DIR, "RAW_recipes_filtered.csv")
OUTPUT_PATH = os.path.join(SCRIPT_DIR, "synthetic_interactions.csv")

# Sanal Kullanıcı Profilleri ve Zevkleri (TF-IDF için Ayırt Edici Malzemeler)
PROFILES = {
    "meat_lover": {
        "likes": ["chicken", "beef", "pork", "steak", "bacon", "sausage", "ham", "meat"],
        "dislikes": ["tofu", "soy", "vegan"],
        "prob": 0.25 # Toplam nüfus içindeki oranı
    },
    "vegetarian": {
        "likes": ["tofu", "spinach", "broccoli", "mushroom", "lentil", "beans", "vegetable", "chickpea"],
        "dislikes": ["chicken", "beef", "pork", "steak", "bacon", "sausage", "ham", "meat", "fish", "salmon", "shrimp"],
        "prob": 0.15
    },
    "pescatarian": {
        "likes": ["fish", "salmon", "shrimp", "tuna", "cod", "seafood", "crab"],
        "dislikes": ["chicken", "beef", "pork", "steak", "bacon", "sausage", "ham", "meat"],
        "prob": 0.10
    },
    "sweet_tooth": {
        "likes": ["sugar", "chocolate", "vanilla", "butter", "cream", "cake", "cookie", "honey", "syrup"],
        "dislikes": ["spicy", "chili", "jalapeno", "garlic"],
        "prob": 0.20
    },
    "healthy_eater": {
        "likes": ["spinach", "kale", "quinoa", "oats", "chicken breast", "salmon", "avocado", "olive oil"],
        "dislikes": ["sugar", "butter", "cream", "bacon", "deep fried", "lard"],
        "prob": 0.20
    },
    "spicy_lover": {
        "likes": ["chili", "jalapeno", "cayenne", "hot sauce", "curry", "spicy", "pepper"],
        "dislikes": ["sugar", "sweet", "vanilla"],
        "prob": 0.10
    }
}

NUM_USERS = 600
MIN_REVIEWS_PER_USER = 15
MAX_REVIEWS_PER_USER = 50

def generate_data():
    print("1. Tarifler yükleniyor...")
    try:
        df_recipes = pd.read_csv(RECIPES_PATH)
    except FileNotFoundError:
        print(f"Hata: {RECIPES_PATH} bulunamadı!")
        return

    # Sadece ID, name ve ingredients bize yeter
    # Veri tiplerini düzeltelim
    df_recipes['ingredients_list'] = df_recipes['ingredients'].apply(
        lambda x: ast.literal_eval(x) if isinstance(x, str) and x.startswith('[') else str(x).split(',')
    )
    
    recipe_ids = df_recipes['id'].tolist()
    recipe_dict = df_recipes.set_index('id')['ingredients_list'].to_dict()
    
    print("2. Sanal kullanıcılar ve profilleri oluşturuluyor...")
    users = []
    for user_id in range(1, NUM_USERS + 1):
        # Rastgele bir profil seç
        r = random.random()
        cumulative = 0.0
        chosen_profile = "meat_lover"
        for profile, data in PROFILES.items():
            cumulative += data["prob"]
            if r <= cumulative:
                chosen_profile = profile
                break
        
        users.append({
            "user_id": user_id,
            "profile": chosen_profile
        })
        
    print("3. Kullanıcıların tarif değerlendirmeleri simüle ediliyor...")
    interactions = []
    
    for user in users:
        num_reviews = random.randint(MIN_REVIEWS_PER_USER, MAX_REVIEWS_PER_USER)
        # Kullanıcı için rastgele tarifler seç
        sampled_recipes = random.sample(recipe_ids, num_reviews)
        
        profile_data = PROFILES[user["profile"]]
        likes = profile_data["likes"]
        dislikes = profile_data["dislikes"]
        
        for r_id in sampled_recipes:
            ings = recipe_dict.get(r_id, [])
            ings_text = " ".join(ings).lower()
            
            # Puanı hesapla
            base_score = 3.0 # Ortalama başlangıç puanı
            
            # Sevdiği malzemeler varsa puan artar
            like_count = sum(1 for item in likes if item in ings_text)
            if like_count > 0:
                base_score += 1.0 + (like_count * 0.2)
                
            # Sevmediği malzemeler varsa puan düşer
            dislike_count = sum(1 for item in dislikes if item in ings_text)
            if dislike_count > 0:
                base_score -= 1.5 + (dislike_count * 0.5)
                
            # Rastgelelik (Noise) ekle ki veri doğal görünsün
            noise = random.uniform(-0.5, 0.5)
            final_rating = base_score + noise
            
            # 1 ile 5 arasına sabitle
            final_rating = max(1.0, min(5.0, final_rating))
            
            # Tam sayı yapma olasılığı yüksek olsun (kullanıcılar genelde 4, 5, 3 verir)
            final_rating = round(final_rating)
            
            interactions.append({
                "user_id": user["user_id"],
                "recipe_id": r_id,
                "rating": final_rating,
                "profile_tag": user["profile"] # İleride analiz için
            })

    df_interactions = pd.DataFrame(interactions)
    print(f"4. Toplam {len(df_interactions)} etkileşim (rating) oluşturuldu.")
    print("Profili bazlı ortalama puanlar:")
    print(df_interactions.groupby('profile_tag')['rating'].mean())
    
    df_interactions.to_csv(OUTPUT_PATH, index=False)
    print(f"\n✅ {OUTPUT_PATH} başarıyla kaydedildi!")

if __name__ == "__main__":
    generate_data()
