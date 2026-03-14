# Environment Setup

## Backend

Start from `backend/catalog_backend/.env.example`.

Required for production:
- `APP_ENV=production`
- `ENFORCE_PROD_GUARDS=true`
- strong `JWT_SECRET`
- strong `ADMIN_PASSWORD`
- real `POSTER_API_TOKEN`
- real `POSTER_ACCOUNT` if required

Optional push configuration:
- `PUSH_NOTIFICATIONS_ENABLED=false` for no-push deployments
- `PUSH_NOTIFICATIONS_ENABLED=true` plus:
  - `FIREBASE_PROJECT_ID`
  - `FIREBASE_SERVICE_ACCOUNT_FILE` or `FIREBASE_SERVICE_ACCOUNT_JSON`

## Android

Default production application id:
- `uz.sushixl.app`

Signing sources, in priority order:
1. `mobile/android/key.properties`
2. Environment variables:
   - `SUSHIXL_STORE_FILE`
   - `SUSHIXL_STORE_PASSWORD`
   - `SUSHIXL_KEY_ALIAS`
   - `SUSHIXL_KEY_PASSWORD`

Yandex Maps key source:
- `YANDEX_MAPS_API_KEY` from Gradle property, environment variable, or `local.properties`

## iOS

Copy `mobile/ios/Flutter/ReleaseConfig.xcconfig.example` to `mobile/ios/Flutter/ReleaseConfig.xcconfig` and set:
- `SUSHIXL_BUNDLE_ID`
- `SUSHIXL_DEVELOPMENT_TEAM`
- `YANDEX_MAPS_API_KEY`
- `APS_ENVIRONMENT`

Then complete signing in Xcode with your Apple Developer account.

## Firebase Mobile Config

The repo contains tracked Firebase mobile config files only as placeholders for project wiring.
Before enabling push or publishing to stores, replace them with Firebase config files downloaded for the production app ids:
- Android: `mobile/android/app/google-services.json`
- iOS: `mobile/ios/Runner/GoogleService-Info.plist`
