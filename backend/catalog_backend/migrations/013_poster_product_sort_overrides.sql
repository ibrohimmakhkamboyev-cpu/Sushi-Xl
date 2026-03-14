CREATE TABLE IF NOT EXISTS poster_product_sort_overrides (
    product_id INTEGER PRIMARY KEY,
    category_id INTEGER NOT NULL DEFAULT 0,
    sort_order INTEGER NOT NULL DEFAULT 0,
    updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_poster_product_sort_overrides_category
ON poster_product_sort_overrides(category_id, sort_order, product_id);
