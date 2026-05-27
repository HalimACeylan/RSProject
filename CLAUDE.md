# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Flutter app (`fridge_app`, Dart SDK ^3.11.0) that manages a fridge inventory and recommends recipes based on what's on hand. Targets iOS, Android, macOS, Linux, Windows, and Web from a single codebase. All data is local SQLite — no backend (a separate Python CF recommender service is optional, see below).

## Commands

```bash
flutter pub get                          # Install dependencies
flutter run                              # Run the app
flutter run -d chrome                    # Run on web
flutter analyze                          # Lint
flutter test                             # Run all tests
flutter test test/database_service_test.dart  # Run a single test file
flutter clean                            # Required after a fresh clone or asset/db changes

# Rebuild the shipped SQLite asset from CSV datasets (must be run from repo root):
dart run scripts/build_db.dart

# Inspect the live app DB (run while the app is open with DB_FILE override below):
python3 datasets_to_use/inspect_app_state.py            # dump fridge / logs / profile
python3 datasets_to_use/inspect_app_state.py --recs     # also rank top KB picks
```

After modifying `assets/fridge_app.db` or anything else in `assets/`, run `flutter clean` before the next `flutter run` — Flutter caches asset bundles aggressively.

## Architecture

### Service initialization order (lib/main.dart)
`main()` runs these steps before `runApp()`:
1. `initDbFactory()` — selects the right sqflite backend for the current platform.
2. `DatabaseService.instance.initialize()` — opens the SQLite DB.
3. `UserProfileService.instance.initialize()` — loads the single saved profile row (if any).
4. `FridgeService.instance.initialize()` — loads fridge items.
5. `RecipeService.instance.initialize()` is fired with `unawaited(...)` — it loads ~20k recipes off the critical path. Screens that need the cache `await RecipeService.instance.ready`.

If `UserProfileService.instance.hasProfile` is false, `MaterialApp` starts on `welcomeLogin`; otherwise it starts on `insideFridge`.

All services are singletons (`ClassName.instance`). They are NOT injected — screens reach for them directly. Don't add DI without changing every screen.

### Platform-conditional SQLite factory
`lib/services/db_factory.dart` uses Dart's conditional export pattern:
- `db_factory_native.dart` (when `dart.library.io` is available) — uses `sqflite_common_ffi` on macOS/Linux/Windows; default sqflite on iOS/Android.
- `db_factory_web.dart` (when `dart.library.js_interop` is available) — uses `sqflite_common_ffi_web` (SQLite-on-WASM).
- `db_factory_stub.dart` — no-op fallback.

If you add a new platform-specific service, follow this same conditional-export pattern instead of runtime `Platform.is*` checks at call sites.

### Pre-populated database asset
The SQLite DB ships as `assets/fridge_app.db` and is listed in `pubspec.yaml` under `flutter.assets`. On first launch, `DatabaseService.initialize()` copies it from the bundle to the platform's databases directory via `databaseFactory.writeDatabaseBytes`. Subsequent launches open it in place.

The asset is built offline by `scripts/build_db.dart`, which imports CSVs from `datasets_to_use/`:
- `daily_food_nutrition_dataset.csv` → `food_items`
- `RAW_recipes_filtered.csv` → `recipes`, `recipe_steps`, `recipe_ingredients` (Python-list-literal strings parsed via `_parsePythonList`)
- `synthetic_interactions.csv` → `user_interactions`

Schema also includes `fridge_items`, `consumption_logs`, and `users` (user-written, empty in the shipped asset). `DatabaseService.initialize()` runs `CREATE TABLE IF NOT EXISTS` for `consumption_logs` + `users`, and `_migrateFridgeItemsColumns()` for `fridge_items`, as a safety net for assets built against an older schema. Loaded recipes are loaded into `RecipeService` via three batched queries (recipes / ingredients / steps) — not N+1 sub-queries.

### `DB_FILE` override and per-platform DB locations
Pass `--dart-define=DB_FILE=$(pwd)/assets/fridge_app.db` to make the app open the asset file directly instead of copying it to the OS sandbox. Reliable on macOS/Linux/Windows desktop. **iOS Simulator and Android emulators have their own sandbox** — `DB_FILE` will be honored if the sandboxed process can reach the host path, but in practice you should expect:

| Platform | Where writes go (no override) | DB_FILE works? |
|---|---|---|
| macOS / Linux / Windows | `~/Library/Containers/.../Documents/fridge_app.db` (or similar) | Yes |
| iOS Simulator | `~/Library/Developer/CoreSimulator/Devices/<uuid>/data/Containers/Data/Application/<uuid>/Documents/fridge_app.db` | Sometimes — try it, fall back to inspecting the sandbox path |
| Real iOS device | App sandbox on device | No — truly sealed |
| Android emulator | `/data/data/<package>/databases/fridge_app.db` | No — use `adb pull` to copy out |

The app prints the resolved path in a `[DB]` banner at startup. To inspect from external tools, copy that path into DBeaver, or use `python3 datasets_to_use/inspect_app_state.py` if it's the asset file.

`datasets_to_use/inspect_app_state.py` is a read-only dumper for the live DB; pass `--recs` to also rank the top KB picks for the saved user (slim Python port of `KbRecommenderService`).

### Recommender pipeline
`RecommendationService.getRecommendations()` returns a `RecommendationBundle` blending two sources:
1. **KB (`KbRecommenderService`)** — pure Dart port of `datasets_to_use/test_kb_recommendations.py`. Scoring constants live in `lib/services/kb_constants.dart` (WHO `MacroRules`, per-profile `ProfileScoring` weights, allergy keyword map). Slot allocation: 3 full-match (≥0.8 ingredient ratio) + 2 partial (0.3–0.8).
2. **CF (`CfRecommenderClient`)** — HTTP client for the optional Python FastAPI service in `cf_server/`. 3-second timeout, returns `null` on any failure, never throws to the caller. When `null`, the bundle is KB-only and the UI surfaces "CF service offline — KB only".

To enable CF: `cd cf_server && pip install -r requirements.txt && uvicorn server:app --port 8000`. Android emulator quirk: the Dart client uses `10.0.2.2:8000` on Android, `localhost:8000` elsewhere.

### Routing
All routes are declared in `lib/routes.dart` as static constants on `AppRoutes`, and `AppRoutes.routes` is the single map passed to `MaterialApp`. Add new screens here, not via `onGenerateRoute`.

### Recipe matching
`RecipeService.getSuggestedRecipes()` is the only place that computes "missing ingredients" — it cross-references each recipe's ingredients against the current `FridgeService` inventory using substring matching in both directions (`fridgeName.contains(ingName) || ingName.contains(fridgeName)`). The same bidirectional substring rule is used by `KbRecommenderService.ingredientMatch`.

### Ingredient emoji thumbnails
DB-loaded recipes have no images. `lib/widgets/ingredient_thumbnail.dart` renders 1–4 emoji collage on a pastel background derived from the first emoji. The emoji map (`lib/utils/ingredient_emoji.dart`) is keyword-substring based — order matters in the entries list (more specific keywords first, e.g. `eggplant` before `egg`).
