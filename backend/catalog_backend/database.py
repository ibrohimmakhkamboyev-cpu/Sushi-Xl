from __future__ import annotations

import os
import sqlite3
from contextlib import contextmanager
from pathlib import Path
from typing import Iterator

ROOT = Path(__file__).resolve().parent
DEFAULT_DB = ROOT / 'data' / 'catalog.sqlite3'


def _resolve_database_path() -> Path:
    raw = os.getenv('DATABASE_PATH', str(DEFAULT_DB)).strip()
    candidate = Path(raw)
    if candidate.is_absolute():
        return candidate.resolve()
    # Keep relative paths stable regardless of where backend is launched from.
    # Legacy value "./catalog_backend/data/catalog.sqlite3" should map to
    # "<repo>/backend/catalog_backend/data/catalog.sqlite3".
    if candidate.parts and candidate.parts[0] == 'catalog_backend':
        return (ROOT.parent / candidate).resolve()
    return (ROOT / candidate).resolve()


DATABASE_PATH = _resolve_database_path()
MIGRATIONS_DIR = ROOT / 'migrations'


def ensure_parent_dir() -> None:
    DATABASE_PATH.parent.mkdir(parents=True, exist_ok=True)


@contextmanager
def get_conn() -> Iterator[sqlite3.Connection]:
    ensure_parent_dir()
    conn = sqlite3.connect(DATABASE_PATH)
    conn.row_factory = sqlite3.Row
    conn.execute('PRAGMA foreign_keys = ON')
    try:
        yield conn
        conn.commit()
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()


def apply_migrations() -> None:
    ensure_parent_dir()
    with get_conn() as conn:
        conn.execute(
            'CREATE TABLE IF NOT EXISTS schema_migrations ('
            'version TEXT PRIMARY KEY, '
            'applied_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP)'
        )
        applied = {
            row['version']
            for row in conn.execute('SELECT version FROM schema_migrations').fetchall()
        }
        for path in sorted(MIGRATIONS_DIR.glob('*.sql')):
            if path.name in applied:
                continue
            script = path.read_text(encoding='utf-8')
            _executescript_resilient(conn, script)
            conn.execute(
                'INSERT INTO schema_migrations(version) VALUES (?)',
                (path.name,),
            )


def _executescript_resilient(conn: sqlite3.Connection, script: str) -> None:
    try:
        conn.executescript(script)
        return
    except sqlite3.OperationalError as exc:
        if 'duplicate column name' not in str(exc).lower():
            raise

    statements = [stmt.strip() for stmt in script.split(';') if stmt.strip()]
    for statement in statements:
        try:
            conn.execute(statement)
        except sqlite3.OperationalError as exc:
            message = str(exc).lower()
            if 'duplicate column name' in message:
                continue
            raise
