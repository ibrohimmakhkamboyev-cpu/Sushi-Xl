CREATE TABLE IF NOT EXISTS poster_product_localizations (
    product_id INTEGER PRIMARY KEY,
    title_en TEXT,
    title_ru TEXT,
    title_uz TEXT,
    description_en TEXT,
    description_ru TEXT,
    description_uz TEXT,
    updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS poster_category_localizations (
    category_id INTEGER PRIMARY KEY,
    name_en TEXT,
    name_ru TEXT,
    name_uz TEXT,
    description_en TEXT,
    description_ru TEXT,
    description_uz TEXT,
    updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);
