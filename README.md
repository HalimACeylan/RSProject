# Fridge App

A cross-platform Flutter app that manages a fridge inventory and recommends recipes the user can actually cook from what they have on hand. Recommendations are produced by a two-layer hybrid recommender:

- **Knowledge-Based (Dart, in-app)** — fridge ingredient match, WHO/ISSN profile-based macro scoring, allergy and diet disqualification, an adaptive daily nutrient tracker, and a 3-full + 2-partial slot allocation per meal.
- **Collaborative Filtering (Python FastAPI)** — TF-IDF taste vectors over recipe ingredients, cosine similarity over 600 synthetic users, top-20 neighbor weighting, plus a serendipity bonus that nudges the user out of their filter bubble.

All persistent state (profile, fridge inventory, consumption logs, cooked/dismissed recipes) lives in a local SQLite database. There is no cloud backend.

## Targets

iOS, Android, macOS, Linux, Windows, Web — single Dart codebase. The SQLite driver is selected at compile time per platform (`sqflite` on mobile, `sqflite_common_ffi` on desktop, `sqflite_common_ffi_web` on web).

---

## Quick Start

### 1. Prerequisites

- [Flutter SDK](https://docs.flutter.dev/get-started/install) (Dart `^3.11`)
- A connected device or simulator (`flutter devices`)
- Python 3.10+ for the Collaborative Filtering service

### 2. Start the Collaborative Filtering service

In one terminal, set up and launch the FastAPI service. The first request triggers a one-time data load (≈5–10 s); subsequent requests respond in ~100 ms.

```bash
cd cf_server
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
uvicorn server:app --host 0.0.0.0 --port 8000
```

Verify it is up:

```bash
curl http://localhost:8000/health
# {"ok":true,"recipes":20000,"users":600,"profile_tags":["healthy_eater","meat_lover", ...]}
```

The Dart client expects:
- **Desktop / iOS simulator** → `http://localhost:8000`
- **Android emulator** → `http://10.0.2.2:8000` (Android's loopback to the host)

### 3. Run the app

In a second terminal:

```bash
flutter clean         # required after a fresh clone or asset/db changes
flutter pub get       # fetch dependencies
flutter run           # launch on the default device
```

Or pick a specific device:

```bash
flutter run -d <device_uuid>
flutter run -d chrome
flutter run -d macos
```

Each meal slot is filled by `3 KB-full + 2 CF + KB-partial overflow + KB-full overflow` (deduped, top 5).

---

## What Ships in the Repo

```
.
├── lib/                      # Flutter app
│   ├── main.dart             # service init order + root MaterialApp
│   ├── routes.dart           # 10 screen routes
│   ├── models/               # UserProfile, Recipe, FridgeItem, MealSlot, ...
│   ├── services/
│   │   ├── database_service.dart       # SQLite open, asset copy, WAL mode
│   │   ├── db_factory*.dart            # per-platform sqflite selection
│   │   ├── fridge_service.dart         # fridge_items CRUD
│   │   ├── recipe_service.dart         # loads ~20k recipes off the critical path
│   │   ├── user_profile_service.dart   # users table, single saved profile
│   │   ├── cooking_service.dart        # cooked_recipes writes
│   │   ├── dismissal_service.dart      # dismissed_recipes
│   │   ├── kb_constants.dart           # WHO macro rules + profile bonus/penalty maps
│   │   ├── kb_recommender_service.dart # KB engine (Dart port of Python reference)
│   │   ├── cf_recommender_client.dart  # HTTP client for the CF service
│   │   └── recommendation_service.dart # KB+CF blend per meal slot
│   ├── screens/              # WelcomeLogin, InsideFridge, FridgeGrid,
│   │                         # FoodItemDetails, AddIngredients, ManualEntry,
│   │                         # LogConsumption, SuggestedRecipes, RecipeVoting,
│   │                         # RecipePreparationGuide
│   └── widgets/              # FridgeHeader, IngredientThumbnail,
│                             # RecipeRatingBottomSheet, UserPickerBottomSheet, ...
│
├── assets/
│   └── fridge_app.db         # pre-built SQLite asset (~23 MB, 10 tables, 20k recipes)
│
├── scripts/
│   └── build_db.dart         # CSV → SQLite asset builder
│
├── cf_server/
│   ├── server.py             # FastAPI service exposing /health and /recommend
│   ├── requirements.txt      # FastAPI, uvicorn, pandas, numpy, scikit-learn
│   └── README.md
│
└── datasets_to_use/
    ├── RAW_recipes_filtered.csv          # 20k recipes from Food.com, nutrition-validated
    ├── daily_food_nutrition_dataset.csv  # 650-entry ingredient/category dictionary
    ├── synthetic_interactions.csv        # 600 synthetic users × 19,360 ratings
    ├── who_daily_nutrient_guidelines.json # WHO + ISSN macro rules per profile
    ├── generate_synthetic_interactions.py # the script that built the CF training set
    ├── inspect_app_state.py              # read-only dumper for the live app DB
    ├── test_kb_recommendations.py        # Python reference for KB scoring
    ├── test_ml_recommendations.py        # Python reference for CF
    ├── test_boundary_cf_recommendations.py
    └── combined_recommender_demo.py
```

---

## Database

The shipped asset DB contains ten tables, divided into a read-only asset layer and a runtime layer the app writes to:

| Layer   | Table                | Purpose                                                              |
| ------- | -------------------- | -------------------------------------------------------------------- |
| Asset   | `food_items`         | ingredient/category dictionary used by Add Ingredients search        |
| Asset   | `recipes`            | 20k recipes (id, name, minutes, tags, 7-element nutrition, counts)   |
| Asset   | `recipe_steps`       | per-recipe ordered instruction list                                  |
| Asset   | `recipe_ingredients` | per-recipe ingredient list                                           |
| Asset   | `user_interactions`  | synthetic ratings used as CF training data                           |
| Runtime | `users`              | single saved profile (profile_key, age, sex, is_pregnant, allergens) |
| Runtime | `fridge_items`       | current inventory                                                    |
| Runtime | `consumption_logs`   | Log Consumption screen writes                                        |
| Runtime | `cooked_recipes`     | feeds DailyTracker and CF's `liked_recipe_ids`                       |
| Runtime | `dismissed_recipes`  | permanent "don't suggest again" filter                               |

### Rebuilding the asset DB

If you change a CSV in `datasets_to_use/` or modify the schema in `scripts/build_db.dart`, rebuild the asset DB and re-run with a clean bundle:

```bash
dart run scripts/build_db.dart
flutter clean
flutter run
```

### Inspecting the live DB

Point the running app at the asset file directly so external tools can read it concurrently (WAL mode is enabled). Desktop only — mobile sandboxes are sealed:

```bash
flutter run -d macos --dart-define=DB_FILE=$(pwd)/assets/fridge_app.db
```

While the app is running, dump state with the read-only inspector:

```bash
python3 datasets_to_use/inspect_app_state.py            # fridge / logs / profile
python3 datasets_to_use/inspect_app_state.py --recs     # also rank top KB picks
```

---

## Recommender Profiles

Four nutritional profiles map to four `scoringKey` values that drive the KB scoring rules. `pregnant` is derived at runtime from the `is_pregnant` boolean on the user row, so it composes with any of the other three.

| Profile (`scoringKey`) | Driver                                  | Macro rule highlights                              |
| ---------------------- | --------------------------------------- | -------------------------------------------------- |
| `general_adult`        | Balanced reference                      | protein ≥15%, sodium ≤2000 mg/day                  |
| `athlete_bodybuilder`  | High protein, muscle recovery           | protein ≥25%, candy/soda heavily penalised         |
| `adolescent`           | Growth, calcium                         | protein ≥18%, milk/yogurt bonus, sugar penalty 1.5 |
| `pregnant`             | `is_pregnant=true` overlay              | sodium ≤1800 mg, alcohol −50, raw fish −10         |

For the CF cold-start path the request body accepts a `profile_tag` from a separate set of six taste-clustering tags: `meat_lover`, `vegetarian`, `pescatarian`, `sweet_tooth`, `healthy_eater`, `spicy_lover`.

---

## Tests

```bash
flutter test                                                # all Dart tests
flutter test test/database_service_test.dart                # single file

python3 datasets_to_use/test_kb_recommendations.py          # KB regression
python3 datasets_to_use/test_ml_recommendations.py          # CF sanity check
python3 datasets_to_use/test_boundary_cf_recommendations.py # CF edge cases
```

The KB regression runs ten synthetic users across the four profile types and validates ingredient matching, slot allocation, no-duplicate enforcement, adaptive nutrient limits, profile-specific bonus/penalty application, and dietary disqualification.

---

## Common Operations

| Task                                            | Command                                                                  |
| ----------------------------------------------- | ------------------------------------------------------------------------ |
| Start the CF service                            | `cd cf_server && uvicorn server:app --port 8000`                         |
| Run on a specific device                        | `flutter run -d <device_uuid>`                                           |
| Open DB asset directly (desktop dev mode)       | `flutter run -d macos --dart-define=DB_FILE=$(pwd)/assets/fridge_app.db` |
| Lint                                            | `flutter analyze`                                                        |
| Run all tests                                   | `flutter test`                                                           |
| Rebuild SQLite asset from CSVs                  | `dart run scripts/build_db.dart`                                         |
| Dump live app state from outside the app        | `python3 datasets_to_use/inspect_app_state.py`                           |
| Force-clean Flutter caches (after asset change) | `flutter clean`                                                          |
