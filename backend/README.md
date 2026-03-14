# Backend

All backend services for this project are grouped here.

## Folders

- `backend_proxy` - Yandex HTTP geocoder proxy
- `catalog_backend` - catalog, admin, auth, addresses, and orders backend

## Run

Geocoder proxy:

```bash
cd backend/backend_proxy
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
python main.py
```

Catalog backend:

```bash
cd backend/catalog_backend
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
python main.py
```

## Poster Menu Source

To use Poster as the single menu source for both mobile app and admin panel, configure `backend/catalog_backend/.env`:

```env
MENU_SOURCE=poster
POSTER_MENU_ENABLED=true
POSTER_API_TOKEN=...       # required
POSTER_ACCOUNT=...         # optional, depends on your Poster setup
```

`./backend/scripts/run_stack.sh` now validates these values before starting services.
