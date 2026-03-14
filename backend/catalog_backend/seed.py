from __future__ import annotations

import csv
import os
from pathlib import Path
from typing import Dict, Iterable, Iterator, Optional

try:
    from .auth import hash_password
    from .database import ROOT, get_conn
except ImportError:  # pragma: no cover - script execution fallback
    from auth import hash_password
    from database import ROOT, get_conn


def _default_asset_csv() -> Path:
    direct = ROOT.parent / 'assets' / 'menu_import.csv'
    if direct.exists():
        return direct
    nested = ROOT.parent.parent / 'assets' / 'menu_import.csv'
    if nested.exists():
        return nested
    return nested


ASSET_CSV = Path(os.getenv('MENU_CSV_PATH', str(_default_asset_csv())))
DEFAULT_ADMIN_EMAIL = os.getenv('ADMIN_EMAIL', 'admin@sushixl.local')
DEFAULT_ADMIN_PASSWORD = os.getenv('ADMIN_PASSWORD', 'admin123').strip() or 'admin123'
DEFAULT_ADMIN_NAME = os.getenv('ADMIN_NAME', 'Admin')
ADMIN_FORCE_RESET = os.getenv('ADMIN_FORCE_RESET', 'false').strip().lower() in {
    '1',
    'true',
    'yes',
    'on',
}


def _is_drink_category(name: str) -> bool:
    value = name.lower()
    return any(token in value for token in ('напит', 'drink', 'ichim', 'beverage'))


def _normalize_header(value: str) -> str:
    return value.strip().lower().replace('ё', 'е')


def _find_index(headers: list[str], variants: Iterable[str]) -> Optional[int]:
    normalized = [_normalize_header(h) for h in headers]
    target = {_normalize_header(v) for v in variants}
    for idx, header in enumerate(normalized):
        if header in target:
            return idx
    return None


def _iter_menu_rows(path: Path) -> Iterator[dict[str, str]]:
    with path.open('r', encoding='utf-8-sig', newline='') as fh:
        rows = list(csv.reader(fh))
    if not rows:
        return

    while rows and all(not cell.strip() for cell in rows[0]):
        rows.pop(0)
    if not rows:
        return

    if len(rows[0]) == 1 and rows[0][0].strip().lower() == 'menu_import':
        rows = rows[1:]
    if not rows:
        return

    headers = [cell.strip() for cell in rows[0]]
    title_idx = _find_index(headers, ('name_ru', 'name', 'название'))
    category_idx = _find_index(headers, ('category_ru', 'category', 'категория'))
    price_idx = _find_index(headers, ('price', 'цена'))
    image_idx = _find_index(headers, ('image_url', 'photo', 'фото'))
    description_idx = _find_index(headers, ('description_ru', 'description', 'описание'))

    if title_idx is None or category_idx is None or price_idx is None:
        return

    for raw in rows[1:]:
        row = [cell.strip() for cell in raw]

        def val(index: Optional[int]) -> str:
            if index is None:
                return ''
            if index < 0 or index >= len(row):
                return ''
            return row[index].strip()

        yield {
            'title': val(title_idx),
            'category': val(category_idx),
            'price': val(price_idx),
            'image': val(image_idx),
            'description': val(description_idx),
        }


def _seed_fallback(conn) -> None:
    sushi = conn.execute(
        'INSERT INTO categories(name, description, is_active, sort_order, updated_at) VALUES (?, ?, 1, 1, CURRENT_TIMESTAMP)',
        ('Роллы', 'Основное меню',),
    ).lastrowid
    drinks = conn.execute(
        'INSERT INTO categories(name, description, is_active, sort_order, updated_at) VALUES (?, ?, 1, 2, CURRENT_TIMESTAMP)',
        ('Напитки', 'Рекомендуемые напитки',),
    ).lastrowid
    conn.execute(
        'INSERT INTO products(title, description, image_url, category_id, price, old_price, is_active, is_drink, updated_at) VALUES (?, ?, ?, ?, ?, ?, 1, 0, CURRENT_TIMESTAMP)',
        ('Филадельфия', 'Лосось, сыр, рис', None, sushi, 62000, 74000),
    )
    for idx, title in enumerate(['Coca-Cola', 'Fanta', 'Sprite', 'Lipton']):
        conn.execute(
            'INSERT INTO products(title, description, image_url, category_id, price, old_price, is_active, is_drink, updated_at) VALUES (?, ?, ?, ?, ?, ?, 1, 1, CURRENT_TIMESTAMP)',
            (title, 'Напиток', None, drinks, 12000 + idx * 1000, None),
        )


def seed_database() -> None:
    with get_conn() as conn:
        admin = conn.execute(
            'SELECT id FROM admin_users WHERE lower(email) = lower(?) LIMIT 1',
            (DEFAULT_ADMIN_EMAIL,),
        ).fetchone()
        if admin:
            if ADMIN_FORCE_RESET:
                conn.execute(
                    'UPDATE admin_users SET password_hash = ?, full_name = ?, is_active = 1, updated_at = CURRENT_TIMESTAMP WHERE id = ?',
                    (hash_password(DEFAULT_ADMIN_PASSWORD), DEFAULT_ADMIN_NAME, int(admin['id'])),
                )
        else:
            conn.execute(
                'INSERT INTO admin_users(email, password_hash, full_name, updated_at) VALUES (?, ?, ?, CURRENT_TIMESTAMP)',
                (DEFAULT_ADMIN_EMAIL, hash_password(DEFAULT_ADMIN_PASSWORD), DEFAULT_ADMIN_NAME),
            )

        product_exists = conn.execute('SELECT 1 FROM products LIMIT 1').fetchone()
        if product_exists:
            return

        if ASSET_CSV.exists():
            category_ids: Dict[str, int] = {}
            inserted = 0
            for row in _iter_menu_rows(ASSET_CSV):
                title = row.get('title', '').strip()
                category_name = row.get('category', '').strip()
                if not title or not category_name:
                    continue
                description = row.get('description', '').strip() or None
                image_url = row.get('image', '').strip() or None
                try:
                    price = float((row.get('price') or '0').replace(' ', '').replace(',', '.'))
                except ValueError:
                    continue
                if price <= 0:
                    continue
                if category_name not in category_ids:
                    cur = conn.execute(
                        'INSERT INTO categories(name, description, is_active, sort_order, updated_at) VALUES (?, ?, 1, ?, CURRENT_TIMESTAMP)',
                        (category_name, None, len(category_ids) + 1),
                    )
                    category_ids[category_name] = int(cur.lastrowid)
                old_price = None
                if inserted < 4 and not _is_drink_category(category_name):
                    old_price = round(price * 1.2, 2)
                conn.execute(
                    'INSERT INTO products(title, description, image_url, category_id, price, old_price, is_active, is_drink, updated_at) '
                    'VALUES (?, ?, ?, ?, ?, ?, 1, ?, CURRENT_TIMESTAMP)',
                    (
                        title,
                        description,
                        image_url,
                        category_ids[category_name],
                        price,
                        old_price,
                        1 if _is_drink_category(category_name) else 0,
                    ),
                )
                inserted += 1
            if inserted == 0:
                _seed_fallback(conn)
        else:
            _seed_fallback(conn)
