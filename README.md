# Sushi-XL

Sushi-XL is a production-oriented food ordering platform with three codebases in one repository:

- `backend/` - FastAPI APIs, admin/auth endpoints, Poster integration, and notification delivery.
- `frontend/admin-panel/` - lightweight admin panel served as static assets.
- `mobile/` - Flutter client for Android and iOS.

## Repository Structure

- `backend/catalog_backend/` - primary API and database-backed business logic.
- `backend/backend_proxy/` - supporting proxy service.
- `backend/scripts/run_stack.sh` - local backend + admin launcher.
- `frontend/admin-panel/` - admin UI.
- `mobile/` - Flutter app.
- `docs/RELEASE_CHECKLIST.md` - manual release checklist.
- `docs/ENVIRONMENT_SETUP.md` - environment and credential setup.
- `scripts/release_audit.sh` - local release-readiness audit.

## Local Development

### Backend + Admin

```bash
cd /path/to/Sushi-Xl
cp backend/catalog_backend/.env.example backend/catalog_backend/.env
./backend/scripts/run_stack.sh
```

Services:
- Backend: `http://127.0.0.1:8010`
- Admin panel: `http://127.0.0.1:5174`

### Mobile App

```bash
cd /path/to/Sushi-Xl/mobile
flutter pub get
flutter run
```

## Production Configuration

### Android release signing

1. Copy `mobile/android/key.properties.example` to `mobile/android/key.properties`
2. Provide your real keystore path and passwords
3. Or provide the same values via environment variables:
   - `SUSHIXL_STORE_FILE`
   - `SUSHIXL_STORE_PASSWORD`
   - `SUSHIXL_KEY_ALIAS`
   - `SUSHIXL_KEY_PASSWORD`

Default production Android package id:
- `uz.sushixl.app`

### iOS release signing

1. Copy `mobile/ios/Flutter/ReleaseConfig.xcconfig.example` to `mobile/ios/Flutter/ReleaseConfig.xcconfig`
2. Set:
   - `SUSHIXL_BUNDLE_ID`
   - `SUSHIXL_DEVELOPMENT_TEAM`
   - `YANDEX_MAPS_API_KEY`
   - `APS_ENVIRONMENT`
3. Open `mobile/ios/Runner.xcworkspace` in Xcode
4. Select the correct Apple team, signing certificate, and provisioning profile

Default production iOS bundle id:
- `uz.sushixl.app`

### Push notifications

Push is explicitly controlled by backend config.

- `PUSH_NOTIFICATIONS_ENABLED=false` disables push cleanly.
- `PUSH_NOTIFICATIONS_ENABLED=true` requires Firebase HTTP v1 credentials:
  - `FIREBASE_PROJECT_ID`
  - `FIREBASE_SERVICE_ACCOUNT_FILE` or `FIREBASE_SERVICE_ACCOUNT_JSON`

Legacy `FCM_SERVER_KEY` is retained only as a temporary compatibility path and is not the recommended production setup.

## Release Gates

Run the local audit before every release:

```bash
./scripts/release_audit.sh
```

CI also runs:
- backend Python compile checks
- admin-panel JavaScript syntax checks
- `flutter analyze`
- `flutter test`

## Important Security Rules

Do not commit:
- `.env` files
- Android `key.properties`
- `.jks` / `.keystore` files
- Firebase service-account JSON files
- local/generated Flutter iOS config files

## Publishing

Follow the full checklist in [docs/RELEASE_CHECKLIST.md](docs/RELEASE_CHECKLIST.md).
