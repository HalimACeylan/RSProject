# Fridge App

A streamlined Flutter application to manage your fridge inventory and surface recipe suggestions based on what's on hand.

## Getting Started

### 1. Prerequisites
Install the [Flutter SDK](https://docs.flutter.dev/get-started/install).

### 2. Setup & Run
```bash
flutter clean        # Required after a fresh clone
flutter pub get      # Fetch dependencies
flutter run          # Launch on the connected device
```

## Architecture

All data is stored locally in a SQLite database that ships with the app at `assets/fridge_app.db`. On first launch, `DatabaseService` copies the asset into the platform's databases directory and opens it. There is no backend.

The asset DB is built offline from the CSVs in `datasets_to_use/`:

```bash
dart run scripts/build_db.dart
```

Run `flutter clean` after rebuilding the asset so Flutter picks up the new bundle.

### Inspecting the live app DB

By default, the app copies `assets/fridge_app.db` into the platform sandbox on first launch and writes to that copy. For development you can point the app at the asset file directly so external scripts can read the same DB:

```bash
flutter run -d macos --dart-define=DB_FILE=$(pwd)/assets/fridge_app.db
```

Then, while the app is running:

```bash
python3 datasets_to_use/inspect_app_state.py            # dump fridge / logs / user profile
python3 datasets_to_use/inspect_app_state.py --recs     # also rank top KB picks for the saved user
```

Desktop only — mobile asset bundles are read-only at runtime.
