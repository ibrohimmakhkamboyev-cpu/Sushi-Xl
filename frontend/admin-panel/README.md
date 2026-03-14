# Sushi XL Web Admin Dashboard

## Run

1. Start backend API (FastAPI) on `http://127.0.0.1:8010`.
2. Serve this folder with any static server:
   - `python3 -m http.server 5174 --directory frontend/admin-panel`
3. Open `http://127.0.0.1:5174`.

## Authentication

Uses the same admin authentication endpoint:
- `POST /api/v1/auth/login`

The dashboard uses secure HttpOnly session cookies by default and sends requests with `credentials: include`.
For compatibility fallback, an access token may be kept only in in-memory JS state for the current tab session (not persisted in storage).

## Pages

- Dashboard
- Orders
- Products
- Categories
- Discounts
- Users
- Notifications
- Banners
- FAQ
- Settings
- Admin Profile
