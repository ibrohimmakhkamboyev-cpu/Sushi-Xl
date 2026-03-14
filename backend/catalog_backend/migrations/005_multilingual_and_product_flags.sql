ALTER TABLE categories ADD COLUMN name_en TEXT;
ALTER TABLE categories ADD COLUMN name_ru TEXT;
ALTER TABLE categories ADD COLUMN name_uz TEXT;
ALTER TABLE categories ADD COLUMN description_en TEXT;
ALTER TABLE categories ADD COLUMN description_ru TEXT;
ALTER TABLE categories ADD COLUMN description_uz TEXT;

UPDATE categories
SET
  name_en = COALESCE(NULLIF(name_en, ''), name),
  name_ru = COALESCE(NULLIF(name_ru, ''), name),
  name_uz = COALESCE(NULLIF(name_uz, ''), name),
  description_en = COALESCE(description_en, description),
  description_ru = COALESCE(description_ru, description),
  description_uz = COALESCE(description_uz, description);

ALTER TABLE products ADD COLUMN title_en TEXT;
ALTER TABLE products ADD COLUMN title_ru TEXT;
ALTER TABLE products ADD COLUMN title_uz TEXT;
ALTER TABLE products ADD COLUMN description_en TEXT;
ALTER TABLE products ADD COLUMN description_ru TEXT;
ALTER TABLE products ADD COLUMN description_uz TEXT;
ALTER TABLE products ADD COLUMN sort_order INTEGER NOT NULL DEFAULT 0;
ALTER TABLE products ADD COLUMN is_recommended INTEGER NOT NULL DEFAULT 0;
ALTER TABLE products ADD COLUMN is_popular INTEGER NOT NULL DEFAULT 0;
ALTER TABLE products ADD COLUMN is_new INTEGER NOT NULL DEFAULT 0;

UPDATE products
SET
  title_en = COALESCE(NULLIF(title_en, ''), title),
  title_ru = COALESCE(NULLIF(title_ru, ''), title),
  title_uz = COALESCE(NULLIF(title_uz, ''), title),
  description_en = COALESCE(description_en, description),
  description_ru = COALESCE(description_ru, description),
  description_uz = COALESCE(description_uz, description),
  sort_order = CASE WHEN sort_order IS NULL OR sort_order = 0 THEN id ELSE sort_order END;

ALTER TABLE admin_banners ADD COLUMN title_en TEXT;
ALTER TABLE admin_banners ADD COLUMN title_ru TEXT;
ALTER TABLE admin_banners ADD COLUMN title_uz TEXT;

UPDATE admin_banners
SET
  title_en = COALESCE(NULLIF(title_en, ''), title),
  title_ru = COALESCE(NULLIF(title_ru, ''), title),
  title_uz = COALESCE(NULLIF(title_uz, ''), title);

ALTER TABLE admin_notifications ADD COLUMN title_en TEXT;
ALTER TABLE admin_notifications ADD COLUMN title_ru TEXT;
ALTER TABLE admin_notifications ADD COLUMN title_uz TEXT;
ALTER TABLE admin_notifications ADD COLUMN message_en TEXT;
ALTER TABLE admin_notifications ADD COLUMN message_ru TEXT;
ALTER TABLE admin_notifications ADD COLUMN message_uz TEXT;

UPDATE admin_notifications
SET
  title_en = COALESCE(NULLIF(title_en, ''), title),
  title_ru = COALESCE(NULLIF(title_ru, ''), title),
  title_uz = COALESCE(NULLIF(title_uz, ''), title),
  message_en = COALESCE(NULLIF(message_en, ''), message),
  message_ru = COALESCE(NULLIF(message_ru, ''), message),
  message_uz = COALESCE(NULLIF(message_uz, ''), message);

ALTER TABLE admin_faq ADD COLUMN question_en TEXT;
ALTER TABLE admin_faq ADD COLUMN question_ru TEXT;
ALTER TABLE admin_faq ADD COLUMN question_uz TEXT;
ALTER TABLE admin_faq ADD COLUMN answer_en TEXT;
ALTER TABLE admin_faq ADD COLUMN answer_ru TEXT;
ALTER TABLE admin_faq ADD COLUMN answer_uz TEXT;

UPDATE admin_faq
SET
  question_en = COALESCE(NULLIF(question_en, ''), question),
  question_ru = COALESCE(NULLIF(question_ru, ''), question),
  question_uz = COALESCE(NULLIF(question_uz, ''), question),
  answer_en = COALESCE(NULLIF(answer_en, ''), answer),
  answer_ru = COALESCE(NULLIF(answer_ru, ''), answer),
  answer_uz = COALESCE(NULLIF(answer_uz, ''), answer);
