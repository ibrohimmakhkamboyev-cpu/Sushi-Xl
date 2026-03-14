# Sushi XL

Project is now split into three top-level code folders:

- `backend/` - FastAPI backend services
- `frontend/` - web interface (admin panel)
- `mobile/` - Flutter mobile app

## Run Backend Services

Catalog backend:

```bash
cd backend/catalog_backend
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
python main.py
```

Geocoder proxy:

```bash
cd backend/backend_proxy
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env
python main.py
```

## Run Frontend (Admin Panel)

```bash
python3 -m http.server 5174 --directory frontend/admin-panel
```

Open `http://127.0.0.1:5174`.

## Run Mobile App

```bash
cd mobile
flutter pub get
flutter run
```

Poster menu integration example:

```bash
cd mobile
flutter run \
  --dart-define=USE_POSTER_MENU=true \
  --dart-define=POSTER_API_TOKEN=your_token \
  --dart-define=POSTER_ACCOUNT=your_account
```

## Poster Order Sync (Catalog Backend)

Configure `backend/catalog_backend/.env`:

```bash
POSTER_ORDER_ENABLED=true
POSTER_API_TOKEN=your_token
POSTER_ACCOUNT=your_account
POSTER_ORDER_SPOT_ID=1
POSTER_SKIP_PHONE_VALIDATION=false
```

## Optional: Run Backend + Frontend Together

```bash
bash backend/scripts/run_stack.sh
```

Stop:

```bash
bash backend/scripts/stop_stack.sh
```
