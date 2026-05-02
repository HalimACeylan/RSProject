# Fridge App

A streamlined Flutter application to manage your fridge inventory.

## Getting Started

If you are a new developer who has just cloned the application, you can get it up and running in a few simple steps. The app is configured to use **mock data** by default, meaning you do not need to configure Firebase to test the application.

### 1. Prerequisites
Ensure you have the [Flutter SDK](https://docs.flutter.dev/get-started/install) installed.

### 2. Setup & Run
Run the following commands in your terminal at the root of the project:

```bash
# 1. Clean any stale build files (crucial after a fresh clone)
flutter clean

# 2. Get the necessary packages
flutter pub get

# 3. Run the app
flutter run
```

## Architecture & Mock Data

To make onboarding easy, the app does not strictly require a backend to run. Because the Firebase configuration file (`firebase_options.dart`) is not committed to source control for security reasons, the app is designed to gracefully fall back to **in-memory mock data**.

When you run the app, it will attempt to initialize Firebase. If it fails or the configuration is missing, services like `FridgeService` will automatically load mock files/sample items. This allows you to immediately interact with the UI, view items, and test the basic logic without spending time on backend setup.

### Sample Data Modes

If you eventually connect the app to Firebase, you can control how the sample data behaves using run-time variables:

```bash
flutter run --dart-define=FIREBASE_SEED_MODE=if-empty   # Seeds sample data only if cloud is empty (default)
flutter run --dart-define=FIREBASE_SEED_MODE=overwrite  # Replaces active cloud data with sample data
flutter run --dart-define=FIREBASE_SEED_MODE=skip       # Skips seeding entirely
```

## Firebase Backend (Optional Setup)

If you wish to connect your own Firebase project:

1. Create a Firebase project and add a Flutter app via the Firebase Console.
2. Run `flutterfire configure` at the root of this project to generate `lib/firebase_options.dart`.
3. Enable **Anonymous** Authentication in the Firebase Console (`Authentication > Sign-in method > Anonymous`).
4. Deploy the necessary Firestore rules and indexes:
   ```bash
   firebase deploy --only firestore:rules,firestore:indexes
   ```
