ALTER TABLE admin_banners ADD COLUMN subtitle TEXT;
ALTER TABLE admin_banners ADD COLUMN subtitle_en TEXT;
ALTER TABLE admin_banners ADD COLUMN subtitle_ru TEXT;
ALTER TABLE admin_banners ADD COLUMN subtitle_uz TEXT;
ALTER TABLE admin_banners ADD COLUMN action_type TEXT NOT NULL DEFAULT 'none';
ALTER TABLE admin_banners ADD COLUMN product_id INTEGER;
ALTER TABLE admin_banners ADD COLUMN category_id INTEGER;
ALTER TABLE admin_banners ADD COLUMN linked_product_ids_json TEXT NOT NULL DEFAULT '[]';
ALTER TABLE admin_banners ADD COLUMN target_url TEXT;

UPDATE admin_banners
SET
  title_en = COALESCE(NULLIF(title_en, ''), title),
  title_ru = COALESCE(NULLIF(title_ru, ''), title),
  title_uz = COALESCE(NULLIF(title_uz, ''), title),
  linked_product_ids_json = CASE
    WHEN linked_product_ids_json IS NULL OR trim(linked_product_ids_json) = '' THEN COALESCE(product_ids_json, '[]')
    ELSE linked_product_ids_json
  END,
  action_type = CASE
    WHEN lower(trim(COALESCE(action_type, ''))) IN ('open_product', 'open_products', 'open_category', 'open_discounts', 'open_url', 'none') THEN lower(trim(action_type))
    WHEN COALESCE(product_ids_json, '[]') != '[]' THEN 'open_products'
    ELSE 'none'
  END;
