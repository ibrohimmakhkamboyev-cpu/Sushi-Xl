from __future__ import annotations

import json
import logging
import os
import plistlib
import secrets
import time
import uuid
from collections import defaultdict, deque
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any, Deque, Dict, Iterable, Optional

import httpx
from dotenv import load_dotenv
from fastapi import Cookie, Depends, FastAPI, File, Header, HTTPException, Query, Request, Response, UploadFile, status
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from fastapi.staticfiles import StaticFiles
from pydantic import ValidationError

_BOOTSTRAP_ROOT = Path(__file__).resolve().parent
load_dotenv(_BOOTSTRAP_ROOT / '.env')
load_dotenv(Path.cwd() / '.env', override=False)

try:
    from .auth import (
        create_access_token,
        create_user_access_token,
        decode_access_token,
        hash_password,
        verify_password,
    )
    from .database import DATABASE_PATH, ROOT, apply_migrations, get_conn
    from .repositories import (
        AddressRepository,
        AdminDashboardRepository,
        AdminRepository,
        CategoryRepository,
        OrderRepository,
        ProductFilters,
        ProductRepository,
        PublicRepository,
        UserAuthRepository,
        UserRepository,
    )
    from .poster import PosterClient, PosterSyncError
    from .schemas import (
        AddressIn,
        AdminBannerIn,
        AdminFaqIn,
        AdminLoginIn,
        AdminNotificationIn,
        AdminOrderUpdateIn,
        AdminProfileUpdateIn,
        AdminSettingsIn,
        AdminUserIn,
        CategoryCreateIn,
        CategoryReorderIn,
        CategoryUpdateIn,
        OrderCreateIn,
        ProductCreateIn,
        ProductReorderIn,
        ProductUpdateIn,
        UserLoginIn,
        UserProfileUpdateIn,
        UserOtpRequestIn,
        UserOtpVerifyIn,
    )
    from .seed import seed_database
except ImportError:  # pragma: no cover - script execution fallback
    from auth import (
        create_access_token,
        create_user_access_token,
        decode_access_token,
        hash_password,
        verify_password,
    )
    from database import DATABASE_PATH, ROOT, apply_migrations, get_conn
    from repositories import (
        AddressRepository,
        AdminDashboardRepository,
        AdminRepository,
        CategoryRepository,
        OrderRepository,
        ProductFilters,
        ProductRepository,
        PublicRepository,
        UserAuthRepository,
        UserRepository,
    )
    from poster import PosterClient, PosterSyncError
    from schemas import (
        AddressIn,
        AdminBannerIn,
        AdminFaqIn,
        AdminLoginIn,
        AdminNotificationIn,
        AdminOrderUpdateIn,
        AdminProfileUpdateIn,
        AdminSettingsIn,
        AdminUserIn,
        CategoryCreateIn,
        CategoryReorderIn,
        CategoryUpdateIn,
        OrderCreateIn,
        ProductCreateIn,
        ProductReorderIn,
        ProductUpdateIn,
        UserLoginIn,
        UserProfileUpdateIn,
        UserOtpRequestIn,
        UserOtpVerifyIn,
    )
    from seed import seed_database

logging.basicConfig(
    level=os.getenv('LOG_LEVEL', 'INFO').upper(),
    format='[catalog-backend] %(levelname)s %(message)s',
)
logger = logging.getLogger(__name__)
logging.getLogger('httpx').setLevel(logging.WARNING)
logging.getLogger('httpcore').setLevel(logging.WARNING)

product_repo = ProductRepository()
category_repo = CategoryRepository()
user_repo = UserRepository()
user_auth_repo = UserAuthRepository()
address_repo = AddressRepository()
order_repo = OrderRepository()
admin_repo = AdminRepository()
public_repo = PublicRepository()
dashboard_repo = AdminDashboardRepository()
poster_client = PosterClient()

RATE_LIMIT_REQUESTS = int(os.getenv('RATE_LIMIT_REQUESTS', '120'))
RATE_LIMIT_WINDOW_SECONDS = int(os.getenv('RATE_LIMIT_WINDOW_SECONDS', '60'))
_rate_limit_buckets: Dict[str, Deque[float]] = defaultdict(deque)
POSTER_MENU_ENABLED = os.getenv('POSTER_MENU_ENABLED', 'true').strip().lower() in {
    '1',
    'true',
    'yes',
    'on',
}
POSTER_MENU_CACHE_SECONDS = int(os.getenv('POSTER_MENU_CACHE_SECONDS', '45'))
POSTER_ON_THE_WAY_AFTER_MINUTES = int(
    os.getenv('POSTER_ON_THE_WAY_AFTER_MINUTES', '20'),
)
MENU_SOURCE = os.getenv('MENU_SOURCE', 'database').strip().lower()
UPLOADS_DIR = ROOT / 'data' / 'uploads'
_poster_menu_cache_data: Optional[dict[str, list[dict[str, Any]]]] = None
_poster_menu_cache_at: float = 0.0
PUSH_NOTIFICATIONS_ENABLED = os.getenv('PUSH_NOTIFICATIONS_ENABLED', 'false').strip().lower() in {
    '1',
    'true',
    'yes',
    'on',
}
FCM_SERVER_KEY = os.getenv('FCM_SERVER_KEY', '').strip()
FIREBASE_PROJECT_ID = os.getenv('FIREBASE_PROJECT_ID', '').strip()
FIREBASE_SERVICE_ACCOUNT_FILE = (
    os.getenv('FIREBASE_SERVICE_ACCOUNT_FILE', '').strip()
    or os.getenv('GOOGLE_APPLICATION_CREDENTIALS', '').strip()
)
FIREBASE_SERVICE_ACCOUNT_JSON = os.getenv('FIREBASE_SERVICE_ACCOUNT_JSON', '').strip()
FCM_PUSH_TIMEOUT_SECONDS = float(os.getenv('FCM_PUSH_TIMEOUT_SECONDS', '10'))
MAX_UPLOAD_BYTES = int(os.getenv('MAX_UPLOAD_BYTES', str(5 * 1024 * 1024)))
APP_ENV = os.getenv('APP_ENV', 'development').strip().lower()
ENFORCE_PROD_GUARDS = os.getenv('ENFORCE_PROD_GUARDS', 'true').strip().lower() in {
    '1',
    'true',
    'yes',
    'on',
}
USER_LEGACY_PHONE_LOGIN = os.getenv('USER_LEGACY_PHONE_LOGIN', 'false').strip().lower() in {
    '1',
    'true',
    'yes',
    'on',
}
USER_OTP_TTL_SECONDS = max(60, int(os.getenv('USER_OTP_TTL_SECONDS', '300')))
USER_OTP_MAX_ATTEMPTS = max(1, int(os.getenv('USER_OTP_MAX_ATTEMPTS', '5')))
USER_OTP_WEBHOOK_URL = os.getenv('USER_OTP_WEBHOOK_URL', '').strip()
USER_OTP_WEBHOOK_TOKEN = os.getenv('USER_OTP_WEBHOOK_TOKEN', '').strip()
USER_OTP_DEBUG_RESPONSE = os.getenv('USER_OTP_DEBUG_RESPONSE', 'false').strip().lower() in {
    '1',
    'true',
    'yes',
    'on',
}
ADMIN_LOGIN_INCLUDE_TOKEN = os.getenv('ADMIN_LOGIN_INCLUDE_TOKEN', 'false').strip().lower() in {
    '1',
    'true',
    'yes',
    'on',
}
ADMIN_AUTH_COOKIE_NAME = os.getenv('ADMIN_AUTH_COOKIE_NAME', 'sushixl_admin_session').strip() or 'sushixl_admin_session'
ADMIN_AUTH_COOKIE_SECURE = os.getenv('ADMIN_AUTH_COOKIE_SECURE', 'auto').strip().lower()
ADMIN_AUTH_COOKIE_SAMESITE = os.getenv('ADMIN_AUTH_COOKIE_SAMESITE', 'lax').strip().lower()
ALLOWED_IMAGE_MIME_TYPES = {
    'image/jpeg',
    'image/png',
    'image/webp',
    'image/gif',
}

UPLOADS_DIR.mkdir(parents=True, exist_ok=True)

app = FastAPI(title='Sushi XL Catalog Backend', version='1.0.0')
_cors_allow_origins = [
    origin.strip()
    for origin in os.getenv('CORS_ALLOW_ORIGINS', '*').split(',')
    if origin.strip()
]
if not _cors_allow_origins:
    _cors_allow_origins = ['*']
_cors_allow_credentials = os.getenv('CORS_ALLOW_CREDENTIALS', 'false').strip().lower() in {
    '1',
    'true',
    'yes',
    'on',
}
if '*' in _cors_allow_origins and _cors_allow_credentials:
    logger.warning(
        'CORS_ALLOW_CREDENTIALS=true with wildcard origins is unsafe. Forcing allow_credentials=false.',
    )
    _cors_allow_credentials = False
app.add_middleware(
    CORSMiddleware,
    allow_origins=_cors_allow_origins,
    allow_credentials=_cors_allow_credentials,
    allow_methods=['*'],
    allow_headers=['*'],
)
app.mount('/static/uploads', StaticFiles(directory=str(UPLOADS_DIR)), name='uploads')


def _mobile_root() -> Path:
    return ROOT.parent.parent / 'mobile'


def _firebase_service_account_info() -> Optional[dict[str, Any]]:
    if FIREBASE_SERVICE_ACCOUNT_JSON:
        raw = FIREBASE_SERVICE_ACCOUNT_JSON.strip()
        try:
            info = json.loads(raw)
        except json.JSONDecodeError:
            logger.warning('FIREBASE_SERVICE_ACCOUNT_JSON is not valid JSON.')
            return None
        if isinstance(info, dict):
            private_key = str(info.get('private_key') or '')
            if private_key:
                info['private_key'] = private_key.replace('\\n', '\n')
            return info
        return None

    if FIREBASE_SERVICE_ACCOUNT_FILE:
        candidate = Path(FIREBASE_SERVICE_ACCOUNT_FILE).expanduser()
        if not candidate.is_absolute():
            candidate = (Path.cwd() / candidate).resolve()
        if not candidate.exists():
            logger.warning('Firebase service account file not found: %s', candidate)
            return None
        try:
            info = json.loads(candidate.read_text(encoding='utf-8'))
        except Exception as exc:
            logger.warning('Failed to read Firebase service account file: %s', exc)
            return None
        if isinstance(info, dict):
            private_key = str(info.get('private_key') or '')
            if private_key:
                info['private_key'] = private_key.replace('\\n', '\n')
            return info
    return None


def _firebase_project_id() -> str:
    if FIREBASE_PROJECT_ID:
        return FIREBASE_PROJECT_ID

    info = _firebase_service_account_info()
    if info:
        project_id = str(info.get('project_id') or '').strip()
        if project_id:
            return project_id

    android_path = _mobile_root() / 'android' / 'app' / 'google-services.json'
    if android_path.exists():
        try:
            payload = json.loads(android_path.read_text(encoding='utf-8'))
            project_id = str(payload.get('project_info', {}).get('project_id') or '').strip()
            if project_id:
                return project_id
        except Exception:
            pass

    ios_path = _mobile_root() / 'ios' / 'Runner' / 'GoogleService-Info.plist'
    if ios_path.exists():
        try:
            payload = plistlib.loads(ios_path.read_bytes())
            project_id = str(payload.get('PROJECT_ID') or '').strip()
            if project_id:
                return project_id
        except Exception:
            pass
    return ''


def _push_config_error() -> Optional[str]:
    if not PUSH_NOTIFICATIONS_ENABLED:
        return None
    if _firebase_service_account_info():
        if not _firebase_project_id():
            return 'Push is enabled, but FIREBASE_PROJECT_ID could not be resolved.'
        return None
    if FCM_SERVER_KEY:
        return (
            'FCM_SERVER_KEY is deprecated for production use. '
            'Use FIREBASE_SERVICE_ACCOUNT_FILE or FIREBASE_SERVICE_ACCOUNT_JSON.'
        )
    return (
        'Push is enabled, but Firebase HTTP v1 credentials are missing. '
        'Set FIREBASE_SERVICE_ACCOUNT_FILE or FIREBASE_SERVICE_ACCOUNT_JSON.'
    )


def _push_delivery_mode() -> str:
    if not PUSH_NOTIFICATIONS_ENABLED:
        return 'disabled_by_config'
    if _firebase_service_account_info():
        return 'firebase_http_v1'
    if FCM_SERVER_KEY:
        return 'legacy_server_key_deprecated'
    return 'misconfigured'


def _is_production_env() -> bool:
    return APP_ENV in {'production', 'prod'}


def _cookie_secure_enabled() -> bool:
    if ADMIN_AUTH_COOKIE_SECURE == 'auto':
        return _is_production_env()
    return ADMIN_AUTH_COOKIE_SECURE in {'1', 'true', 'yes', 'on'}


def _cookie_samesite_value() -> str:
    value = ADMIN_AUTH_COOKIE_SAMESITE.strip().lower()
    if value not in {'lax', 'strict', 'none'}:
        return 'lax'
    return value


def _debug_otp_enabled() -> bool:
    return USER_OTP_DEBUG_RESPONSE and not _is_production_env()


def _validate_security_config() -> None:
    if not _is_production_env() or not ENFORCE_PROD_GUARDS:
        return
    issues: list[str] = []
    jwt_secret = os.getenv('JWT_SECRET', '').strip()
    if (
        not jwt_secret
        or jwt_secret == 'change-me'
        or jwt_secret.upper().startswith('__SET_')
    ):
        issues.append('JWT_SECRET is weak/default.')
    admin_password = os.getenv('ADMIN_PASSWORD', '').strip()
    if (
        not admin_password
        or admin_password == 'admin123'
        or admin_password.upper().startswith('__SET_')
    ):
        issues.append('ADMIN_PASSWORD is weak/default.')
    if '*' in _cors_allow_origins:
        issues.append('CORS_ALLOW_ORIGINS contains wildcard.')
    if USER_LEGACY_PHONE_LOGIN:
        issues.append('USER_LEGACY_PHONE_LOGIN must be disabled in production.')
    if not USER_OTP_WEBHOOK_URL:
        issues.append('USER_OTP_WEBHOOK_URL is required for production OTP delivery.')
    if _debug_otp_enabled():
        issues.append('USER_OTP_DEBUG_RESPONSE cannot be enabled in production.')
    if issues:
        raise RuntimeError(
            'Refusing to start in production with insecure defaults: ' + '; '.join(issues),
        )


def _validate_menu_source_config() -> None:
    if MENU_SOURCE != 'poster':
        return
    issues: list[str] = []
    if not POSTER_MENU_ENABLED:
        issues.append('POSTER_MENU_ENABLED must be true when MENU_SOURCE=poster.')
    if not poster_client.enabled:
        issues.append('Poster client is disabled. Set POSTER_API_TOKEN (and POSTER_ACCOUNT if required).')
    if issues:
        raise RuntimeError(
            'Refusing to start with invalid poster menu configuration: ' + '; '.join(issues),
        )


@app.on_event('startup')
def startup() -> None:
    _validate_security_config()
    _validate_menu_source_config()
    apply_migrations()
    seed_database()
    logger.info(
        'database ready: path=%s menu_source=%s poster_menu_enabled=%s poster_enabled=%s poster_menu_writable=%s',
        DATABASE_PATH,
        MENU_SOURCE,
        POSTER_MENU_ENABLED,
        poster_client.enabled,
        poster_client.menu_writable,
    )


@app.middleware('http')
async def rate_limit_middleware(request: Request, call_next):
    client_host = request.client.host if request.client else 'unknown'
    key = f'{client_host}:{request.url.path}'
    now = time.monotonic()
    bucket = _rate_limit_buckets[key]
    while bucket and (now - bucket[0]) > RATE_LIMIT_WINDOW_SECONDS:
        bucket.popleft()
    if len(bucket) >= RATE_LIMIT_REQUESTS:
        return JSONResponse(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            content={'error': 'RATE_LIMITED'},
        )
    bucket.append(now)
    return await call_next(request)


def _format_validation_details(errors: list[dict[str, Any]]) -> tuple[list[dict[str, str]], str]:
    details: list[dict[str, str]] = []
    for err in errors:
        raw_loc = err.get('loc') or ()
        loc = '.'.join(str(part) for part in raw_loc if part not in {'query', 'body', 'path', 'header'})
        field = loc or str(raw_loc[-1] if raw_loc else 'request')
        message = str(err.get('msg') or 'Invalid request input.')
        details.append(
            {
                'field': field,
                'message': message,
                'type': str(err.get('type') or ''),
            }
        )
    joined = '; '.join(f"{item['field']}: {item['message']}" for item in details) or 'Invalid request input.'
    return details, joined


@app.exception_handler(ValidationError)
async def validation_error_handler(_: Request, exc: ValidationError):
    details, message = _format_validation_details(exc.errors())
    return JSONResponse(
        status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
        content={'error': 'VALIDATION_ERROR', 'details': details, 'message': message},
    )


@app.exception_handler(RequestValidationError)
async def request_validation_error_handler(_: Request, exc: RequestValidationError):
    details, joined = _format_validation_details(exc.errors())
    return JSONResponse(
        status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
        content={'error': 'REQUEST_VALIDATION_ERROR', 'details': details, 'message': joined},
    )


@app.exception_handler(HTTPException)
async def http_exception_handler(_: Request, exc: HTTPException):
    detail = exc.detail
    if isinstance(detail, str):
        message = detail
    elif isinstance(detail, dict):
        message = str(detail.get('message') or detail.get('detail') or detail.get('error') or 'Request failed.')
    else:
        message = str(detail)
    return JSONResponse(
        status_code=exc.status_code,
        content={
            'error': 'HTTP_ERROR',
            'message': message,
            'detail': detail,
            'status': exc.status_code,
        },
    )


@app.get('/health')
def health() -> dict[str, Any]:
    return {
        'status': 'ok',
        'menu_source': MENU_SOURCE,
        'poster_menu_enabled': POSTER_MENU_ENABLED,
        'poster_enabled': poster_client.enabled,
        'poster_menu_writable': poster_client.menu_writable,
        'poster_config_error': poster_client.config_error,
        'push_enabled': PUSH_NOTIFICATIONS_ENABLED,
        'push_delivery_mode': _push_delivery_mode(),
        'push_config_error': _push_config_error(),
        'firebase_project_id': _firebase_project_id() or None,
        'release_guards_enforced': ENFORCE_PROD_GUARDS,
    }


@app.get('/')
def root() -> dict[str, str]:
    return {'service': 'catalog-backend', 'health': '/health', 'api': '/api/v1'}


@app.get('/favicon.ico', status_code=status.HTTP_204_NO_CONTENT)
def favicon() -> Response:
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@app.get('/api/v1/menu')
def get_menu(lang: str = Query(default='ru')) -> dict[str, list[dict[str, Any]]]:
    lang = _normalize_lang(lang)
    if _use_poster_menu_source():
        return _localize_poster_menu(_require_poster_menu_snapshot(), lang)
    with get_conn() as conn:
        return _build_menu_from_database(conn, lang)


@app.get('/api/v1/products')
def list_products(
    discounted: bool = Query(default=False),
    category: Optional[str] = Query(default=None),
    categoryId: Optional[int] = Query(default=None, ge=1),
    limit: Optional[int] = Query(default=None, ge=1, le=100),
    lang: str = Query(default='ru'),
) -> dict[str, list[dict[str, Any]]]:
    lang = _normalize_lang(lang)
    if _use_poster_menu_source():
        poster_menu = _require_poster_menu_snapshot()
        rows = _active_poster_menu_products(poster_menu)
        if discounted:
            rows = [row for row in rows if row.get('oldPrice') and row.get('oldPrice') > row.get('price')]
        if category and category.strip():
            needle = category.strip().lower()
            rows = [row for row in rows if needle in str(row.get('categoryName') or '').lower()]
        if categoryId is not None:
            rows = [row for row in rows if int(row.get('categoryId') or 0) == categoryId]
        if limit is not None:
            rows = rows[:limit]
        return {'results': [_public_product(row, lang=lang) for row in rows]}

    filters = ProductFilters(
        discounted=False,
        category=category,
        category_id=categoryId,
        limit=limit,
        active_only=True,
    )
    with get_conn() as conn:
        rows = product_repo.list(conn, filters)
    result = [_public_product(row, lang=lang) for row in rows]
    if discounted:
        result = [row for row in result if row.get('discountPercent') is not None]
    return {'results': result}


@app.get('/api/v1/products/{product_id}')
def get_product(product_id: int, lang: str = Query(default='ru')) -> dict[str, Any]:
    lang = _normalize_lang(lang)
    if _use_poster_menu_source():
        poster_menu = _require_poster_menu_snapshot()
        rows = _active_poster_menu_products(poster_menu)
        for row in rows:
            if int(row['id']) == product_id:
                return _public_product(row, lang=lang)
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='Product not found.')

    with get_conn() as conn:
        row = product_repo.get(conn, product_id)
    if not row:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='Product not found.')
    return _public_product(row, lang=lang)


@app.get('/api/v1/recommendations/drinks')
def recommended_drinks(
    productId: Optional[int] = Query(default=None, ge=1),
    limit: int = Query(default=6, ge=1, le=24),
    lang: str = Query(default='ru'),
) -> dict[str, list[dict[str, Any]]]:
    lang = _normalize_lang(lang)
    if _use_poster_menu_source():
        poster_menu = _require_poster_menu_snapshot()
        rows = [
            row for row in _active_poster_menu_products(poster_menu)
            if bool(row.get('isDrink'))
        ]
        if productId is not None:
            rows = [row for row in rows if int(row.get('id') or 0) != productId]
        return {'results': [_public_product(row, lang=lang) for row in rows[:limit]]}

    with get_conn() as conn:
        rows = product_repo.recommendations(conn, product_id=productId, limit=limit)
    return {'results': [_public_product(row, lang=lang) for row in rows]}


def _extract_bearer_token(authorization: Optional[str]) -> str:
    if not authorization or not authorization.lower().startswith('bearer '):
        return ''
    return authorization.split(' ', 1)[1].strip()


def _set_admin_auth_cookie(response: Response, token: str) -> None:
    response.set_cookie(
        key=ADMIN_AUTH_COOKIE_NAME,
        value=token,
        httponly=True,
        secure=_cookie_secure_enabled(),
        samesite=_cookie_samesite_value(),
        max_age=max(60, int(os.getenv('JWT_EXPIRES_MINUTES', '480')) * 60),
        path='/',
    )


def _clear_admin_auth_cookie(response: Response) -> None:
    response.delete_cookie(
        key=ADMIN_AUTH_COOKIE_NAME,
        path='/',
        secure=_cookie_secure_enabled(),
        samesite=_cookie_samesite_value(),
    )


def _require_admin(
    request: Request,
    authorization: Optional[str] = Header(default=None),
    admin_session: Optional[str] = Cookie(default=None, alias=ADMIN_AUTH_COOKIE_NAME),
) -> dict[str, Any]:
    token = _extract_bearer_token(authorization)
    if not token:
        token = str(admin_session or request.cookies.get(ADMIN_AUTH_COOKIE_NAME) or '').strip()
    if not token:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail='Missing bearer token.')
    return decode_access_token(token, expected_role='admin')


def _require_user(authorization: Optional[str] = Header(default=None)) -> dict[str, Any]:
    token = _extract_bearer_token(authorization)
    if not token:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail='Missing bearer token.')
    return decode_access_token(token, expected_role='user')


def _claims_user_id(claims: dict[str, Any]) -> int:
    raw = claims.get('sub')
    try:
        user_id = int(raw)
    except (TypeError, ValueError) as exc:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail='Invalid access token subject.',
        ) from exc
    if user_id <= 0:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail='Invalid access token subject.',
        )
    return user_id


def _normalize_phone(raw: str) -> str:
    phone = str(raw or '').strip()
    if not phone:
        raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail='Phone is required.')
    return phone


def _user_session_out(session: dict[str, Any]) -> dict[str, Any]:
    return {
        'user_id': int(session['user_id']),
        'phone': str(session['phone']),
        'full_name': str(session['full_name']),
        'preferred_lang': str(session['preferred_lang']),
        'access_token': create_user_access_token(
            user_id=int(session['user_id']),
            phone=str(session['phone']),
        ),
        'token_type': 'bearer',
    }


def _format_otp_expires_at() -> tuple[str, int]:
    now = datetime.now(timezone.utc)
    expires = now + timedelta(seconds=USER_OTP_TTL_SECONDS)
    return expires.strftime('%Y-%m-%d %H:%M:%S'), USER_OTP_TTL_SECONDS


def _deliver_user_otp(phone: str, code: str) -> None:
    if not USER_OTP_WEBHOOK_URL:
        if _debug_otp_enabled():
            return
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail='OTP delivery service is not configured.',
        )
    payload = {
        'phone': phone,
        'code': code,
        'ttl_seconds': USER_OTP_TTL_SECONDS,
        'message': f'Sushi XL verification code: {code}',
    }
    headers: dict[str, str] = {'Content-Type': 'application/json'}
    if USER_OTP_WEBHOOK_TOKEN:
        headers['Authorization'] = f'Bearer {USER_OTP_WEBHOOK_TOKEN}'
    try:
        with httpx.Client(timeout=10.0) as client:
            response = client.post(USER_OTP_WEBHOOK_URL, json=payload, headers=headers)
    except httpx.HTTPError as exc:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail='OTP delivery service is unavailable.',
        ) from exc
    if response.status_code >= 400:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail='OTP delivery service rejected the request.',
        )


@app.post('/api/v1/auth/login')
def login(payload: dict[str, Any], response: Response) -> dict[str, Any]:
    if 'email' in payload:
        body = AdminLoginIn.model_validate(payload)
        with get_conn() as conn:
            admin = None
            for candidate in _admin_login_candidates(body.email):
                row = admin_repo.get_by_email(conn, candidate)
                if row and row['is_active'] and verify_password(body.password, row['password_hash']):
                    admin = row
                    break
        if not admin:
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail='Invalid credentials.')
        token = create_access_token(admin_id=admin['id'], email=admin['email'])
        _set_admin_auth_cookie(response, token)
        payload: dict[str, Any] = {
            'token_type': 'cookie',
            'admin': {
                'id': admin['id'],
                'email': admin['email'],
                'fullName': admin['full_name'],
            },
        }
        if ADMIN_LOGIN_INCLUDE_TOKEN:
            payload['access_token'] = token
        return payload

    if not USER_LEGACY_PHONE_LOGIN:
        raise HTTPException(
            status_code=status.HTTP_410_GONE,
            detail='Legacy phone login is disabled. Use /api/v1/auth/request-code and /api/v1/auth/verify-code.',
        )

    body = UserLoginIn.model_validate(payload)
    with get_conn() as conn:
        session = user_repo.upsert_login(
            conn,
            phone=_normalize_phone(body.phone),
            full_name=body.full_name.strip(),
            preferred_lang=body.preferred_lang.strip() or 'ru',
        )
    return _user_session_out(session)


@app.post('/api/v1/auth/logout')
def logout(response: Response) -> dict[str, bool]:
    _clear_admin_auth_cookie(response)
    return {'ok': True}


@app.post('/api/v1/auth/request-code')
def request_login_code(body: UserOtpRequestIn) -> dict[str, Any]:
    phone = _normalize_phone(body.phone)
    preferred_lang = body.preferred_lang.strip() or 'ru'
    provided_name = (body.full_name or '').strip()
    with get_conn() as conn:
        user = user_repo.get_by_phone(conn, phone)
        if user is None:
            if not provided_name:
                raise HTTPException(
                    status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                    detail='full_name is required for first-time registration.',
                )
            session = user_repo.upsert_login(
                conn,
                phone=phone,
                full_name=provided_name,
                preferred_lang=preferred_lang,
            )
            user_id = int(session['user_id'])
        else:
            user_id = int(user['id'])
            if provided_name:
                user_repo.upsert_login(
                    conn,
                    phone=phone,
                    full_name=provided_name,
                    preferred_lang=preferred_lang,
                )
        code = str(secrets.randbelow(900000) + 100000)
        expires_at, ttl = _format_otp_expires_at()
        user_auth_repo.create_login_code(
            conn,
            user_id=user_id,
            phone=phone,
            code_hash=hash_password(code),
            expires_at=expires_at,
        )
    _deliver_user_otp(phone, code)
    payload: dict[str, Any] = {
        'status': 'sent',
        'delivery': 'webhook' if USER_OTP_WEBHOOK_URL else 'debug',
        'expires_in': ttl,
    }
    if _debug_otp_enabled():
        payload['debug_code'] = code
    return payload


@app.post('/api/v1/auth/verify-code')
def verify_login_code(body: UserOtpVerifyIn) -> dict[str, Any]:
    phone = _normalize_phone(body.phone)
    code = str(body.code or '').strip()
    if not code:
        raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail='Code is required.')
    preferred_lang = body.preferred_lang.strip() or 'ru'
    provided_name = (body.full_name or '').strip()
    deferred_error: Optional[HTTPException] = None
    session: Optional[dict[str, Any]] = None
    with get_conn() as conn:
        challenge = user_auth_repo.get_active_code(conn, phone=phone)
        if not challenge:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail='Verification code is invalid or expired.',
            )
        attempts = int(challenge['attempts'])
        if attempts >= USER_OTP_MAX_ATTEMPTS:
            raise HTTPException(
                status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                detail='Too many invalid attempts. Request a new code.',
            )
        if not verify_password(code, str(challenge['code_hash'])):
            next_attempt = user_auth_repo.increment_attempts(conn, code_id=int(challenge['id']))
            if next_attempt >= USER_OTP_MAX_ATTEMPTS:
                deferred_error = HTTPException(
                    status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                    detail='Too many invalid attempts. Request a new code.',
                )
            else:
                deferred_error = HTTPException(
                    status_code=status.HTTP_401_UNAUTHORIZED,
                    detail='Verification code is invalid or expired.',
                )
        else:
            user_auth_repo.consume_code(conn, code_id=int(challenge['id']))
            user = user_repo.get_by_phone(conn, phone)
            if user is None:
                if not provided_name:
                    raise HTTPException(
                        status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                        detail='full_name is required to create account.',
                    )
                session = user_repo.upsert_login(
                    conn,
                    phone=phone,
                    full_name=provided_name,
                    preferred_lang=preferred_lang,
                )
            else:
                if provided_name:
                    session = user_repo.upsert_login(
                        conn,
                        phone=phone,
                        full_name=provided_name,
                        preferred_lang=preferred_lang,
                    )
                else:
                    session = {
                        'user_id': int(user['id']),
                        'phone': str(user['phone']),
                        'full_name': str(user['full_name']),
                        'preferred_lang': str(user['preferred_lang']),
                    }
    if deferred_error is not None:
        raise deferred_error
    if session is None:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail='Failed to resolve authenticated user session.',
        )
    return _user_session_out(session)


@app.put('/api/v1/users/me')
def update_my_profile(
    body: UserProfileUpdateIn,
    claims: dict[str, Any] = Depends(_require_user),
) -> dict[str, Any]:
    resolved_user_id = _claims_user_id(claims)
    phone = _normalize_phone(body.phone)
    full_name = body.full_name.strip()
    preferred_lang = body.preferred_lang.strip() or 'ru'
    if not full_name:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail='full_name is required.',
        )
    try:
        with get_conn() as conn:
            session = user_repo.update_profile_session(
                conn,
                user_id=resolved_user_id,
                phone=phone,
                full_name=full_name,
                preferred_lang=preferred_lang,
            )
    except ValueError as exc:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail=str(exc)) from exc
    if session is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='User not found.')
    return _user_session_out(session)


@app.get('/api/v1/addresses')
def list_addresses(
    claims: dict[str, Any] = Depends(_require_user),
    user_id: Optional[int] = Query(default=None, alias='user_id', ge=1),
) -> list[dict[str, Any]]:
    resolved_user_id = _claims_user_id(claims)
    if user_id is not None and int(user_id) != resolved_user_id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail='Cannot access another user address book.',
        )
    with get_conn() as conn:
        rows = address_repo.list(conn, resolved_user_id)
    return [_address_out(row) for row in rows]


@app.post('/api/v1/addresses')
def create_address(
    body: AddressIn,
    claims: dict[str, Any] = Depends(_require_user),
) -> dict[str, Any]:
    resolved_user_id = _claims_user_id(claims)
    if int(body.userId) != resolved_user_id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail='Cannot create address for another user.',
        )
    with get_conn() as conn:
        existing_user = user_repo.get(conn, resolved_user_id)
        if not existing_user:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail='Unknown userId.',
            )
        payload = body.model_dump(by_alias=False)
        payload['userId'] = resolved_user_id
        row = address_repo.create(conn, payload)
    return _address_out(row)


@app.post('/api/v1/orders')
def create_order(
    body: OrderCreateIn,
    claims: dict[str, Any] = Depends(_require_user),
) -> dict[str, Any]:
    resolved_user_id = _claims_user_id(claims)
    if int(body.userId) != resolved_user_id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail='Cannot create order for another user.',
        )
    if not poster_client.enabled:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail=poster_client.config_error or 'Poster order sync is disabled.',
        )
    with get_conn() as conn:
        customer = user_repo.get(conn, resolved_user_id)
        if not customer:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail='Unknown user_id.',
            )
        if body.addressId is not None:
            existing_address = address_repo.get(conn, int(body.addressId))
            if not existing_address:
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail='Unknown address_id.',
                )
            if int(existing_address.get('userId') or 0) != resolved_user_id:
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail='address_id does not belong to user_id.',
                )
        payload = body.model_dump(by_alias=True)
        payload['user_id'] = resolved_user_id
        row = order_repo.create(conn, payload, product_repo)
        address_lat = None
        address_lng = None
        address_id = row.get('address_id')
        if address_id is not None:
            address = address_repo.get(conn, int(address_id))
            if address:
                address_lat = address.get('lat')
                address_lng = address.get('lng')
        try:
            poster_order_id = poster_client.create_incoming_order(
                order=row,
                customer=customer,
                address_lat=address_lat,
                address_lng=address_lng,
            )
        except PosterSyncError as exc:
            raise HTTPException(
                status_code=status.HTTP_502_BAD_GATEWAY,
                detail=f'Poster sync failed: {exc}',
            ) from exc
        updated = order_repo.set_poster_order_id(conn, int(row['id']), poster_order_id)
        if updated is not None:
            row = updated
    return _order_summary(row)


@app.get('/api/v1/orders/{order_id}')
def get_order(
    order_id: int,
    claims: dict[str, Any] = Depends(_require_user),
) -> dict[str, Any]:
    resolved_user_id = _claims_user_id(claims)
    with get_conn() as conn:
        row = order_repo.get(conn, order_id)
        if row and int(row.get('user_id') or 0) != resolved_user_id:
            row = None
        if row:
            row = _sync_order_status_from_poster(conn, row)
    if not row:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='Order not found.')
    return _order_summary(row)


@app.get('/api/v1/order-history')
def order_history(
    claims: dict[str, Any] = Depends(_require_user),
    user_id: Optional[int] = Query(default=None, alias='user_id', ge=1),
) -> list[dict[str, Any]]:
    resolved_user_id = _claims_user_id(claims)
    if user_id is not None and int(user_id) != resolved_user_id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail='Cannot access another user order history.',
        )
    with get_conn() as conn:
        rows = conn.execute(
            'SELECT id, status, payment_status, poster_order_id, delivery_type, created_at FROM orders WHERE user_id = ? ORDER BY created_at DESC, id DESC',
            (resolved_user_id,),
        ).fetchall()
        output = [
            {
                'id': int(row['id']),
                'status': str(row['status']),
                'payment_status': str(row['payment_status']),
                'poster_order_id': row['poster_order_id'],
                'delivery_type': str(row['delivery_type']),
                'created_at': str(row['created_at']),
            }
            for row in rows
        ]
        for i in range(len(output)):
            output[i] = _sync_order_status_from_poster(conn, output[i])
    return output


@app.get('/api/v1/order-history/{order_id}')
def order_history_detail(
    order_id: int,
    claims: dict[str, Any] = Depends(_require_user),
) -> dict[str, Any]:
    resolved_user_id = _claims_user_id(claims)
    with get_conn() as conn:
        row = order_repo.get(conn, order_id)
    if not row or int(row.get('user_id') or 0) != resolved_user_id:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='Order not found.')
    return {
        'id': row['id'],
        'items': [
            {
                'product_id': item['product_id'] or 0,
                'qty': item['qty'],
                'price': item['price'],
                'modifiers': item['modifiers'],
            }
            for item in row['items']
        ],
    }


@app.get('/api/v1/public/hours')
def public_hours() -> dict[str, list[dict[str, Any]]]:
    return {'hours': public_repo.working_hours()}


@app.get('/api/v1/public/banners')
def public_banners(lang: str = Query(default='ru')) -> dict[str, list[dict[str, Any]]]:
    lang = _normalize_lang(lang)
    with get_conn() as conn:
        rows = dashboard_repo.list_banners(conn, active_only=True)
    return {'results': [_localized_banner(row, lang) for row in rows]}


@app.get('/api/v1/banners')
def list_banners(lang: str = Query(default='ru')) -> dict[str, list[dict[str, Any]]]:
    lang = _normalize_lang(lang)
    with get_conn() as conn:
        rows = dashboard_repo.list_banners(conn, active_only=True)
    return {'results': [_localized_banner(row, lang) for row in rows]}


@app.get('/api/v1/banners/{banner_id}')
def get_banner(banner_id: int, lang: str = Query(default='ru')) -> dict[str, Any]:
    lang = _normalize_lang(lang)
    with get_conn() as conn:
        row = dashboard_repo.get_banner(conn, banner_id, active_only=True)
    if not row:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='Banner not found.')
    return _localized_banner(row, lang)


@app.get('/api/v1/public/faqs')
def public_faqs(lang: str = Query(default='ru')) -> dict[str, list[dict[str, Any]]]:
    lang = _normalize_lang(lang)
    with get_conn() as conn:
        rows = dashboard_repo.list_faq(conn, active_only=True)
    return {'results': [_localized_faq(row, lang) for row in rows]}


@app.get('/api/v1/public/notifications')
def public_notifications(lang: str = Query(default='ru')) -> dict[str, list[dict[str, Any]]]:
    lang = _normalize_lang(lang)
    with get_conn() as conn:
        rows = dashboard_repo.list_notifications(conn, active_only=True)
    return {'results': [_localized_notification(row, lang) for row in rows]}


@app.get('/api/v1/public/settings')
def public_settings(lang: str = Query(default='ru')) -> dict[str, Any]:
    lang = _normalize_lang(lang)
    with get_conn() as conn:
        row = dashboard_repo.get_settings(conn)
    return _localized_settings(row, lang)


def _admin_login_candidates(raw_login: str) -> list[str]:
    login = raw_login.strip().lower()
    out: list[str] = []

    def add(value: str) -> None:
        candidate = value.strip().lower()
        if not candidate or candidate in out:
            return
        out.append(candidate)

    add(login)
    configured = os.getenv('ADMIN_EMAIL', 'admin@sushixl.local').strip().lower()
    if '@' not in login:
        add(f'{login}@sushixl.local')
        add(configured)
    if login == 'admin':
        add('admin@sushixl.local')
    return out


def _banner_payload_action(payload: dict[str, Any]) -> str:
    action = str(payload.get('actionType') or payload.get('action_type') or 'none').strip().lower()
    if action not in {'open_product', 'open_products', 'open_category', 'open_discounts', 'open_url', 'none'}:
        return 'none'
    return action


def _payload_positive_int(value: Any) -> Optional[int]:
    if isinstance(value, bool) or value is None:
        return None
    if isinstance(value, (int, float)):
        parsed = int(value)
        return parsed if parsed > 0 else None
    text = str(value).strip()
    if not text or not text.isdigit():
        return None
    parsed = int(text)
    return parsed if parsed > 0 else None


def _payload_int_list(value: Any) -> list[int]:
    raw_values: list[Any]
    if value is None:
        raw_values = []
    elif isinstance(value, list):
        raw_values = value
    else:
        raw_values = [value]
    out: list[int] = []
    seen: set[int] = set()
    for item in raw_values:
        parsed = _payload_positive_int(item)
        if parsed is None or parsed in seen:
            continue
        seen.add(parsed)
        out.append(parsed)
    return out


def _validate_banner_action_targets(conn, payload: dict[str, Any]) -> None:
    action = _banner_payload_action(payload)
    poster_ids: Optional[set[int]] = None
    if _use_poster_menu_source():
        menu = _require_poster_menu_snapshot()
        poster_ids = {
            int(row.get('id') or 0)
            for row in _flatten_poster_menu_products(menu)
            if int(row.get('id') or 0) > 0
        }
    if action == 'open_product':
        product_id = _payload_positive_int(payload.get('productId') or payload.get('product_id'))
        if product_id is None:
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail='open_product requires a valid product.',
            )
        exists = product_id in poster_ids if poster_ids is not None else bool(
            product_repo.get(conn, product_id, include_inactive=True)
        )
        if not exists:
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail='Selected product not found.',
            )
        return

    if action == 'open_products':
        linked_ids = _payload_int_list(
            payload.get('linkedProductIds')
            if payload.get('linkedProductIds') is not None
            else (
                payload.get('linked_product_ids')
                if payload.get('linked_product_ids') is not None
                else payload.get('productIds')
            )
        )
        if not linked_ids:
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail='open_products requires at least one product.',
            )
        if poster_ids is not None:
            found_ids = {product_id for product_id in linked_ids if product_id in poster_ids}
        else:
            placeholders = ','.join(['?'] * len(linked_ids))
            rows = conn.execute(
                f'SELECT id FROM products WHERE id IN ({placeholders})',
                linked_ids,
            ).fetchall()
            found_ids = {int(row['id']) for row in rows}
        missing = [product_id for product_id in linked_ids if product_id not in found_ids]
        if missing:
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail=f'Products not found: {", ".join(str(item) for item in missing)}',
            )
        return

    if action == 'open_category':
        category_id = _payload_positive_int(payload.get('categoryId') or payload.get('category_id'))
        if category_id is None:
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail='open_category requires a valid category.',
            )
        category = category_repo.get(conn, category_id)
        if not category:
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail='Selected category not found.',
            )
        return

    if action == 'open_url':
        raw_url = str(payload.get('targetUrl') or payload.get('target_url') or '').strip()
        if not raw_url:
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail='open_url requires target URL.',
            )
        if not (
            raw_url.startswith('http://')
            or raw_url.startswith('https://')
            or raw_url.startswith('/')
        ):
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail='target URL must start with https://, http://, or /.',
            )


@app.post('/api/v1/admin/uploads/image')
async def admin_upload_image(
    request: Request,
    file: UploadFile = File(...),
    _: dict[str, Any] = Depends(_require_admin),
) -> dict[str, str]:
    filename = file.filename or ''
    ext = Path(filename).suffix.strip().lower()
    if ext not in {'.jpg', '.jpeg', '.png', '.webp', '.gif'}:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail='Unsupported image type. Allowed: jpg, jpeg, png, webp, gif.',
        )
    content_type = (file.content_type or '').split(';', 1)[0].strip().lower()
    if content_type and content_type not in ALLOWED_IMAGE_MIME_TYPES:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail='Unsupported image content type.',
        )
    generated = f'{uuid.uuid4().hex}{ext}'
    target = UPLOADS_DIR / generated
    written = 0
    with target.open('wb') as fh:
        while True:
            chunk = await file.read(1024 * 1024)
            if not chunk:
                break
            written += len(chunk)
            if written > MAX_UPLOAD_BYTES:
                fh.close()
                target.unlink(missing_ok=True)
                raise HTTPException(
                    status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
                    detail=f'Image is too large. Max size is {MAX_UPLOAD_BYTES} bytes.',
                )
            fh.write(chunk)
    await file.close()
    path = f'/static/uploads/{generated}'
    base = str(request.base_url).rstrip('/')
    return {
        'imageUrl': f'{base}{path}',
        'path': path,
    }


@app.get('/api/v1/admin/products')
def admin_list_products(
    search: Optional[str] = Query(default=None),
    categoryId: Optional[int] = Query(default=None, ge=1),
    discounted: Optional[bool] = Query(default=None),
    limit: Optional[int] = Query(default=None, ge=1, le=200),
    _: dict[str, Any] = Depends(_require_admin),
) -> dict[str, Any]:
    if _use_poster_menu_source():
        menu = _require_poster_menu_snapshot()
        rows = _flatten_poster_menu_products(menu)
        if categoryId is not None:
            rows = [row for row in rows if int(row.get('categoryId') or 0) == categoryId]
        if discounted:
            rows = [row for row in rows if row.get('oldPrice') and row.get('oldPrice') > row.get('price')]
        if search and search.strip():
            needle = search.strip().lower()
            rows = [
                row for row in rows
                if (
                    needle in str(row.get('title') or '').lower()
                    or needle in str(row.get('description') or '').lower()
                    or needle in str(row.get('categoryName') or '').lower()
                )
            ]
        if limit is not None:
            rows = rows[:limit]
        return {
            'results': [_admin_product(row) for row in rows],
            'source': 'poster',
            'readOnly': not poster_client.menu_writable,
        }

    filters = ProductFilters(
        discounted=bool(discounted),
        category_id=categoryId,
        limit=limit,
        active_only=False,
    )
    with get_conn() as conn:
        rows = product_repo.list(conn, filters)
    if search and search.strip():
        needle = search.strip().lower()
        rows = [
            row for row in rows
            if (
                needle in str(row['title']).lower()
                or needle in str(row.get('description') or '').lower()
                or needle in str(row.get('titleEn') or '').lower()
                or needle in str(row.get('titleRu') or '').lower()
                or needle in str(row.get('titleUz') or '').lower()
                or needle in str(row.get('descriptionEn') or '').lower()
                or needle in str(row.get('descriptionRu') or '').lower()
                or needle in str(row.get('descriptionUz') or '').lower()
            )
        ]
    return {'results': [_admin_product(row) for row in rows], 'source': 'database', 'readOnly': False}


@app.post('/api/v1/admin/products/reorder')
def admin_reorder_products(
    body: ProductReorderIn,
    _: dict[str, Any] = Depends(_require_admin),
) -> dict[str, list[dict[str, Any]]]:
    if _use_poster_menu_source():
        menu = _require_poster_menu_snapshot()
        _set_poster_product_sort_overrides([int(item) for item in body.ids], menu=menu)
        menu = _require_poster_menu_snapshot()
        rows = _flatten_poster_menu_products(menu)
        return {'results': [_admin_product(row) for row in rows]}

    _ensure_admin_menu_write_allowed()
    try:
        with get_conn() as conn:
            rows = product_repo.reorder(conn, body.ids)
    except ValueError as exc:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc)) from exc
    return {'results': [_admin_product(row) for row in rows]}


@app.post('/api/v1/admin/products', status_code=status.HTTP_201_CREATED)
def admin_create_product(
    body: ProductCreateIn,
    _: dict[str, Any] = Depends(_require_admin),
) -> dict[str, Any]:
    if _use_poster_menu_source():
        if not poster_client.menu_writable:
            _ensure_admin_menu_write_allowed()
        payload = body.model_dump()
        try:
            row = poster_client.create_menu_product(
                title=_poster_pick_text(payload, 'title', 'titleRu', 'titleEn', 'titleUz'),
                category_id=int(payload['categoryId']),
                price=float(payload['price']),
                description=_poster_pick_optional_text(
                    payload,
                    'description',
                    'descriptionRu',
                    'descriptionEn',
                    'descriptionUz',
                ),
                is_active=bool(payload.get('isActive', True)),
                is_drink=bool(payload.get('isDrink', False)),
                image_url=str(payload.get('imageUrl') or '').strip() or None,
            )
        except PosterSyncError as exc:
            raise HTTPException(status_code=status.HTTP_502_BAD_GATEWAY, detail=str(exc)) from exc
        created_product_id = int(row.get('product_id') or 0)
        _set_poster_product_active_override(created_product_id, bool(payload.get('isActive', True)))
        _set_poster_product_localization_override(created_product_id, payload)
        _invalidate_poster_menu_cache()
        menu = _require_poster_menu_snapshot()
        flat_rows = _flatten_poster_menu_products(menu)
        matched = next((item for item in flat_rows if int(item.get('id') or 0) == created_product_id), None)
        if matched is None:
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail='Created product is not visible in poster menu snapshot.',
            )
        return _admin_product(matched)

    _ensure_admin_menu_write_allowed()
    payload = body.model_dump()
    with get_conn() as conn:
        _ensure_category_exists(conn, payload['categoryId'])
        row = product_repo.create(conn, payload)
    return _admin_product(row)


@app.put('/api/v1/admin/products/{product_id}')
def admin_update_product(
    product_id: int,
    body: ProductUpdateIn,
    _: dict[str, Any] = Depends(_require_admin),
) -> dict[str, Any]:
    if _use_poster_menu_source():
        if not poster_client.menu_writable:
            _ensure_admin_menu_write_allowed()
        payload = body.model_dump()
        try:
            row = poster_client.update_menu_product(
                product_id=product_id,
                title=_poster_pick_text(payload, 'title', 'titleRu', 'titleEn', 'titleUz'),
                category_id=int(payload['categoryId']),
                price=float(payload['price']),
                description=_poster_pick_optional_text(
                    payload,
                    'description',
                    'descriptionRu',
                    'descriptionEn',
                    'descriptionUz',
                ),
                is_active=bool(payload.get('isActive', True)),
                is_drink=bool(payload.get('isDrink', False)),
                image_url=str(payload.get('imageUrl') or '').strip() or None,
            )
        except PosterSyncError as exc:
            raise HTTPException(status_code=status.HTTP_502_BAD_GATEWAY, detail=str(exc)) from exc
        updated_product_id = int(row.get('product_id') or product_id)
        _set_poster_product_active_override(updated_product_id, bool(payload.get('isActive', True)))
        _set_poster_product_localization_override(updated_product_id, payload)
        _invalidate_poster_menu_cache()
        menu = _require_poster_menu_snapshot()
        flat_rows = _flatten_poster_menu_products(menu)
        matched = next((item for item in flat_rows if int(item.get('id') or 0) == updated_product_id), None)
        if matched is None:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail='Product not found after update in poster.',
            )
        return _admin_product(matched)

    _ensure_admin_menu_write_allowed()
    payload = body.model_dump()
    with get_conn() as conn:
        _ensure_category_exists(conn, payload['categoryId'])
        row = product_repo.update(conn, product_id, payload)
    if not row:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='Product not found.')
    return _admin_product(row)


@app.delete('/api/v1/admin/products/{product_id}', status_code=status.HTTP_204_NO_CONTENT)
def admin_delete_product(
    product_id: int,
    _: dict[str, Any] = Depends(_require_admin),
) -> Response:
    if _use_poster_menu_source():
        if not poster_client.menu_writable:
            _ensure_admin_menu_write_allowed()
        try:
            poster_client.delete_menu_product(product_id=product_id)
        except PosterSyncError as exc:
            raise HTTPException(status_code=status.HTTP_502_BAD_GATEWAY, detail=str(exc)) from exc
        _delete_poster_product_active_override(product_id)
        _delete_poster_product_localization_override(product_id)
        _invalidate_poster_menu_cache()
        return Response(status_code=status.HTTP_204_NO_CONTENT)

    _ensure_admin_menu_write_allowed()
    with get_conn() as conn:
        deleted = product_repo.delete(conn, product_id)
    if not deleted:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='Product not found.')
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@app.get('/api/v1/admin/categories')
def admin_list_categories(_: dict[str, Any] = Depends(_require_admin)) -> dict[str, Any]:
    if _use_poster_menu_source():
        menu = _require_poster_menu_snapshot()
        return {
            'results': _poster_admin_categories(menu),
            'source': 'poster',
            'readOnly': not poster_client.menu_writable,
        }
    with get_conn() as conn:
        rows = category_repo.list(conn, active_only=False)
    return {'results': rows, 'source': 'database', 'readOnly': False}


@app.post('/api/v1/admin/categories', status_code=status.HTTP_201_CREATED)
def admin_create_category(
    body: CategoryCreateIn,
    _: dict[str, Any] = Depends(_require_admin),
) -> dict[str, Any]:
    if _use_poster_menu_source():
        if not poster_client.menu_writable:
            _ensure_admin_menu_write_allowed()
        payload = body.model_dump()
        try:
            created = poster_client.create_menu_category(
                name=_poster_pick_text(payload, 'name', 'nameRu', 'nameEn', 'nameUz'),
                parent_category=0,
                is_active=bool(payload.get('isActive', True)),
            )
        except PosterSyncError as exc:
            raise HTTPException(status_code=status.HTTP_502_BAD_GATEWAY, detail=str(exc)) from exc
        category_id = int(created.get('category_id') or created.get('id') or 0)
        _set_poster_category_localization_override(category_id, payload)
        _invalidate_poster_menu_cache()
        menu = _require_poster_menu_snapshot()
        rows = _poster_admin_categories(menu)
        row = next((item for item in rows if int(item.get('id') or 0) == category_id), None)
        if row is None:
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail='Created category is not visible in poster menu snapshot.',
            )
        return row

    _ensure_admin_menu_write_allowed()
    with get_conn() as conn:
        row = category_repo.create(conn, body.model_dump())
    return row


@app.put('/api/v1/admin/categories/{category_id}')
def admin_update_category(
    category_id: int,
    body: CategoryUpdateIn,
    _: dict[str, Any] = Depends(_require_admin),
) -> dict[str, Any]:
    if _use_poster_menu_source():
        if not poster_client.menu_writable:
            _ensure_admin_menu_write_allowed()
        payload = body.model_dump()
        try:
            poster_client.update_menu_category(
                category_id=category_id,
                name=_poster_pick_text(payload, 'name', 'nameRu', 'nameEn', 'nameUz'),
                parent_category=0,
                is_active=bool(payload.get('isActive', True)),
                sort_order=int(payload.get('sortOrder') or 0),
            )
        except PosterSyncError as exc:
            raise HTTPException(status_code=status.HTTP_502_BAD_GATEWAY, detail=str(exc)) from exc
        _set_poster_category_localization_override(int(category_id), payload)
        _invalidate_poster_menu_cache()
        menu = _require_poster_menu_snapshot()
        rows = _poster_admin_categories(menu)
        row = next((item for item in rows if int(item.get('id') or 0) == int(category_id)), None)
        if row is None:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='Category not found.')
        return row

    _ensure_admin_menu_write_allowed()
    with get_conn() as conn:
        row = category_repo.update(conn, category_id, body.model_dump())
    if not row:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='Category not found.')
    return row


@app.delete('/api/v1/admin/categories/{category_id}', status_code=status.HTTP_204_NO_CONTENT)
def admin_delete_category(
    category_id: int,
    _: dict[str, Any] = Depends(_require_admin),
) -> Response:
    if _use_poster_menu_source():
        if not poster_client.menu_writable:
            _ensure_admin_menu_write_allowed()
        try:
            poster_client.delete_menu_category(category_id=category_id)
        except PosterSyncError as exc:
            raise HTTPException(status_code=status.HTTP_502_BAD_GATEWAY, detail=str(exc)) from exc
        _delete_poster_category_localization_override(category_id)
        _invalidate_poster_menu_cache()
        return Response(status_code=status.HTTP_204_NO_CONTENT)

    _ensure_admin_menu_write_allowed()
    try:
        with get_conn() as conn:
            deleted = category_repo.delete(conn, category_id)
    except ValueError as exc:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail=str(exc)) from exc
    if not deleted:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='Category not found.')
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@app.post('/api/v1/admin/categories/reorder')
def admin_reorder_categories(
    body: CategoryReorderIn,
    _: dict[str, Any] = Depends(_require_admin),
) -> dict[str, list[dict[str, Any]]]:
    if _use_poster_menu_source():
        _set_poster_category_sort_overrides([int(item) for item in body.ids])
        menu = _require_poster_menu_snapshot()
        return {'results': _poster_admin_categories(menu)}

    _ensure_admin_menu_write_allowed()
    try:
        with get_conn() as conn:
            rows = category_repo.reorder(conn, body.ids)
    except ValueError as exc:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc)) from exc
    return {'results': rows}


@app.get('/api/v1/admin/dashboard/stats')
def admin_dashboard_stats(_: dict[str, Any] = Depends(_require_admin)) -> dict[str, Any]:
    with get_conn() as conn:
        stats = dashboard_repo.stats(conn)
    return stats


@app.get('/api/v1/admin/orders')
def admin_list_orders(
    search: Optional[str] = Query(default=None),
    statusValue: Optional[str] = Query(default=None, alias='status'),
    paymentStatus: Optional[str] = Query(default=None, alias='paymentStatus'),
    limit: int = Query(default=300, ge=1, le=1000),
    _: dict[str, Any] = Depends(_require_admin),
) -> dict[str, list[dict[str, Any]]]:
    with get_conn() as conn:
        rows = order_repo.list_for_admin(
            conn,
            search=search,
            status=statusValue,
            payment_status=paymentStatus,
            limit=limit,
        )
        synced = [_sync_order_status_from_poster(conn, row) for row in rows]
    return {'results': synced}


@app.patch('/api/v1/admin/orders/{order_id}')
def admin_update_order(
    order_id: int,
    body: AdminOrderUpdateIn,
    _: dict[str, Any] = Depends(_require_admin),
) -> dict[str, Any]:
    payload = body.model_dump(by_alias=True)
    with get_conn() as conn:
        row = order_repo.update_admin_status(
            conn,
            order_id,
            status_value=payload['status'],
            payment_status=payload['paymentStatus'],
        )
    if not row:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='Order not found.')
    return row


@app.get('/api/v1/admin/users')
def admin_list_users(
    search: Optional[str] = Query(default=None),
    limit: int = Query(default=200, ge=1, le=1000),
    _: dict[str, Any] = Depends(_require_admin),
) -> dict[str, list[dict[str, Any]]]:
    with get_conn() as conn:
        rows = user_repo.list_for_admin(conn, search=search, limit=limit)
    return {'results': rows}


@app.post('/api/v1/admin/users', status_code=status.HTTP_201_CREATED)
def admin_create_user(
    body: AdminUserIn,
    _: dict[str, Any] = Depends(_require_admin),
) -> dict[str, Any]:
    payload = body.model_dump(by_alias=True)
    try:
        with get_conn() as conn:
            row = user_repo.create_for_admin(conn, payload)
    except ValueError as exc:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail=str(exc)) from exc
    return row


@app.put('/api/v1/admin/users/{user_id}')
def admin_update_user(
    user_id: int,
    body: AdminUserIn,
    _: dict[str, Any] = Depends(_require_admin),
) -> dict[str, Any]:
    payload = body.model_dump(by_alias=True)
    try:
        with get_conn() as conn:
            row = user_repo.update_for_admin(conn, user_id, payload)
    except ValueError as exc:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail=str(exc)) from exc
    if not row:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='User not found.')
    return row


@app.delete('/api/v1/admin/users/{user_id}', status_code=status.HTTP_204_NO_CONTENT)
def admin_delete_user(
    user_id: int,
    _: dict[str, Any] = Depends(_require_admin),
) -> Response:
    try:
        with get_conn() as conn:
            deleted = user_repo.delete_for_admin(conn, user_id)
    except ValueError as exc:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail=str(exc)) from exc
    if not deleted:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='User not found.')
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@app.get('/api/v1/admin/banners')
def admin_list_banners(_: dict[str, Any] = Depends(_require_admin)) -> dict[str, list[dict[str, Any]]]:
    with get_conn() as conn:
        rows = dashboard_repo.list_banners(conn, active_only=False)
    return {'results': rows}


@app.get('/api/v1/admin/banners/{banner_id}')
def admin_get_banner(
    banner_id: int,
    _: dict[str, Any] = Depends(_require_admin),
) -> dict[str, Any]:
    with get_conn() as conn:
        row = dashboard_repo.get_banner(conn, banner_id, active_only=False)
    if not row:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='Banner not found.')
    return row


@app.post('/api/v1/admin/banners', status_code=status.HTTP_201_CREATED)
def admin_create_banner(
    body: AdminBannerIn,
    _: dict[str, Any] = Depends(_require_admin),
) -> dict[str, Any]:
    payload = body.model_dump(by_alias=True)
    with get_conn() as conn:
        _validate_banner_action_targets(conn, payload)
        row = dashboard_repo.create_banner(conn, payload)
    return row


@app.put('/api/v1/admin/banners/{banner_id}')
def admin_update_banner(
    banner_id: int,
    body: AdminBannerIn,
    _: dict[str, Any] = Depends(_require_admin),
) -> dict[str, Any]:
    payload = body.model_dump(by_alias=True)
    with get_conn() as conn:
        _validate_banner_action_targets(conn, payload)
        row = dashboard_repo.update_banner(conn, banner_id, payload)
    if not row:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='Banner not found.')
    return row


@app.delete('/api/v1/admin/banners/{banner_id}', status_code=status.HTTP_204_NO_CONTENT)
def admin_delete_banner(
    banner_id: int,
    _: dict[str, Any] = Depends(_require_admin),
) -> Response:
    with get_conn() as conn:
        deleted = dashboard_repo.delete_banner(conn, banner_id)
    if not deleted:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='Banner not found.')
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@app.post('/api/v1/banners', status_code=status.HTTP_201_CREATED)
def create_banner(
    body: AdminBannerIn,
    _: dict[str, Any] = Depends(_require_admin),
) -> dict[str, Any]:
    payload = body.model_dump(by_alias=True)
    with get_conn() as conn:
        _validate_banner_action_targets(conn, payload)
        row = dashboard_repo.create_banner(conn, payload)
    return row


@app.put('/api/v1/banners/{banner_id}')
def update_banner(
    banner_id: int,
    body: AdminBannerIn,
    _: dict[str, Any] = Depends(_require_admin),
) -> dict[str, Any]:
    payload = body.model_dump(by_alias=True)
    with get_conn() as conn:
        _validate_banner_action_targets(conn, payload)
        row = dashboard_repo.update_banner(conn, banner_id, payload)
    if not row:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='Banner not found.')
    return row


@app.delete('/api/v1/banners/{banner_id}', status_code=status.HTTP_204_NO_CONTENT)
def remove_banner(
    banner_id: int,
    _: dict[str, Any] = Depends(_require_admin),
) -> Response:
    with get_conn() as conn:
        deleted = dashboard_repo.delete_banner(conn, banner_id)
    if not deleted:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='Banner not found.')
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@app.get('/api/v1/admin/notifications')
def admin_list_notifications(
    _: dict[str, Any] = Depends(_require_admin),
) -> dict[str, list[dict[str, Any]]]:
    with get_conn() as conn:
        rows = dashboard_repo.list_notifications(conn)
    return {'results': rows}


@app.post('/api/v1/admin/notifications', status_code=status.HTTP_201_CREATED)
def admin_create_notification(
    body: AdminNotificationIn,
    _: dict[str, Any] = Depends(_require_admin),
) -> dict[str, Any]:
    payload = body.model_dump(by_alias=True)
    try:
        with get_conn() as conn:
            row = dashboard_repo.create_notification(conn, payload)
            _dispatch_notification_delivery(conn, row)
            row['deliveryLogs'] = dashboard_repo.list_notification_delivery_logs(
                conn,
                notification_id=int(row.get('id') or 0),
                limit=30,
            )
    except ValueError as exc:
        raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail=str(exc))
    return row


@app.put('/api/v1/admin/notifications/{notification_id}')
def admin_update_notification(
    notification_id: int,
    body: AdminNotificationIn,
    _: dict[str, Any] = Depends(_require_admin),
) -> dict[str, Any]:
    payload = body.model_dump(by_alias=True)
    try:
        with get_conn() as conn:
            row = dashboard_repo.update_notification(conn, notification_id, payload)
            if row:
                row['deliveryLogs'] = dashboard_repo.list_notification_delivery_logs(
                    conn,
                    notification_id=int(row.get('id') or 0),
                    limit=30,
                )
    except ValueError as exc:
        raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail=str(exc))
    if not row:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='Notification not found.')
    return row


@app.delete('/api/v1/admin/notifications/{notification_id}', status_code=status.HTTP_204_NO_CONTENT)
def admin_delete_notification(
    notification_id: int,
    _: dict[str, Any] = Depends(_require_admin),
) -> Response:
    with get_conn() as conn:
        deleted = dashboard_repo.delete_notification(conn, notification_id)
    if not deleted:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='Notification not found.')
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@app.get('/api/v1/admin/faqs')
def admin_list_faq(_: dict[str, Any] = Depends(_require_admin)) -> dict[str, list[dict[str, Any]]]:
    with get_conn() as conn:
        rows = dashboard_repo.list_faq(conn, active_only=False)
    return {'results': rows}


@app.post('/api/v1/admin/faqs', status_code=status.HTTP_201_CREATED)
def admin_create_faq(
    body: AdminFaqIn,
    _: dict[str, Any] = Depends(_require_admin),
) -> dict[str, Any]:
    with get_conn() as conn:
        row = dashboard_repo.create_faq(conn, body.model_dump())
    return row


@app.put('/api/v1/admin/faqs/{faq_id}')
def admin_update_faq(
    faq_id: int,
    body: AdminFaqIn,
    _: dict[str, Any] = Depends(_require_admin),
) -> dict[str, Any]:
    with get_conn() as conn:
        row = dashboard_repo.update_faq(conn, faq_id, body.model_dump())
    if not row:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='FAQ not found.')
    return row


@app.delete('/api/v1/admin/faqs/{faq_id}', status_code=status.HTTP_204_NO_CONTENT)
def admin_delete_faq(
    faq_id: int,
    _: dict[str, Any] = Depends(_require_admin),
) -> Response:
    with get_conn() as conn:
        deleted = dashboard_repo.delete_faq(conn, faq_id)
    if not deleted:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='FAQ not found.')
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@app.get('/api/v1/admin/settings')
def admin_get_settings(_: dict[str, Any] = Depends(_require_admin)) -> dict[str, Any]:
    with get_conn() as conn:
        row = dashboard_repo.get_settings(conn)
    return row


@app.post('/api/v1/admin/settings', status_code=status.HTTP_201_CREATED)
def admin_create_settings(
    body: AdminSettingsIn,
    _: dict[str, Any] = Depends(_require_admin),
) -> dict[str, Any]:
    payload = body.model_dump(by_alias=True)
    with get_conn() as conn:
        row = dashboard_repo.create_settings(conn, payload)
    return row


@app.put('/api/v1/admin/settings')
def admin_update_settings(
    body: AdminSettingsIn,
    _: dict[str, Any] = Depends(_require_admin),
) -> dict[str, Any]:
    payload = body.model_dump(by_alias=True)
    with get_conn() as conn:
        row = dashboard_repo.update_settings(conn, payload)
    return row


@app.delete('/api/v1/admin/settings')
def admin_reset_settings(_: dict[str, Any] = Depends(_require_admin)) -> dict[str, Any]:
    with get_conn() as conn:
        row = dashboard_repo.reset_settings(conn)
    return row


@app.get('/api/v1/admin/profile')
def admin_get_profile(claims: dict[str, Any] = Depends(_require_admin)) -> dict[str, Any]:
    with get_conn() as conn:
        admin = admin_repo.get_by_id(conn, int(claims['sub']))
    if not admin:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='Admin not found.')
    return {
        'id': admin['id'],
        'email': admin['email'],
        'fullName': admin['full_name'],
    }


@app.put('/api/v1/admin/profile')
def admin_update_profile(
    body: AdminProfileUpdateIn,
    claims: dict[str, Any] = Depends(_require_admin),
) -> dict[str, Any]:
    payload = body.model_dump(by_alias=True)
    password = (payload.get('password') or '').strip()
    pass_hash = hash_password(password) if password else None
    with get_conn() as conn:
        updated = admin_repo.update_profile(
            conn,
            int(claims['sub']),
            full_name=payload['fullName'],
            password_hash=pass_hash,
        )
    if not updated:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='Admin not found.')
    return {
        'id': updated['id'],
        'email': updated['email'],
        'fullName': updated['full_name'],
    }


@app.get('/api/v1/categories')
def public_categories(lang: str = Query(default='ru')) -> dict[str, list[dict[str, Any]]]:
    lang = _normalize_lang(lang)
    if _use_poster_menu_source():
        poster_menu = _require_poster_menu_snapshot()
        localized = _localize_poster_menu(poster_menu, lang)
        rows: list[dict[str, Any]] = []
        for idx, category in enumerate(localized.get('categories') or []):
            if not isinstance(category, dict):
                continue
            name = str(category.get('name') or '').strip()
            rows.append(
                {
                    'id': int(category.get('id') or idx + 1),
                    'name': name,
                    'description': category.get('description'),
                    'nameEn': name,
                    'nameRu': name,
                    'nameUz': name,
                    'descriptionEn': category.get('description'),
                    'descriptionRu': category.get('description'),
                    'descriptionUz': category.get('description'),
                    'isActive': True,
                    'sortOrder': idx,
                }
            )
        return {'results': rows}

    with get_conn() as conn:
        rows = category_repo.list(conn, active_only=True)
    return {'results': [_localized_category(row, lang) for row in rows]}


def _discount_percent(price: float, old_price: Optional[float]) -> Optional[int]:
    if old_price is None or old_price <= price or old_price <= 0:
        return None
    return round(((old_price - price) / old_price) * 100)


def _parse_dt(value: Any) -> Optional[datetime]:
    text = str(value or '').strip()
    if not text:
        return None
    for fmt in (
        '%Y-%m-%d %H:%M:%S',
        '%Y-%m-%dT%H:%M:%S',
        '%Y-%m-%dT%H:%M',
    ):
        try:
            dt = datetime.strptime(text, fmt)
            return dt.replace(tzinfo=timezone.utc)
        except ValueError:
            continue
    try:
        dt = datetime.fromisoformat(text.replace('Z', '+00:00'))
    except ValueError:
        return None
    if dt.tzinfo is None:
        return dt.replace(tzinfo=timezone.utc)
    return dt.astimezone(timezone.utc)


def _normalize_lang(lang: Optional[str]) -> str:
    value = str(lang or 'ru').strip().lower()
    if value.startswith('en'):
        return 'en'
    if value.startswith('uz'):
        return 'uz'
    return 'ru'


def _to_int(value: Any) -> Optional[int]:
    if value is None:
        return None
    try:
        return int(str(value).strip())
    except (TypeError, ValueError):
        return None


def _pick_lang_value(
    row: dict[str, Any],
    *,
    lang: str,
    base_key: str,
    en_key: str,
    ru_key: str,
    uz_key: str,
) -> Any:
    if lang == 'en':
        preferred = row.get(en_key)
    elif lang == 'uz':
        preferred = row.get(uz_key)
    else:
        preferred = row.get(ru_key)
    if preferred is not None and str(preferred).strip():
        return preferred
    fallback = row.get(base_key)
    if fallback is not None and str(fallback).strip():
        return fallback
    for key in (ru_key, en_key, uz_key):
        value = row.get(key)
        if value is not None and str(value).strip():
            return value
    return fallback


def _effective_old_price(row: dict[str, Any]) -> Optional[float]:
    old_price = row.get('oldPrice')
    price = float(row.get('price') or 0)
    if old_price is None or old_price <= price:
        return None
    starts_at = _parse_dt(row.get('discountStartAt'))
    ends_at = _parse_dt(row.get('discountEndAt'))
    now = datetime.now(timezone.utc)
    if starts_at is not None and now < starts_at:
        return None
    if ends_at is not None and now > ends_at:
        return None
    return old_price


def _public_product(row: dict[str, Any], *, lang: str = 'ru') -> dict[str, Any]:
    price = float(row['price'])
    effective_old_price = _effective_old_price(row)
    title = str(
        _pick_lang_value(
            row,
            lang=lang,
            base_key='title',
            en_key='titleEn',
            ru_key='titleRu',
            uz_key='titleUz',
        )
        or ''
    )
    description = _pick_lang_value(
        row,
        lang=lang,
        base_key='description',
        en_key='descriptionEn',
        ru_key='descriptionRu',
        uz_key='descriptionUz',
    )
    category_name = _pick_lang_value(
        row,
        lang=lang,
        base_key='categoryName',
        en_key='categoryNameEn',
        ru_key='categoryNameRu',
        uz_key='categoryNameUz',
    )
    return {
        'id': int(row['id']),
        'title': title,
        'name': title,
        'description': description,
        'imageUrl': row.get('imageUrl'),
        'image_url': row.get('imageUrl'),
        'categoryId': int(row['categoryId']),
        'categoryName': category_name,
        'categoryNameEn': row.get('categoryNameEn'),
        'categoryNameRu': row.get('categoryNameRu'),
        'categoryNameUz': row.get('categoryNameUz'),
        'price': price,
        'oldPrice': effective_old_price,
        'old_price': effective_old_price,
        'discountPercent': _discount_percent(price, effective_old_price),
        'isActive': bool(row.get('isActive', True)),
        'isDrink': bool(row.get('isDrink', False)),
        'isRecommended': bool(row.get('isRecommended', False)),
        'isPopular': bool(row.get('isPopular', False)),
        'isNew': bool(row.get('isNew', False)),
        'sortOrder': int(row.get('sortOrder') or 0),
        'titleEn': row.get('titleEn'),
        'titleRu': row.get('titleRu'),
        'titleUz': row.get('titleUz'),
        'descriptionEn': row.get('descriptionEn'),
        'descriptionRu': row.get('descriptionRu'),
        'descriptionUz': row.get('descriptionUz'),
    }


def _admin_product(row: dict[str, Any]) -> dict[str, Any]:
    old_price = row.get('oldPrice')
    price = float(row['price'])
    result = _public_product(row)
    result['oldPrice'] = old_price
    result['old_price'] = old_price
    result['discountPercent'] = _discount_percent(price, old_price)
    result['discountStartAt'] = row.get('discountStartAt')
    result['discountEndAt'] = row.get('discountEndAt')
    result['discountActive'] = _effective_old_price(row) is not None
    return result


def _menu_product(row: dict[str, Any], *, lang: str) -> dict[str, Any]:
    data = _public_product(row, lang=lang)
    data['modifiers'] = []
    return data


def _address_out(row: dict[str, Any]) -> dict[str, Any]:
    return {
        'id': row['id'],
        'user_id': row['userId'],
        'label': row.get('label'),
        'address_line': row['addressLine'],
        'lat': row.get('lat'),
        'lng': row.get('lng'),
    }


def _order_summary(row: dict[str, Any]) -> dict[str, Any]:
    return {
        'id': int(row['id']),
        'status': str(row['status']),
        'payment_status': str(row['payment_status']),
        'poster_order_id': row.get('poster_order_id'),
        'poster_status': row.get('poster_status'),
    }


def _get_poster_menu_snapshot() -> Optional[dict[str, list[dict[str, Any]]]]:
    global _poster_menu_cache_data, _poster_menu_cache_at
    if not POSTER_MENU_ENABLED or not poster_client.enabled:
        return None
    now = time.monotonic()
    if (
        _poster_menu_cache_data is not None
        and (now - _poster_menu_cache_at) <= POSTER_MENU_CACHE_SECONDS
    ):
        return _poster_menu_cache_data
    try:
        menu = poster_client.get_menu_catalog()
    except PosterSyncError as exc:
        logger.warning('poster menu fetch failed: %s', exc)
        return _poster_menu_cache_data
    _poster_menu_cache_data = menu
    _poster_menu_cache_at = now
    return menu


def _use_poster_menu_source() -> bool:
    return MENU_SOURCE == 'poster'


def _build_menu_from_database(conn, lang: str) -> dict[str, list[dict[str, Any]]]:
    categories = category_repo.list(conn, active_only=True)
    products = product_repo.list(
        conn,
        ProductFilters(active_only=True),
    )
    by_category: dict[int, list[dict[str, Any]]] = {}
    for row in products:
        category_id = int(row.get('categoryId') or 0)
        by_category.setdefault(category_id, []).append(_menu_product(row, lang=lang))
    result_categories: list[dict[str, Any]] = []
    for category in categories:
        category_products = by_category.get(int(category['id']), [])
        if not category_products:
            continue
        name = _pick_lang_value(
            category,
            lang=lang,
            base_key='name',
            en_key='nameEn',
            ru_key='nameRu',
            uz_key='nameUz',
        )
        description = _pick_lang_value(
            category,
            lang=lang,
            base_key='description',
            en_key='descriptionEn',
            ru_key='descriptionRu',
            uz_key='descriptionUz',
        )
        result_categories.append(
            {
                'id': int(category['id']),
                'name': str(name or ''),
                'description': description,
                'nameEn': category.get('nameEn'),
                'nameRu': category.get('nameRu'),
                'nameUz': category.get('nameUz'),
                'descriptionEn': category.get('descriptionEn'),
                'descriptionRu': category.get('descriptionRu'),
                'descriptionUz': category.get('descriptionUz'),
                'products': category_products,
            },
        )
    return {'categories': result_categories}


def _require_poster_menu_snapshot() -> dict[str, list[dict[str, Any]]]:
    menu = _get_poster_menu_snapshot()
    if menu is None:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail='Poster menu is unavailable. Check POSTER_* configuration.',
        )
    menu = _apply_poster_category_sort_overrides(menu)
    return _apply_poster_product_sort_overrides(menu)


def _invalidate_poster_menu_cache() -> None:
    global _poster_menu_cache_data, _poster_menu_cache_at
    _poster_menu_cache_data = None
    _poster_menu_cache_at = 0.0


def _poster_pick_text(payload: dict[str, Any], *keys: str) -> str:
    for key in keys:
        value = payload.get(key)
        if value is None:
            continue
        text = str(value).strip()
        if text:
            return text
    return ''


def _poster_pick_optional_text(payload: dict[str, Any], *keys: str) -> Optional[str]:
    text = _poster_pick_text(payload, *keys)
    if not text:
        return None
    return text


def _ensure_admin_menu_write_allowed() -> None:
    if _use_poster_menu_source():
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail='Poster menu write is not available for current backend configuration.',
        )


def _poster_admin_categories(menu: dict[str, list[dict[str, Any]]]) -> list[dict[str, Any]]:
    localizations = _poster_category_localization_overrides()
    rows: list[dict[str, Any]] = []
    for index, category in enumerate(menu.get('categories') or []):
        if not isinstance(category, dict):
            continue
        category_id_raw = category.get('id')
        if category_id_raw is None:
            category_id = index + 1
        else:
            category_id = int(category_id_raw)
        if category_id <= 0:
            continue
        name = str(category.get('name') or '').strip()
        description = category.get('description')
        localized = localizations.get(category_id) or {}
        name_en = str(localized.get('nameEn') or name)
        name_ru = str(localized.get('nameRu') or name)
        name_uz = str(localized.get('nameUz') or name)
        description_en = (
            localized.get('descriptionEn')
            if localized.get('descriptionEn') is not None
            else description
        )
        description_ru = (
            localized.get('descriptionRu')
            if localized.get('descriptionRu') is not None
            else description
        )
        description_uz = (
            localized.get('descriptionUz')
            if localized.get('descriptionUz') is not None
            else description
        )
        rows.append(
            {
                'id': category_id,
                'name': str(localized.get('name') or name_ru or name_en or name_uz or name),
                'nameEn': name_en,
                'nameRu': name_ru,
                'nameUz': name_uz,
                'description': (
                    localized.get('description')
                    if localized.get('description') is not None
                    else description_ru
                ),
                'descriptionEn': description_en,
                'descriptionRu': description_ru,
                'descriptionUz': description_uz,
                'sortOrder': int(category.get('sort_order') or index),
                'isActive': bool(category.get('is_active', True)),
            }
        )
    rows.sort(key=lambda item: (int(item.get('sortOrder') or 0), int(item.get('id') or 0)))
    return rows


def _flatten_poster_menu_products(menu: dict[str, list[dict[str, Any]]]) -> list[dict[str, Any]]:
    category_localizations = _poster_category_localization_overrides()
    product_localizations = _poster_product_localization_overrides()
    rows: list[dict[str, Any]] = []
    categories = menu.get('categories') or []
    for category in categories:
        if not isinstance(category, dict):
            continue
        category_id = int(category.get('id') or 0)
        category_name = str(category.get('name') or '').strip()
        category_description = category.get('description')
        localized_category = category_localizations.get(category_id) or {}
        category_name_en = str(localized_category.get('nameEn') or category_name)
        category_name_ru = str(localized_category.get('nameRu') or category_name)
        category_name_uz = str(localized_category.get('nameUz') or category_name)
        category_description_en = (
            localized_category.get('descriptionEn')
            if localized_category.get('descriptionEn') is not None
            else category_description
        )
        category_description_ru = (
            localized_category.get('descriptionRu')
            if localized_category.get('descriptionRu') is not None
            else category_description
        )
        category_description_uz = (
            localized_category.get('descriptionUz')
            if localized_category.get('descriptionUz') is not None
            else category_description
        )
        products = category.get('products') or []
        for product in products:
            if not isinstance(product, dict):
                continue
            product_id = int(product.get('id') or 0)
            localized_product = product_localizations.get(product_id) or {}
            base_title = str(product.get('name') or product.get('title') or '')
            base_description = product.get('description')
            title_en = str(localized_product.get('titleEn') or base_title)
            title_ru = str(localized_product.get('titleRu') or base_title)
            title_uz = str(localized_product.get('titleUz') or base_title)
            description_en = (
                localized_product.get('descriptionEn')
                if localized_product.get('descriptionEn') is not None
                else base_description
            )
            description_ru = (
                localized_product.get('descriptionRu')
                if localized_product.get('descriptionRu') is not None
                else base_description
            )
            description_uz = (
                localized_product.get('descriptionUz')
                if localized_product.get('descriptionUz') is not None
                else base_description
            )
            price = float(product.get('price') or 0)
            rows.append(
                {
                    'id': product_id,
                    'title': str(
                        localized_product.get('title')
                        or title_ru
                        or title_en
                        or title_uz
                        or base_title
                    ),
                    'titleEn': title_en,
                    'titleRu': title_ru,
                    'titleUz': title_uz,
                    'description': (
                        localized_product.get('description')
                        if localized_product.get('description') is not None
                        else description_ru
                    ),
                    'descriptionEn': description_en,
                    'descriptionRu': description_ru,
                    'descriptionUz': description_uz,
                    'imageUrl': product.get('image_url'),
                    'categoryId': category_id,
                    'categoryName': str(
                        localized_category.get('name')
                        or category_name_ru
                        or category_name_en
                        or category_name_uz
                        or category_name
                    ),
                    'categoryNameEn': category_name_en,
                    'categoryNameRu': category_name_ru,
                    'categoryNameUz': category_name_uz,
                    'categoryDescription': (
                        localized_category.get('description')
                        if localized_category.get('description') is not None
                        else category_description_ru
                    ),
                    'categoryDescriptionEn': category_description_en,
                    'categoryDescriptionRu': category_description_ru,
                    'categoryDescriptionUz': category_description_uz,
                    'price': price,
                    'oldPrice': product.get('old_price'),
                    'isActive': bool(product.get('is_active', True)),
                    'isDrink': (
                        _to_int(product.get('type')) == 2
                        if product.get('type') is not None
                        else _is_drink_category(category_name)
                    ),
                    'isRecommended': False,
                    'isPopular': False,
                    'isNew': False,
                    'sortOrder': int(product.get('sort_order') or 0),
                },
            )
    overrides = _poster_product_active_overrides()
    if overrides:
        for row in rows:
            product_id = int(row.get('id') or 0)
            if product_id in overrides:
                row['isActive'] = bool(overrides[product_id])
    return rows


def _poster_product_sort_overrides() -> dict[int, dict[str, int]]:
    with get_conn() as conn:
        rows = conn.execute(
            'SELECT product_id, category_id, sort_order FROM poster_product_sort_overrides',
        ).fetchall()
    out: dict[int, dict[str, int]] = {}
    for row in rows:
        product_id = int(row['product_id'] or 0)
        if product_id <= 0:
            continue
        out[product_id] = {
            'categoryId': int(row['category_id'] or 0),
            'sortOrder': int(row['sort_order'] or 0),
        }
    return out


def _poster_category_sort_overrides() -> dict[int, int]:
    with get_conn() as conn:
        rows = conn.execute(
            'SELECT category_id, sort_order FROM poster_category_sort_overrides',
        ).fetchall()
    return {
        int(row['category_id']): int(row['sort_order'] or 0)
        for row in rows
        if row['category_id'] is not None
    }


def _apply_poster_category_sort_overrides(
    menu: dict[str, list[dict[str, Any]]],
) -> dict[str, list[dict[str, Any]]]:
    overrides = _poster_category_sort_overrides()
    categories = menu.get('categories') or []
    if not overrides or not categories:
        return menu

    indexed: list[tuple[int, int, dict[str, Any]]] = []
    for index, category in enumerate(categories):
        if not isinstance(category, dict):
            continue
        category_id = int(category.get('id') or 0)
        sort_value = int(overrides.get(category_id, 100000 + index))
        category_copy = dict(category)
        category_copy['sort_order'] = sort_value
        indexed.append((sort_value, index, category_copy))
    return {'categories': [item[2] for item in sorted(indexed, key=lambda row: (row[0], row[1]))]}


def _apply_poster_product_sort_overrides(
    menu: dict[str, list[dict[str, Any]]],
) -> dict[str, list[dict[str, Any]]]:
    overrides = _poster_product_sort_overrides()
    categories = menu.get('categories') or []
    if not overrides or not categories:
        return menu

    next_categories: list[dict[str, Any]] = []
    for category in categories:
        if not isinstance(category, dict):
            continue
        category_id = int(category.get('id') or 0)
        products = list(category.get('products') or [])
        if products:
            indexed = []
            for index, product in enumerate(products):
                if not isinstance(product, dict):
                    continue
                product_id = int(product.get('id') or 0)
                override = overrides.get(product_id)
                if override and int(override.get('categoryId') or 0) == category_id:
                    sort_value = int(override.get('sortOrder') or 0)
                else:
                    sort_value = 100000 + index
                product_copy = dict(product)
                product_copy['sort_order'] = sort_value
                indexed.append((sort_value, index, product_copy))
            products = [item[2] for item in sorted(indexed, key=lambda row: (row[0], row[1]))]
        category_copy = dict(category)
        category_copy['products'] = products
        next_categories.append(category_copy)
    return {'categories': next_categories}


def _poster_product_active_overrides() -> dict[int, bool]:
    with get_conn() as conn:
        rows = conn.execute(
            'SELECT product_id, is_active FROM poster_product_overrides',
        ).fetchall()
    return {
        int(row['product_id']): bool(row['is_active'])
        for row in rows
        if int(row['product_id']) > 0
    }


def _set_poster_product_active_override(product_id: int, is_active: bool) -> None:
    if product_id <= 0:
        return
    with get_conn() as conn:
        conn.execute(
            'INSERT INTO poster_product_overrides(product_id, is_active, updated_at) '
            'VALUES (?, ?, CURRENT_TIMESTAMP) '
            'ON CONFLICT(product_id) DO UPDATE SET '
            'is_active = excluded.is_active, '
            'updated_at = CURRENT_TIMESTAMP',
            (int(product_id), 1 if is_active else 0),
        )


def _delete_poster_product_active_override(product_id: int) -> None:
    if product_id <= 0:
        return
    with get_conn() as conn:
        conn.execute(
            'DELETE FROM poster_product_overrides WHERE product_id = ?',
            (int(product_id),),
        )


def _set_poster_product_sort_overrides(
    product_ids: list[int],
    *,
    menu: Optional[dict[str, list[dict[str, Any]]]] = None,
) -> None:
    deduped: list[int] = []
    seen: set[int] = set()
    for product_id in product_ids:
        normalized = int(product_id or 0)
        if normalized <= 0 or normalized in seen:
            continue
        deduped.append(normalized)
        seen.add(normalized)
    if not deduped:
        return

    snapshot = menu or _get_poster_menu_snapshot() or {'categories': []}
    product_category: dict[int, int] = {}
    for category in snapshot.get('categories') or []:
        if not isinstance(category, dict):
            continue
        category_id = int(category.get('id') or 0)
        for product in category.get('products') or []:
            if not isinstance(product, dict):
                continue
            product_id = int(product.get('id') or 0)
            if product_id > 0:
                product_category[product_id] = category_id

    if deduped[0] not in product_category:
        return
    first_category_id = int(product_category[deduped[0]])

    scoped_ids = [
        product_id for product_id in deduped
        if int(product_category.get(product_id) or 0) == first_category_id
    ]
    if not scoped_ids:
        return

    with get_conn() as conn:
        conn.execute(
            'DELETE FROM poster_product_sort_overrides WHERE category_id = ?',
            (first_category_id,),
        )
        for index, product_id in enumerate(scoped_ids):
            conn.execute(
                'INSERT INTO poster_product_sort_overrides(product_id, category_id, sort_order, updated_at) '
                'VALUES (?, ?, ?, CURRENT_TIMESTAMP) '
                'ON CONFLICT(product_id) DO UPDATE SET '
                'category_id = excluded.category_id, '
                'sort_order = excluded.sort_order, '
                'updated_at = CURRENT_TIMESTAMP',
                (product_id, first_category_id, index),
            )


def _set_poster_category_sort_overrides(category_ids: list[int]) -> None:
    deduped: list[int] = []
    seen: set[int] = set()
    for category_id in category_ids:
        normalized = int(category_id or 0)
        if normalized in seen:
            continue
        deduped.append(normalized)
        seen.add(normalized)
    if not deduped:
        return

    with get_conn() as conn:
        conn.execute('DELETE FROM poster_category_sort_overrides')
        for index, category_id in enumerate(deduped):
            conn.execute(
                'INSERT INTO poster_category_sort_overrides(category_id, sort_order, updated_at) '
                'VALUES (?, ?, CURRENT_TIMESTAMP) '
                'ON CONFLICT(category_id) DO UPDATE SET '
                'sort_order = excluded.sort_order, '
                'updated_at = CURRENT_TIMESTAMP',
                (category_id, index),
            )


def _clean_localized_text(value: Any) -> Optional[str]:
    text = str(value or '').strip()
    return text or None


def _poster_product_localization_overrides() -> dict[int, dict[str, Optional[str]]]:
    with get_conn() as conn:
        rows = conn.execute(
            'SELECT product_id, title_en, title_ru, title_uz, description_en, description_ru, description_uz '
            'FROM poster_product_localizations',
        ).fetchall()
    out: dict[int, dict[str, Optional[str]]] = {}
    for row in rows:
        product_id = int(row['product_id'] or 0)
        if product_id <= 0:
            continue
        out[product_id] = {
            'title': _clean_localized_text(row['title_ru']) or _clean_localized_text(row['title_en']),
            'titleEn': _clean_localized_text(row['title_en']),
            'titleRu': _clean_localized_text(row['title_ru']),
            'titleUz': _clean_localized_text(row['title_uz']),
            'description': (
                _clean_localized_text(row['description_ru'])
                if row['description_ru'] is not None
                else None
            ),
            'descriptionEn': (
                _clean_localized_text(row['description_en'])
                if row['description_en'] is not None
                else None
            ),
            'descriptionRu': (
                _clean_localized_text(row['description_ru'])
                if row['description_ru'] is not None
                else None
            ),
            'descriptionUz': (
                _clean_localized_text(row['description_uz'])
                if row['description_uz'] is not None
                else None
            ),
        }
    return out


def _set_poster_product_localization_override(product_id: int, payload: dict[str, Any]) -> None:
    if product_id <= 0:
        return
    title_default = _clean_localized_text(payload.get('title'))
    description_default = _clean_localized_text(payload.get('description'))
    with get_conn() as conn:
        conn.execute(
            'INSERT INTO poster_product_localizations('
            'product_id, title_en, title_ru, title_uz, description_en, description_ru, description_uz, updated_at'
            ') VALUES (?, ?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP) '
            'ON CONFLICT(product_id) DO UPDATE SET '
            'title_en = excluded.title_en, '
            'title_ru = excluded.title_ru, '
            'title_uz = excluded.title_uz, '
            'description_en = excluded.description_en, '
            'description_ru = excluded.description_ru, '
            'description_uz = excluded.description_uz, '
            'updated_at = CURRENT_TIMESTAMP',
            (
                int(product_id),
                _clean_localized_text(payload.get('titleEn')) or title_default,
                _clean_localized_text(payload.get('titleRu')) or title_default,
                _clean_localized_text(payload.get('titleUz')) or title_default,
                (
                    _clean_localized_text(payload.get('descriptionEn'))
                    if payload.get('descriptionEn') is not None
                    else description_default
                ),
                (
                    _clean_localized_text(payload.get('descriptionRu'))
                    if payload.get('descriptionRu') is not None
                    else description_default
                ),
                (
                    _clean_localized_text(payload.get('descriptionUz'))
                    if payload.get('descriptionUz') is not None
                    else description_default
                ),
            ),
        )


def _delete_poster_product_localization_override(product_id: int) -> None:
    if product_id <= 0:
        return
    with get_conn() as conn:
        conn.execute(
            'DELETE FROM poster_product_localizations WHERE product_id = ?',
            (int(product_id),),
        )


def _poster_category_localization_overrides() -> dict[int, dict[str, Optional[str]]]:
    with get_conn() as conn:
        rows = conn.execute(
            'SELECT category_id, name_en, name_ru, name_uz, description_en, description_ru, description_uz '
            'FROM poster_category_localizations',
        ).fetchall()
    out: dict[int, dict[str, Optional[str]]] = {}
    for row in rows:
        category_id = int(row['category_id'] or 0)
        if category_id <= 0:
            continue
        out[category_id] = {
            'name': _clean_localized_text(row['name_ru']) or _clean_localized_text(row['name_en']),
            'nameEn': _clean_localized_text(row['name_en']),
            'nameRu': _clean_localized_text(row['name_ru']),
            'nameUz': _clean_localized_text(row['name_uz']),
            'description': (
                _clean_localized_text(row['description_ru'])
                if row['description_ru'] is not None
                else None
            ),
            'descriptionEn': (
                _clean_localized_text(row['description_en'])
                if row['description_en'] is not None
                else None
            ),
            'descriptionRu': (
                _clean_localized_text(row['description_ru'])
                if row['description_ru'] is not None
                else None
            ),
            'descriptionUz': (
                _clean_localized_text(row['description_uz'])
                if row['description_uz'] is not None
                else None
            ),
        }
    return out


def _set_poster_category_localization_override(category_id: int, payload: dict[str, Any]) -> None:
    if category_id <= 0:
        return
    name_default = _clean_localized_text(payload.get('name'))
    description_default = _clean_localized_text(payload.get('description'))
    with get_conn() as conn:
        conn.execute(
            'INSERT INTO poster_category_localizations('
            'category_id, name_en, name_ru, name_uz, description_en, description_ru, description_uz, updated_at'
            ') VALUES (?, ?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP) '
            'ON CONFLICT(category_id) DO UPDATE SET '
            'name_en = excluded.name_en, '
            'name_ru = excluded.name_ru, '
            'name_uz = excluded.name_uz, '
            'description_en = excluded.description_en, '
            'description_ru = excluded.description_ru, '
            'description_uz = excluded.description_uz, '
            'updated_at = CURRENT_TIMESTAMP',
            (
                int(category_id),
                _clean_localized_text(payload.get('nameEn')) or name_default,
                _clean_localized_text(payload.get('nameRu')) or name_default,
                _clean_localized_text(payload.get('nameUz')) or name_default,
                (
                    _clean_localized_text(payload.get('descriptionEn'))
                    if payload.get('descriptionEn') is not None
                    else description_default
                ),
                (
                    _clean_localized_text(payload.get('descriptionRu'))
                    if payload.get('descriptionRu') is not None
                    else description_default
                ),
                (
                    _clean_localized_text(payload.get('descriptionUz'))
                    if payload.get('descriptionUz') is not None
                    else description_default
                ),
            ),
        )


def _delete_poster_category_localization_override(category_id: int) -> None:
    if category_id <= 0:
        return
    with get_conn() as conn:
        conn.execute(
            'DELETE FROM poster_category_localizations WHERE category_id = ?',
            (int(category_id),),
        )


def _localize_poster_menu(
    menu: dict[str, list[dict[str, Any]]],
    lang: str,
) -> dict[str, list[dict[str, Any]]]:
    rows = _active_poster_menu_products(menu)
    category_order: dict[int, tuple[int, int]] = {}
    for index, category in enumerate(menu.get('categories') or []):
        if not isinstance(category, dict):
            continue
        cat_id = int(category.get('id') or 0)
        category_order[cat_id] = (int(category.get('sort_order') or index), index)
    by_cat: dict[int, dict[str, Any]] = {}
    for row in rows:
        cat_id = int(row['categoryId'])
        if cat_id not in by_cat:
            by_cat[cat_id] = {
                'id': cat_id,
                'name': _pick_lang_value(
                    row,
                    lang=lang,
                    base_key='categoryName',
                    en_key='categoryNameEn',
                    ru_key='categoryNameRu',
                    uz_key='categoryNameUz',
                ),
                'description': _pick_lang_value(
                    row,
                    lang=lang,
                    base_key='categoryDescription',
                    en_key='categoryDescriptionEn',
                    ru_key='categoryDescriptionRu',
                    uz_key='categoryDescriptionUz',
                ),
                'products': [],
            }
        by_cat[cat_id]['products'].append(_menu_product(row, lang=lang))
    categories = list(by_cat.values())
    categories.sort(
        key=lambda item: (
            category_order.get(int(item.get('id') or 0), (999999, 999999))[0],
            category_order.get(int(item.get('id') or 0), (999999, 999999))[1],
            int(item.get('id') or 0),
        ),
    )
    return {'categories': categories}


def _active_poster_menu_products(
    menu: dict[str, list[dict[str, Any]]],
) -> list[dict[str, Any]]:
    return [
        row for row in _flatten_poster_menu_products(menu)
        if bool(row.get('isActive', True))
    ]


def _dispatch_notification_delivery(conn, notification_row: dict[str, Any]) -> list[dict[str, str]]:
    notification_id = int(notification_row.get('id') or 0)
    if notification_id <= 0:
        return []
    channels = list(notification_row.get('deliveryTypes') or [])
    if not channels:
        channels = ['in_app']

    logs: list[dict[str, str]] = []
    if not bool(notification_row.get('isActive', True)):
        for channel in channels:
            logs.append(
                {
                    'channel': str(channel),
                    'status': 'skipped',
                    'message': 'Notification is inactive.',
                }
            )
    else:
        if 'in_app' in channels:
            logs.append(
                {
                    'channel': 'in_app',
                    'status': 'sent',
                    'message': 'Saved for in-app notification center.',
                }
            )
        if 'mailing' in channels:
            logs.append(
                {
                    'channel': 'mailing',
                    'status': 'sent',
                    'message': 'Broadcast available to all app users.',
                }
            )
        if 'push' in channels:
            logs.extend(_send_fcm_push(notification_row))

    for log_item in logs:
        dashboard_repo.log_notification_delivery(
            conn,
            notification_id=notification_id,
            channel=log_item.get('channel') or 'unknown',
            status=log_item.get('status') or 'unknown',
            message=log_item.get('message') or '',
        )
    return logs


def _send_fcm_push(notification_row: dict[str, Any]) -> list[dict[str, str]]:
    if not PUSH_NOTIFICATIONS_ENABLED:
        return [
            {
                'channel': 'push',
                'status': 'skipped',
                'message': 'Push notifications are disabled by configuration.',
            }
        ]
    service_account_info = _firebase_service_account_info()
    if service_account_info:
        return _send_fcm_push_http_v1(notification_row, service_account_info)
    if FCM_SERVER_KEY:
        return _send_fcm_push_legacy(notification_row)
    return [
        {
            'channel': 'push',
            'status': 'failed',
            'message': (
                'Push is enabled, but Firebase HTTP v1 credentials are missing. '
                'Set FIREBASE_SERVICE_ACCOUNT_FILE or FIREBASE_SERVICE_ACCOUNT_JSON.'
            ),
        }
    ]


def _notification_push_payload(
    notification_row: dict[str, Any],
    *,
    lang: str,
) -> tuple[str, str, str, dict[str, str]]:
    image_url = str(notification_row.get('imageUrl') or '').strip()
    shared_data = {
        'notificationId': str(notification_row.get('id') or ''),
        'type': str(notification_row.get('type') or 'info'),
        'titleEn': str(notification_row.get('titleEn') or notification_row.get('title') or ''),
        'titleRu': str(notification_row.get('titleRu') or notification_row.get('title') or ''),
        'titleUz': str(notification_row.get('titleUz') or notification_row.get('title') or ''),
        'messageEn': str(notification_row.get('messageEn') or notification_row.get('message') or ''),
        'messageRu': str(notification_row.get('messageRu') or notification_row.get('message') or ''),
        'messageUz': str(notification_row.get('messageUz') or notification_row.get('message') or ''),
    }
    if image_url:
        shared_data['imageUrl'] = image_url
    title = str(
        _pick_lang_value(
            notification_row,
            lang=lang,
            base_key='title',
            en_key='titleEn',
            ru_key='titleRu',
            uz_key='titleUz',
        )
        or ''
    )
    message = str(
        _pick_lang_value(
            notification_row,
            lang=lang,
            base_key='message',
            en_key='messageEn',
            ru_key='messageRu',
            uz_key='messageUz',
        )
        or ''
    )
    payload = {
        **shared_data,
        'lang': lang,
        'title': title,
        'message': message,
    }
    return title, message, image_url, payload


def _send_fcm_push_http_v1(
    notification_row: dict[str, Any],
    service_account_info: dict[str, Any],
) -> list[dict[str, str]]:
    project_id = _firebase_project_id()
    if not project_id:
        return [
            {
                'channel': 'push',
                'status': 'failed',
                'message': 'Firebase project id is missing.',
            }
        ]

    try:
        from google.auth.transport.requests import Request
        from google.oauth2 import service_account
    except Exception as exc:
        return [
            {
                'channel': 'push',
                'status': 'failed',
                'message': f'google-auth is not available: {exc}',
            }
        ]

    try:
        credentials = service_account.Credentials.from_service_account_info(
            service_account_info,
            scopes=['https://www.googleapis.com/auth/firebase.messaging'],
        )
        credentials.refresh(Request())
        access_token = str(credentials.token or '').strip()
    except Exception as exc:
        return [
            {
                'channel': 'push',
                'status': 'failed',
                'message': f'Failed to authorize Firebase service account: {exc}',
            }
        ]

    results: list[dict[str, str]] = []
    topic_by_lang = {'en': 'lang_en', 'ru': 'lang_ru', 'uz': 'lang_uz'}
    headers = {
        'Authorization': f'Bearer {access_token}',
        'Content-Type': 'application/json; charset=UTF-8',
    }
    endpoint = f'https://fcm.googleapis.com/v1/projects/{project_id}/messages:send'
    with httpx.Client(timeout=FCM_PUSH_TIMEOUT_SECONDS) as client:
        for lang, topic in topic_by_lang.items():
            title, message, image_url, data_payload = _notification_push_payload(
                notification_row,
                lang=lang,
            )
            body: dict[str, Any] = {
                'message': {
                    'topic': topic,
                    'notification': {
                        'title': title,
                        'body': message,
                    },
                    'data': data_payload,
                    'android': {
                        'priority': 'high',
                        'notification': {
                            'channel_id': 'sushixl_general',
                            'sound': 'default',
                        },
                    },
                    'apns': {
                        'headers': {
                            'apns-priority': '10',
                        },
                        'payload': {
                            'aps': {
                                'sound': 'default',
                            },
                        },
                    },
                }
            }
            if image_url:
                body['message']['android']['notification']['image'] = image_url
            try:
                response = client.post(endpoint, headers=headers, json=body)
                if response.is_success:
                    results.append(
                        {
                            'channel': f'push_{lang}',
                            'status': 'sent',
                            'message': f'Push sent to topic {topic} via Firebase HTTP v1.',
                        }
                    )
                else:
                    payload = response.text[:240].strip()
                    results.append(
                        {
                            'channel': f'push_{lang}',
                            'status': 'failed',
                            'message': f'Firebase HTTP v1 {response.status_code}: {payload}',
                        }
                    )
            except Exception as exc:
                results.append(
                    {
                        'channel': f'push_{lang}',
                        'status': 'failed',
                        'message': str(exc),
                    }
                )
    return results


def _send_fcm_push_legacy(notification_row: dict[str, Any]) -> list[dict[str, str]]:
    # Legacy server-key delivery remains only as a temporary compatibility path.
    # Public production releases should migrate to Firebase HTTP v1 service accounts.
    if not FCM_SERVER_KEY:
        return [
            {
                'channel': 'push',
                'status': 'failed',
                'message': 'FCM_SERVER_KEY is not configured.',
            }
        ]

    results: list[dict[str, str]] = []
    topic_by_lang = {'en': 'lang_en', 'ru': 'lang_ru', 'uz': 'lang_uz'}
    headers = {
        'Authorization': f'key={FCM_SERVER_KEY}',
        'Content-Type': 'application/json',
    }
    with httpx.Client(timeout=FCM_PUSH_TIMEOUT_SECONDS) as client:
        for lang, topic in topic_by_lang.items():
            title, message, image_url, data_payload = _notification_push_payload(
                notification_row,
                lang=lang,
            )
            body: dict[str, Any] = {
                'to': f'/topics/{topic}',
                'priority': 'high',
                'notification': {
                    'title': title,
                    'body': message,
                },
                'data': data_payload,
            }
            if image_url:
                body['notification']['image'] = image_url
            try:
                response = client.post(
                    'https://fcm.googleapis.com/fcm/send',
                    headers=headers,
                    json=body,
                )
                if response.is_success:
                    results.append(
                        {
                            'channel': f'push_{lang}',
                            'status': 'sent',
                            'message': f'Push sent to topic {topic}.',
                        }
                    )
                else:
                    payload = response.text[:240].strip()
                    results.append(
                        {
                            'channel': f'push_{lang}',
                            'status': 'failed',
                            'message': f'FCM HTTP {response.status_code}: {payload}',
                        }
                    )
            except Exception as exc:
                results.append(
                    {
                        'channel': f'push_{lang}',
                        'status': 'failed',
                        'message': str(exc),
                    }
                )
    return results


def _localized_category(row: dict[str, Any], lang: str) -> dict[str, Any]:
    return {
        **row,
        'name': str(
            _pick_lang_value(
                row,
                lang=lang,
                base_key='name',
                en_key='nameEn',
                ru_key='nameRu',
                uz_key='nameUz',
            )
            or ''
        ),
        'description': _pick_lang_value(
            row,
            lang=lang,
            base_key='description',
            en_key='descriptionEn',
            ru_key='descriptionRu',
            uz_key='descriptionUz',
        ),
    }


def _localized_banner(row: dict[str, Any], lang: str) -> dict[str, Any]:
    localized = {
        **row,
        'title': str(
            _pick_lang_value(
                row,
                lang=lang,
                base_key='title',
                en_key='titleEn',
                ru_key='titleRu',
                uz_key='titleUz',
            )
            or ''
        ),
        'subtitle': str(
            _pick_lang_value(
                row,
                lang=lang,
                base_key='subtitle',
                en_key='subtitleEn',
                ru_key='subtitleRu',
                uz_key='subtitleUz',
            )
            or ''
        ),
    }
    localized['image_url'] = localized.get('imageUrl')
    return localized


def _localized_notification(row: dict[str, Any], lang: str) -> dict[str, Any]:
    localized = {
        **row,
        'title': str(
            _pick_lang_value(
                row,
                lang=lang,
                base_key='title',
                en_key='titleEn',
                ru_key='titleRu',
                uz_key='titleUz',
            )
            or ''
        ),
        'message': str(
            _pick_lang_value(
                row,
                lang=lang,
                base_key='message',
                en_key='messageEn',
                ru_key='messageRu',
                uz_key='messageUz',
            )
            or ''
        ),
    }
    localized['image_url'] = localized.get('imageUrl')
    return localized


def _localized_faq(row: dict[str, Any], lang: str) -> dict[str, Any]:
    return {
        **row,
        'question': str(
            _pick_lang_value(
                row,
                lang=lang,
                base_key='question',
                en_key='questionEn',
                ru_key='questionRu',
                uz_key='questionUz',
            )
            or ''
        ),
        'answer': str(
            _pick_lang_value(
                row,
                lang=lang,
                base_key='answer',
                en_key='answerEn',
                ru_key='answerRu',
                uz_key='answerUz',
            )
            or ''
        ),
    }


def _localized_settings(row: dict[str, Any], lang: str) -> dict[str, Any]:
    return {
        'supportPhone': row.get('supportPhone') or '',
        'timezone': row.get('timezone') or 'Asia/Tashkent',
        'currencyCode': row.get('currencyCode') or 'UZS',
        'callLabel': _pick_lang_value(
            row,
            lang=lang,
            base_key='callLabelRu',
            en_key='callLabelEn',
            ru_key='callLabelRu',
            uz_key='callLabelUz',
        )
        or '',
        'chatLabel': _pick_lang_value(
            row,
            lang=lang,
            base_key='chatLabelRu',
            en_key='chatLabelEn',
            ru_key='chatLabelRu',
            uz_key='chatLabelUz',
        )
        or '',
        'chatSubtitle': _pick_lang_value(
            row,
            lang=lang,
            base_key='chatSubtitleRu',
            en_key='chatSubtitleEn',
            ru_key='chatSubtitleRu',
            uz_key='chatSubtitleUz',
        )
        or '',
        'chatIntro': _pick_lang_value(
            row,
            lang=lang,
            base_key='chatIntroRu',
            en_key='chatIntroEn',
            ru_key='chatIntroRu',
            uz_key='chatIntroUz',
        )
        or '',
    }


def _is_drink_category(name: str) -> bool:
    value = name.strip().lower()
    return any(
        token in value
        for token in ('напит', 'drink', 'ichim', 'beverage', 'сок', 'cola', 'pepsi')
    )


def _is_terminal_status(status_value: str) -> bool:
    value = status_value.strip().lower()
    return (
        'deliver' in value
        or 'cancel' in value
        or 'complete' in value
        or 'done' in value
    )


def _sync_order_status_from_poster(conn, row: dict[str, Any]) -> dict[str, Any]:
    poster_order_id = row.get('poster_order_id')
    if poster_order_id in (None, ''):
        return row
    if not poster_client.enabled:
        return row
    if _is_terminal_status(str(row.get('status') or '')):
        return row
    try:
        poster_state = poster_client.get_incoming_order_state(
            incoming_order_id=poster_order_id,
        )
    except PosterSyncError as exc:
        logger.warning(
            'poster status sync failed for app_order=%s poster_order=%s: %s',
            row.get('id'),
            poster_order_id,
            exc,
        )
        return row

    poster_status = poster_state.get('poster_status')
    app_status = str(poster_state.get('app_status') or '').strip()
    tx_id = poster_state.get('transaction_id')
    if tx_id is not None:
        try:
            tx_state = poster_client.get_transaction_state(
                transaction_id=tx_id,
                created_at=str(row.get('created_at') or ''),
            )
            tx_app_status = str(tx_state.get('app_status') or '').strip()
            if tx_app_status:
                app_status = tx_app_status
            closed = tx_state.get('closed')
            if not isinstance(closed, bool):
                closed = poster_client.is_transaction_closed(
                    transaction_id=tx_id,
                    created_at=str(row.get('created_at') or ''),
                )
        except PosterSyncError as exc:
            logger.warning(
                'poster transaction sync failed for app_order=%s tx=%s: %s',
                row.get('id'),
                tx_id,
                exc,
            )
            closed = None
        if closed is True:
            app_status = 'delivered'
    if (
        app_status == 'preparing'
        and str(row.get('delivery_type') or row.get('deliveryType') or '').strip().lower() == 'delivery'
    ):
        minutes_since_created = _minutes_since_created(row.get('created_at'))
        if (
            minutes_since_created is not None
            and minutes_since_created >= POSTER_ON_THE_WAY_AFTER_MINUTES
        ):
            app_status = 'on_the_way'

    updated = dict(row)
    updated['poster_status'] = poster_status
    current_status = str(updated.get('status') or '').strip()
    if app_status and app_status != current_status:
        conn.execute(
            'UPDATE orders SET status = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?',
            (app_status, int(updated['id'])),
        )
        updated['status'] = app_status
    return updated


def _ensure_category_exists(conn, category_id: int) -> None:
    existing = category_repo.get(conn, int(category_id))
    if not existing:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail='Unknown categoryId.')


def _minutes_since_created(created_at: Any) -> Optional[float]:
    text = str(created_at or '').strip()
    if not text:
        return None
    parsed: Optional[datetime] = None
    for fmt in ('%Y-%m-%d %H:%M:%S', '%Y-%m-%dT%H:%M:%S'):
        try:
            parsed = datetime.strptime(text, fmt)
            break
        except ValueError:
            continue
    if parsed is None:
        try:
            parsed = datetime.fromisoformat(text.replace('Z', '+00:00'))
        except ValueError:
            return None
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    now = datetime.now(timezone.utc)
    return max((now - parsed.astimezone(timezone.utc)).total_seconds() / 60.0, 0.0)


if __name__ == '__main__':
    import uvicorn

    uvicorn.run(app, host='0.0.0.0', port=int(os.getenv('PORT', '8010')), reload=False)
