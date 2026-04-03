# Trusted Tracker (Flutter + Firebase)

**Trusted Tracker** is a consent-based personal locator prototype (Life360-style).  
Two trusted users can share location through a cloud **middleware** (Firebase Firestore), view each other on a map, and receive a **safe-zone (geofence) exit alert**.

## Key Features (Prototype)
- **Consent-based sharing**: Start/Stop sharing with clear UI status
- **Real-time sync via middleware**: User A ⇄ **Firestore** ⇄ User B
- **Map view**: Shows both users with “Jump to A/B”
- **Safe Zone**: Set center + radius; alert on exit
- **Audit trail**: Logs tab records actions and alerts (timestamps)

## Tech Stack
- Flutter (Dart)
- Firebase: Firestore (and Authentication in final hardening)
- `flutter_map` + OpenStreetMap tiles
- Android Emulator for mobile testing

## Architecture (High-Level)
- **Clients**: Two Flutter apps (User A and User B)
- **Middleware/Backend**: Firebase Firestore
- **Data**:
  - `locations/{id}` → `{ lat, lng, ts, sharing }`
  - `zones/{ownerId}` → `{ target, lat, lng, radiusM, ts }`

> Note: A and B do **not** communicate directly. They exchange updates through Firestore.

## Project Structure
- `lib/` → main Dart code (UI + logic)
- `android/` → Android wrapper (permissions/build)
- `web/` → Web wrapper
- `pubspec.yaml` → dependencies

## How to Run (Web / Chrome)
```bash
flutter clean
flutter pub get
flutter run -d chrome


## How to Run (App / Android) # Example id: emulator-5554
```bash
flutter clean
flutter pub get
flutter devices
flutter run -d emulator-5554