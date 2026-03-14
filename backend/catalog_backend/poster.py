from __future__ import annotations

import os
import re
import time
from datetime import datetime, timedelta
from typing import Any, Dict, List, Optional, Set, Tuple

import httpx


class PosterSyncError(RuntimeError):
    pass


class PosterClient:
    def __init__(self) -> None:
        self._token = os.getenv('POSTER_API_TOKEN', '').strip()
        self._account = os.getenv('POSTER_ACCOUNT', '').strip()
        self._base_url = os.getenv('POSTER_BASE_URL', 'https://joinposter.com').strip()
        self._requested = _to_bool(os.getenv('POSTER_ORDER_ENABLED'), default=False)
        self._menu_requested = _to_bool(os.getenv('POSTER_MENU_ENABLED'), default=False)
        self._enabled = (self._requested or self._menu_requested) and bool(self._token)
        self._config_error: Optional[str] = None
        if (self._requested or self._menu_requested) and not self._token:
            self._config_error = (
                'Poster is enabled but POSTER_API_TOKEN is empty. '
                'Set POSTER_API_TOKEN in backend/catalog_backend/.env'
            )
        self._configured_spot_id = _to_int(os.getenv('POSTER_ORDER_SPOT_ID'))
        self._skip_phone_validation = _to_bool(
            os.getenv('POSTER_SKIP_PHONE_VALIDATION'),
            default=False,
        )
        self._timeout = httpx.Timeout(connect=10.0, read=20.0, write=20.0, pool=20.0)
        self._spot_id_cache: Optional[int] = self._configured_spot_id
        self._product_ids_cache: Optional[Set[int]] = None
        self._product_name_to_id_cache: Optional[Dict[str, int]] = None
        self._transaction_closed_cache: Dict[int, Tuple[Optional[bool], float]] = {}
        self._transaction_state_cache: Dict[int, Tuple[Dict[str, Any], float]] = {}

    @property
    def enabled(self) -> bool:
        return self._enabled

    @property
    def config_error(self) -> Optional[str]:
        return self._config_error

    @property
    def menu_writable(self) -> bool:
        return self.enabled

    def create_incoming_order(
        self,
        *,
        order: Dict[str, Any],
        customer: Dict[str, Any],
        address_lat: Optional[float],
        address_lng: Optional[float],
    ) -> str:
        if not self.enabled:
            raise PosterSyncError('Poster order sync is disabled.')

        phone = str(customer.get('phone') or '').strip()
        if not phone:
            raise PosterSyncError('Customer phone is empty.')

        spot_id = self._resolve_spot_id()
        products = self._build_products(order)
        first_name, last_name = _split_name(str(customer.get('full_name') or '').strip())

        payload: Dict[str, Any] = {
            'spot_id': spot_id,
            'phone': phone,
            'products': products,
            'service_mode': 3 if str(order.get('delivery_type')) == 'delivery' else 2,
        }
        if first_name:
            payload['first_name'] = first_name
        if last_name:
            payload['last_name'] = last_name
        if self._skip_phone_validation:
            payload['skip_phone_validation'] = True

        order_notes = str(order.get('notes') or '').strip()
        comment_parts = [f'App order #{order.get("id")}']
        if order_notes:
            comment_parts.append(order_notes)
        payload['comment'] = ' | '.join(comment_parts)

        address = str(order.get('address') or '').strip()
        if payload['service_mode'] == 3 and address:
            client_address: Dict[str, Any] = {'address1': address}
            if address_lat is not None:
                client_address['lat'] = address_lat
            if address_lng is not None:
                client_address['lng'] = address_lng
            payload['client_address'] = client_address

        body = self._request(
            method='POST',
            path='/api/incomingOrders.createIncomingOrder',
            payload=payload,
        )
        response = body.get('response') if isinstance(body, dict) else None
        if not isinstance(response, dict):
            raise PosterSyncError(f'Unexpected Poster response: {body}')
        incoming_order_id = response.get('incoming_order_id')
        if incoming_order_id in (None, ''):
            raise PosterSyncError(f'Poster did not return incoming_order_id: {body}')
        return str(incoming_order_id)

    def get_incoming_order_state(self, *, incoming_order_id: Any) -> Dict[str, Any]:
        if not self.enabled:
            raise PosterSyncError('Poster order sync is disabled.')
        order_id = _to_int(incoming_order_id)
        if order_id is None or order_id <= 0:
            raise PosterSyncError(f'Invalid incoming_order_id: {incoming_order_id}')

        body = self._request(
            method='GET',
            path='/api/incomingOrders.getIncomingOrder',
            query={'incoming_order_id': order_id},
        )
        response = body.get('response') if isinstance(body, dict) else None
        if not isinstance(response, dict):
            raise PosterSyncError(f'Unexpected Poster response: {body}')
        poster_status = _to_int(response.get('status'))
        return {
            'poster_status': poster_status,
            'transaction_id': _to_int(response.get('transaction_id')),
            'app_status': _map_poster_status_to_app_status(poster_status),
            'updated_at': response.get('updated_at'),
        }

    def is_transaction_closed(
        self,
        *,
        transaction_id: Any,
        created_at: Optional[str] = None,
    ) -> Optional[bool]:
        if not self.enabled:
            raise PosterSyncError('Poster order sync is disabled.')
        tx_id = _to_int(transaction_id)
        if tx_id is None or tx_id <= 0:
            return None

        state = self.get_transaction_state(
            transaction_id=tx_id,
            created_at=created_at,
        )
        cached_closed = state.get('closed')
        if isinstance(cached_closed, bool):
            return cached_closed

        cache_row = self._transaction_closed_cache.get(tx_id)
        now_ts = datetime.utcnow().timestamp()
        if cache_row is not None:
            cached_value, cached_at = cache_row
            if now_ts - cached_at <= 60:
                return cached_value

        start_date, end_date = _transaction_lookup_window(created_at)
        rows = self._get_transactions_between(start_date=start_date, end_date=end_date)
        for row in rows:
            if not isinstance(row, dict):
                continue
            row_tx_id = _to_int(row.get('transaction_id'))
            if row_tx_id != tx_id:
                continue
            date_close = str(row.get('date_close') or '').strip()
            closed = bool(date_close and date_close != '0000-00-00 00:00:00')
            self._transaction_closed_cache[tx_id] = (closed, now_ts)
            return closed

        self._transaction_closed_cache[tx_id] = (None, now_ts)
        return None

    def get_transaction_state(
        self,
        *,
        transaction_id: Any,
        created_at: Optional[str] = None,
    ) -> Dict[str, Any]:
        if not self.enabled:
            raise PosterSyncError('Poster order sync is disabled.')
        tx_id = _to_int(transaction_id)
        if tx_id is None or tx_id <= 0:
            return {
                'transaction_id': None,
                'transaction_status': None,
                'processing_status': None,
                'closed': None,
                'app_status': None,
            }

        now_ts = datetime.utcnow().timestamp()
        cached = self._transaction_state_cache.get(tx_id)
        if cached is not None:
            state, cached_at = cached
            if now_ts - cached_at <= 45:
                return state

        start_date, end_date = _transaction_lookup_window(created_at)
        row = self._find_dash_transaction(
            transaction_id=tx_id,
            start_date=start_date,
            end_date=end_date,
        )
        if row is None:
            state = {
                'transaction_id': tx_id,
                'transaction_status': None,
                'processing_status': None,
                'closed': None,
                'app_status': None,
            }
            self._transaction_state_cache[tx_id] = (state, now_ts)
            return state

        tx_status = _to_int(row.get('status'))
        processing_status = _to_int(row.get('processing_status'))
        closed = _dash_transaction_closed(row)
        app_status = _map_dash_transaction_to_app_status(
            transaction_status=tx_status,
            processing_status=processing_status,
            closed=closed,
        )
        state = {
            'transaction_id': tx_id,
            'transaction_status': tx_status,
            'processing_status': processing_status,
            'closed': closed,
            'app_status': app_status,
        }
        self._transaction_state_cache[tx_id] = (state, now_ts)
        return state

    def get_menu_catalog(self) -> Dict[str, List[Dict[str, Any]]]:
        if not self.enabled:
            raise PosterSyncError('Poster order sync is disabled.')
        media_base_url = _effective_base_url(self._base_url, self._account).rstrip('/')
        categories_rows = self.list_menu_categories_raw()
        products_rows = self.list_menu_products_raw()
        if not products_rows:
            return {'categories': []}

        categories_by_id: Dict[int, Dict[str, Any]] = {}
        for row in categories_rows:
            if not isinstance(row, dict):
                continue
            raw_id = _to_int(
                row.get('category_id')
                if row.get('category_id') is not None
                else row.get('id'),
            )
            name = str(row.get('category_name') or row.get('name') or '').strip()
            if raw_id is None or not name:
                continue
            categories_by_id[raw_id] = {
                'id': raw_id,
                'name': name,
                'description': None,
                'parent_category': _to_int(row.get('parent_category')) or 0,
                'sort_order': _to_int(row.get('sort_order')) or 0,
                'is_active': str(row.get('category_hidden') or '0') != '1',
                'image_url': _to_absolute_media_url(
                media_base_url,
                str(row.get('category_photo_origin') or row.get('category_photo') or '').strip(),
                ),
                'products': [],
            }

        for row in products_rows:
            if not isinstance(row, dict):
                continue
            product_id = _to_int(
                row.get('product_id') if row.get('product_id') is not None else row.get('id'),
            )
            if product_id is None or product_id <= 0:
                continue
            title = str(row.get('product_name') or row.get('name') or '').strip()
            if not title:
                continue
            raw_cat_id = _to_int(row.get('menu_category_id') or row.get('category_id'))
            cat_name = str(row.get('category_name') or row.get('category') or '').strip()
            category_id = raw_cat_id if raw_cat_id is not None else 0
            if category_id not in categories_by_id:
                categories_by_id[category_id] = {
                    'id': category_id,
                    'name': cat_name or 'Без категории',
                    'description': None,
                    'parent_category': 0,
                    'sort_order': 0,
                    'is_active': True,
                    'image_url': '',
                    'products': [],
                }
            price = _poster_price(
                row,
                ('price', 'price1', 'cost', 'spots_price'),
            )
            if price is None:
                price = 0.0
            image_url = _to_absolute_media_url(
                media_base_url,
                str(
                row.get('photo_origin')
                or row.get('photo')
                or row.get('image')
                or row.get('image_url')
                or '',
                ).strip(),
            )
            category = categories_by_id[category_id]
            if not image_url:
                image_url = str(category.get('image_url') or '')
            category['products'].append(
                {
                    'id': product_id,
                    'name': title,
                    'description': str(
                        row.get('product_production_description')
                        or row.get('product_description')
                        or row.get('description')
                        or '',
                    ).strip() or None,
                    'price': price,
                    'image_url': image_url or None,
                    'modifiers': [],
                    'sort_order': _to_int(row.get('sort_order')) or 0,
                    'is_active': str(row.get('hidden') or '0') != '1',
                    'type': _to_int(row.get('type')),
                    'raw': row,
                },
            )

        categories: List[Dict[str, Any]] = []
        ordered_categories = sorted(
            categories_by_id.values(),
            key=lambda item: (int(item.get('sort_order') or 0), int(item.get('id') or 0)),
        )
        for category in ordered_categories:
            products = list(category.get('products') or [])
            products.sort(key=lambda item: (int(item.get('sort_order') or 0), int(item.get('id') or 0)))
            categories.append(
                {
                    'id': int(category.get('id') or 0),
                    'name': str(category.get('name') or ''),
                    'description': category.get('description'),
                    'sort_order': int(category.get('sort_order') or 0),
                    'is_active': bool(category.get('is_active', True)),
                    'parent_category': int(category.get('parent_category') or 0),
                    'products': products,
                },
            )
        return {'categories': categories}

    def list_menu_categories_raw(self) -> List[Dict[str, Any]]:
        body = self._request(
            method='GET',
            path='/api/menu.getCategories',
            query={'type': 'products'},
        )
        return [row for row in _unwrap_poster_collection(body) if isinstance(row, dict)]

    def list_menu_products_raw(self) -> List[Dict[str, Any]]:
        body = self._request(method='GET', path='/api/menu.getProducts')
        return [row for row in _unwrap_poster_collection(body) if isinstance(row, dict)]

    def get_menu_category(self, *, category_id: int) -> Optional[Dict[str, Any]]:
        for row in self.list_menu_categories_raw():
            cid = _to_int(row.get('category_id') if row.get('category_id') is not None else row.get('id'))
            if cid == int(category_id):
                return row
        return None

    def create_menu_category(
        self,
        *,
        name: str,
        parent_category: int = 0,
        is_active: bool = True,
    ) -> Dict[str, Any]:
        if not self.menu_writable:
            raise PosterSyncError('Poster menu write is disabled.')
        payload = {
            'category_name': str(name).strip(),
            'parent_category': int(parent_category),
            'type': 'products',
            'category_hidden': '0' if is_active else '1',
        }
        body = self._request(
            method='POST',
            path='/api/menu.createCategory',
            payload=payload,
        )
        category_id = _response_int(body)
        if category_id is None:
            raise PosterSyncError(f'Poster did not return category id: {body}')
        row = self._wait_menu_category(
            category_id=category_id,
            expected_name=str(name).strip(),
            expected_parent=int(parent_category),
            expected_active=bool(is_active),
            expected_sort_order=None,
        )
        if row is None:
            raise PosterSyncError(f'Created category {category_id} not found in Poster menu.getCategories.')
        return row

    def update_menu_category(
        self,
        *,
        category_id: int,
        name: Optional[str] = None,
        parent_category: Optional[int] = None,
        is_active: Optional[bool] = None,
        sort_order: Optional[int] = None,
    ) -> Dict[str, Any]:
        if not self.menu_writable:
            raise PosterSyncError('Poster menu write is disabled.')
        current = self.get_menu_category(category_id=category_id)
        if current is None:
            raise PosterSyncError(f'Poster category {category_id} not found.')
        payload = {
            'category_id': int(category_id),
            'category_name': str(name).strip() if name is not None else str(current.get('category_name') or '').strip(),
            'parent_category': int(parent_category) if parent_category is not None else (_to_int(current.get('parent_category')) or 0),
            'type': 'products',
            'category_hidden': '0'
            if (is_active if is_active is not None else (str(current.get('category_hidden') or '0') != '1'))
            else '1',
        }
        if sort_order is not None:
            payload['sort_order'] = int(sort_order)
        self._request(
            method='POST',
            path='/api/menu.updateCategory',
            payload=payload,
        )
        expected_name = str(name).strip() if name is not None else None
        expected_parent = int(parent_category) if parent_category is not None else None
        expected_active = bool(is_active) if is_active is not None else None
        expected_sort_order = int(sort_order) if sort_order is not None else None
        updated = self._wait_menu_category(
            category_id=category_id,
            expected_name=expected_name,
            expected_parent=expected_parent,
            expected_active=expected_active,
            expected_sort_order=expected_sort_order,
        )
        if updated is None:
            raise PosterSyncError(f'Updated category {category_id} not found in Poster menu.getCategories.')
        return updated

    def delete_menu_category(self, *, category_id: int) -> None:
        if not self.menu_writable:
            raise PosterSyncError('Poster menu write is disabled.')
        self._request(
            method='POST',
            path='/api/menu.removeCategory',
            payload={'category_id': int(category_id)},
        )

    def reorder_menu_categories(self, *, ids: List[int]) -> None:
        if not self.menu_writable:
            raise PosterSyncError('Poster menu write is disabled.')
        categories = self.list_menu_categories_raw()
        by_id = {
            int(_to_int(row.get('category_id') if row.get('category_id') is not None else row.get('id')) or 0): row
            for row in categories
            if _to_int(row.get('category_id') if row.get('category_id') is not None else row.get('id')) is not None
        }
        for index, category_id in enumerate(ids):
            row = by_id.get(int(category_id))
            if row is None:
                continue
            self._request(
                method='POST',
                path='/api/menu.updateCategory',
                payload={
                    'category_id': int(category_id),
                    'category_name': str(row.get('category_name') or '').strip(),
                    'parent_category': _to_int(row.get('parent_category')) or 0,
                    'type': 'products',
                    'category_hidden': str(row.get('category_hidden') or '0'),
                    'sort_order': index,
                },
            )

    def get_menu_product(self, *, product_id: int) -> Optional[Dict[str, Any]]:
        body = self._request(
            method='GET',
            path='/api/menu.getProduct',
            query={'product_id': int(product_id)},
        )
        row = body.get('response') if isinstance(body, dict) else None
        if not isinstance(row, dict):
            return None
        return row

    def create_menu_product(
        self,
        *,
        title: str,
        category_id: int,
        price: float,
        description: Optional[str] = None,
        is_active: bool = True,
        is_drink: bool = False,
        image_url: Optional[str] = None,
    ) -> Dict[str, Any]:
        if not self.menu_writable:
            raise PosterSyncError('Poster menu write is disabled.')
        payload = {
            'visible': 1 if is_active else 0,
            'weight_flag': 0,
            'workshop': 0,
            'menu_category_id': int(category_id),
            'product_name': str(title).strip(),
            'price': _to_poster_price(price),
            'type': 2 if is_drink else 3,
        }
        if description is not None:
            payload['product_production_description'] = str(description)
        if image_url is not None:
            payload['photo'] = str(image_url).strip()
        body = self._request(
            method='POST',
            path='/api/menu.createDish',
            payload=payload,
        )
        product_id = _response_int(body)
        if product_id is None:
            raise PosterSyncError(f'Poster did not return product id: {body}')
        row = self._wait_menu_product(
            product_id=product_id,
            expected_title=str(title).strip(),
            expected_category_id=int(category_id),
            expected_price=float(price),
            expected_active=bool(is_active),
            expected_type=2 if is_drink else 3,
        )
        if row is None:
            raise PosterSyncError(f'Created product {product_id} not found in Poster menu.getProduct.')
        return row

    def update_menu_product(
        self,
        *,
        product_id: int,
        title: Optional[str] = None,
        category_id: Optional[int] = None,
        price: Optional[float] = None,
        description: Optional[str] = None,
        is_active: Optional[bool] = None,
        is_drink: Optional[bool] = None,
        image_url: Optional[str] = None,
    ) -> Dict[str, Any]:
        if not self.menu_writable:
            raise PosterSyncError('Poster menu write is disabled.')
        current = self.get_menu_product(product_id=product_id)
        if current is None:
            raise PosterSyncError(f'Poster product {product_id} not found.')
        effective_price = price
        if effective_price is None:
            current_price = _poster_price(current, ('price', 'price1', 'cost', 'spots_price'))
            effective_price = float(current_price or 0)
        hidden = str(current.get('hidden') or '0') == '1'
        effective_active = (not hidden) if is_active is None else bool(is_active)
        effective_type = _to_int(current.get('type')) or 3
        if is_drink is not None:
            effective_type = 2 if is_drink else 3

        payload = {
            'dish_id': int(product_id),
            'visible': 1 if effective_active else 0,
            'weight_flag': _to_int(current.get('weight_flag')) or 0,
            'workshop': _to_int(current.get('workshop')) or 0,
            'menu_category_id': int(category_id)
            if category_id is not None
            else (_to_int(current.get('menu_category_id')) or 0),
            'product_name': str(title).strip() if title is not None else str(current.get('product_name') or '').strip(),
            'price': _to_poster_price(float(effective_price)),
            'type': effective_type,
        }
        if description is not None:
            payload['product_production_description'] = str(description)
        if image_url is not None:
            payload['photo'] = str(image_url).strip()

        self._request(
            method='POST',
            path='/api/menu.updateDish',
            payload=payload,
        )
        expected_title = str(title).strip() if title is not None else None
        expected_category_id = int(category_id) if category_id is not None else None
        expected_price = float(price) if price is not None else None
        expected_active = bool(is_active) if is_active is not None else None
        expected_type = 2 if bool(is_drink) else 3 if is_drink is not None else None
        updated = self._wait_menu_product(
            product_id=product_id,
            expected_title=expected_title,
            expected_category_id=expected_category_id,
            expected_price=expected_price,
            expected_active=expected_active,
            expected_type=expected_type,
        )
        if updated is None:
            raise PosterSyncError(f'Updated product {product_id} not found in Poster menu.getProduct.')
        return updated

    def delete_menu_product(self, *, product_id: int) -> None:
        if not self.menu_writable:
            raise PosterSyncError('Poster menu write is disabled.')
        self._request(
            method='POST',
            path='/api/menu.removeDish',
            payload={'dish_id': int(product_id)},
        )

    def reorder_menu_products(self, *, ids: List[int]) -> None:
        if not self.menu_writable:
            raise PosterSyncError('Poster menu write is disabled.')
        for index, product_id in enumerate(ids):
            current = self.get_menu_product(product_id=int(product_id))
            if current is None:
                continue
            self._request(
                method='POST',
                path='/api/menu.updateDish',
                payload={
                    'dish_id': int(product_id),
                    'visible': 0 if str(current.get('hidden') or '0') == '1' else 1,
                    'weight_flag': _to_int(current.get('weight_flag')) or 0,
                    'workshop': _to_int(current.get('workshop')) or 0,
                    'menu_category_id': _to_int(current.get('menu_category_id')) or 0,
                    'product_name': str(current.get('product_name') or '').strip(),
                    'price': _to_poster_price(float(_poster_price(current, ('price', 'price1', 'cost', 'spots_price')) or 0)),
                    'sort_order': int(index),
                    'type': _to_int(current.get('type')) or 3,
                },
            )

    def _wait_menu_category(
        self,
        *,
        category_id: int,
        expected_name: Optional[str],
        expected_parent: Optional[int],
        expected_active: Optional[bool],
        expected_sort_order: Optional[int],
        attempts: int = 8,
        delay_seconds: float = 0.35,
    ) -> Optional[Dict[str, Any]]:
        last_row: Optional[Dict[str, Any]] = None
        for _ in range(max(1, attempts)):
            row = self.get_menu_category(category_id=category_id)
            if row is not None:
                last_row = row
                if self._category_matches(
                    row,
                    expected_name=expected_name,
                    expected_parent=expected_parent,
                    expected_active=expected_active,
                    expected_sort_order=expected_sort_order,
                ):
                    return row
            time.sleep(max(0.0, delay_seconds))
        return last_row

    def _wait_menu_product(
        self,
        *,
        product_id: int,
        expected_title: Optional[str],
        expected_category_id: Optional[int],
        expected_price: Optional[float],
        expected_active: Optional[bool],
        expected_type: Optional[int],
        attempts: int = 8,
        delay_seconds: float = 0.35,
    ) -> Optional[Dict[str, Any]]:
        last_row: Optional[Dict[str, Any]] = None
        for _ in range(max(1, attempts)):
            row = self.get_menu_product(product_id=product_id)
            if row is not None:
                last_row = row
                if self._product_matches(
                    row,
                    expected_title=expected_title,
                    expected_category_id=expected_category_id,
                    expected_price=expected_price,
                    expected_active=expected_active,
                    expected_type=expected_type,
                ):
                    return row
            time.sleep(max(0.0, delay_seconds))
        return last_row

    def _category_matches(
        self,
        row: Dict[str, Any],
        *,
        expected_name: Optional[str],
        expected_parent: Optional[int],
        expected_active: Optional[bool],
        expected_sort_order: Optional[int],
    ) -> bool:
        if expected_name is not None:
            current_name = str(row.get('category_name') or row.get('name') or '').strip()
            if current_name != expected_name:
                return False
        if expected_parent is not None:
            current_parent = _to_int(row.get('parent_category')) or 0
            if int(current_parent) != int(expected_parent):
                return False
        if expected_active is not None:
            hidden = str(row.get('category_hidden') or '0') == '1'
            current_active = not hidden
            if current_active != bool(expected_active):
                return False
        if expected_sort_order is not None:
            current_sort = _to_int(row.get('sort_order')) or 0
            if int(current_sort) != int(expected_sort_order):
                return False
        return True

    def _product_matches(
        self,
        row: Dict[str, Any],
        *,
        expected_title: Optional[str],
        expected_category_id: Optional[int],
        expected_price: Optional[float],
        expected_active: Optional[bool],
        expected_type: Optional[int],
    ) -> bool:
        if expected_title is not None:
            current_title = str(row.get('product_name') or row.get('title') or '').strip()
            if current_title != expected_title:
                return False
        if expected_category_id is not None:
            current_category_id = _to_int(row.get('menu_category_id')) or 0
            if int(current_category_id) != int(expected_category_id):
                return False
        if expected_price is not None:
            current_price = _poster_price(row, ('price', 'price1', 'cost', 'spots_price')) or 0.0
            if abs(float(current_price) - float(expected_price)) > 0.01:
                return False
        if expected_active is not None:
            hidden = str(row.get('hidden') or '0') == '1'
            current_active = not hidden
            if current_active != bool(expected_active):
                return False
        if expected_type is not None:
            current_type = _to_int(row.get('type')) or 0
            if int(current_type) != int(expected_type):
                return False
        return True

    def _build_products(self, order: Dict[str, Any]) -> List[Dict[str, Any]]:
        items = order.get('items')
        if not isinstance(items, list) or not items:
            raise PosterSyncError('Order has no items.')
        available_ids, names = self._load_product_mapping()
        products: List[Dict[str, Any]] = []
        for item in items:
            if not isinstance(item, dict):
                continue
            qty = _to_float(item.get('qty'))
            if qty <= 0:
                continue
            product_id = self._resolve_product_id(
                item=item,
                available_ids=available_ids,
                names=names,
            )
            if product_id is None:
                title = str(item.get('title') or '').strip()
                raise PosterSyncError(
                    f'Could not map product to Poster id: "{title or item.get("product_id")}"',
                )
            products.append({'product_id': product_id, 'count': qty})
        if not products:
            raise PosterSyncError('No valid products to send.')
        return products

    def _resolve_product_id(
        self,
        *,
        item: Dict[str, Any],
        available_ids: Set[int],
        names: Dict[str, int],
    ) -> Optional[int]:
        product_id = _to_int(item.get('product_id'))
        if product_id is not None and product_id in available_ids:
            return product_id
        title = str(item.get('title') or '').strip()
        normalized_title = _normalize_name(title)
        if normalized_title and normalized_title in names:
            return names[normalized_title]
        return None

    def _load_product_mapping(self) -> Tuple[Set[int], Dict[str, int]]:
        if self._product_ids_cache is not None and self._product_name_to_id_cache is not None:
            return self._product_ids_cache, self._product_name_to_id_cache

        body = self._request(method='GET', path='/api/menu.getProducts')
        rows = _unwrap_poster_collection(body)
        ids: Set[int] = set()
        names: Dict[str, int] = {}
        for row in rows:
            if not isinstance(row, dict):
                continue
            raw_id = row.get('product_id') if row.get('product_id') is not None else row.get('id')
            pid = _to_int(raw_id)
            if pid is None:
                continue
            ids.add(pid)
            title = str(row.get('product_name') or row.get('name') or '').strip()
            normalized = _normalize_name(title)
            if normalized and normalized not in names:
                names[normalized] = pid

        if not ids:
            raise PosterSyncError('Poster menu.getProducts returned no products.')

        self._product_ids_cache = ids
        self._product_name_to_id_cache = names
        return ids, names

    def _resolve_spot_id(self) -> int:
        if self._spot_id_cache is not None:
            return self._spot_id_cache

        body = self._request(method='GET', path='/api/spots.getSpots')
        rows = _unwrap_poster_collection(body)
        for row in rows:
            if not isinstance(row, dict):
                continue
            spot_id = _to_int(row.get('spot_id') if row.get('spot_id') is not None else row.get('id'))
            if spot_id is not None and spot_id > 0:
                self._spot_id_cache = spot_id
                return spot_id
        raise PosterSyncError(
            'Could not resolve spot_id. Set POSTER_ORDER_SPOT_ID explicitly.',
        )

    def _find_dash_transaction(
        self,
        *,
        transaction_id: int,
        start_date: str,
        end_date: str,
    ) -> Optional[Dict[str, Any]]:
        query: Dict[str, Any] = {
            'date_from': start_date,
            'date_to': end_date,
            'per_page': 500,
            'page': 1,
        }
        try:
            spot_id = self._resolve_spot_id()
        except PosterSyncError:
            spot_id = None
        if isinstance(spot_id, int) and spot_id > 0:
            query['spot_id'] = spot_id

        body = self._request(
            method='GET',
            path='/api/dash.getTransactions',
            query=query,
        )
        response = body.get('response') if isinstance(body, dict) else None
        rows: List[Any]
        if isinstance(response, list):
            rows = response
        elif isinstance(response, dict):
            data = response.get('data')
            rows = data if isinstance(data, list) else []
        else:
            rows = []
        for row in rows:
            if not isinstance(row, dict):
                continue
            row_tx_id = _to_int(row.get('transaction_id'))
            if row_tx_id == transaction_id:
                return row
        return None

    def _request(
        self,
        *,
        method: str,
        path: str,
        payload: Optional[Dict[str, Any]] = None,
        query: Optional[Dict[str, Any]] = None,
    ) -> Dict[str, Any]:
        base_url = _effective_base_url(self._base_url, self._account)
        params: Dict[str, Any] = {'token': self._token, 'format': 'json'}
        if self._account:
            params['account_name'] = self._account
        if query:
            params.update(query)
        try:
            with httpx.Client(base_url=base_url, timeout=self._timeout) as client:
                if method == 'POST':
                    response = client.post(path, params=params, json=payload or {})
                else:
                    response = client.get(path, params=params)
        except httpx.HTTPError as exc:
            raise PosterSyncError(f'Poster request failed: {exc}') from exc

        if response.status_code >= 400:
            raise PosterSyncError(
                f'Poster HTTP {response.status_code}: {response.text[:300]}',
            )

        try:
            body = response.json()
        except ValueError as exc:
            raise PosterSyncError(f'Poster returned non-JSON response: {response.text[:300]}') from exc

        if isinstance(body, dict) and isinstance(body.get('error'), dict):
            error = body['error']
            code = error.get('code')
            message = error.get('message')
            raise PosterSyncError(f'Poster API error {code}: {message}')

        if not isinstance(body, dict):
            raise PosterSyncError(f'Poster returned invalid body: {body}')
        return body

    def _get_transactions_between(
        self,
        *,
        start_date: str,
        end_date: str,
    ) -> List[Dict[str, Any]]:
        page = 1
        out: List[Dict[str, Any]] = []
        while True:
            body = self._request(
                method='GET',
                path='/api/transactions.getTransactions',
                query={
                    'date_from': start_date,
                    'date_to': end_date,
                    'per_page': 100,
                    'page': page,
                },
            )
            response = body.get('response')
            if not isinstance(response, dict):
                break
            data = response.get('data')
            if not isinstance(data, list):
                break
            out.extend([row for row in data if isinstance(row, dict)])
            page_info = response.get('page')
            if not isinstance(page_info, dict):
                break
            page_count = _to_int(page_info.get('count')) or 1
            if page >= page_count:
                break
            page += 1
        return out


def _normalize_name(value: str) -> str:
    text = value.strip().lower()
    text = re.sub(r'\s+', ' ', text)
    return text


def _split_name(full_name: str) -> Tuple[str, str]:
    parts = [chunk for chunk in full_name.split(' ') if chunk]
    if not parts:
        return '', ''
    if len(parts) == 1:
        return parts[0], ''
    return parts[0], ' '.join(parts[1:])


def _to_bool(value: Optional[str], *, default: bool) -> bool:
    if value is None:
        return default
    normalized = value.strip().lower()
    if normalized in {'1', 'true', 'yes', 'on'}:
        return True
    if normalized in {'0', 'false', 'no', 'off'}:
        return False
    return default


def _to_int(value: Any) -> Optional[int]:
    if value is None:
        return None
    try:
        return int(str(value).strip())
    except (TypeError, ValueError):
        return None


def _response_int(body: Dict[str, Any]) -> Optional[int]:
    if not isinstance(body, dict):
        return None
    if 'response' in body:
        return _to_int(body.get('response'))
    return None


def _to_float(value: Any) -> float:
    if value is None:
        return 0.0
    try:
        return float(str(value).strip())
    except (TypeError, ValueError):
        return 0.0


def _to_poster_price(value: float) -> str:
    # Poster menu API commonly expects monetary values in minor units.
    normalized = max(0.0, float(value))
    return str(int(round(normalized * 100)))


def _effective_base_url(base_url: str, account: str) -> str:
    base = base_url.strip().rstrip('/')
    if base != 'https://joinposter.com':
        return base
    if not account:
        return base
    return f'https://{account}.joinposter.com'


def _unwrap_poster_collection(body: Dict[str, Any]) -> List[Any]:
    response = body.get('response')
    if isinstance(response, list):
        return response
    if isinstance(response, dict):
        data = response.get('data')
        if isinstance(data, list):
            return data
    data = body.get('data')
    if isinstance(data, list):
        return data
    result = body.get('result')
    if isinstance(result, list):
        return result
    if isinstance(result, dict):
        data = result.get('data')
        if isinstance(data, list):
            return data
    return []


def _map_poster_status_to_app_status(poster_status: Optional[int]) -> str:
    # Poster incoming order status is numeric. Map it to app timeline statuses.
    if poster_status is None:
        return 'pending'
    if poster_status == 7:
        return 'delivered'
    if poster_status in {8, 9, 10}:
        return 'cancelled'
    if poster_status in {2, 3, 4, 5, 6}:
        return 'on_the_way'
    if poster_status == 1:
        return 'preparing'
    if poster_status == 0:
        return 'pending'
    return 'pending'


def _dash_transaction_closed(row: Dict[str, Any]) -> Optional[bool]:
    date_close = str(row.get('date_close') or '').strip()
    if date_close and date_close not in {'0', '0000-00-00 00:00:00'}:
        return True
    tx_status = _to_int(row.get('status'))
    if tx_status == 2:
        return True
    if tx_status in {0, 1, 3, 4, 5, 6, 7, 8, 9, 10}:
        return False
    return None


def _map_dash_transaction_to_app_status(
    *,
    transaction_status: Optional[int],
    processing_status: Optional[int],
    closed: Optional[bool],
) -> Optional[str]:
    if closed is True:
        return 'delivered'

    if processing_status is not None:
        if processing_status >= 60:
            return 'delivered'
        if processing_status >= 40:
            return 'on_the_way'
        if processing_status >= 30:
            return 'preparing'
        if processing_status >= 10:
            return 'accepted'
        if processing_status >= 0:
            return 'pending'

    if transaction_status is not None:
        if transaction_status == 2:
            return 'delivered'
        if transaction_status in {8, 9, 10}:
            return 'cancelled'
        if transaction_status == 1:
            return 'preparing'
        if transaction_status == 0:
            return 'pending'

    return None


def _poster_price(row: Dict[str, Any], keys: Tuple[str, ...]) -> Optional[float]:
    for key in keys:
        parsed = _extract_price_value(row.get(key))
        if parsed is not None:
            return _normalize_price(parsed)
    spots = row.get('spots')
    if isinstance(spots, list):
        for item in spots:
            if not isinstance(item, dict):
                continue
            parsed = _extract_price_value(item.get('price'))
            if parsed is not None:
                return _normalize_price(parsed)
    return None


def _extract_price_value(raw: Any) -> Optional[float]:
    if raw is None:
        return None
    if isinstance(raw, (int, float)):
        return float(raw)
    if isinstance(raw, str):
        text = raw.strip().replace(',', '.')
        if not text:
            return None
        try:
            return float(text)
        except ValueError:
            cleaned = re.sub(r'[^0-9.\-]', '', text)
            if not cleaned:
                return None
            try:
                return float(cleaned)
            except ValueError:
                return None
    if isinstance(raw, dict):
        for value in raw.values():
            parsed = _extract_price_value(value)
            if parsed is not None:
                return parsed
        return None
    if isinstance(raw, list):
        for value in raw:
            parsed = _extract_price_value(value)
            if parsed is not None:
                return parsed
        return None
    return None


def _normalize_price(value: float) -> float:
    if value >= 100000 and value % 100 == 0:
        return value / 100
    return value


def _to_absolute_media_url(base_url: str, raw_path: str) -> str:
    path = raw_path.strip()
    if not path:
        return ''
    if path.startswith('http://') or path.startswith('https://'):
        return path
    if path.startswith('/'):
        return f'{base_url}{path}'
    return f'{base_url}/{path}'


def _transaction_lookup_window(created_at: Optional[str]) -> Tuple[str, str]:
    start = None
    if created_at:
        parsed = _parse_datetime(created_at)
        if parsed is not None:
            start = parsed - timedelta(days=1)
    if start is None:
        start = datetime.utcnow() - timedelta(days=30)
    end = datetime.utcnow() + timedelta(days=1)
    return (start.strftime('%Y-%m-%d'), end.strftime('%Y-%m-%d'))


def _parse_datetime(value: str) -> Optional[datetime]:
    text = value.strip()
    if not text:
        return None
    for fmt in ('%Y-%m-%d %H:%M:%S', '%Y-%m-%dT%H:%M:%S'):
        try:
            return datetime.strptime(text, fmt)
        except ValueError:
            continue
    try:
        return datetime.fromisoformat(text)
    except ValueError:
        return None
