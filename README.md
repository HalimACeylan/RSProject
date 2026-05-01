# fridge_app

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Firebase Backend

The app now uses authenticated users with household-scoped Firestore data.

### Auth + Bootstrap Flow

On startup:

1. App signs in with Firebase Auth (anonymous for now).
2. App ensures `users/{uid}` exists.
3. App ensures the user has `primaryHouseholdId`.
4. If missing, app creates:
   - `households/{householdId}`
   - `households/{householdId}/members/{uid}` as owner
   - `households/{householdId}/subscriptions/current`
   - `households/{householdId}/payments/payment_profile`
5. Fridge and receipts are read/written under that household.

Firebase Console requirement:

- Enable `Authentication > Sign-in method > Anonymous` (current bootstrap uses anonymous auth).

### Data Model

- `users/{uid}`
  - `primaryHouseholdId`, `role`, `status`, `planTier`, `billingStatus`
  - profile fields: `email`, `displayName`, `photoUrl`
  - auth metadata: `isAnonymous`, `authProviderIds`, timestamps
- `households/{householdId}`
  - ownership: `ownerUserId`, `memberCount`
  - SaaS: `planTier`, `billingStatus`, `billingCycle`, `seatLimit`
  - payment linkage: `stripeCustomerId`, `stripeSubscriptionId`
  - feature flags: `aiReceiptParsingEnabled`
- `households/{householdId}/members/{uid}`
  - `userId`, `role` (`owner/admin/member`), `status`, profile snapshot
- `households/{householdId}/fridge_items/{itemId}`
  - fridge item data + audit fields (`createdByUserId`, `updatedByUserId`)
- `households/{householdId}/receipts/{receiptId}`
  - receipt data + audit fields
- `households/{householdId}/subscriptions/current`
  - subscription status (`planId`, `status`, `interval`, `amountCents`, etc.)
- `households/{householdId}/payments/payment_profile`
  - billing profile (`customerId`, `defaultPaymentMethodId`, tax/billing fields)

### Seed Modes

Use `FIREBASE_SEED_MODE` at run-time:

- `if-empty` (default): seed sample data only if cloud is empty
- `overwrite`: replace active household fridge/receipt data with sample data
- `skip`: skip seeding and only read existing household data

Examples:

```bash
flutter run --dart-define=FIREBASE_SEED_MODE=if-empty
flutter run --dart-define=FIREBASE_SEED_MODE=overwrite
flutter run --dart-define=FIREBASE_SEED_MODE=skip
```

### Join Existing Household (Flutter)

To connect another signed-in user to an existing household:

```dart
await UserHouseholdService.instance.joinHousehold(
  existingHouseholdId,
  inviteCode: inviteCodeFromOwner,
);
await FridgeService.instance.refreshFromCloud();
await ReceiptService.instance.refreshFromCloud();
```

### Deploy Firestore Rules/Indexes

```bash
firebase deploy --only firestore:rules,firestore:indexes
```
