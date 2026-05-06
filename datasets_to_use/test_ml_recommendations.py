import pandas as pd
import numpy as np
import ast
import os
import json
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.metrics.pairwise import cosine_similarity
from sklearn.neighbors import NearestNeighbors

# Yollar
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
RECIPES_PATH = os.path.join(SCRIPT_DIR, "RAW_recipes_filtered.csv")
INTERACTIONS_PATH = os.path.join(SCRIPT_DIR, "synthetic_interactions.csv")
GUIDELINES_PATH = os.path.join(SCRIPT_DIR, "who_daily_nutrient_guidelines.json")

class MLRecommender:
    def __init__(self):
        self.df_recipes = None
        self.df_interactions = None
        self.user_item_matrix = None
        self.tfidf_matrix = None
        self.vectorizer = None
        self.recipe_ids = []
        self.user_profiles = {} # Kullanıcıların TF-IDF zevk vektörleri
        
    def load_data(self):
        print("1. Veriler yükleniyor...")
        self.df_recipes = pd.read_csv(RECIPES_PATH)
        self.df_interactions = pd.read_csv(INTERACTIONS_PATH)
        
        # String halindeki listeleri python listesine çevir
        self.df_recipes['ingredients_list'] = self.df_recipes['ingredients'].apply(
            lambda x: ast.literal_eval(x) if isinstance(x, str) and x.startswith('[') else str(x).split(',')
        )
        self.recipe_ids = self.df_recipes['id'].tolist()
        
    def prepare_matrices(self):
        print("2. Matrisler hazırlanıyor (TF-IDF & User-Item)...")
        
        # 1. TF-IDF ile Tarif-Malzeme Vektörizasyonu
        # "soğan", "su", "tuz" gibi ortak malzemelerin TF-IDF skoru düşük olacak
        # "karides", "kuzu eti" gibi ayırt edici malzemelerin skoru yüksek olacak
        self.df_recipes['ingredients_text'] = self.df_recipes['ingredients_list'].apply(lambda x: " ".join([i.replace(" ", "_") for i in x]))
        
        self.vectorizer = TfidfVectorizer(max_df=0.85, min_df=2) # Çok ortak olanları(max_df) veya çok nadir olanları(min_df) filtrele
        self.tfidf_matrix = self.vectorizer.fit_transform(self.df_recipes['ingredients_text'])
        
        # 2. Kullanıcı-Tarif (User-Item) Puan Matrisi
        self.user_item_matrix = self.df_interactions.pivot(index='user_id', columns='recipe_id', values='rating').fillna(0)
        
    def build_user_profiles(self):
        print("3. Kullanıcıların İçerik Zevk Vektörleri hesaplanıyor...")
        # Bir kullanıcının zevk vektörü = Yüksek puan verdiği tariflerin TF-IDF vektörlerinin ağırlıklı ortalaması
        
        # DataFrame index'leri ile TF-IDF index'leri eşleşmeli
        recipe_id_to_idx = {r_id: idx for idx, r_id in enumerate(self.df_recipes['id'])}
        
        user_profiles_list = []
        user_ids = self.user_item_matrix.index.tolist()
        
        for user_id in user_ids:
            # Kullanıcının puan verdiği tarifler ve puanları
            user_ratings = self.df_interactions[self.df_interactions['user_id'] == user_id]
            
            # Sadece sevdiği tarifleri (rating >= 3.0) baz al
            liked_recipes = user_ratings[user_ratings['rating'] >= 3.0]
            
            if liked_recipes.empty:
                # Hiç sevdiği tarif yoksa sıfır vektörü
                user_prof = np.zeros((1, self.tfidf_matrix.shape[1]))
            else:
                # Sevdiği tariflerin TF-IDF satırlarını al
                liked_idxs = [recipe_id_to_idx[r_id] for r_id in liked_recipes['recipe_id'] if r_id in recipe_id_to_idx]
                if liked_idxs:
                    # Orijinal Sparse matristen indexleri çekip ortalama al
                    liked_tfidf = self.tfidf_matrix[liked_idxs].toarray()
                    # Ağırlıklı ortalama (puanlarına göre)
                    weights = liked_recipes['rating'].values.reshape(-1, 1)
                    if len(weights) == len(liked_tfidf):
                        user_prof = np.average(liked_tfidf, axis=0, weights=weights.flatten()).reshape(1, -1)
                    else:
                        user_prof = np.mean(liked_tfidf, axis=0).reshape(1, -1)
                else:
                    user_prof = np.zeros((1, self.tfidf_matrix.shape[1]))
                    
            self.user_profiles[user_id] = user_prof.flatten()
            user_profiles_list.append(user_prof.flatten())
            
        # Kullanıcı-İçerik Matrisi (Tüm kullanıcıların zevk vektörleri)
        self.user_content_matrix = np.array(user_profiles_list)
        
    def find_similar_users(self, target_user_id, k=10):
        """Hedef kullanıcıya K-NN ve Cosine Similarity ile benzeyen K kullanıcıyı bulur."""
        if target_user_id not in self.user_profiles:
            return []
            
        target_profile = self.user_profiles[target_user_id].reshape(1, -1)
        
        # Diğer tüm kullanıcılarla (kendisi hariç) Cosine Similarity
        similarities = cosine_similarity(target_profile, self.user_content_matrix)[0]
        
        user_ids = self.user_item_matrix.index.tolist()
        sim_scores = list(zip(user_ids, similarities))
        
        # Kendisini çıkar ve benzerliğe göre sırala
        sim_scores = sorted([s for s in sim_scores if s[0] != target_user_id], key=lambda x: x[1], reverse=True)
        
        return sim_scores[:k]
        
    def predict_rating_and_serendipity(self, target_user_id, recipe_ids_to_predict):
        """Benzer kullanıcıların puanlarına göre tariflerin tahmin edilen puanını ve Serendipity skorunu hesaplar."""
        similar_users = self.find_similar_users(target_user_id, k=20)
        
        predictions = []
        target_profile = self.user_profiles.get(target_user_id, np.zeros(self.tfidf_matrix.shape[1]))
        recipe_id_to_idx = {r_id: idx for idx, r_id in enumerate(self.df_recipes['id'])}
        
        for r_id in recipe_ids_to_predict:
            if r_id not in recipe_id_to_idx:
                continue
                
            total_sim = 0
            weighted_rating = 0
            
            # 1. CF Tahmini: Komşuların bu tarife verdiği puanlar
            if r_id in self.user_item_matrix.columns:
                for sim_user_id, sim_score in similar_users:
                    # O komşu bu tarife puan vermiş mi?
                    rating = self.user_item_matrix.loc[sim_user_id, r_id]
                    if rating > 0:
                        weighted_rating += sim_score * rating
                        total_sim += sim_score
                    
            pred_rating = (weighted_rating / total_sim) if total_sim > 0 else 2.5 # Varsayılan ortalama
            
            # 2. Serendipity Hesaplaması
            # Eğer komşular tarife çok yüksek puan vermişse (pred_rating > 4.0)
            # VE bu tarifin içindeki önemli malzemeler hedef kullanıcının vektöründe "0" veya çok düşükse, bu Serendipity'dir.
            serendipity_score = 0
            if pred_rating > 3.5:
                r_idx = recipe_id_to_idx[r_id]
                recipe_tfidf = self.tfidf_matrix[r_idx].toarray().flatten()
                
                # Tarifin öne çıkan (TF-IDF değeri > 0.1) malzemelerini bul
                significant_features = np.where(recipe_tfidf > 0.1)[0]
                
                if len(significant_features) > 0:
                    # Kullanıcının bu öne çıkan malzemelere aşinalığını kontrol et
                    user_familiarity = np.mean(target_profile[significant_features])
                    
                    # Kullanıcı hiç aşina değilse (0'a yakınsa), Serendipity yüksektir!
                    if user_familiarity < 0.05:
                        serendipity_score = pred_rating * (1.0 - user_familiarity)
                        
            predictions.append({
                "recipe_id": r_id,
                "cf_score": pred_rating,
                "serendipity_score": serendipity_score
            })
            
        return pd.DataFrame(predictions)

# ----------------- TEST SENARYOSU -----------------
def run_demo():
    recommender = MLRecommender()
    recommender.load_data()
    recommender.prepare_matrices()
    recommender.build_user_profiles()
    
    # Simüle edilmiş kullanıcılardan birini hedef olarak alalım
    # Mesela User 1
    target_user = 1
    
    print(f"\n🎯 HEDEF KULLANICI: {target_user}")
    print("Bu kullanıcının geçmişte sevdiği bazı tariflerin içerikleri:")
    user_past = recommender.df_interactions[(recommender.df_interactions['user_id'] == target_user) & (recommender.df_interactions['rating'] >= 4.0)]
    liked_r_ids = user_past['recipe_id'].tolist()
    
    for r in liked_r_ids[:3]:
        name = recommender.df_recipes[recommender.df_recipes['id'] == r]['name'].values[0]
        ings = recommender.df_recipes[recommender.df_recipes['id'] == r]['ingredients_list'].values[0]
        print(f"  - {name} | Malzemeler: {', '.join(ings[:4])}...")
        
    print("\n🔍 K-NN (Benzer Kullanıcılar) Aranıyor...")
    similar = recommender.find_similar_users(target_user, k=5)
    for u_id, sim in similar:
        # Komşunun sevdiği bir tarifi de yazalım
        neighbor_liked = recommender.df_interactions[(recommender.df_interactions['user_id'] == u_id) & (recommender.df_interactions['rating'] == 5.0)]
        n_rec = "-"
        if not neighbor_liked.empty:
            n_r_id = neighbor_liked.iloc[0]['recipe_id']
            n_rec = recommender.df_recipes[recommender.df_recipes['id'] == n_r_id]['name'].values[0]
        print(f"  > Kullanıcı {u_id} (Benzerlik: {sim:.2f}) -> Örn sevdiği: {n_rec[:30]}")

    print("\n🔮 Puan Tahmini (Prediction) ve Sürpriz (Serendipity) Hesaplaması Yapılıyor...")
    
    # Kullanıcının henüz puanlamadığı rastgele 1000 tarif üzerinden arama yapalım
    all_r_ids = set(recommender.recipe_ids)
    past_r_ids = set(recommender.df_interactions[recommender.df_interactions['user_id'] == target_user]['recipe_id'].tolist())
    unseen_r_ids = list(all_r_ids - past_r_ids)[:1000]
    
    preds_df = recommender.predict_rating_and_serendipity(target_user, unseen_r_ids)
    
    # Normal CF'ye göre en iyi 3
    print("\n📈 [Normal CF] Komşuların En Çok Sevdiği 3 Tarif:")
    top_cf = preds_df.sort_values(by='cf_score', ascending=False).head(3)
    for _, row in top_cf.iterrows():
        name = recommender.df_recipes[recommender.df_recipes['id'] == row['recipe_id']]['name'].values[0]
        print(f"  - {name[:40]:<40} | Tahmini Puan: {row['cf_score']:.2f}")

    # Serendipity'ye göre en iyi 3
    print("\n✨ [Serendipity] Kullanıcının Hiç Denemediği Ama Komşuların Sevdiği 3 Sürpriz Tarif:")
    top_serendipity = preds_df[preds_df['serendipity_score'] > 0].sort_values(by='serendipity_score', ascending=False).head(3)
    for _, row in top_serendipity.iterrows():
        name = recommender.df_recipes[recommender.df_recipes['id'] == row['recipe_id']]['name'].values[0]
        ings = recommender.df_recipes[recommender.df_recipes['id'] == row['recipe_id']]['ingredients_list'].values[0]
        print(f"  - {name[:40]:<40} | Sürpriz Skoru: {row['serendipity_score']:.2f} | Yabancı Malzemeler: {', '.join(ings[:4])}...")

if __name__ == "__main__":
    run_demo()
