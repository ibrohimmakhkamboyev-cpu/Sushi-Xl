import logging
import os
import re
import time
import uuid
from math import asin, cos, radians, sin, sqrt
from typing import Any, Dict, List, Optional, Tuple

import httpx
from dotenv import load_dotenv
from fastapi import FastAPI, HTTPException, Query, Request
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

load_dotenv()

YANDEX_GEOCODER_API_KEY = os.getenv('YANDEX_GEOCODER_API_KEY', '').strip()
RATE_LIMIT_PER_MINUTE = int(os.getenv('RATE_LIMIT_PER_MINUTE', '60'))
CACHE_TTL_SECONDS = int(os.getenv('CACHE_TTL_SECONDS', '300'))
ALLOWED_ORIGINS = [
    origin.strip()
    for origin in os.getenv('ALLOWED_ORIGINS', '*').split(',')
    if origin.strip()
]
if not ALLOWED_ORIGINS:
    ALLOWED_ORIGINS = ['*']

DEFAULT_LL = '69.2401,41.2995'
DEFAULT_SPN = '3,3'
WIDE_SPN = '10,10'
DEFAULT_LANG = 'ru_RU'
FALLBACK_LANGS = ('ru_RU',)
STRUCTURAL_KINDS = {
    'country',
    'province',
    'area',
    'locality',
    'district',
    'street',
    'house',
}
ADMIN_LABEL_PATTERNS = (
    'махалл',
    'махалля',
    'махаллин',
    'махалляс',
    'mahall',
    'mahalla',
    'mahallasi',
    'сход граждан',
    'сгм',
    'мфй',
    'mfy',
    'qfy',
)
RUSSIAN_PREFIX_PATTERNS = (
    (re.compile(r'^(улица|ул\.?)\s+', re.IGNORECASE), 'ул. '),
    (re.compile(r'^(проспект|пр-т|просп\.?)\s+', re.IGNORECASE), 'пр-т '),
    (re.compile(r'^(площадь|пл\.?)\s+', re.IGNORECASE), 'пл. '),
)

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s %(levelname)s [%(name)s] %(message)s',
)
logger = logging.getLogger('geocoder-proxy')
logging.getLogger('httpx').setLevel(logging.WARNING)
logging.getLogger('httpcore').setLevel(logging.WARNING)

app = FastAPI(title='Yandex Geocoder Proxy', version='3.0.0')
app.add_middleware(
    CORSMiddleware,
    allow_origins=ALLOWED_ORIGINS,
    allow_credentials=False,
    allow_methods=['GET'],
    allow_headers=['*'],
)


def _validation_payload(errors: List[Dict[str, Any]]) -> Dict[str, Any]:
    details: List[Dict[str, str]] = []
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
    message = '; '.join(f"{item['field']}: {item['message']}" for item in details) or 'Invalid request input.'
    return {
        'error': 'REQUEST_VALIDATION_ERROR',
        'details': details,
        'message': message,
    }


@app.exception_handler(RequestValidationError)
async def request_validation_error_handler(_: Request, exc: RequestValidationError):
    return JSONResponse(
        status_code=422,
        content=_validation_payload(exc.errors()),
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


class SimpleCache:
    def __init__(self, ttl_seconds: int) -> None:
        self._ttl = ttl_seconds
        self._store: Dict[str, Tuple[float, Dict[str, Any]]] = {}

    def get(self, key: str) -> Optional[Dict[str, Any]]:
        current = time.time()
        item = self._store.get(key)
        if item is None:
            return None
        expires_at, value = item
        if expires_at <= current:
            self._store.pop(key, None)
            return None
        return value

    def set(self, key: str, value: Dict[str, Any]) -> None:
        self._store[key] = (time.time() + self._ttl, value)


class SimpleRateLimiter:
    def __init__(self, max_per_minute: int) -> None:
        self._max_per_minute = max_per_minute
        self._counters: Dict[str, Tuple[float, int]] = {}

    def check(self, key: str) -> None:
        now = time.time()
        window_start, count = self._counters.get(key, (now, 0))
        if now - window_start >= 60:
            window_start, count = now, 0
        count += 1
        self._counters[key] = (window_start, count)
        if count > self._max_per_minute:
            raise HTTPException(
                status_code=429,
                detail='Too many requests. Slow down and retry.',
            )


cache = SimpleCache(CACHE_TTL_SECONDS)
rate_limiter = SimpleRateLimiter(RATE_LIMIT_PER_MINUTE)


def _request_id(request: Request) -> str:
    return getattr(request.state, 'request_id', 'unknown')


def _normalize_query(text: str) -> str:
    return ' '.join(text.strip().split())


def _normalize_lang(lang: str) -> str:
    return DEFAULT_LANG


def _language_chain(lang: str) -> List[str]:
    preferred = _normalize_lang(lang)
    out: List[str] = []
    for candidate in (preferred, *FALLBACK_LANGS):
        if candidate not in out:
            out.append(candidate)
    return out


def _parse_point_pos(pos: str) -> Optional[Tuple[float, float]]:
    chunks = str(pos).strip().split()
    if len(chunks) != 2:
        return None
    try:
        lon = float(chunks[0])
        lat = float(chunks[1])
    except ValueError:
        return None
    if not (-90 <= lat <= 90 and -180 <= lon <= 180):
        return None
    return lat, lon


def _parse_lon_lat_param(value: str, *, field_name: str) -> Tuple[float, float]:
    parts = [part.strip() for part in str(value).split(',')]
    if len(parts) != 2:
        raise HTTPException(status_code=422, detail=f'Invalid {field_name} format.')
    try:
        lon = float(parts[0])
        lat = float(parts[1])
    except ValueError as exc:
        raise HTTPException(
            status_code=422,
            detail=f'Invalid {field_name} coordinates.',
        ) from exc
    if not (-180 <= lon <= 180 and -90 <= lat <= 90):
        raise HTTPException(
            status_code=422,
            detail=f'{field_name} coordinates are out of range.',
        )
    return lon, lat


def _parse_spn_param(value: str) -> Tuple[float, float]:
    parts = [part.strip() for part in str(value).split(',')]
    if len(parts) != 2:
        raise HTTPException(status_code=422, detail='Invalid spn format.')
    try:
        lon_delta = float(parts[0])
        lat_delta = float(parts[1])
    except ValueError as exc:
        raise HTTPException(status_code=422, detail='Invalid spn values.') from exc
    if lon_delta <= 0 or lat_delta <= 0:
        raise HTTPException(status_code=422, detail='spn values must be positive.')
    return lon_delta, lat_delta


def _extract_component_map(address_map: Dict[str, Any]) -> Dict[str, List[str]]:
    components: Dict[str, List[str]] = {}
    raw_components = address_map.get('Components')
    if not isinstance(raw_components, list):
        return components
    for item in raw_components:
        if not isinstance(item, dict):
            continue
        c_kind = str(item.get('kind', '')).strip()
        c_name = str(item.get('name', '')).strip()
        if not c_kind or not c_name:
            continue
        bucket = components.setdefault(c_kind, [])
        if c_name not in bucket:
            bucket.append(c_name)
    return components


def _component_first(components: Dict[str, List[str]], *kinds: str) -> str:
    for kind in kinds:
        values = components.get(kind) or []
        if values:
            return values[0].strip()
    return ''


def _component_values(components: Dict[str, List[str]], *kinds: str) -> List[str]:
    out: List[str] = []
    for kind in kinds:
        for value in components.get(kind) or []:
            candidate = str(value).strip()
            if candidate and candidate not in out:
                out.append(candidate)
    return out


def _component_first_filtered(
    components: Dict[str, List[str]],
    *kinds: str,
    reject_admin: bool = False,
    reject_country: bool = False,
) -> str:
    for kind in kinds:
        values = components.get(kind) or []
        for value in values:
            candidate = str(value).strip()
            if not candidate:
                continue
            if reject_country and _is_country_only_label(candidate):
                continue
            if reject_admin and _is_admin_like_label(candidate):
                continue
            return candidate
    return ''


def _is_country_only_label(label: str) -> bool:
    value = label.strip().lower()
    return value in {
        'uzbekistan',
        "o'zbekiston",
        'o`zbekiston',
        'узбекистан',
        'ўзбекистон',
    }


def _is_uzbekistan_country(label: str) -> bool:
    value = ' '.join(label.strip().lower().split())
    return value in {
        'узбекистан',
        'uzbekistan',
        "o'zbekiston",
        'o`zbekiston',
        'ўзбекистон',
    }


def _is_admin_like_label(label: str) -> bool:
    value = ' '.join(label.strip().lower().split())
    if not value:
        return False
    if _is_country_only_label(value):
        return True
    return any(pattern in value for pattern in ADMIN_LABEL_PATTERNS)


def _normalize_russian_prefix(label: str) -> str:
    text = ' '.join(label.strip().split())
    if not text:
        return ''
    for pattern, replacement in RUSSIAN_PREFIX_PATTERNS:
        if pattern.search(text):
            return pattern.sub(replacement, text, count=1)
    return text


def _normalize_street_label(street: str) -> str:
    text = _normalize_russian_prefix(street)
    lower = text.lower()
    if lower.startswith(('ул. ', 'пр-т ', 'пл. ')):
        return text
    return f'ул. {text}'


def _normalize_district_label(district: str) -> str:
    text = ' '.join(district.strip().split())
    if not text:
        return ''
    text = re.sub(r'\bрайон\b', '', text, flags=re.IGNORECASE).strip(' ,')
    text = re.sub(r'\bр-?н\b', '', text, flags=re.IGNORECASE).strip(' ,')
    return text or district.strip()


def _distance_km(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    radius_km = 6371.0
    d_lat = radians(lat2 - lat1)
    d_lon = radians(lon2 - lon1)
    a = (
        sin(d_lat / 2) ** 2
        + cos(radians(lat1)) * cos(radians(lat2)) * sin(d_lon / 2) ** 2
    )
    c = 2 * asin(min(1.0, sqrt(a)))
    return radius_km * c


def buildFullAddress(components: Dict[str, List[str]], geo_object: Dict[str, Any]) -> str:
    street = _component_first_filtered(
        components,
        'street',
        reject_admin=True,
        reject_country=True,
    )
    house = _component_first(components, 'house')
    city = _component_first_filtered(
        components,
        'locality',
        'province',
        reject_admin=True,
        reject_country=True,
    )
    district = _component_first_filtered(
        components,
        'district',
        reject_admin=True,
        reject_country=True,
    )
    country = _component_first_filtered(components, 'country', reject_admin=True)
    place_name = str(geo_object.get('placeName', '')).strip()
    kind = str(geo_object.get('kind', '')).strip().lower()
    raw_address = str(geo_object.get('formattedAddress', '')).strip()

    parts: List[str] = []
    if street and house:
        parts.append(f'{street}, {house}')
    elif street:
        parts.append(street)
    elif (
        place_name
        and kind not in STRUCTURAL_KINDS
        and not _is_country_only_label(place_name)
        and not _is_admin_like_label(place_name)
    ):
        parts.append(place_name)
    elif district:
        parts.append(_normalize_district_label(district))
    elif city:
        parts.append(city)

    if not country and 'узбекистан' in raw_address.lower():
        country = 'Узбекистан'
    if city and city not in parts:
        parts.append(city)
    if country and not _is_country_only_label(parts[-1] if parts else ''):
        parts.append(country)

    cleaned = [
        part
        for part in parts
        if part and (not _is_admin_like_label(part) or _is_uzbekistan_country(part))
    ]
    if cleaned:
        return ', '.join(cleaned)
    return str(geo_object.get('formattedAddress', '')).strip()


def _is_uzbekistan_result(item: Dict[str, Any]) -> bool:
    components = item.get('componentMap') or {}
    if not isinstance(components, dict):
        components = {}
    country_values = _component_values(components, 'country')
    country_code = str(item.get('countryCode', '')).strip().upper()
    if country_code == 'UZ':
        return True
    if any(_is_uzbekistan_country(value) for value in country_values):
        return True
    full_address = str(item.get('fullAddress', '')).strip()
    return 'узбекистан' in full_address.lower()


def buildShortLabel(components: Dict[str, List[str]], geo_object: Dict[str, Any]) -> str:
    street = _component_first_filtered(
        components,
        'street',
        reject_admin=True,
        reject_country=True,
    )
    house = _component_first(components, 'house')
    city = _component_first_filtered(
        components,
        'locality',
        reject_admin=True,
        reject_country=True,
    )
    district = _component_first_filtered(
        components,
        'district',
        reject_admin=True,
        reject_country=True,
    )
    place_name = str(geo_object.get('placeName', '')).strip()
    kind = str(geo_object.get('kind', '')).strip().lower()
    normalized_place_name = _normalize_russian_prefix(place_name)
    normalized_district = _normalize_district_label(district) if district else ''

    if street and house:
        return f'{_normalize_street_label(street)}, {house}'
    if street:
        return _normalize_street_label(street)
    if (
        normalized_place_name
        and kind not in STRUCTURAL_KINDS
        and not _is_country_only_label(normalized_place_name)
        and not _is_admin_like_label(normalized_place_name)
    ):
        return normalized_place_name
    if normalized_district and city and normalized_district.lower() != city.lower():
        return normalized_district
    if city:
        return city
    if normalized_district:
        return normalized_district
    if (
        normalized_place_name
        and not _is_country_only_label(normalized_place_name)
        and not _is_admin_like_label(normalized_place_name)
    ):
        return normalized_place_name
    return ''


def _reverse_score(item: Dict[str, Any]) -> int:
    components = item.get('componentMap') or {}
    if not isinstance(components, dict):
        components = {}
    street = _component_first_filtered(
        components,
        'street',
        reject_admin=True,
        reject_country=True,
    )
    house = _component_first(components, 'house')
    city = _component_first_filtered(
        components,
        'locality',
        reject_admin=True,
        reject_country=True,
    )
    district = _component_first_filtered(
        components,
        'district',
        reject_admin=True,
        reject_country=True,
    )
    short_label = str(item.get('shortLabel', '')).strip()
    kind = str(item.get('kind', '')).strip().lower()
    precision = str(item.get('precision', '')).strip().lower()

    score = 0
    if street and house:
        score += 600
    elif street:
        score += 500
    elif (
        kind not in STRUCTURAL_KINDS
        and short_label
        and not _is_country_only_label(short_label)
        and not _is_admin_like_label(short_label)
    ):
        score += 450
    elif district and city:
        score += 350
    elif city:
        score += 250
    elif district:
        score += 200
    elif short_label and not _is_country_only_label(short_label) and not _is_admin_like_label(short_label):
        score += 150

    if kind == 'house':
        score += 40
    elif kind == 'street':
        score += 20

    if precision in {'exact', 'number'}:
        score += 40
    elif precision in {'near', 'street'}:
        score += 20

    if _is_country_only_label(short_label):
        score -= 500
    if _is_admin_like_label(short_label):
        score -= 400

    return score


def _geocode_score(item: Dict[str, Any], *, center_lat: float, center_lon: float) -> float:
    base = float(_reverse_score(item))
    lat = float(item.get('lat', 0.0))
    lon = float(item.get('lon', 0.0))
    distance = _distance_km(center_lat, center_lon, lat, lon)
    proximity_bonus = max(0.0, 300.0 - min(distance, 1500.0) / 4.0)
    return base + proximity_bonus


def _pick_best_reverse_result(results: List[Dict[str, Any]]) -> Dict[str, Any]:
    meaningful = [item for item in results if str(item.get('shortLabel', '')).strip()]
    if meaningful:
        return max(meaningful, key=_reverse_score)
    return max(results, key=_reverse_score)


def _parse_geo_object(geo: Dict[str, Any]) -> Optional[Dict[str, Any]]:
    point = geo.get('Point')
    if not isinstance(point, dict):
        return None
    parsed_point = _parse_point_pos(str(point.get('pos', '')))
    if parsed_point is None:
        return None
    lat, lon = parsed_point

    place_name = str(geo.get('name', '')).strip()
    geocoder_meta: Dict[str, Any] = {}
    meta_prop = geo.get('metaDataProperty')
    if isinstance(meta_prop, dict):
        raw_meta = meta_prop.get('GeocoderMetaData')
        if isinstance(raw_meta, dict):
            geocoder_meta = raw_meta

    formatted_address = str(geocoder_meta.get('text', '')).strip()
    precision = str(geocoder_meta.get('precision', '')).strip()
    kind = str(geocoder_meta.get('kind', '')).strip()

    address_map = geocoder_meta.get('Address')
    component_map: Dict[str, List[str]] = {}
    country_code = ''
    if isinstance(address_map, dict):
        if not formatted_address:
            formatted_address = str(address_map.get('formatted', '')).strip()
        component_map = _extract_component_map(address_map)
        country_code = str(address_map.get('country_code', '')).strip().upper()

    if not formatted_address:
        description = str(geo.get('description', '')).strip()
        formatted_address = ', '.join(
            [part for part in [place_name, description] if part]
        )
    if not place_name:
        place_name = formatted_address
    if not place_name or not formatted_address:
        return None

    short_label = buildShortLabel(
        component_map,
        {
            'placeName': place_name,
            'formattedAddress': formatted_address,
            'kind': kind,
            'precision': precision,
        },
    )
    full_address = buildFullAddress(
        component_map,
        {
            'placeName': place_name,
            'formattedAddress': formatted_address,
            'kind': kind,
            'precision': precision,
        },
    )

    return {
        'lat': lat,
        'lon': lon,
        'placeName': place_name,
        'formattedAddress': formatted_address,
        'shortLabel': short_label,
        'fullAddress': full_address,
        'precision': precision,
        'kind': kind,
        'countryCode': country_code,
        'components': component_map,
        'componentMap': component_map,
    }


def _extract_results(payload: Dict[str, Any]) -> List[Dict[str, Any]]:
    response = payload.get('response')
    if not isinstance(response, dict):
        return []
    collection = response.get('GeoObjectCollection')
    if not isinstance(collection, dict):
        return []
    members = collection.get('featureMember')
    if not isinstance(members, list):
        return []

    out: List[Dict[str, Any]] = []
    for member in members:
        if not isinstance(member, dict):
            continue
        geo = member.get('GeoObject')
        if not isinstance(geo, dict):
            continue
        parsed = _parse_geo_object(geo)
        if parsed is not None:
            out.append(parsed)
    return out


def _cache_key(prefix: str, *parts: str) -> str:
    return ':'.join([prefix, *[part.strip().lower() for part in parts]])


async def _request_yandex(
    *,
    geocode: str,
    lang: str,
    results: int,
    request_id: str,
    ll: Optional[str] = None,
    spn: Optional[str] = None,
) -> List[Dict[str, Any]]:
    if not YANDEX_GEOCODER_API_KEY:
        raise HTTPException(
            status_code=503,
            detail='Server geocoder key is not configured.',
        )

    params: Dict[str, Any] = {
        'apikey': YANDEX_GEOCODER_API_KEY,
        'geocode': geocode,
        'format': 'json',
        'lang': lang,
        'results': results,
    }
    if ll:
        params['ll'] = ll
    if spn:
        params['spn'] = spn

    async with httpx.AsyncClient(timeout=12.0) as client:
        try:
            response = await client.get(
                'https://geocode-maps.yandex.ru/1.x/',
                params=params,
            )
        except Exception as exc:  # noqa: BLE001
            logger.exception('[%s] upstream request failed', request_id)
            raise HTTPException(
                status_code=502,
                detail='Upstream geocoder request failed.',
            ) from exc

    if response.status_code != 200:
        logger.warning(
            '[%s] yandex status=%s geocode=%s ll=%s spn=%s',
            request_id,
            response.status_code,
            geocode,
            ll or '-',
            spn or '-',
        )
        raise HTTPException(
            status_code=502,
            detail='Upstream geocoder returned non-200 status.',
        )

    try:
        payload = response.json()
    except Exception as exc:  # noqa: BLE001
        raise HTTPException(
            status_code=502,
            detail='Invalid upstream JSON payload.',
        ) from exc

    parsed = _extract_results(payload)
    first = parsed[0] if parsed else None
    logger.info(
        '[%s] yandex status=%s results=%d first.place=%s first.addr=%s first.kind=%s first.precision=%s',
        request_id,
        response.status_code,
        len(parsed),
        first.get('placeName') if first else '-',
        first.get('formattedAddress') if first else '-',
        first.get('kind') if first else '-',
        first.get('precision') if first else '-',
    )
    return parsed


@app.middleware('http')
async def attach_request_id(request: Request, call_next):
    request_id = request.headers.get('x-request-id') or uuid.uuid4().hex[:12]
    request.state.request_id = request_id
    started = time.time()
    try:
        response = await call_next(request)
    except HTTPException:
        raise
    except Exception:  # noqa: BLE001
        logger.exception('[%s] unhandled exception', request_id)
        return JSONResponse(status_code=500, content={'error': 'INTERNAL_ERROR'})
    finally:
        elapsed_ms = int((time.time() - started) * 1000)
        logger.info('[%s] %s %s %sms', request_id, request.method, request.url.path, elapsed_ms)
    response.headers['x-request-id'] = request_id
    return response


@app.get('/health')
async def health():
    return {'status': 'ok'}


@app.get('/api/geocode')
async def geocode(
    request: Request,
    text: str = Query(..., min_length=1, max_length=200),
    lang: str = Query(DEFAULT_LANG, min_length=2, max_length=16),
    ll: str = Query(DEFAULT_LL),
    spn: str = Query(DEFAULT_SPN),
    results: int = Query(5, ge=1, le=5),
):
    rid = _request_id(request)
    client_ip = request.client.host if request.client else 'unknown'
    rate_limiter.check(f'{client_ip}:geocode')

    normalized_text = _normalize_query(text)
    if len(normalized_text) < 2:
        raise HTTPException(status_code=422, detail='Query text is too short.')

    ll_lon, ll_lat = _parse_lon_lat_param(ll, field_name='ll')
    spn_lon, spn_lat = _parse_spn_param(spn)
    ll_value = f'{ll_lon},{ll_lat}'
    spn_value = f'{spn_lon},{spn_lat}'
    language_chain = _language_chain(lang)

    cache_key = _cache_key(
        'geocode',
        normalized_text,
        language_chain[0],
        ll_value,
        spn_value,
        str(results),
    )
    cached = cache.get(cache_key)
    if cached is not None:
        return cached

    filtered_results: List[Dict[str, Any]] = []
    search_spans = [spn_value]
    if WIDE_SPN != spn_value:
        search_spans.append(WIDE_SPN)
    for current_spn in search_spans:
        raw_results: List[Dict[str, Any]] = []
        for candidate_lang in language_chain:
            raw_results = await _request_yandex(
                geocode=normalized_text,
                lang=candidate_lang,
                results=results,
                request_id=rid,
                ll=ll_value,
                spn=current_spn,
            )
            if raw_results:
                break
        filtered_results = [
            item
            for item in raw_results
            if _is_uzbekistan_result(item)
            and str(item.get('shortLabel', '')).strip()
        ]
        filtered_results.sort(
            key=lambda item: _geocode_score(
                item,
                center_lat=ll_lat,
                center_lon=ll_lon,
            ),
            reverse=True,
        )
        logger.info(
            '[%s] geocode filter spn=%s kept=%d/%d',
            rid,
            current_spn,
            len(filtered_results),
            len(raw_results),
        )
        if filtered_results:
            break

    if not filtered_results:
        return JSONResponse(status_code=404, content={'error': 'NOT_FOUND'})

    response = {
        'results': [
            {
                'lat': item['lat'],
                'lon': item['lon'],
                'placeName': item['shortLabel'],
                'formattedAddress': item['fullAddress'],
                'shortLabel': item['shortLabel'],
                'fullAddress': item['fullAddress'],
                'precision': item['precision'],
                'kind': item['kind'],
            }
            for item in filtered_results[:results]
        ],
    }
    cache.set(cache_key, response)
    return response


@app.get('/api/reverse')
async def reverse(
    request: Request,
    lat: float = Query(..., ge=-90, le=90),
    lon: float = Query(..., ge=-180, le=180),
    lang: str = Query(DEFAULT_LANG, min_length=2, max_length=16),
):
    rid = _request_id(request)
    client_ip = request.client.host if request.client else 'unknown'
    rate_limiter.check(f'{client_ip}:reverse')

    geocode_value = f'{lon},{lat}'
    language_chain = _language_chain(lang)
    cache_key = _cache_key('reverse', geocode_value, language_chain[0])
    cached = cache.get(cache_key)
    if cached is not None:
        return cached

    results_payload: List[Dict[str, Any]] = []
    for candidate_lang in language_chain:
        results_payload = await _request_yandex(
            geocode=geocode_value,
            lang=candidate_lang,
            results=5,
            request_id=rid,
        )
        if results_payload:
            break

    if not results_payload:
        return JSONResponse(status_code=404, content={'error': 'NOT_FOUND'})

    uz_results = [item for item in results_payload if _is_uzbekistan_result(item)]
    logger.info(
        '[%s] reverse filter kept=%d/%d',
        rid,
        len(uz_results),
        len(results_payload),
    )
    if not uz_results:
        return JSONResponse(status_code=400, content={'error': 'OUTSIDE_UZ'})

    top = _pick_best_reverse_result(uz_results)
    if not str(top.get('shortLabel', '')).strip():
        return JSONResponse(status_code=404, content={'error': 'NOT_FOUND'})
    response = {
        'lat': lat,
        'lon': lon,
        'shortLabel': top['shortLabel'],
        'fullAddress': top['fullAddress'],
        'placeName': top['shortLabel'],
        'formattedAddress': top['fullAddress'],
        'precision': top['precision'],
        'kind': top['kind'],
    }
    cache.set(cache_key, response)
    return response


if __name__ == '__main__':
    import uvicorn

    host = os.getenv('HOST', '0.0.0.0')
    port = int(os.getenv('PORT', '8000'))
    uvicorn.run('main:app', host=host, port=port, reload=False)
