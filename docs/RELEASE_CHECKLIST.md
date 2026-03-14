# Release Checklist

## Code and CI

- [ ] `./scripts/release_audit.sh` passes locally
- [ ] GitHub Actions `release-readiness` workflow passes
- [ ] `flutter analyze` passes
- [ ] `flutter test` passes
- [ ] backend health endpoint returns expected production values

## Backend

- [ ] `backend/catalog_backend/.env` uses production values
- [ ] `JWT_SECRET` is strong and unique
- [ ] `ADMIN_PASSWORD` is strong and unique
- [ ] Poster credentials are real and validated
- [ ] `PUSH_NOTIFICATIONS_ENABLED` is intentionally set
- [ ] If push is enabled, Firebase HTTP v1 service account is configured
- [ ] `/health` shows no push misconfiguration for the intended mode

## Admin Panel

- [ ] admin login works
- [ ] product/category CRUD basics work
- [ ] banner CRUD works and reflects in app
- [ ] notification CRUD works and reflects in app
- [ ] settings and FAQ content are localized and saved

## Mobile Functional Smoke Test

- [ ] app launches cleanly
- [ ] language switching works for `uz`, `ru`, `en`
- [ ] menu loads from Poster-backed backend
- [ ] banners load and banner tap actions work
- [ ] cart works
- [ ] checkout/address flow works
- [ ] order creation works
- [ ] profile edit works
- [ ] support phone/chat/FAQ work

## Android Release

- [ ] `mobile/android/key.properties` or signing env vars are configured
- [ ] production keystore is available
- [ ] Play Store package id is confirmed: `uz.sushixl.app`
- [ ] Firebase Android config file matches the production package id
- [ ] `flutter build appbundle --release` succeeds

## iOS Release

- [ ] `mobile/ios/Flutter/ReleaseConfig.xcconfig` is created from the example file
- [ ] production Apple team is selected in Xcode
- [ ] signing certificate is valid
- [ ] provisioning profile is valid
- [ ] Firebase iOS config file matches the production bundle id
- [ ] Xcode Archive succeeds

## Final Publish Gate

- [ ] no secrets are committed
- [ ] no `com.example.*` placeholders remain in production app targets
- [ ] no debug signing is used for release builds
- [ ] store metadata/screenshots/privacy info are prepared
