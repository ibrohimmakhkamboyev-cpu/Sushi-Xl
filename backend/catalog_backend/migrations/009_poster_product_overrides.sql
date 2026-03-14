CREATE TABLE IF NOT EXISTS poster_product_overrides (
    product_id INTEGER PRIMARY KEY,
    is_active INTEGER NOT NULL DEFAULT 1,
    updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

