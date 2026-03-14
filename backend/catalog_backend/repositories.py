from __future__ import annotations

import json
import sqlite3
from dataclasses import dataclass
from typing import Any, Dict, Iterable, List, Optional


@dataclass
class ProductFilters:
    discounted: bool = False
    category: Optional[str] = None
    category_id: Optional[int] = None
    limit: Optional[int] = None
    active_only: bool = True
    drinks_only: bool = False


class CategoryRepository:
    def list(self, conn: sqlite3.Connection, *, active_only: bool = False) -> List[dict]:
        query = (
            'SELECT id, name, description, name_en, name_ru, name_uz, '
            'description_en, description_ru, description_uz, is_active, sort_order '
            'FROM categories'
        )
        params: List[Any] = []
        if active_only:
            query += ' WHERE is_active = 1'
        query += ' ORDER BY sort_order ASC, name COLLATE NOCASE ASC'
        rows = conn.execute(query, params).fetchall()
        return [self._row_to_dict(row) for row in rows]

    def get(self, conn: sqlite3.Connection, category_id: int) -> Optional[dict]:
        row = conn.execute(
            'SELECT id, name, description, name_en, name_ru, name_uz, '
            'description_en, description_ru, description_uz, is_active, sort_order '
            'FROM categories WHERE id = ?',
            (category_id,),
        ).fetchone()
        return self._row_to_dict(row) if row else None

    def create(self, conn: sqlite3.Connection, payload: dict) -> dict:
        cur = conn.execute(
            'INSERT INTO categories('
            'name, description, name_en, name_ru, name_uz, description_en, description_ru, description_uz, '
            'is_active, sort_order, updated_at'
            ') VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP)',
            (
                payload['name'].strip(),
                (payload.get('description') or '').strip() or None,
                self._pick_lang(payload, 'nameEn', payload['name']),
                self._pick_lang(payload, 'nameRu', payload['name']),
                self._pick_lang(payload, 'nameUz', payload['name']),
                self._pick_lang(payload, 'descriptionEn', payload.get('description')),
                self._pick_lang(payload, 'descriptionRu', payload.get('description')),
                self._pick_lang(payload, 'descriptionUz', payload.get('description')),
                1 if payload.get('isActive', True) else 0,
                int(payload.get('sortOrder', 0)),
            ),
        )
        return self.get(conn, int(cur.lastrowid))  # type: ignore[arg-type]

    def update(self, conn: sqlite3.Connection, category_id: int, payload: dict) -> Optional[dict]:
        exists = self.get(conn, category_id)
        if not exists:
            return None
        conn.execute(
            'UPDATE categories SET '
            'name = ?, description = ?, name_en = ?, name_ru = ?, name_uz = ?, '
            'description_en = ?, description_ru = ?, description_uz = ?, '
            'is_active = ?, sort_order = ?, updated_at = CURRENT_TIMESTAMP '
            'WHERE id = ?',
            (
                payload['name'].strip(),
                (payload.get('description') or '').strip() or None,
                self._pick_lang(payload, 'nameEn', payload['name']),
                self._pick_lang(payload, 'nameRu', payload['name']),
                self._pick_lang(payload, 'nameUz', payload['name']),
                self._pick_lang(payload, 'descriptionEn', payload.get('description')),
                self._pick_lang(payload, 'descriptionRu', payload.get('description')),
                self._pick_lang(payload, 'descriptionUz', payload.get('description')),
                1 if payload.get('isActive', True) else 0,
                int(payload.get('sortOrder', 0)),
                category_id,
            ),
        )
        return self.get(conn, category_id)

    def delete(self, conn: sqlite3.Connection, category_id: int) -> bool:
        row = conn.execute(
            'SELECT COUNT(*) AS total FROM products WHERE category_id = ?',
            (category_id,),
        ).fetchone()
        if row and int(row['total']) > 0:
            raise ValueError('CATEGORY_HAS_PRODUCTS')
        cur = conn.execute('DELETE FROM categories WHERE id = ?', (category_id,))
        return cur.rowcount > 0

    def reorder(self, conn: sqlite3.Connection, ids: List[int]) -> List[dict]:
        if not ids:
            return self.list(conn, active_only=False)
        placeholders = ','.join(['?'] * len(ids))
        rows = conn.execute(
            f'SELECT id FROM categories WHERE id IN ({placeholders})',
            ids,
        ).fetchall()
        found = {int(row['id']) for row in rows}
        missing = [cat_id for cat_id in ids if cat_id not in found]
        if missing:
            raise ValueError('CATEGORY_NOT_FOUND')
        seen = set()
        deduped = []
        for cat_id in ids:
            if cat_id in seen:
                continue
            seen.add(cat_id)
            deduped.append(cat_id)
        for idx, cat_id in enumerate(deduped):
            conn.execute(
                'UPDATE categories SET sort_order = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?',
                (idx, cat_id),
            )
        return self.list(conn, active_only=False)

    def _row_to_dict(self, row: sqlite3.Row) -> dict:
        return {
            'id': int(row['id']),
            'name': str(row['name']),
            'description': row['description'],
            'nameEn': row['name_en'] or row['name'],
            'nameRu': row['name_ru'] or row['name'],
            'nameUz': row['name_uz'] or row['name'],
            'descriptionEn': row['description_en'] if row['description_en'] is not None else row['description'],
            'descriptionRu': row['description_ru'] if row['description_ru'] is not None else row['description'],
            'descriptionUz': row['description_uz'] if row['description_uz'] is not None else row['description'],
            'isActive': bool(row['is_active']),
            'sortOrder': int(row['sort_order']),
        }

    def _pick_lang(self, payload: dict, key: str, fallback: Any) -> Optional[str]:
        value = (payload.get(key) or '').strip()
        if value:
            return value
        fallback_text = '' if fallback is None else str(fallback).strip()
        return fallback_text or None


class ProductRepository:
    def list(self, conn: sqlite3.Connection, filters: ProductFilters) -> List[dict]:
        query = (
            'SELECT p.id, p.title, p.description, p.title_en, p.title_ru, p.title_uz, '
            'p.description_en, p.description_ru, p.description_uz, p.image_url, p.category_id, '
            'p.price, p.old_price, p.discount_start_at, p.discount_end_at, p.sort_order, '
            'p.is_active, p.is_drink, p.is_recommended, p.is_popular, p.is_new, '
            'c.name AS category_name, c.name_en AS category_name_en, c.name_ru AS category_name_ru, c.name_uz AS category_name_uz, '
            'c.is_active AS category_active '
            'FROM products p '
            'JOIN categories c ON c.id = p.category_id '
        )
        conditions: List[str] = []
        params: List[Any] = []
        if filters.active_only:
            conditions.append('p.is_active = 1 AND c.is_active = 1')
        if filters.discounted:
            conditions.append('p.old_price IS NOT NULL AND p.old_price > p.price')
        if filters.drinks_only:
            conditions.append('p.is_drink = 1')
        if filters.category_id is not None:
            conditions.append('p.category_id = ?')
            params.append(filters.category_id)
        elif filters.category:
            normalized = filters.category.strip().lower()
            if normalized == 'drinks':
                conditions.append('p.is_drink = 1')
            else:
                conditions.append('LOWER(c.name) = ?')
                params.append(normalized)
        if conditions:
            query += ' WHERE ' + ' AND '.join(conditions)
        query += (
            ' ORDER BY c.sort_order ASC, c.name COLLATE NOCASE ASC, p.sort_order ASC, p.title COLLATE NOCASE ASC'
        )
        if filters.limit:
            query += ' LIMIT ?'
            params.append(filters.limit)
        rows = conn.execute(query, params).fetchall()
        return [self._row_to_dict(row) for row in rows]

    def get(self, conn: sqlite3.Connection, product_id: int, *, include_inactive: bool = False) -> Optional[dict]:
        query = (
            'SELECT p.id, p.title, p.description, p.title_en, p.title_ru, p.title_uz, '
            'p.description_en, p.description_ru, p.description_uz, p.image_url, p.category_id, '
            'p.price, p.old_price, p.discount_start_at, p.discount_end_at, p.sort_order, '
            'p.is_active, p.is_drink, p.is_recommended, p.is_popular, p.is_new, '
            'c.name AS category_name, c.name_en AS category_name_en, c.name_ru AS category_name_ru, c.name_uz AS category_name_uz, '
            'c.is_active AS category_active '
            'FROM products p '
            'JOIN categories c ON c.id = p.category_id '
            'WHERE p.id = ?'
        )
        params: List[Any] = [product_id]
        if not include_inactive:
            query += ' AND p.is_active = 1 AND c.is_active = 1'
        row = conn.execute(query, params).fetchone()
        return self._row_to_dict(row) if row else None

    def create(self, conn: sqlite3.Connection, payload: dict) -> dict:
        cur = conn.execute(
            'INSERT INTO products('
            'title, description, title_en, title_ru, title_uz, description_en, description_ru, description_uz, '
            'image_url, category_id, price, old_price, discount_start_at, discount_end_at, sort_order, '
            'is_active, is_drink, is_recommended, is_popular, is_new, updated_at'
            ') VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP)',
            self._write_tuple(payload),
        )
        return self.get(conn, int(cur.lastrowid), include_inactive=True)  # type: ignore[arg-type]

    def update(self, conn: sqlite3.Connection, product_id: int, payload: dict) -> Optional[dict]:
        exists = self.get(conn, product_id, include_inactive=True)
        if not exists:
            return None
        conn.execute(
            'UPDATE products SET '
            'title = ?, description = ?, title_en = ?, title_ru = ?, title_uz = ?, '
            'description_en = ?, description_ru = ?, description_uz = ?, '
            'image_url = ?, category_id = ?, price = ?, old_price = ?, '
            'discount_start_at = ?, discount_end_at = ?, sort_order = ?, '
            'is_active = ?, is_drink = ?, is_recommended = ?, is_popular = ?, is_new = ?, '
            'updated_at = CURRENT_TIMESTAMP WHERE id = ?',
            (*self._write_tuple(payload), product_id),
        )
        return self.get(conn, product_id, include_inactive=True)

    def delete(self, conn: sqlite3.Connection, product_id: int) -> bool:
        cur = conn.execute('DELETE FROM products WHERE id = ?', (product_id,))
        return cur.rowcount > 0

    def reorder(self, conn: sqlite3.Connection, ids: List[int]) -> List[dict]:
        if not ids:
            return self.list(conn, ProductFilters(active_only=False))
        placeholders = ','.join(['?'] * len(ids))
        rows = conn.execute(
            f'SELECT id FROM products WHERE id IN ({placeholders})',
            ids,
        ).fetchall()
        found = {int(row['id']) for row in rows}
        missing = [product_id for product_id in ids if product_id not in found]
        if missing:
            raise ValueError('PRODUCT_NOT_FOUND')
        seen = set()
        deduped = []
        for product_id in ids:
            if product_id in seen:
                continue
            seen.add(product_id)
            deduped.append(product_id)
        for idx, product_id in enumerate(deduped):
            conn.execute(
                'UPDATE products SET sort_order = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?',
                (idx, product_id),
            )
        return self.list(conn, ProductFilters(active_only=False))

    def recommendations(self, conn: sqlite3.Connection, *, product_id: Optional[int], limit: int) -> List[dict]:
        product = self.get(conn, product_id, include_inactive=True) if product_id else None
        category_id = int(product['categoryId']) if product else None
        query = (
            'SELECT p.id, p.title, p.description, p.title_en, p.title_ru, p.title_uz, '
            'p.description_en, p.description_ru, p.description_uz, p.image_url, p.category_id, '
            'p.price, p.old_price, p.discount_start_at, p.discount_end_at, p.sort_order, '
            'p.is_active, p.is_drink, p.is_recommended, p.is_popular, p.is_new, '
            'c.name AS category_name, c.name_en AS category_name_en, c.name_ru AS category_name_ru, c.name_uz AS category_name_uz, '
            'c.is_active AS category_active '
            'FROM products p JOIN categories c ON c.id = p.category_id '
            'WHERE p.is_active = 1 AND c.is_active = 1 AND p.is_drink = 1 '
        )
        params: List[Any] = []
        if product_id:
            query += ' AND p.id != ?'
            params.append(product_id)
        query += ' ORDER BY CASE WHEN p.category_id = ? THEN 0 ELSE 1 END, p.title COLLATE NOCASE ASC LIMIT ?'
        params.extend([category_id or -1, limit])
        rows = conn.execute(query, params).fetchall()
        return [self._row_to_dict(row) for row in rows]

    def _write_tuple(self, payload: dict) -> tuple[Any, ...]:
        title = payload['title'].strip()
        description = (payload.get('description') or '').strip() or None
        title_en = self._pick_lang(payload, 'titleEn', title)
        title_ru = self._pick_lang(payload, 'titleRu', title)
        title_uz = self._pick_lang(payload, 'titleUz', title)
        description_en = self._pick_lang(payload, 'descriptionEn', description)
        description_ru = self._pick_lang(payload, 'descriptionRu', description)
        description_uz = self._pick_lang(payload, 'descriptionUz', description)
        image_url = (payload.get('imageUrl') or '').strip() or None
        category_id = int(payload['categoryId'])
        price = float(payload['price'])
        old_price = payload.get('oldPrice')
        if old_price is not None:
            old_price = float(old_price)
            if old_price <= price:
                old_price = None
        discount_start_at = (payload.get('discountStartAt') or '').strip() or None
        discount_end_at = (payload.get('discountEndAt') or '').strip() or None
        if old_price is None:
            discount_start_at = None
            discount_end_at = None
        return (
            title,
            description,
            title_en,
            title_ru,
            title_uz,
            description_en,
            description_ru,
            description_uz,
            image_url,
            category_id,
            price,
            old_price,
            discount_start_at,
            discount_end_at,
            int(payload.get('sortOrder', 0)),
            1 if payload.get('isActive', True) else 0,
            1 if payload.get('isDrink', False) else 0,
            1 if payload.get('isRecommended', False) else 0,
            1 if payload.get('isPopular', False) else 0,
            1 if payload.get('isNew', False) else 0,
        )

    def _row_to_dict(self, row: sqlite3.Row) -> dict:
        price = float(row['price'])
        old_price = row['old_price']
        old_price_value = float(old_price) if old_price is not None else None
        return {
            'id': int(row['id']),
            'title': str(row['title']),
            'description': row['description'],
            'titleEn': row['title_en'] or row['title'],
            'titleRu': row['title_ru'] or row['title'],
            'titleUz': row['title_uz'] or row['title'],
            'descriptionEn': row['description_en'] if row['description_en'] is not None else row['description'],
            'descriptionRu': row['description_ru'] if row['description_ru'] is not None else row['description'],
            'descriptionUz': row['description_uz'] if row['description_uz'] is not None else row['description'],
            'imageUrl': row['image_url'],
            'categoryId': int(row['category_id']),
            'categoryName': str(row['category_name']),
            'categoryNameEn': row['category_name_en'] or row['category_name'],
            'categoryNameRu': row['category_name_ru'] or row['category_name'],
            'categoryNameUz': row['category_name_uz'] or row['category_name'],
            'price': price,
            'oldPrice': old_price_value,
            'discountStartAt': row['discount_start_at'],
            'discountEndAt': row['discount_end_at'],
            'sortOrder': int(row['sort_order'] or 0),
            'isActive': bool(row['is_active']),
            'isDrink': bool(row['is_drink']),
            'isRecommended': bool(row['is_recommended']),
            'isPopular': bool(row['is_popular']),
            'isNew': bool(row['is_new']),
        }

    def _pick_lang(self, payload: dict, key: str, fallback: Any) -> Optional[str]:
        value = (payload.get(key) or '').strip()
        if value:
            return value
        fallback_text = '' if fallback is None else str(fallback).strip()
        return fallback_text or None


class UserRepository:
    def get(self, conn: sqlite3.Connection, user_id: int) -> Optional[dict]:
        row = conn.execute(
            'SELECT id, phone, full_name, preferred_lang FROM users WHERE id = ?',
            (user_id,),
        ).fetchone()
        if not row:
            return None
        return {
            'id': int(row['id']),
            'phone': str(row['phone']),
            'full_name': str(row['full_name']),
            'preferred_lang': str(row['preferred_lang']),
        }

    def upsert_login(self, conn: sqlite3.Connection, *, phone: str, full_name: str, preferred_lang: str) -> dict:
        row = conn.execute('SELECT id FROM users WHERE phone = ?', (phone,)).fetchone()
        if row:
            conn.execute(
                'UPDATE users SET full_name = ?, preferred_lang = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?',
                (full_name, preferred_lang, int(row['id'])),
            )
            user_id = int(row['id'])
        else:
            cur = conn.execute(
                'INSERT INTO users(phone, full_name, preferred_lang, updated_at) VALUES (?, ?, ?, CURRENT_TIMESTAMP)',
                (phone, full_name, preferred_lang),
            )
            user_id = int(cur.lastrowid)
        return {
            'user_id': user_id,
            'phone': phone,
            'full_name': full_name,
            'preferred_lang': preferred_lang,
        }

    def update_profile_session(
        self,
        conn: sqlite3.Connection,
        *,
        user_id: int,
        phone: str,
        full_name: str,
        preferred_lang: str,
    ) -> Optional[dict]:
        existing = self.get(conn, user_id)
        if not existing:
            return None
        try:
            conn.execute(
                'UPDATE users SET phone = ?, full_name = ?, preferred_lang = ?, updated_at = CURRENT_TIMESTAMP '
                'WHERE id = ?',
                (phone, full_name, preferred_lang, user_id),
            )
        except sqlite3.IntegrityError as exc:
            raise ValueError('USER_PHONE_ALREADY_EXISTS') from exc
        return {
            'user_id': user_id,
            'phone': phone,
            'full_name': full_name,
            'preferred_lang': preferred_lang,
        }

    def get_by_phone(self, conn: sqlite3.Connection, phone: str) -> Optional[dict]:
        row = conn.execute(
            'SELECT id, phone, full_name, preferred_lang FROM users WHERE phone = ?',
            (phone,),
        ).fetchone()
        if not row:
            return None
        return {
            'id': int(row['id']),
            'phone': str(row['phone']),
            'full_name': str(row['full_name']),
            'preferred_lang': str(row['preferred_lang']),
        }

    def create_for_admin(self, conn: sqlite3.Connection, payload: dict) -> dict:
        phone = str(payload['phone']).strip()
        full_name = str(payload['fullName']).strip()
        preferred_lang = str(payload.get('preferredLang') or 'ru').strip() or 'ru'
        try:
            cur = conn.execute(
                'INSERT INTO users(phone, full_name, preferred_lang, updated_at) VALUES (?, ?, ?, CURRENT_TIMESTAMP)',
                (phone, full_name, preferred_lang),
            )
        except sqlite3.IntegrityError as exc:
            raise ValueError('USER_PHONE_ALREADY_EXISTS') from exc
        row = self.get_for_admin(conn, int(cur.lastrowid))
        if not row:
            raise ValueError('USER_NOT_FOUND')
        return row

    def update_for_admin(self, conn: sqlite3.Connection, user_id: int, payload: dict) -> Optional[dict]:
        existing = self.get(conn, user_id)
        if not existing:
            return None
        phone = str(payload['phone']).strip()
        full_name = str(payload['fullName']).strip()
        preferred_lang = str(payload.get('preferredLang') or 'ru').strip() or 'ru'
        try:
            conn.execute(
                'UPDATE users SET phone = ?, full_name = ?, preferred_lang = ?, updated_at = CURRENT_TIMESTAMP '
                'WHERE id = ?',
                (phone, full_name, preferred_lang, user_id),
            )
        except sqlite3.IntegrityError as exc:
            raise ValueError('USER_PHONE_ALREADY_EXISTS') from exc
        return self.get_for_admin(conn, user_id)

    def delete_for_admin(self, conn: sqlite3.Connection, user_id: int) -> bool:
        row = conn.execute(
            'SELECT COUNT(*) AS total FROM orders WHERE user_id = ?',
            (user_id,),
        ).fetchone()
        if row and int(row['total'] or 0) > 0:
            raise ValueError('USER_HAS_ORDERS')
        cur = conn.execute('DELETE FROM users WHERE id = ?', (user_id,))
        return cur.rowcount > 0

    def get_for_admin(self, conn: sqlite3.Connection, user_id: int) -> Optional[dict]:
        row = conn.execute(
            'SELECT u.id, u.phone, u.full_name, u.preferred_lang, u.created_at, '
            'COUNT(o.id) AS orders_count, COALESCE(SUM(o.total), 0) AS total_spent '
            'FROM users u '
            'LEFT JOIN orders o ON o.user_id = u.id '
            'WHERE u.id = ? '
            'GROUP BY u.id, u.phone, u.full_name, u.preferred_lang, u.created_at',
            (user_id,),
        ).fetchone()
        if not row:
            return None
        return {
            'id': int(row['id']),
            'phone': str(row['phone']),
            'full_name': str(row['full_name']),
            'preferred_lang': str(row['preferred_lang']),
            'created_at': str(row['created_at']),
            'orders_count': int(row['orders_count'] or 0),
            'total_spent': float(row['total_spent'] or 0),
        }

    def list_for_admin(
        self,
        conn: sqlite3.Connection,
        *,
        search: Optional[str] = None,
        limit: int = 200,
    ) -> List[dict]:
        query = (
            'SELECT u.id, u.phone, u.full_name, u.preferred_lang, u.created_at, '
            'COUNT(o.id) AS orders_count, COALESCE(SUM(o.total), 0) AS total_spent '
            'FROM users u '
            'LEFT JOIN orders o ON o.user_id = u.id '
        )
        params: List[Any] = []
        if search and search.strip():
            needle = f"%{search.strip().lower()}%"
            query += ' WHERE lower(u.full_name) LIKE ? OR lower(u.phone) LIKE ? '
            params.extend([needle, needle])
        query += (
            'GROUP BY u.id, u.phone, u.full_name, u.preferred_lang, u.created_at '
            'ORDER BY u.created_at DESC, u.id DESC '
            'LIMIT ?'
        )
        params.append(limit)
        rows = conn.execute(query, params).fetchall()
        return [
            {
                'id': int(row['id']),
                'phone': str(row['phone']),
                'full_name': str(row['full_name']),
                'preferred_lang': str(row['preferred_lang']),
                'created_at': str(row['created_at']),
                'orders_count': int(row['orders_count'] or 0),
                'total_spent': float(row['total_spent'] or 0),
            }
            for row in rows
        ]


class UserAuthRepository:
    def create_login_code(
        self,
        conn: sqlite3.Connection,
        *,
        user_id: int,
        phone: str,
        code_hash: str,
        expires_at: str,
    ) -> dict:
        cur = conn.execute(
            'INSERT INTO user_login_codes(user_id, phone, code_hash, expires_at, attempts, updated_at) '
            'VALUES (?, ?, ?, ?, 0, CURRENT_TIMESTAMP)',
            (user_id, phone, code_hash, expires_at),
        )
        row = conn.execute(
            'SELECT id, user_id, phone, code_hash, expires_at, attempts, used_at '
            'FROM user_login_codes WHERE id = ?',
            (int(cur.lastrowid),),
        ).fetchone()
        return self._row_to_dict(row)

    def get_active_code(self, conn: sqlite3.Connection, *, phone: str) -> Optional[dict]:
        row = conn.execute(
            'SELECT id, user_id, phone, code_hash, expires_at, attempts, used_at '
            'FROM user_login_codes '
            'WHERE phone = ? AND used_at IS NULL AND expires_at >= CURRENT_TIMESTAMP '
            'ORDER BY id DESC LIMIT 1',
            (phone,),
        ).fetchone()
        if not row:
            return None
        return self._row_to_dict(row)

    def increment_attempts(self, conn: sqlite3.Connection, *, code_id: int) -> int:
        conn.execute(
            'UPDATE user_login_codes SET attempts = attempts + 1, updated_at = CURRENT_TIMESTAMP WHERE id = ?',
            (code_id,),
        )
        row = conn.execute(
            'SELECT attempts FROM user_login_codes WHERE id = ?',
            (code_id,),
        ).fetchone()
        return int(row['attempts'] if row else 0)

    def consume_code(self, conn: sqlite3.Connection, *, code_id: int) -> None:
        conn.execute(
            'UPDATE user_login_codes SET used_at = CURRENT_TIMESTAMP, updated_at = CURRENT_TIMESTAMP WHERE id = ?',
            (code_id,),
        )

    def _row_to_dict(self, row: sqlite3.Row) -> dict:
        return {
            'id': int(row['id']),
            'user_id': int(row['user_id']),
            'phone': str(row['phone']),
            'code_hash': str(row['code_hash']),
            'expires_at': str(row['expires_at']),
            'attempts': int(row['attempts'] or 0),
            'used_at': str(row['used_at']) if row['used_at'] is not None else None,
        }


class AddressRepository:
    def list(self, conn: sqlite3.Connection, user_id: int) -> List[dict]:
        rows = conn.execute(
            'SELECT id, user_id, label, address_line, lat, lng FROM addresses WHERE user_id = ? ORDER BY created_at DESC',
            (user_id,),
        ).fetchall()
        return [self._row_to_dict(row) for row in rows]

    def create(self, conn: sqlite3.Connection, payload: dict) -> dict:
        cur = conn.execute(
            'INSERT INTO addresses(user_id, label, address_line, lat, lng, updated_at) VALUES (?, ?, ?, ?, ?, CURRENT_TIMESTAMP)',
            (
                int(payload['userId']),
                (payload.get('label') or '').strip() or None,
                payload['addressLine'].strip(),
                payload.get('lat'),
                payload.get('lng'),
            ),
        )
        row = conn.execute(
            'SELECT id, user_id, label, address_line, lat, lng FROM addresses WHERE id = ?',
            (int(cur.lastrowid),),
        ).fetchone()
        return self._row_to_dict(row)

    def get(self, conn: sqlite3.Connection, address_id: int) -> Optional[dict]:
        row = conn.execute(
            'SELECT id, user_id, label, address_line, lat, lng FROM addresses WHERE id = ?',
            (address_id,),
        ).fetchone()
        if not row:
            return None
        return self._row_to_dict(row)

    def _row_to_dict(self, row: sqlite3.Row) -> dict:
        return {
            'id': int(row['id']),
            'userId': int(row['user_id']),
            'label': row['label'],
            'addressLine': str(row['address_line']),
            'lat': float(row['lat']) if row['lat'] is not None else None,
            'lng': float(row['lng']) if row['lng'] is not None else None,
        }


class OrderRepository:
    def create(self, conn: sqlite3.Connection, payload: dict, products: ProductRepository) -> dict:
        total = 0.0
        items_payload = payload['items']
        for item in items_payload:
            total += float(item['price']) * int(item['qty'])
            total += sum(float(mod['price']) for mod in item.get('modifiers', [])) * int(item['qty'])

        address_text = None
        address_id = payload.get('address_id')
        if address_id:
            addr_row = conn.execute(
                'SELECT address_line FROM addresses WHERE id = ?',
                (int(address_id),),
            ).fetchone()
            if addr_row:
                address_text = str(addr_row['address_line'])

        cur = conn.execute(
            'INSERT INTO orders(user_id, delivery_type, payment_method, address_id, address, notes, status, payment_status, total, updated_at) '
            'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP)',
            (
                int(payload['user_id']),
                payload['delivery_type'],
                payload['payment_method'],
                address_id,
                address_text,
                payload.get('notes'),
                'pending',
                'unpaid' if payload['payment_method'] == 'cash' else 'pending',
                total,
            ),
        )
        order_id = int(cur.lastrowid)
        for item in items_payload:
            product_id = item.get('product_id')
            title = item.get('title')
            if not title and product_id:
                product = products.get(conn, int(product_id), include_inactive=True)
                title = product['title'] if product else f'Product #{product_id}'
            conn.execute(
                'INSERT INTO order_items(order_id, product_id, title, qty, unit_price, old_price, modifiers_json) '
                'VALUES (?, ?, ?, ?, ?, ?, ?)',
                (
                    order_id,
                    product_id,
                    title or 'Unknown product',
                    int(item['qty']),
                    float(item['price']),
                    item.get('old_price'),
                    json.dumps(item.get('modifiers', []), ensure_ascii=False),
                ),
            )
        return self.get(conn, order_id)

    def get(self, conn: sqlite3.Connection, order_id: int) -> Optional[dict]:
        order = conn.execute(
            'SELECT id, user_id, delivery_type, payment_method, address_id, address, notes, status, payment_status, total, poster_order_id, created_at '
            'FROM orders WHERE id = ?',
            (order_id,),
        ).fetchone()
        if not order:
            return None
        items = conn.execute(
            'SELECT id, product_id, title, qty, unit_price, old_price, modifiers_json FROM order_items WHERE order_id = ?',
            (order_id,),
        ).fetchall()
        return {
            'id': int(order['id']),
            'user_id': int(order['user_id']),
            'delivery_type': str(order['delivery_type']),
            'payment_method': str(order['payment_method']),
            'address_id': order['address_id'],
            'address': order['address'],
            'notes': order['notes'],
            'status': str(order['status']),
            'payment_status': str(order['payment_status']),
            'total': float(order['total']),
            'poster_order_id': order['poster_order_id'],
            'created_at': str(order['created_at']),
            'items': [
                {
                    'id': int(item['id']),
                    'product_id': item['product_id'],
                    'title': str(item['title']),
                    'qty': int(item['qty']),
                    'price': float(item['unit_price']),
                    'old_price': float(item['old_price']) if item['old_price'] is not None else None,
                    'modifiers': json.loads(item['modifiers_json'] or '[]'),
                }
                for item in items
            ],
        }

    def set_poster_order_id(self, conn: sqlite3.Connection, order_id: int, poster_order_id: str) -> Optional[dict]:
        conn.execute(
            'UPDATE orders SET poster_order_id = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?',
            (poster_order_id, order_id),
        )
        return self.get(conn, order_id)

    def list_for_admin(
        self,
        conn: sqlite3.Connection,
        *,
        search: Optional[str] = None,
        status: Optional[str] = None,
        payment_status: Optional[str] = None,
        limit: int = 300,
    ) -> List[dict]:
        query = (
            'SELECT o.id, o.user_id, o.delivery_type, o.payment_method, o.address, o.notes, '
            'o.status, o.payment_status, o.total, o.poster_order_id, o.created_at, '
            'u.full_name AS user_name, u.phone AS user_phone '
            'FROM orders o '
            'LEFT JOIN users u ON u.id = o.user_id '
        )
        conditions: List[str] = []
        params: List[Any] = []
        if search and search.strip():
            needle = f"%{search.strip().lower()}%"
            conditions.append(
                '('
                'cast(o.id as text) LIKE ? OR '
                'lower(COALESCE(u.full_name, \'\')) LIKE ? OR '
                'lower(COALESCE(u.phone, \'\')) LIKE ?'
                ')'
            )
            params.extend([needle, needle, needle])
        if status and status.strip():
            conditions.append('lower(o.status) = ?')
            params.append(status.strip().lower())
        if payment_status and payment_status.strip():
            conditions.append('lower(o.payment_status) = ?')
            params.append(payment_status.strip().lower())
        if conditions:
            query += ' WHERE ' + ' AND '.join(conditions)
        query += ' ORDER BY o.created_at DESC, o.id DESC LIMIT ?'
        params.append(limit)
        rows = conn.execute(query, params).fetchall()
        return [
            {
                'id': int(row['id']),
                'user_id': int(row['user_id']),
                'user_name': str(row['user_name'] or ''),
                'user_phone': str(row['user_phone'] or ''),
                'delivery_type': str(row['delivery_type']),
                'payment_method': str(row['payment_method']),
                'address': row['address'],
                'notes': row['notes'],
                'status': str(row['status']),
                'payment_status': str(row['payment_status']),
                'total': float(row['total']),
                'poster_order_id': row['poster_order_id'],
                'created_at': str(row['created_at']),
            }
            for row in rows
        ]

    def update_admin_status(
        self,
        conn: sqlite3.Connection,
        order_id: int,
        *,
        status_value: str,
        payment_status: str,
    ) -> Optional[dict]:
        exists = conn.execute('SELECT id FROM orders WHERE id = ?', (order_id,)).fetchone()
        if not exists:
            return None
        conn.execute(
            'UPDATE orders SET status = ?, payment_status = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?',
            (status_value.strip(), payment_status.strip(), order_id),
        )
        row = conn.execute(
            'SELECT o.id, o.user_id, o.delivery_type, o.payment_method, o.address, o.notes, '
            'o.status, o.payment_status, o.total, o.poster_order_id, o.created_at, '
            'u.full_name AS user_name, u.phone AS user_phone '
            'FROM orders o LEFT JOIN users u ON u.id = o.user_id WHERE o.id = ?',
            (order_id,),
        ).fetchone()
        if not row:
            return None
        return {
            'id': int(row['id']),
            'user_id': int(row['user_id']),
            'user_name': str(row['user_name'] or ''),
            'user_phone': str(row['user_phone'] or ''),
            'delivery_type': str(row['delivery_type']),
            'payment_method': str(row['payment_method']),
            'address': row['address'],
            'notes': row['notes'],
            'status': str(row['status']),
            'payment_status': str(row['payment_status']),
            'total': float(row['total']),
            'poster_order_id': row['poster_order_id'],
            'created_at': str(row['created_at']),
        }


class AdminRepository:
    def get_by_email(self, conn: sqlite3.Connection, email: str) -> Optional[dict]:
        row = conn.execute(
            'SELECT id, email, password_hash, full_name, is_active FROM admin_users WHERE lower(email) = lower(?)',
            (email,),
        ).fetchone()
        if not row:
            return None
        return {
            'id': int(row['id']),
            'email': str(row['email']),
            'password_hash': str(row['password_hash']),
            'full_name': str(row['full_name']),
            'is_active': bool(row['is_active']),
        }

    def get_by_id(self, conn: sqlite3.Connection, admin_id: int) -> Optional[dict]:
        row = conn.execute(
            'SELECT id, email, password_hash, full_name, is_active FROM admin_users WHERE id = ?',
            (admin_id,),
        ).fetchone()
        if not row:
            return None
        return {
            'id': int(row['id']),
            'email': str(row['email']),
            'password_hash': str(row['password_hash']),
            'full_name': str(row['full_name']),
            'is_active': bool(row['is_active']),
        }

    def update_profile(
        self,
        conn: sqlite3.Connection,
        admin_id: int,
        *,
        full_name: str,
        password_hash: Optional[str] = None,
    ) -> Optional[dict]:
        current = self.get_by_id(conn, admin_id)
        if not current:
            return None
        if password_hash:
            conn.execute(
                'UPDATE admin_users SET full_name = ?, password_hash = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?',
                (full_name.strip(), password_hash, admin_id),
            )
        else:
            conn.execute(
                'UPDATE admin_users SET full_name = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?',
                (full_name.strip(), admin_id),
            )
        return self.get_by_id(conn, admin_id)


class AdminDashboardRepository:
    def stats(self, conn: sqlite3.Connection) -> dict:
        row = conn.execute(
            'SELECT COUNT(*) AS total_orders, COALESCE(SUM(total), 0) AS revenue '
            'FROM orders'
        ).fetchone()
        pending = conn.execute(
            "SELECT COUNT(*) AS total FROM orders WHERE lower(status) = 'pending'"
        ).fetchone()
        users = conn.execute('SELECT COUNT(*) AS total FROM users').fetchone()
        categories = conn.execute('SELECT COUNT(*) AS total FROM categories').fetchone()
        products = conn.execute('SELECT COUNT(*) AS total FROM products').fetchone()
        discounted = conn.execute(
            'SELECT COUNT(*) AS total FROM products WHERE old_price IS NOT NULL AND old_price > price'
        ).fetchone()
        banners = conn.execute('SELECT COUNT(*) AS total FROM admin_banners WHERE is_active = 1').fetchone()
        return {
            'revenue': float(row['revenue'] or 0),
            'totalOrders': int(row['total_orders'] or 0),
            'pendingOrders': int(pending['total'] or 0),
            'users': int(users['total'] or 0),
            'categories': int(categories['total'] or 0),
            'products': int(products['total'] or 0),
            'discountedProducts': int(discounted['total'] or 0),
            'activeBanners': int(banners['total'] or 0),
        }

    def list_banners(self, conn: sqlite3.Connection, *, active_only: bool = False) -> List[dict]:
        query = (
            'SELECT id, title, title_en, title_ru, title_uz, '
            'subtitle, subtitle_en, subtitle_ru, subtitle_uz, '
            'image_url, action_type, product_id, category_id, linked_product_ids_json, product_ids_json, '
            'target_url, '
            'is_active, sort_order, created_at, updated_at '
            'FROM admin_banners'
        )
        params: List[Any] = []
        if active_only:
            query += ' WHERE is_active = 1'
        query += ' ORDER BY sort_order ASC, id DESC'
        rows = conn.execute(query, params).fetchall()
        return [self._banner_row_to_dict(row) for row in rows]

    def get_banner(self, conn: sqlite3.Connection, banner_id: int, *, active_only: bool = False) -> Optional[dict]:
        query = (
            'SELECT id, title, title_en, title_ru, title_uz, '
            'subtitle, subtitle_en, subtitle_ru, subtitle_uz, '
            'image_url, action_type, product_id, category_id, linked_product_ids_json, product_ids_json, '
            'target_url, '
            'is_active, sort_order, created_at, updated_at '
            'FROM admin_banners WHERE id = ?'
        )
        params: List[Any] = [int(banner_id)]
        if active_only:
            query += ' AND is_active = 1'
        row = conn.execute(query, params).fetchone()
        return self._banner_row_to_dict(row) if row else None

    def create_banner(self, conn: sqlite3.Connection, payload: dict) -> dict:
        normalized = self._normalize_banner_payload(payload)
        cur = conn.execute(
            'INSERT INTO admin_banners('
            'title, title_en, title_ru, title_uz, '
            'subtitle, subtitle_en, subtitle_ru, subtitle_uz, '
            'image_url, action_type, product_id, category_id, linked_product_ids_json, product_ids_json, '
            'target_url, is_active, sort_order, updated_at'
            ') VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP)',
            (
                normalized['title'],
                normalized['titleEn'],
                normalized['titleRu'],
                normalized['titleUz'],
                normalized['subtitle'],
                normalized['subtitleEn'],
                normalized['subtitleRu'],
                normalized['subtitleUz'],
                normalized['imageUrl'],
                normalized['actionType'],
                normalized['productId'],
                normalized['categoryId'],
                normalized['linkedProductIdsJson'],
                normalized['legacyProductIdsJson'],
                normalized['targetUrl'],
                1 if normalized['isActive'] else 0,
                normalized['sortOrder'],
            ),
        )
        row_id = int(cur.lastrowid)
        row = self.get_banner(conn, row_id, active_only=False)
        if not row:
            raise ValueError('Banner not found after create.')
        return row

    def update_banner(self, conn: sqlite3.Connection, banner_id: int, payload: dict) -> Optional[dict]:
        existing = conn.execute('SELECT id FROM admin_banners WHERE id = ?', (banner_id,)).fetchone()
        if not existing:
            return None
        normalized = self._normalize_banner_payload(payload)
        conn.execute(
            'UPDATE admin_banners SET '
            'title = ?, title_en = ?, title_ru = ?, title_uz = ?, '
            'subtitle = ?, subtitle_en = ?, subtitle_ru = ?, subtitle_uz = ?, '
            'image_url = ?, action_type = ?, product_id = ?, category_id = ?, '
            'linked_product_ids_json = ?, product_ids_json = ?, target_url = ?, '
            'is_active = ?, sort_order = ?, '
            'updated_at = CURRENT_TIMESTAMP WHERE id = ?',
            (
                normalized['title'],
                normalized['titleEn'],
                normalized['titleRu'],
                normalized['titleUz'],
                normalized['subtitle'],
                normalized['subtitleEn'],
                normalized['subtitleRu'],
                normalized['subtitleUz'],
                normalized['imageUrl'],
                normalized['actionType'],
                normalized['productId'],
                normalized['categoryId'],
                normalized['linkedProductIdsJson'],
                normalized['legacyProductIdsJson'],
                normalized['targetUrl'],
                1 if normalized['isActive'] else 0,
                normalized['sortOrder'],
                banner_id,
            ),
        )
        return self.get_banner(conn, banner_id, active_only=False)

    def delete_banner(self, conn: sqlite3.Connection, banner_id: int) -> bool:
        cur = conn.execute('DELETE FROM admin_banners WHERE id = ?', (banner_id,))
        return cur.rowcount > 0

    def list_notifications(self, conn: sqlite3.Connection, *, active_only: bool = False) -> List[dict]:
        query = (
            'SELECT id, title, message, title_en, title_ru, title_uz, '
            'message_en, message_ru, message_uz, delivery_types_json, image_url, '
            'type, is_active, created_at, updated_at '
            'FROM admin_notifications'
        )
        if active_only:
            query += ' WHERE is_active = 1'
        query += ' ORDER BY created_at DESC, id DESC'
        rows = conn.execute(query).fetchall()
        return [self._notification_row_to_dict(row) for row in rows]

    def create_notification(self, conn: sqlite3.Connection, payload: dict) -> dict:
        normalized = self._normalize_notification_payload(payload)
        cur = conn.execute(
            'INSERT INTO admin_notifications('
            'title, message, title_en, title_ru, title_uz, message_en, message_ru, message_uz, '
            'delivery_types_json, image_url, type, is_active, updated_at'
            ') VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP)',
            (
                normalized['title'],
                normalized['message'],
                normalized['titleEn'],
                normalized['titleRu'],
                normalized['titleUz'],
                normalized['messageEn'],
                normalized['messageRu'],
                normalized['messageUz'],
                normalized['deliveryTypesJson'],
                normalized['imageUrl'],
                normalized['type'],
                1 if normalized['isActive'] else 0,
            ),
        )
        row_id = int(cur.lastrowid)
        row = conn.execute(
            'SELECT id, title, message, title_en, title_ru, title_uz, message_en, message_ru, message_uz, '
            'delivery_types_json, image_url, '
            'type, is_active, created_at, updated_at '
            'FROM admin_notifications WHERE id = ?',
            (row_id,),
        ).fetchone()
        return self._notification_row_to_dict(row)

    def update_notification(self, conn: sqlite3.Connection, notification_id: int, payload: dict) -> Optional[dict]:
        exists = conn.execute('SELECT id FROM admin_notifications WHERE id = ?', (notification_id,)).fetchone()
        if not exists:
            return None
        normalized = self._normalize_notification_payload(payload)
        conn.execute(
            'UPDATE admin_notifications SET title = ?, message = ?, title_en = ?, title_ru = ?, title_uz = ?, '
            'message_en = ?, message_ru = ?, message_uz = ?, delivery_types_json = ?, image_url = ?, '
            'type = ?, is_active = ?, updated_at = CURRENT_TIMESTAMP '
            'WHERE id = ?',
            (
                normalized['title'],
                normalized['message'],
                normalized['titleEn'],
                normalized['titleRu'],
                normalized['titleUz'],
                normalized['messageEn'],
                normalized['messageRu'],
                normalized['messageUz'],
                normalized['deliveryTypesJson'],
                normalized['imageUrl'],
                normalized['type'],
                1 if normalized['isActive'] else 0,
                notification_id,
            ),
        )
        row = conn.execute(
            'SELECT id, title, message, title_en, title_ru, title_uz, message_en, message_ru, message_uz, '
            'delivery_types_json, image_url, '
            'type, is_active, created_at, updated_at '
            'FROM admin_notifications WHERE id = ?',
            (notification_id,),
        ).fetchone()
        return self._notification_row_to_dict(row)

    def delete_notification(self, conn: sqlite3.Connection, notification_id: int) -> bool:
        cur = conn.execute('DELETE FROM admin_notifications WHERE id = ?', (notification_id,))
        return cur.rowcount > 0

    def log_notification_delivery(
        self,
        conn: sqlite3.Connection,
        *,
        notification_id: int,
        channel: str,
        status: str,
        message: Optional[str] = None,
    ) -> None:
        conn.execute(
            'INSERT INTO admin_notification_delivery_logs('
            'notification_id, channel, status, message'
            ') VALUES (?, ?, ?, ?)',
            (
                int(notification_id),
                str(channel).strip().lower() or 'unknown',
                str(status).strip().lower() or 'unknown',
                (message or '').strip() or None,
            ),
        )

    def list_notification_delivery_logs(
        self,
        conn: sqlite3.Connection,
        *,
        notification_id: int,
        limit: int = 20,
    ) -> List[dict]:
        rows = conn.execute(
            'SELECT id, notification_id, channel, status, message, created_at '
            'FROM admin_notification_delivery_logs '
            'WHERE notification_id = ? '
            'ORDER BY created_at DESC, id DESC '
            'LIMIT ?',
            (int(notification_id), max(1, min(int(limit), 200))),
        ).fetchall()
        return [
            {
                'id': int(row['id']),
                'notificationId': int(row['notification_id']),
                'channel': str(row['channel']),
                'status': str(row['status']),
                'message': str(row['message'] or ''),
                'createdAt': str(row['created_at']),
            }
            for row in rows
        ]

    def list_faq(self, conn: sqlite3.Connection, *, active_only: bool = False) -> List[dict]:
        query = (
            'SELECT id, question, answer, question_en, question_ru, question_uz, '
            'answer_en, answer_ru, answer_uz, is_active, sort_order, created_at, updated_at '
            'FROM admin_faq'
        )
        params: List[Any] = []
        if active_only:
            query += ' WHERE is_active = 1'
        query += ' ORDER BY sort_order ASC, id DESC'
        rows = conn.execute(query, params).fetchall()
        return [
            {
                'id': int(row['id']),
                'question': str(row['question']),
                'answer': str(row['answer']),
                'questionEn': row['question_en'] or row['question'],
                'questionRu': row['question_ru'] or row['question'],
                'questionUz': row['question_uz'] or row['question'],
                'answerEn': row['answer_en'] or row['answer'],
                'answerRu': row['answer_ru'] or row['answer'],
                'answerUz': row['answer_uz'] or row['answer'],
                'isActive': bool(row['is_active']),
                'sortOrder': int(row['sort_order']),
                'createdAt': str(row['created_at']),
                'updatedAt': str(row['updated_at']),
            }
            for row in rows
        ]

    def create_faq(self, conn: sqlite3.Connection, payload: dict) -> dict:
        cur = conn.execute(
            'INSERT INTO admin_faq('
            'question, answer, question_en, question_ru, question_uz, answer_en, answer_ru, answer_uz, '
            'is_active, sort_order, updated_at'
            ') VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP)',
            (
                payload['question'].strip(),
                payload['answer'].strip(),
                self._pick_lang(payload, 'questionEn', payload['question']),
                self._pick_lang(payload, 'questionRu', payload['question']),
                self._pick_lang(payload, 'questionUz', payload['question']),
                self._pick_lang(payload, 'answerEn', payload['answer']),
                self._pick_lang(payload, 'answerRu', payload['answer']),
                self._pick_lang(payload, 'answerUz', payload['answer']),
                1 if payload.get('isActive', True) else 0,
                int(payload.get('sortOrder', 0)),
            ),
        )
        row_id = int(cur.lastrowid)
        row = conn.execute(
            'SELECT id, question, answer, question_en, question_ru, question_uz, answer_en, answer_ru, answer_uz, '
            'is_active, sort_order, created_at, updated_at FROM admin_faq WHERE id = ?',
            (row_id,),
        ).fetchone()
        return {
            'id': int(row['id']),
            'question': str(row['question']),
            'answer': str(row['answer']),
            'questionEn': row['question_en'] or row['question'],
            'questionRu': row['question_ru'] or row['question'],
            'questionUz': row['question_uz'] or row['question'],
            'answerEn': row['answer_en'] or row['answer'],
            'answerRu': row['answer_ru'] or row['answer'],
            'answerUz': row['answer_uz'] or row['answer'],
            'isActive': bool(row['is_active']),
            'sortOrder': int(row['sort_order']),
            'createdAt': str(row['created_at']),
            'updatedAt': str(row['updated_at']),
        }

    def update_faq(self, conn: sqlite3.Connection, faq_id: int, payload: dict) -> Optional[dict]:
        exists = conn.execute('SELECT id FROM admin_faq WHERE id = ?', (faq_id,)).fetchone()
        if not exists:
            return None
        conn.execute(
            'UPDATE admin_faq SET '
            'question = ?, answer = ?, question_en = ?, question_ru = ?, question_uz = ?, '
            'answer_en = ?, answer_ru = ?, answer_uz = ?, '
            'is_active = ?, sort_order = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?',
            (
                payload['question'].strip(),
                payload['answer'].strip(),
                self._pick_lang(payload, 'questionEn', payload['question']),
                self._pick_lang(payload, 'questionRu', payload['question']),
                self._pick_lang(payload, 'questionUz', payload['question']),
                self._pick_lang(payload, 'answerEn', payload['answer']),
                self._pick_lang(payload, 'answerRu', payload['answer']),
                self._pick_lang(payload, 'answerUz', payload['answer']),
                1 if payload.get('isActive', True) else 0,
                int(payload.get('sortOrder', 0)),
                faq_id,
            ),
        )
        row = conn.execute(
            'SELECT id, question, answer, question_en, question_ru, question_uz, answer_en, answer_ru, answer_uz, '
            'is_active, sort_order, created_at, updated_at FROM admin_faq WHERE id = ?',
            (faq_id,),
        ).fetchone()
        return {
            'id': int(row['id']),
            'question': str(row['question']),
            'answer': str(row['answer']),
            'questionEn': row['question_en'] or row['question'],
            'questionRu': row['question_ru'] or row['question'],
            'questionUz': row['question_uz'] or row['question'],
            'answerEn': row['answer_en'] or row['answer'],
            'answerRu': row['answer_ru'] or row['answer'],
            'answerUz': row['answer_uz'] or row['answer'],
            'isActive': bool(row['is_active']),
            'sortOrder': int(row['sort_order']),
            'createdAt': str(row['created_at']),
            'updatedAt': str(row['updated_at']),
        }

    def delete_faq(self, conn: sqlite3.Connection, faq_id: int) -> bool:
        cur = conn.execute('DELETE FROM admin_faq WHERE id = ?', (faq_id,))
        return cur.rowcount > 0

    def get_settings(self, conn: sqlite3.Connection) -> dict:
        row = conn.execute(
            'SELECT id, support_phone, timezone, currency_code, '
            'call_label_en, call_label_ru, call_label_uz, '
            'chat_label_en, chat_label_ru, chat_label_uz, '
            'chat_subtitle_en, chat_subtitle_ru, chat_subtitle_uz, '
            'chat_intro_en, chat_intro_ru, chat_intro_uz, '
            'updated_at FROM admin_settings WHERE id = 1'
        ).fetchone()
        if not row:
            conn.execute(
                "INSERT INTO admin_settings(id, support_phone, timezone, currency_code, updated_at) VALUES (1, '', 'Asia/Tashkent', 'UZS', CURRENT_TIMESTAMP)"
            )
            row = conn.execute(
                'SELECT id, support_phone, timezone, currency_code, '
                'call_label_en, call_label_ru, call_label_uz, '
                'chat_label_en, chat_label_ru, chat_label_uz, '
                'chat_subtitle_en, chat_subtitle_ru, chat_subtitle_uz, '
                'chat_intro_en, chat_intro_ru, chat_intro_uz, '
                'updated_at FROM admin_settings WHERE id = 1'
            ).fetchone()
        return {
            'supportPhone': str(row['support_phone'] or ''),
            'timezone': str(row['timezone'] or 'Asia/Tashkent'),
            'currencyCode': str(row['currency_code'] or 'UZS'),
            'callLabelEn': str(row['call_label_en'] or ''),
            'callLabelRu': str(row['call_label_ru'] or ''),
            'callLabelUz': str(row['call_label_uz'] or ''),
            'chatLabelEn': str(row['chat_label_en'] or ''),
            'chatLabelRu': str(row['chat_label_ru'] or ''),
            'chatLabelUz': str(row['chat_label_uz'] or ''),
            'chatSubtitleEn': str(row['chat_subtitle_en'] or ''),
            'chatSubtitleRu': str(row['chat_subtitle_ru'] or ''),
            'chatSubtitleUz': str(row['chat_subtitle_uz'] or ''),
            'chatIntroEn': str(row['chat_intro_en'] or ''),
            'chatIntroRu': str(row['chat_intro_ru'] or ''),
            'chatIntroUz': str(row['chat_intro_uz'] or ''),
            'updatedAt': str(row['updated_at']),
        }

    def update_settings(self, conn: sqlite3.Connection, payload: dict) -> dict:
        current = self.get_settings(conn)
        def _text(key: str, fallback: str) -> str:
            if key not in payload:
                return fallback.strip()
            value = payload.get(key)
            if value is None:
                return ''
            return str(value).strip()

        conn.execute(
            'UPDATE admin_settings SET '
            'support_phone = ?, timezone = ?, currency_code = ?, '
            'call_label_en = ?, call_label_ru = ?, call_label_uz = ?, '
            'chat_label_en = ?, chat_label_ru = ?, chat_label_uz = ?, '
            'chat_subtitle_en = ?, chat_subtitle_ru = ?, chat_subtitle_uz = ?, '
            'chat_intro_en = ?, chat_intro_ru = ?, chat_intro_uz = ?, '
            'updated_at = CURRENT_TIMESTAMP WHERE id = 1',
            (
                _text('supportPhone', current['supportPhone']),
                _text('timezone', current['timezone']),
                _text('currencyCode', current['currencyCode']),
                _text('callLabelEn', current['callLabelEn']),
                _text('callLabelRu', current['callLabelRu']),
                _text('callLabelUz', current['callLabelUz']),
                _text('chatLabelEn', current['chatLabelEn']),
                _text('chatLabelRu', current['chatLabelRu']),
                _text('chatLabelUz', current['chatLabelUz']),
                _text('chatSubtitleEn', current['chatSubtitleEn']),
                _text('chatSubtitleRu', current['chatSubtitleRu']),
                _text('chatSubtitleUz', current['chatSubtitleUz']),
                _text('chatIntroEn', current['chatIntroEn']),
                _text('chatIntroRu', current['chatIntroRu']),
                _text('chatIntroUz', current['chatIntroUz']),
            ),
        )
        return self.get_settings(conn)

    def create_settings(self, conn: sqlite3.Connection, payload: dict) -> dict:
        # Singleton resource; "create" is treated as an idempotent upsert.
        current = conn.execute('SELECT id FROM admin_settings WHERE id = 1').fetchone()
        if not current:
            conn.execute(
                'INSERT INTO admin_settings('
                'id, support_phone, timezone, currency_code, '
                'call_label_en, call_label_ru, call_label_uz, '
                'chat_label_en, chat_label_ru, chat_label_uz, '
                'chat_subtitle_en, chat_subtitle_ru, chat_subtitle_uz, '
                'chat_intro_en, chat_intro_ru, chat_intro_uz, '
                'updated_at'
                ') VALUES (1, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP)',
                (
                    str(payload.get('supportPhone') or '').strip(),
                    str(payload.get('timezone') or 'Asia/Tashkent').strip() or 'Asia/Tashkent',
                    str(payload.get('currencyCode') or 'UZS').strip() or 'UZS',
                    str(payload.get('callLabelEn') or '').strip(),
                    str(payload.get('callLabelRu') or '').strip(),
                    str(payload.get('callLabelUz') or '').strip(),
                    str(payload.get('chatLabelEn') or '').strip(),
                    str(payload.get('chatLabelRu') or '').strip(),
                    str(payload.get('chatLabelUz') or '').strip(),
                    str(payload.get('chatSubtitleEn') or '').strip(),
                    str(payload.get('chatSubtitleRu') or '').strip(),
                    str(payload.get('chatSubtitleUz') or '').strip(),
                    str(payload.get('chatIntroEn') or '').strip(),
                    str(payload.get('chatIntroRu') or '').strip(),
                    str(payload.get('chatIntroUz') or '').strip(),
                ),
            )
            return self.get_settings(conn)
        return self.update_settings(conn, payload)

    def reset_settings(self, conn: sqlite3.Connection) -> dict:
        self.get_settings(conn)
        conn.execute(
            'UPDATE admin_settings SET '
            'support_phone = ?, timezone = ?, currency_code = ?, '
            'call_label_en = ?, call_label_ru = ?, call_label_uz = ?, '
            'chat_label_en = ?, chat_label_ru = ?, chat_label_uz = ?, '
            'chat_subtitle_en = ?, chat_subtitle_ru = ?, chat_subtitle_uz = ?, '
            'chat_intro_en = ?, chat_intro_ru = ?, chat_intro_uz = ?, '
            'updated_at = CURRENT_TIMESTAMP WHERE id = 1',
            (
                '',
                'Asia/Tashkent',
                'UZS',
                '',
                '',
                '',
                '',
                '',
                '',
                '',
                '',
                '',
                '',
                '',
                '',
            ),
        )
        return self.get_settings(conn)

    def _banner_row_to_dict(self, row: sqlite3.Row) -> dict:
        action_type = str(row['action_type'] or 'none').strip().lower() if 'action_type' in row.keys() else 'none'
        if action_type not in {'open_product', 'open_products', 'open_category', 'open_discounts', 'open_url', 'none'}:
            action_type = 'none'
        linked_raw = (
            row['linked_product_ids_json']
            if 'linked_product_ids_json' in row.keys()
            else row['product_ids_json']
        )
        linked_product_ids = self._normalize_id_list(linked_raw)
        product_id = self._parse_positive_int(row['product_id']) if 'product_id' in row.keys() else None
        if action_type == 'open_product' and product_id is not None:
            product_ids = [product_id]
        elif action_type == 'open_products':
            product_ids = linked_product_ids
        else:
            product_ids = []
        category_id = self._parse_positive_int(row['category_id']) if 'category_id' in row.keys() else None
        target_url = str(row['target_url'] or '').strip() if 'target_url' in row.keys() else ''
        subtitle = str(row['subtitle'] or '').strip() if 'subtitle' in row.keys() else ''
        title = str(row['title'] or '').strip()
        title_en = str(row['title_en'] or title).strip()
        title_ru = str(row['title_ru'] or title).strip()
        title_uz = str(row['title_uz'] or title).strip()
        subtitle_en = (
            str(row['subtitle_en']).strip()
            if ('subtitle_en' in row.keys() and row['subtitle_en'] is not None)
            else subtitle
        )
        subtitle_ru = (
            str(row['subtitle_ru']).strip()
            if ('subtitle_ru' in row.keys() and row['subtitle_ru'] is not None)
            else subtitle
        )
        subtitle_uz = (
            str(row['subtitle_uz']).strip()
            if ('subtitle_uz' in row.keys() and row['subtitle_uz'] is not None)
            else subtitle
        )
        return {
            'id': int(row['id']),
            'title': title,
            'titleEn': title_en,
            'titleRu': title_ru,
            'titleUz': title_uz,
            'subtitle': subtitle or None,
            'subtitleEn': subtitle_en or None,
            'subtitleRu': subtitle_ru or None,
            'subtitleUz': subtitle_uz or None,
            'imageUrl': str(row['image_url']),
            'productIds': product_ids,
            'linkedProductIds': linked_product_ids,
            'actionType': action_type,
            'productId': product_id,
            'categoryId': category_id,
            'targetUrl': target_url or None,
            'isActive': bool(row['is_active']),
            'sortOrder': int(row['sort_order']),
            'createdAt': str(row['created_at']),
            'updatedAt': str(row['updated_at']),
        }

    def _notification_row_to_dict(self, row: sqlite3.Row) -> dict:
        raw_delivery_types = row['delivery_types_json'] if 'delivery_types_json' in row.keys() else '["in_app"]'
        delivery_types = self._normalize_delivery_types(raw_delivery_types)
        return {
            'id': int(row['id']),
            'title': str(row['title']),
            'message': str(row['message']),
            'titleEn': row['title_en'] or row['title'],
            'titleRu': row['title_ru'] or row['title'],
            'titleUz': row['title_uz'] or row['title'],
            'messageEn': row['message_en'] or row['message'],
            'messageRu': row['message_ru'] or row['message'],
            'messageUz': row['message_uz'] or row['message'],
            'deliveryTypes': delivery_types,
            'imageUrl': str(row['image_url'] or '').strip(),
            'type': str(row['type']),
            'isActive': bool(row['is_active']),
            'createdAt': str(row['created_at']),
            'updatedAt': str(row['updated_at']),
        }

    def _normalize_notification_payload(self, payload: dict) -> dict:
        def _text(key: str) -> str:
            value = payload.get(key)
            if value is None:
                return ''
            return str(value).strip()

        title = _text('title')
        title_en = _text('titleEn')
        title_ru = _text('titleRu')
        title_uz = _text('titleUz')
        base_title = title or title_en or title_ru or title_uz
        title_en = title_en or base_title
        title_ru = title_ru or base_title
        title_uz = title_uz or base_title
        title = title or title_en or title_ru or title_uz

        message = _text('message')
        message_en = _text('messageEn')
        message_ru = _text('messageRu')
        message_uz = _text('messageUz')
        base_message = message or message_en or message_ru or message_uz
        message_en = message_en or base_message
        message_ru = message_ru or base_message
        message_uz = message_uz or base_message
        message = message or message_en or message_ru or message_uz

        if not title:
            raise ValueError('At least one title is required.')
        if not message:
            raise ValueError('At least one message is required.')

        delivery_types = self._normalize_delivery_types(
            payload.get('deliveryTypes') or payload.get('delivery_types') or ['in_app']
        )
        image_url = _text('imageUrl') or _text('image_url') or None
        type_value = _text('type') or 'info'
        return {
            'title': title,
            'message': message,
            'titleEn': title_en,
            'titleRu': title_ru,
            'titleUz': title_uz,
            'messageEn': message_en,
            'messageRu': message_ru,
            'messageUz': message_uz,
            'deliveryTypes': delivery_types,
            'deliveryTypesJson': json.dumps(delivery_types, ensure_ascii=False),
            'imageUrl': image_url,
            'type': type_value,
            'isActive': bool(payload.get('isActive', payload.get('is_active', True))),
        }

    def _normalize_delivery_types(self, value: Any) -> List[str]:
        allowed = {'push', 'in_app', 'mailing'}
        if isinstance(value, str):
            try:
                parsed = json.loads(value)
                if isinstance(parsed, list):
                    raw_items = parsed
                else:
                    raw_items = [value]
            except Exception:
                raw_items = [value]
        elif isinstance(value, list):
            raw_items = value
        else:
            raw_items = ['in_app']

        normalized: List[str] = []
        for item in raw_items:
            candidate = str(item or '').strip().lower()
            if not candidate or candidate not in allowed:
                continue
            if candidate not in normalized:
                normalized.append(candidate)
        if not normalized:
            normalized = ['in_app']
        return normalized

    def _pick_lang(self, payload: dict, key: str, fallback: Any) -> Optional[str]:
        value = (payload.get(key) or '').strip()
        if value:
            return value
        fallback_text = '' if fallback is None else str(fallback).strip()
        return fallback_text or None

    def _normalize_banner_payload(self, payload: dict) -> dict:
        def _text(*keys: str) -> str:
            for key in keys:
                value = payload.get(key)
                if value is None:
                    continue
                text = str(value).strip()
                if text:
                    return text
            return ''

        title_en = _text('titleEn', 'title_en')
        title_ru = _text('titleRu', 'title_ru')
        title_uz = _text('titleUz', 'title_uz')
        title = _text('title') or title_en or title_ru or title_uz
        if not title:
            raise ValueError('Banner title is required.')
        if not title_en:
            title_en = title
        if not title_ru:
            title_ru = title_en or title
        if not title_uz:
            title_uz = title_en or title

        subtitle = _text('subtitle') or None
        subtitle_en = _text('subtitleEn', 'subtitle_en') or subtitle
        subtitle_ru = _text('subtitleRu', 'subtitle_ru') or subtitle
        subtitle_uz = _text('subtitleUz', 'subtitle_uz') or subtitle

        image_url = _text('imageUrl', 'image_url')
        if not image_url:
            raise ValueError('Banner image URL is required.')

        action_type = _text('actionType', 'action_type').lower() or 'none'
        allowed_action_types = {
            'open_product',
            'open_products',
            'open_category',
            'open_discounts',
            'open_url',
            'none',
        }
        if action_type not in allowed_action_types:
            raise ValueError('Unsupported action type.')

        linked_product_ids = self._normalize_id_list(
            payload.get('linkedProductIds')
            if payload.get('linkedProductIds') is not None
            else (
                payload.get('linked_product_ids')
                if payload.get('linked_product_ids') is not None
                else (
                    payload.get('productIds')
                    if payload.get('productIds') is not None
                    else payload.get('product_ids')
                )
            )
        )
        product_id = self._parse_positive_int(payload.get('productId') or payload.get('product_id'))
        category_id = self._parse_positive_int(payload.get('categoryId') or payload.get('category_id'))
        target_url = _text('targetUrl', 'target_url') or None

        if action_type == 'open_product':
            if product_id is None:
                raise ValueError('open_product requires productId.')
            category_id = None
            linked_product_ids = []
            target_url = None
        elif action_type == 'open_products':
            if not linked_product_ids:
                raise ValueError('open_products requires linkedProductIds.')
            product_id = None
            category_id = None
            target_url = None
        elif action_type == 'open_category':
            if category_id is None:
                raise ValueError('open_category requires categoryId.')
            product_id = None
            linked_product_ids = []
            target_url = None
        elif action_type == 'open_discounts':
            product_id = None
            category_id = None
            linked_product_ids = []
            target_url = None
        elif action_type == 'open_url':
            if not target_url:
                raise ValueError('open_url requires targetUrl.')
            product_id = None
            category_id = None
            linked_product_ids = []
        else:
            product_id = None
            category_id = None
            linked_product_ids = []
            target_url = None

        if action_type == 'open_product' and product_id is not None:
            legacy_product_ids = [product_id]
        elif action_type == 'open_products':
            legacy_product_ids = linked_product_ids
        else:
            legacy_product_ids = []

        return {
            'title': title,
            'titleEn': title_en,
            'titleRu': title_ru,
            'titleUz': title_uz,
            'subtitle': subtitle,
            'subtitleEn': subtitle_en,
            'subtitleRu': subtitle_ru,
            'subtitleUz': subtitle_uz,
            'imageUrl': image_url,
            'actionType': action_type,
            'productId': product_id,
            'categoryId': category_id,
            'linkedProductIds': linked_product_ids,
            'linkedProductIdsJson': json.dumps(linked_product_ids, ensure_ascii=False),
            'legacyProductIdsJson': json.dumps(legacy_product_ids, ensure_ascii=False),
            'targetUrl': target_url,
            'isActive': bool(payload.get('isActive', True)),
            'sortOrder': int(payload.get('sortOrder') or 0),
        }

    def _normalize_id_list(self, value: Any) -> List[int]:
        raw_values: List[Any]
        if value is None:
            raw_values = []
        elif isinstance(value, str):
            stripped = value.strip()
            if not stripped:
                raw_values = []
            else:
                try:
                    parsed = json.loads(stripped)
                    if isinstance(parsed, list):
                        raw_values = parsed
                    else:
                        raw_values = [stripped]
                except Exception:
                    raw_values = [part.strip() for part in stripped.split(',') if part.strip()]
        elif isinstance(value, list):
            raw_values = value
        else:
            raw_values = [value]

        result: List[int] = []
        seen: set[int] = set()
        for item in raw_values:
            parsed = self._parse_positive_int(item)
            if parsed is None or parsed in seen:
                continue
            seen.add(parsed)
            result.append(parsed)
        return result

    def _parse_positive_int(self, value: Any) -> Optional[int]:
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


class PublicRepository:
    def working_hours(self) -> List[dict]:
        return [
            {'day': 1, 'opens_at': '10:00', 'closes_at': '23:00', 'is_closed': False},
            {'day': 2, 'opens_at': '10:00', 'closes_at': '23:00', 'is_closed': False},
            {'day': 3, 'opens_at': '10:00', 'closes_at': '23:00', 'is_closed': False},
            {'day': 4, 'opens_at': '10:00', 'closes_at': '23:00', 'is_closed': False},
            {'day': 5, 'opens_at': '10:00', 'closes_at': '23:30', 'is_closed': False},
            {'day': 6, 'opens_at': '10:00', 'closes_at': '23:30', 'is_closed': False},
            {'day': 7, 'opens_at': '10:00', 'closes_at': '23:00', 'is_closed': False},
        ]
