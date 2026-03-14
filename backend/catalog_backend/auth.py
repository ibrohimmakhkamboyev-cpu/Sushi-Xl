from __future__ import annotations

import base64
import hashlib
import hmac
import logging
import os
import secrets
from datetime import datetime, timedelta, timezone
from typing import Any, Dict

import jwt
from fastapi import HTTPException, status

logger = logging.getLogger(__name__)

_WEAK_JWT_SECRETS = {'', 'change-me', 'changeme', 'default', 'admin123'}
_configured_secret = os.getenv('JWT_SECRET', '').strip()
if _configured_secret.lower() in _WEAK_JWT_SECRETS or _configured_secret.upper().startswith('__SET_'):
    _configured_secret = secrets.token_urlsafe(48)
    logger.warning(
        'JWT_SECRET is missing/weak. Using an ephemeral runtime secret. '
        'Set a strong JWT_SECRET in environment for stable sessions.',
    )
JWT_SECRET = _configured_secret
JWT_EXPIRES_MINUTES = int(os.getenv('JWT_EXPIRES_MINUTES', '480'))
JWT_ALGORITHM = 'HS256'


def hash_password(password: str) -> str:
    salt = secrets.token_hex(16)
    iterations = 120_000
    digest = hashlib.pbkdf2_hmac(
        'sha256',
        password.encode('utf-8'),
        salt.encode('utf-8'),
        iterations,
    )
    return 'pbkdf2_sha256${}${}${}'.format(
        iterations,
        salt,
        base64.b64encode(digest).decode('ascii'),
    )


def verify_password(password: str, stored_hash: str) -> bool:
    try:
        algo, iterations_raw, salt, encoded = stored_hash.split('$', 3)
        if algo != 'pbkdf2_sha256':
            return False
        iterations = int(iterations_raw)
    except ValueError:
        return False
    digest = hashlib.pbkdf2_hmac(
        'sha256',
        password.encode('utf-8'),
        salt.encode('utf-8'),
        iterations,
    )
    return hmac.compare_digest(
        base64.b64encode(digest).decode('ascii'),
        encoded,
    )


def create_access_token(*, admin_id: int, email: str) -> str:
    now = datetime.now(timezone.utc)
    payload = {
        'sub': str(admin_id),
        'email': email,
        'role': 'admin',
        'iat': int(now.timestamp()),
        'exp': int((now + timedelta(minutes=JWT_EXPIRES_MINUTES)).timestamp()),
    }
    return jwt.encode(payload, JWT_SECRET, algorithm=JWT_ALGORITHM)


def create_user_access_token(*, user_id: int, phone: str) -> str:
    now = datetime.now(timezone.utc)
    payload = {
        'sub': str(user_id),
        'phone': phone,
        'role': 'user',
        'iat': int(now.timestamp()),
        'exp': int((now + timedelta(minutes=JWT_EXPIRES_MINUTES)).timestamp()),
    }
    return jwt.encode(payload, JWT_SECRET, algorithm=JWT_ALGORITHM)


def decode_access_token(token: str, *, expected_role: str | None = None) -> Dict[str, Any]:
    try:
        payload = jwt.decode(token, JWT_SECRET, algorithms=[JWT_ALGORITHM])
    except jwt.PyJWTError as exc:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail='Invalid or expired access token.',
        ) from exc
    if expected_role and payload.get('role') != expected_role:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail='Invalid access token role.',
        )
    return payload
