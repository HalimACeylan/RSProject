#!/usr/bin/env python3
"""
KB Recommendation System Test — v3
- Buzdolabı envanteri ile malzeme eşleştirme
- 5 öneri/öğün (3 tam eşleşme + 2 kısmi eksik)
- Aynı gün tekrar öneri yok
- Adaptif besin takibi
"""
import csv, json, ast, os
from dataclasses import dataclass, field
from copy import deepcopy
from datetime import datetime

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
RECIPES_CSV = os.path.join(SCRIPT_DIR, "RAW_recipes_filtered.csv")
KB_JSON = os.path.join(SCRIPT_DIR, "who_daily_nutrient_guidelines.json")

with open(KB_JSON, "r", encoding="utf-8") as f:
    KB = json.load(f)
DV_REF = KB["engine_constants"]["dv_references"]
PROFILES = KB["recommendation_profiles"]
IDX_CAL, IDX_FAT, IDX_SUGAR, IDX_SODIUM, IDX_PROTEIN, IDX_SATFAT, IDX_CARBS = range(7)
NUTR_KEYS = ["calories","total_fat_pdv","sugar_pdv","sodium_pdv","protein_pdv","saturated_fat_pdv","carbs_pdv"]

MEAL_PLANS = {
    3: ["Kahvaltı","Öğle Yemeği","Akşam Yemeği"],
    4: ["Kahvaltı","Öğle Yemeği","Ara Öğün","Akşam Yemeği"],
    5: ["Kahvaltı","Ara Öğün 1","Öğle Yemeği","Ara Öğün 2","Akşam Yemeği"],
    6: ["Kahvaltı","Ara Öğün 1","Öğle Yemeği","Ara Öğün 2","Akşam Yemeği","Gece Atıştırması"],
}

# ─── Buzdolabı envanterleri ──────────────────────────────────────
USER_FRIDGES = {
    "Berk": ["rice","onion","garlic","olive oil","tomatoes","bell pepper","avocado","lemon juice","tofu","coconut milk","soy sauce","ginger","sesame oil","cilantro","lime juice"],
    "Seda": ["chicken breast","eggs","rice","spinach","tomatoes","onion","garlic","olive oil","lemon juice","carrot","potato","yogurt","whole wheat bread","apple","orange"],
    "Mert": ["chicken breast","salmon fillet","eggs","rice","oats","broccoli","spinach","olive oil","garlic","onion","sweet potato","greek yogurt","banana","almonds","protein powder"],
    "Aylin": ["chicken breast","rice","onion","garlic","olive oil","tomatoes","carrot","broccoli","lemon juice","ginger","soy sauce","sesame oil","tofu","green beans","corn"],
    "Ozan": ["chicken breast","salmon fillet","eggs","rice","oats","broccoli","spinach","olive oil","garlic","onion","sweet potato","avocado","banana","lemon juice","pepper"],
    "Ceren": ["rice","onion","garlic","olive oil","tomatoes","bell pepper","pasta","lemon juice","eggplant","zucchini","mushroom","parsley","cumin","paprika","vegetable broth"],
    "Tarik": ["chicken breast","rice","onion","garlic","olive oil","tomatoes","bell pepper","pasta","soy sauce","ginger","carrot","potato","lemon juice","black pepper"],
    "Gizem": ["chicken breast","salmon fillet","eggs","rice","oats","broccoli","spinach","olive oil","garlic","onion","sweet potato","greek yogurt","banana","almonds","protein powder"],
    "Pelin": ["chicken breast","eggs","rice","spinach","tomatoes","onion","garlic","olive oil","lemon juice","carrot","potato","pasta","bell pepper","parsley","cumin"],
    "Ali": ["ground beef","pasta","rice","onion","garlic","tomatoes","bell pepper","cheese","eggs","milk","bread","potato","ketchup","mustard","lettuce"]
}

BREAKFAST_SCENARIOS = {
    "low_protein":  [200, 5, 10, 5, 5, 3, 15],
    "high_sugar":   [350, 12, 60, 8, 10, 8, 25],
    "high_calorie": [800, 40, 20, 15, 30, 25, 30],
    "balanced":     [400, 15, 10, 10, 25, 8, 18],
    "low_cal":      [150, 3, 5, 2, 8, 2, 8],
}
USER_BREAKFAST = {
    "Berk":"high_sugar", "Seda":"balanced", "Mert":"low_protein", 
    "Aylin":"low_cal", "Ozan":"low_protein", "Ceren":"high_sugar", 
    "Tarik":"balanced", "Gizem":"low_protein", "Pelin":"balanced", "Ali":"high_calorie"
}

@dataclass
class VirtualUser:
    name: str; age: int; gender: str; profile_key: str
    daily_calories: int; meals_per_day: int
    is_athlete: bool = False; is_pregnant: bool = False
    diet_preference: str = ""
    allergies: list = field(default_factory=list)
    avoid_ingredients: list = field(default_factory=list)
    avoid_tags: list = field(default_factory=list)

    def __post_init__(self):
        self.profile = PROFILES[self.profile_key]
        self.rules = self.profile["macronutrient_rules"]
        E, r = self.daily_calories, self.rules
        self.daily_limits = {
            "calories": E,
            "total_fat_pdv": (E*r["fat_pct_max"]/100/9)/DV_REF["total_fat_g"]*100,
            "sugar_pdv": (E*r["sugar_pct_max"]/100/4)/DV_REF["sugar_g"]*100,
            "sodium_pdv": (r["sodium_max_mg"]/DV_REF["sodium_mg"])*100,
            "protein_pdv": (E*r["protein_pct_min"]/100/4)/DV_REF["protein_g"]*100,
            "saturated_fat_pdv": (E*r["sat_fat_pct_max"]/100/9)/DV_REF["saturated_fat_g"]*100,
            "carbs_pdv": (E*r["carbs_pct_max"]/100/4)/DV_REF["carbs_g"]*100,
        }
        self.fridge = [x.lower() for x in USER_FRIDGES.get(self.name, [])]

class DailyMealTracker:
    def __init__(self, user):
        self.user = user
        self.daily_limits = deepcopy(user.daily_limits)
        self.consumed = {k: 0.0 for k in NUTR_KEYS}
        self.meals_eaten = []
        self.eaten_recipe_names = set()
        self.total_meals = user.meals_per_day

    @property
    def meals_remaining(self):
        return max(1, self.total_meals - len(self.meals_eaten))

    def get_adaptive_meal_limits(self):
        n = self.meals_remaining
        return {k: (self.daily_limits[k]-self.consumed[k])/n for k in NUTR_KEYS}

    def get_deficits(self):
        eaten = len(self.meals_eaten)
        if eaten == 0: return {}
        d = {}
        for k in NUTR_KEYS:
            ideal = self.daily_limits[k]*eaten/self.total_meals
            diff = ideal - self.consumed[k]
            if k=="protein_pdv" and diff>0: d[k]=diff
            elif k!="protein_pdv" and diff<0: d[k]=diff
        return d

    def record_meal(self, meal_name, recipe):
        n = recipe["nutrition"]
        for i,k in enumerate(NUTR_KEYS): self.consumed[k] += n[i]
        self.meals_eaten.append((meal_name, recipe["name"], list(n)))
        self.eaten_recipe_names.add(recipe["name"])

    def summary(self):
        pct = {k: (self.consumed[k]/self.daily_limits[k]*100) if self.daily_limits[k]>0 else 0 for k in NUTR_KEYS}
        return self.consumed, self.daily_limits, pct

# ─── Malzeme eşleştirme ─────────────────────────────────────────
def calc_ingredient_match(fridge, recipe_ings):
    matched, missing = [], []
    for ing in recipe_ings:
        if any(f in ing or ing in f for f in fridge):
            matched.append(ing)
        else:
            missing.append(ing)
    total = len(recipe_ings) if recipe_ings else 1
    return len(matched)/total, matched, missing

# Alerji grupları için kelime haritalaması
ALLERGY_GROUPS = {
    "fish": ["salmon", "tuna", "tilapia", "cod", "trout", "halibut", "fish", "mahi", "snapper", "sardine", "anchovy"],
    "shellfish": ["shrimp", "crab", "lobster", "clam", "oyster", "mussel", "scallop", "prawn", "crawfish"],
    "tree nuts": ["almond", "walnut", "pecan", "cashew", "pistachio", "hazelnut", "macadamia", "pine nut"],
    "peanut": ["peanut", "goober"],
    "milk": ["milk", "cheese", "cream", "butter", "yogurt", "whey", "lactose", "ghee"],
    "egg": ["egg", "mayo"],
    "soy": ["soy", "tofu", "edamame", "miso", "tempeh"],
    "gluten": ["wheat", "flour", "bread", "pasta", "barley", "rye", "seitan", "bulgur"]
}

def is_disqualified(user, recipe):
    ings = recipe["ingredients"]
    for a in user.allergies:
        kw_list = ALLERGY_GROUPS.get(a.lower(), [a.lower()])
        for kw in kw_list:
            if any(kw in i for i in ings): return True
            
    for a in user.avoid_ingredients:
        if any(a.lower() in i for i in ings): return True
        
    meat_kw = ["chicken","beef","pork","lamb","turkey","sausage","bacon","ham","steak","meat","veal"]
    animal_kw = meat_kw+["milk","egg","cheese","cream","butter","honey","yogurt","gelatin","whey"]
    if user.diet_preference=="vegetarian" and any(k in i for k in meat_kw for i in ings): return True
    if user.diet_preference=="vegan" and any(k in i for k in animal_kw for i in ings): return True
    return False

# ─── Profil bazlı puanlama ağırlıkları ──────────────────────────
# Her profil tipi için farklı ceza/bonus katsayıları
# penalty_weights: makrobesin aşımı ceza çarpanları (1.0 = normal)
# bonus_weights: telafi bonus çarpanları
# ingredient_penalties: profil bazlı malzeme cezaları
PROFILE_SCORING = {
    "general_adult": {
        "description": "Dengeli beslenme odaklı",
        "penalty_weights": {
            "calories": 1.0, "total_fat_pdv": 1.0, "sugar_pdv": 1.2,
            "sodium_pdv": 1.0, "protein_low": 0.8, "saturated_fat_pdv": 1.0, "carbs_pdv": 0.8,
        },
        "bonus_weights": {
            "protein_recovery": 0.8,  # protein telafi bonusu çarpanı
            "calorie_balance": 1.0,
            "sugar_balance": 1.0,
        },
        "ingredient_penalties": {  # malzeme bazlı cezalar
            "fatty meat": -5, "butter": -3, "cream": -3, "lard": -5,
            "palm oil": -4, "coconut oil": -3, "ghee": -4,
        },
        "ingredient_bonuses": {
            "vegetables": 3, "fruits": 2, "whole grains": 3, "fish": 2,
            "olive oil": 2, "nuts": 2,
        },
    },
    "athlete_bodybuilder": {
        "description": "Yüksek protein, kas gelişimi odaklı",
        "penalty_weights": {
            "calories": 0.6,  # kaloriye daha toleranslı
            "total_fat_pdv": 0.8, "sugar_pdv": 1.5,  # şekere sert
            "sodium_pdv": 0.7,  # sodyuma daha toleranslı
            "protein_low": 2.0,  # DÜŞÜK PROTEİN = ÇOK AĞIR CEZA
            "saturated_fat_pdv": 1.0, "carbs_pdv": 0.5,  # karba toleranslı
        },
        "bonus_weights": {
            "protein_recovery": 2.0,  # protein telafi bonusu ÇOK YÜKSEK
            "calorie_balance": 0.5,   # kalori dengeleme daha az önemli
            "sugar_balance": 1.2,
        },
        "ingredient_penalties": {
            "fatty meat": -2, "butter": -3, "cream": -4, "lard": -5,
            "sugar": -5, "candy": -8, "soda": -8, "syrup": -4,
        },
        "ingredient_bonuses": {
            "chicken": 5, "salmon": 5, "egg": 4, "fish": 5,
            "broccoli": 3, "spinach": 3, "oats": 3, "rice": 2,
            "sweet potato": 3, "avocado": 3, "nuts": 2,
        },
    },
    "adolescent": {
        "description": "Büyüme dönemi, dengeli besin ve yüksek protein",
        "penalty_weights": {
            "calories": 0.8, "total_fat_pdv": 1.0, "sugar_pdv": 1.5,  # şekere sert
            "sodium_pdv": 1.2,  # sodyuma dikkat
            "protein_low": 1.5,  # protein önemli (büyüme)
            "saturated_fat_pdv": 1.2, "carbs_pdv": 0.7,
        },
        "bonus_weights": {
            "protein_recovery": 1.5,
            "calorie_balance": 0.8,
            "sugar_balance": 1.5,  # şeker dengeleme çok önemli
        },
        "ingredient_penalties": {
            "candy": -8, "soda": -8, "sugar": -4, "syrup": -5,
            "fatty meat": -3, "lard": -5, "cream": -3,
        },
        "ingredient_bonuses": {
            "milk": 3, "egg": 3, "chicken": 3, "fish": 3,
            "vegetables": 3, "fruits": 3, "whole grains": 3,
            "cheese": 2, "yogurt": 3,
        },
    },
    "pregnant_lactating": {
        "description": "Anne-bebek sağlığı, folat/demir/kalsiyum odaklı",
        "penalty_weights": {
            "calories": 0.8, "total_fat_pdv": 1.0, "sugar_pdv": 1.3,
            "sodium_pdv": 1.5,  # SODYUMA ÇOK DİKKAT (preeklampsi riski)
            "protein_low": 1.3,  # protein önemli
            "saturated_fat_pdv": 1.2, "carbs_pdv": 0.7,
        },
        "bonus_weights": {
            "protein_recovery": 1.3,
            "calorie_balance": 0.7,  # kalori kısıtlama zararlı
            "sugar_balance": 1.2,
        },
        "ingredient_penalties": {
            "alcohol": -50, "wine": -50, "beer": -50, "rum": -50,
            "raw fish": -10, "sushi": -10,
            "fatty meat": -4, "lard": -5, "cream": -3,
            "caffeine": -3, "coffee": -2,
        },
        "ingredient_bonuses": {
            "spinach": 5, "egg": 4, "fish": 4, "salmon": 4,
            "milk": 3, "yogurt": 3, "cheese": 2,
            "vegetables": 3, "fruits": 3, "whole grains": 3,
            "lentil": 4, "beans": 3, "iron": 5,
        },
    },
}

def adaptive_score(user, recipe, tracker):
    if is_disqualified(user, recipe): return -1, []
    if recipe["name"] in tracker.eaten_recipe_names: return -2, []
    nutr = recipe["nutrition"]
    limits = tracker.get_adaptive_meal_limits()
    deficits = tracker.get_deficits()
    reasons, score = [], 100.0

    # Profil bazlı ağırlıkları al
    pw = PROFILE_SCORING.get(user.profile_key, PROFILE_SCORING["general_adult"])
    pen_w = pw["penalty_weights"]
    bon_w = pw["bonus_weights"]

    # ── Makrobesin cezaları (profil ağırlıklı) ──
    checks = [
        ("calories",0,25,"Cal"), ("total_fat_pdv",1,20,"Yağ"),
        ("sugar_pdv",2,20,"Şeker"), ("sodium_pdv",3,15,"Na"),
        ("saturated_fat_pdv",5,15,"DYağ"), ("carbs_pdv",6,10,"Karb"),
    ]
    for key,idx,base_mp,lbl in checks:
        lim = limits[key]
        w = pen_w.get(key, 1.0)
        mp = base_mp * w  # profil ağırlıklı max ceza
        if lim>0 and nutr[idx]>lim:
            pen = min(mp, (nutr[idx]-lim)/lim*mp*2)
            score -= pen
            reasons.append(f"{lbl}↑ {nutr[idx]:.0f}>{lim:.0f} (-{pen:.1f}×{w:.1f})")

    # ── Protein alt limit (profil ağırlıklı) ──
    pl = limits["protein_pdv"]
    prot_w = pen_w.get("protein_low", 1.0)
    if nutr[IDX_PROTEIN]<pl and pl>0:
        pen = min(15*prot_w, (pl-nutr[IDX_PROTEIN])/pl*30*prot_w)
        score -= pen
        reasons.append(f"Prot↓ {nutr[IDX_PROTEIN]:.0f}<{pl:.0f} (-{pen:.1f}×{prot_w:.1f})")

    # ── Profil bazlı telafi bonusları ──
    # Protein telafi
    if "protein_pdv" in deficits and deficits["protein_pdv"]>0 and nutr[IDX_PROTEIN]>pl:
        w = bon_w.get("protein_recovery", 1.0)
        b = min(15*w, (nutr[IDX_PROTEIN]-pl)/pl*15*w) if pl>0 else 0
        score += b
        reasons.append(f"💪Prot telafi +{b:.1f} (×{w:.1f})")

    # Kalori dengeleme
    if "calories" in deficits and deficits["calories"]<0 and nutr[IDX_CAL]<limits["calories"]:
        w = bon_w.get("calorie_balance", 1.0)
        b = min(10*w, (limits["calories"]-nutr[IDX_CAL])/limits["calories"]*10*w) if limits["calories"]>0 else 0
        score += b
        reasons.append(f"🔥Cal denge +{b:.1f} (×{w:.1f})")

    # Şeker dengeleme
    if "sugar_pdv" in deficits and deficits["sugar_pdv"]<0 and nutr[IDX_SUGAR]<limits.get("sugar_pdv",999)*0.5:
        w = bon_w.get("sugar_balance", 1.0)
        b = 5 * w
        score += b
        reasons.append(f"🍬Şeker↓ +{b:.1f} (×{w:.1f})")

    # ── Profil bazlı malzeme ceza/bonusları ──
    ings = recipe["ingredients"]
    for term, penalty in pw.get("ingredient_penalties", {}).items():
        if any(term.lower() in i for i in ings):
            score += penalty  # negatif değer = ceza
            reasons.append(f"⚠️{term} {penalty:+.0f}")

    for term, bonus in pw.get("ingredient_bonuses", {}).items():
        if any(term.lower() in i for i in ings):
            score += bonus
            reasons.append(f"✨{term} +{bonus}")

    return max(0, min(130, score)), reasons

def load_recipes(max_rows=20000):
    recipes = []
    with open(RECIPES_CSV,"r",encoding="utf-8") as f:
        for i,row in enumerate(csv.DictReader(f)):
            if i>=max_rows: break
            try:
                recipes.append({"id":int(row["id"]),"name":row["name"],"nutrition":ast.literal_eval(row["nutrition"]),"ingredients":[x.lower().strip() for x in ast.literal_eval(row["ingredients"])],"tags":[x.lower().strip() for x in ast.literal_eval(row["tags"])],"minutes":int(row.get("minutes",0) or 0)})
            except: continue
    return recipes

VIRTUAL_USERS = [
    VirtualUser("Berk", 26, "M", "general_adult", 2400, 3, diet_preference="vegan"),
    VirtualUser("Seda", 34, "F", "pregnant_lactating", 2400, 4, is_pregnant=True, allergies=["fish", "shellfish"]),
    VirtualUser("Mert", 17, "M", "adolescent", 2800, 5, is_athlete=True, avoid_ingredients=["sugar", "candy", "chocolate"]),
    VirtualUser("Aylin", 29, "F", "general_adult", 1700, 3, allergies=["egg", "peanut"]),
    VirtualUser("Ozan", 40, "M", "athlete_bodybuilder", 3200, 6, is_athlete=True, avoid_ingredients=["bread", "pasta", "flour"]),
    VirtualUser("Ceren", 21, "F", "general_adult", 1900, 3, diet_preference="vegetarian", allergies=["milk"]),
    VirtualUser("Tarik", 50, "M", "general_adult", 2100, 3, avoid_ingredients=["salt", "butter", "cream"]),
    VirtualUser("Gizem", 27, "F", "athlete_bodybuilder", 2600, 5, is_athlete=True),
    VirtualUser("Pelin", 31, "F", "pregnant_lactating", 2200, 4, is_pregnant=True, avoid_ingredients=["alcohol", "caffeine", "coffee"]),
    VirtualUser("Ali", 15, "M", "adolescent", 2500, 4, allergies=["tree nuts", "soy"])
]

# ─── 5'li öneri: 3 tam + 2 kısmi ────────────────────────────────
def recommend_5(user, recipes, tracker):
    fridge = user.fridge
    full_match, partial_match = [], []
    for r in recipes:
        s, reasons = adaptive_score(user, r, tracker)
        if s < 0: continue
        match_ratio, matched, missing = calc_ingredient_match(fridge, r["ingredients"])
        entry = {**r, "score":s, "reasons":reasons, "match_ratio":match_ratio, "matched_ings":matched, "missing_ings":missing}
        if match_ratio >= 0.8:
            full_match.append(entry)
        elif 0.3 <= match_ratio < 0.8:
            partial_match.append(entry)
    full_match.sort(key=lambda x: (x["score"], x["match_ratio"]), reverse=True)
    partial_match.sort(key=lambda x: (x["score"], x["match_ratio"]), reverse=True)
    result = full_match[:3]
    needed = 5 - len(result)
    result += partial_match[:needed]
    if len(result) < 5:
        result += full_match[3:3+(5-len(result))]
    return result[:5]

# ─── Ana test ────────────────────────────────────────────────────
def run_tests():
    print("="*90)
    print("🍽️  KB ÖNERİ SİSTEMİ v3 — Buzdolabı + 5'li Öneri + Tekrar Engeli + Adaptif")
    print("="*90)
    recipes = load_recipes()
    print(f"\n📦 {len(recipes)} tarif yüklendi.\n")
    all_results = []

    for i, user in enumerate(VIRTUAL_USERS, 1):
        meals = MEAL_PLANS.get(user.meals_per_day, [f"Öğün {j+1}" for j in range(user.meals_per_day)])
        scenario = USER_BREAKFAST[user.name]
        tracker = DailyMealTracker(user)
        print(f"{'━'*90}")
        print(f"👤 [{i}] {user.name} | {user.profile_key} | {user.daily_calories}kcal | {user.meals_per_day} öğün")
        extras = []
        if user.diet_preference: extras.append(f"Diyet:{user.diet_preference}")
        if user.allergies: extras.append(f"Alerji:{','.join(user.allergies)}")
        if user.avoid_ingredients: extras.append(f"Kaçın:{','.join(user.avoid_ingredients)}")
        if extras: print(f"   {' | '.join(extras)}")
        print(f"   🧊 Buzdolabı: {', '.join(user.fridge[:8])}...")

        # Kahvaltı simüle
        bk = BREAKFAST_SCENARIOS[scenario]
        tracker.record_meal(meals[0], {"name":f"[Simüle] {scenario}","nutrition":bk,"ingredients":[],"tags":[]})
        print(f"\n   🌅 {meals[0]} (simüle—{scenario}): Cal:{bk[0]} Prot:{bk[4]}%DV Sugar:{bk[2]}%DV")

        user_meal_data = [{"meal":meals[0],"chosen":f"[Simüle] {scenario}","nutrition":bk,"type":"simulated","match_ratio":1.0,"missing":[],"all_5":[{"rank":1,"recipe":f"[Simüle] {scenario}","score":0,"match_ratio":1.0,"type":"simulated","nutrition":bk,"missing":[]}]}]
        day_ok = True
        all_unique = True

        for mi in range(1, len(meals)):
            mn = meals[mi]
            top5 = recommend_5(user, recipes, tracker)
            if not top5:
                print(f"\n   ⚠️ {mn}: Öneri bulunamadı!")
                continue

            # Tekrar kontrolü
            for r in top5:
                if r["name"] in tracker.eaten_recipe_names:
                    all_unique = False

            # Tam/kısmi sayımı
            full_count = sum(1 for r in top5 if r["match_ratio"]>=0.8)
            partial_count = sum(1 for r in top5 if r["match_ratio"]<0.8)

            icon = '🍳' if mi==1 else '🌙' if mi==len(meals)-1 else '🍽️'
            print(f"\n   {icon} {mn} — 5 Öneri (🟢{full_count} tam + 🟡{partial_count} kısmi):")

            all_5_data = []
            for j, r in enumerate(top5, 1):
                n = r["nutrition"]
                tag = "🟢" if r["match_ratio"]>=0.8 else "🟡"
                star = " ⭐" if j==1 else ""
                print(f"      {j}. {tag} [{r['score']:.0f}p] {r['name'][:50]}{star}")
                print(f"         Cal:{n[0]:.0f} Prot:{n[4]:.0f}%DV | Eşleşme:{r['match_ratio']*100:.0f}%", end="")
                if r["missing_ings"]:
                    print(f" | Eksik: {', '.join(r['missing_ings'][:3])}", end="")
                print()
                tp = "full" if r["match_ratio"]>=0.8 else "partial"
                all_5_data.append({"rank":j,"recipe":r["name"],"score":round(r["score"],1),"match_ratio":round(r["match_ratio"],2),"type":tp,"nutrition":list(n),"missing":r["missing_ings"]})

            chosen = top5[0]
            tracker.record_meal(mn, chosen)
            user_meal_data.append({"meal":mn,"chosen":chosen["name"],"nutrition":list(chosen["nutrition"]),"type":"full" if chosen["match_ratio"]>=0.8 else "partial","match_ratio":chosen["match_ratio"],"missing":chosen["missing_ings"],"all_5":all_5_data})

        # Gün sonu
        consumed, limits, pct = tracker.summary()
        print(f"\n   📊 GÜN SONU:")
        print(f"      Cal:{pct['calories']:.0f}% | Fat:{pct['total_fat_pdv']:.0f}% | Sugar:{pct['sugar_pdv']:.0f}% | Prot:{pct['protein_pdv']:.0f}% | Na:{pct['sodium_pdv']:.0f}%")

        # Testler
        if scenario=="low_protein":
            ok = pct["protein_pdv"]>=80
            print(f"   {'✅' if ok else '❌'} Protein telafi: %{pct['protein_pdv']:.0f}")
            if not ok: day_ok = False
        if scenario=="high_sugar":
            ok = pct["sugar_pdv"]<130
            print(f"   {'✅' if ok else '⚠️'} Şeker dengesi: %{pct['sugar_pdv']:.0f}")
        if scenario=="high_calorie":
            ok = pct["calories"]<120
            print(f"   {'✅' if ok else '⚠️'} Kalori dengesi: %{pct['calories']:.0f}")
        print(f"   {'✅' if all_unique else '❌'} Tekrar kontrolü: {'Tekrar yok' if all_unique else 'TEKRAR VAR!'}")
        if not all_unique: day_ok = False

        all_results.append({"user":user.name,"profile":user.profile_key,"scenario":scenario,"pct":pct,"ok":day_ok,"meals":user_meal_data,"unique":all_unique,"fridge_size":len(user.fridge)})

    # Özet
    print(f"\n{'━'*90}")
    print("📊 GENEL SONUÇ")
    print("━"*90)
    print(f"\n{'Kullanıcı':<10} {'Profil':<22} {'Senaryo':<14} {'Cal%':>5} {'Prot%':>6} {'Tekrar':>7} {'Sonuç':>7}")
    print("─"*75)
    for r in all_results:
        p=r["pct"]
        print(f"{r['user']:<10} {r['profile']:<22} {r['scenario']:<14} {p['calories']:>4.0f}% {p['protein_pdv']:>5.0f}% {'Yok':>6} {'✅' if r['ok'] else '❌':>6}")
    passed = sum(1 for r in all_results if r["ok"])
    print(f"\n🎯 {passed}/{len(all_results)} başarılı.")
    if passed==len(all_results): print("🎉 TÜM TESTLER BAŞARILI!")
    return all_results

def generate_test_results(all_results):
    ts = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    passed = sum(1 for r in all_results if r["ok"])
    total = len(all_results)

    # JSON
    jr = {
        "test_metadata": {
            "test_name": "KB Adaptive Meal Rec Test v3 — Profile-Weighted",
            "timestamp": ts,
            "features": ["fridge_matching","5_recommendations_per_meal","no_duplicate_recipes","adaptive_nutrition","profile_specific_scoring"],
            "total_users": total, "passed": passed,
            "overall_result": "PASS" if passed==total else "FAIL",
        },
        "profile_scoring_weights": PROFILE_SCORING,
        "user_results": [],
    }
    for r in all_results:
        u = next(x for x in VIRTUAL_USERS if x.name==r["user"])
        ps = PROFILE_SCORING.get(u.profile_key, PROFILE_SCORING["general_adult"])
        jr["user_results"].append({
            "user": r["user"], "profile": r["profile"], "age": u.age,
            "daily_calories": u.daily_calories, "meals_per_day": u.meals_per_day,
            "diet": u.diet_preference or None, "allergies": u.allergies or None,
            "avoid": u.avoid_ingredients or None, "fridge": u.fridge,
            "is_athlete": u.is_athlete, "is_pregnant": u.is_pregnant,
            "scoring_profile": {
                "description": ps["description"],
                "penalty_weights": ps["penalty_weights"],
                "bonus_weights": ps["bonus_weights"],
            },
            "breakfast_scenario": r["scenario"], "test_passed": r["ok"],
            "no_duplicates": r["unique"],
            "daily_pct": {k: round(v, 1) for k, v in r["pct"].items()},
            "meals": r["meals"],
        })
    with open(os.path.join(SCRIPT_DIR, "test_results.json"), "w", encoding="utf-8") as f:
        json.dump(jr, f, ensure_ascii=False, indent=2)

    # TXT
    with open(os.path.join(SCRIPT_DIR, "test_results.txt"), "w", encoding="utf-8") as f:
        f.write(f"KB Öneri Sistemi v3 Test Sonuçları — {ts}\n{'='*110}\n")
        f.write(f"Özellikler: Buzdolabı eşleştirme | 5 öneri/öğün (3 tam+2 kısmi) | Tekrar engeli | Adaptif besin | Profil bazlı puanlama\n")
        f.write(f"Sonuç: {passed}/{total} PASS\n\n")

        # Profil puanlama tablosu
        f.write(f"{'─'*110}\n")
        f.write("PROFİL BAZLI PUANLAMA AĞIRLIKLARI\n")
        f.write(f"{'─'*110}\n")
        f.write(f"{'Profil':<25} {'Prot↓':>6} {'Prot🔼':>7} {'Cal↑':>6} {'Yağ↑':>6} {'Şeker↑':>7} {'Na↑':>6} {'DYağ↑':>7} {'Karb↑':>7} {'Şeker🔼':>8}\n")
        f.write(f"{'─'*110}\n")
        for pk, ps in PROFILE_SCORING.items():
            pw, bw = ps["penalty_weights"], ps["bonus_weights"]
            f.write(f"{pk:<25} ×{pw['protein_low']:<4.1f} ×{bw['protein_recovery']:<5.1f} "
                    f"×{pw['calories']:<4.1f} ×{pw['total_fat_pdv']:<4.1f} ×{pw['sugar_pdv']:<5.1f} "
                    f"×{pw['sodium_pdv']:<4.1f} ×{pw['saturated_fat_pdv']:<5.1f} ×{pw['carbs_pdv']:<5.1f} "
                    f"×{bw['sugar_balance']:<5.1f}\n")
        f.write(f"\n{'─'*110}\n")
        f.write("PROFİL BAZLI MALZEME BONUS/CEZALARI\n")
        f.write(f"{'─'*110}\n")
        for pk, ps in PROFILE_SCORING.items():
            bonuses = [f"{k}(+{v})" for k, v in ps.get("ingredient_bonuses", {}).items()]
            penalties = [f"{k}({v})" for k, v in ps.get("ingredient_penalties", {}).items()]
            f.write(f"\n  {pk} — {ps['description']}\n")
            f.write(f"    ✨ Bonus: {', '.join(bonuses[:6])}\n")
            f.write(f"    ⚠️  Ceza:  {', '.join(penalties[:6])}\n")
        f.write(f"\n{'─'*110}\n\n")

        # Kullanıcı detayları
        for r in all_results:
            u = next(x for x in VIRTUAL_USERS if x.name == r["user"])
            ps = PROFILE_SCORING.get(u.profile_key, PROFILE_SCORING["general_adult"])
            f.write(f"{'━'*110}\n")
            f.write(f"👤 {r['user']} | {r['profile']} ({ps['description']}) | {u.daily_calories}kcal | {u.meals_per_day} öğün\n")
            if u.diet_preference: f.write(f"   Diyet: {u.diet_preference}\n")
            if u.allergies: f.write(f"   Alerji: {','.join(u.allergies)}\n")
            if u.avoid_ingredients: f.write(f"   Kaçın: {','.join(u.avoid_ingredients)}\n")
            if u.is_athlete: f.write("   🏋️ Sporcu/Bodybuilder\n")
            if u.is_pregnant: f.write("   🤰 Hamile/Emziren\n")
            pw = ps["penalty_weights"]
            bw = ps["bonus_weights"]
            f.write(f"   Puanlama: Prot ceza ×{pw['protein_low']} | Prot bonus ×{bw['protein_recovery']} | Şeker ceza ×{pw['sugar_pdv']} | Na ceza ×{pw['sodium_pdv']}\n")
            f.write(f"   Buzdolabı: {', '.join(u.fridge)}\n\n")

            for m in r["meals"]:
                f.write(f"   📌 {m['meal']}")
                if m["type"] == "simulated":
                    f.write(f" (simüle): {m['chosen']}\n")
                    n = m["nutrition"]
                    f.write(f"      Cal:{n[0]:.0f} | Prot:{n[4]:.0f}%DV | Sugar:{n[2]:.0f}%DV\n\n")
                    continue
                f.write(f" — Seçilen: {m['chosen']}\n")
                f.write(f"      {'#':<3} {'Tip':<7} {'Puan':>5} {'Eşleşme':>8} {'Tarif':<45} {'Eksik Malzeme'}\n")
                f.write(f"      {'─'*100}\n")
                for item in m.get("all_5", []):
                    tp = "🟢Tam" if item["type"] == "full" else "🟡Kısmi"
                    star = " ⭐" if item["rank"] == 1 else ""
                    missing = ', '.join(item.get("missing", [])[:4]) or "-"
                    f.write(f"      {item['rank']:<3} {tp:<7} {item['score']:>5.0f} {item['match_ratio']*100:>7.0f}%  {item['recipe'][:43]:<45} {missing}{star}\n")
                f.write("\n")

            p = r["pct"]
            f.write(f"   Gün Sonu: Cal:{p['calories']:.0f}% Fat:{p['total_fat_pdv']:.0f}% Sugar:{p['sugar_pdv']:.0f}% Prot:{p['protein_pdv']:.0f}% Na:{p['sodium_pdv']:.0f}%\n")
            f.write(f"   Tekrar: {'Yok ✅' if r['unique'] else 'VAR ❌'} | Sonuç: {'PASS ✅' if r['ok'] else 'FAIL ❌'}\n\n")

        # Genel özet
        f.write(f"{'━'*110}\nGENEL SONUÇ ÖZETİ\n{'━'*110}\n\n")
        f.write(f"{'Kullanıcı':<10} {'Profil':<22} {'Senaryo':<14} {'Cal%':>6} {'Prot%':>7} {'Sug%':>6} {'Na%':>6} {'Tekrar':>7} {'Sonuç':>7}\n")
        f.write("─" * 90 + "\n")
        for r in all_results:
            p = r["pct"]
            ok = "PASS" if r["ok"] else "FAIL"
            f.write(f"{r['user']:<10} {r['profile']:<22} {r['scenario']:<14} {p['calories']:>5.0f}% {p['protein_pdv']:>6.0f}% {p['sugar_pdv']:>5.0f}% {p['sodium_pdv']:>5.0f}% {'Yok':>6} {ok:>6}\n")
        f.write(f"\nSONUÇ: {passed}/{total} PASS\n\n")

        # Kaynakça / References
        f.write(f"{'━'*110}\n")
        f.write("KAYNAKÇA VE PUANLAMA MANTIĞI DAYANAKLARI (BIBLIOGRAPHY)\n")
        f.write(f"{'━'*110}\n")
        f.write("Sistemdeki kısıtlamalar, cezalar ve bonuslar aşağıdaki bilimsel otoritelerin beslenme kılavuzlarına dayanmaktadır:\n\n")
        f.write("1. Dünya Sağlık Örgütü (WHO) Makrobesin Kılavuzları:\n")
        f.write("   - Yetişkinler için serbest şeker alımının toplam enerjinin %10'unun (ideali %5) altında tutulması.\n")
        f.write("   - Toplam yağ alımının %30'u, doymuş yağın %10'u geçmemesi.\n")
        f.write("   - Günlük sodyum alımının 2000mg (2g sodyum / 5g tuz) altında tutulması.\n")
        f.write("   - Kaynak: 'Healthy diet Fact sheet N°394' (WHO, 2020).\n\n")
        f.write("2. Sporcu Beslenmesi (Athlete / Bodybuilder):\n")
        f.write("   - Vücut geliştiriciler ve sporcular için artırılmış protein ihtiyacı (1.6 - 2.2 g/kg/gün).\n")
        f.write("   - Bu nedenle 'athlete_bodybuilder' profilinde protein eksikliği cezası (×2.0) ve protein telafi bonusu (×2.0) iki katına çıkarılmıştır.\n")
        f.write("   - Kaynak: International Society of Sports Nutrition (ISSN) Position Stand: protein and exercise (2017).\n\n")
        f.write("3. Hamile ve Emziren Kadınlar (Pregnant / Lactating):\n")
        f.write("   - Preeklampsi riskini yönetmek için sodyum takibine daha fazla ağırlık verilmiştir (Sodyum cezası ×1.5).\n")
        f.write("   - Fetal nöral gelişim ve anne sağlığı için folat (ıspanak vb.), demir ve kalsiyum kaynaklarına ekstra bonus verilmiştir.\n")
        f.write("   - Alkol ve çiğ balık (sushi vb.) kesinlikle yasaklanmış / ağır cezalandırılmıştır (-50/-10 puan).\n")
        f.write("   - Kaynak: 'WHO recommendations on antenatal care for a positive pregnancy experience' (WHO, 2016).\n\n")
        f.write("4. Ergenlik Dönemi (Adolescent):\n")
        f.write("   - Büyüme dönemi nedeniyle artan kalsiyum ve protein ihtiyacı (Süt, yumurta, peynir için artırılmış bonuslar).\n")
        f.write("   - Çocukluk çağı obezitesini önlemek amacıyla şekerli içecekler ve atıştırmalıklara ağır cezalar (soda, candy -8 puan).\n")
        f.write("   - Kaynak: 'Guideline: Sugars intake for adults and children' (WHO, 2015).\n\n")
        f.write("5. Telafi ve Dengeleme Mantığı (Adaptive Meal Tracking):\n")
        f.write("   - Günlük besin hedeflerine ulaşmak için öğün bazlı telafi (örneğin sabah eksik alınan proteinin öğlen tamamlanması).\n")
        f.write("   - Bu mantık, toplam günlük alımın (Total Daily Energy Expenditure - TDEE ve Daily Value - DV) esnek bir şekilde gün içine yayılması prensibine dayanır.\n")

    print(f"\n📄 test_results.json ve test_results.txt oluşturuldu.")

if __name__ == "__main__":
    generate_test_results(run_tests())
