# Admin Panel Inventory (Before Extraction)

## Mobile app admin screens/routes/navigation
- mobile/lib/features/admin/adim_app.dart
- mobile/lib/app/router.dart
- mobile/lib/features/profile/profile_screen.dart

## Mobile admin models/services/state/cache
- mobile/lib/data/models/admin_models.dart
- mobile/lib/data/repositories/admin_repository.dart
- mobile/lib/core/state/catalog_providers.dart
- mobile/lib/core/state/providers.dart
- mobile/lib/core/cache/admin_panel_cache.dart

## Mobile components influenced by admin data/actions
- mobile/lib/features/home/home_screen.dart
- mobile/lib/features/mailing/mailings_screen.dart
- mobile/lib/features/support/support_screen.dart
- mobile/lib/features/support/support_chat_screen.dart
- mobile/lib/core/cache/report_events_cache.dart
- mobile/lib/core/cache/user_registry_cache.dart

## Localization/admin strings
- mobile/lib/core/localization/sushi_localizations.dart

## Backend admin auth/endpoints/repositories/models
- backend/catalog_backend/main.py
- backend/catalog_backend/repositories.py
- backend/catalog_backend/schemas.py
- backend/catalog_backend/auth.py
- backend/catalog_backend/seed.py
- backend/catalog_backend/migrations/001_initial.sql
- backend/catalog_backend/migrations/002_orders_add_poster_order_id.sql

## Backend database objects used by admin currently
- table: admin_users
- table: categories
- table: products
- table: orders
- table: users
