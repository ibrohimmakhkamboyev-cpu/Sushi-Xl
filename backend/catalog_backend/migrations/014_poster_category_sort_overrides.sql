CREATE TABLE IF NOT EXISTS poster_category_sort_overrides (
    category_id INTEGER PRIMARY KEY,
    sort_order INTEGER NOT NULL DEFAULT 0,
    updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);
