ALTER TABLE admin_settings ADD COLUMN call_label_en TEXT;
ALTER TABLE admin_settings ADD COLUMN call_label_ru TEXT;
ALTER TABLE admin_settings ADD COLUMN call_label_uz TEXT;

ALTER TABLE admin_settings ADD COLUMN chat_label_en TEXT;
ALTER TABLE admin_settings ADD COLUMN chat_label_ru TEXT;
ALTER TABLE admin_settings ADD COLUMN chat_label_uz TEXT;

ALTER TABLE admin_settings ADD COLUMN chat_subtitle_en TEXT;
ALTER TABLE admin_settings ADD COLUMN chat_subtitle_ru TEXT;
ALTER TABLE admin_settings ADD COLUMN chat_subtitle_uz TEXT;

ALTER TABLE admin_settings ADD COLUMN chat_intro_en TEXT;
ALTER TABLE admin_settings ADD COLUMN chat_intro_ru TEXT;
ALTER TABLE admin_settings ADD COLUMN chat_intro_uz TEXT;

UPDATE admin_settings
SET
  call_label_en = COALESCE(NULLIF(call_label_en, ''), 'Call Support'),
  call_label_ru = COALESCE(NULLIF(call_label_ru, ''), 'Позвонить в поддержку'),
  call_label_uz = COALESCE(NULLIF(call_label_uz, ''), 'Qo‘llab-quvvatlashga qo‘ng‘iroq'),
  chat_label_en = COALESCE(NULLIF(chat_label_en, ''), 'Chat with us'),
  chat_label_ru = COALESCE(NULLIF(chat_label_ru, ''), 'Написать в чат'),
  chat_label_uz = COALESCE(NULLIF(chat_label_uz, ''), 'Chat orqali yozing'),
  chat_subtitle_en = COALESCE(NULLIF(chat_subtitle_en, ''), 'Describe the issue and we will reply here.'),
  chat_subtitle_ru = COALESCE(NULLIF(chat_subtitle_ru, ''), 'Опишите проблему, и мы ответим здесь.'),
  chat_subtitle_uz = COALESCE(NULLIF(chat_subtitle_uz, ''), 'Muammoni yozing, shu yerda javob beramiz.'),
  chat_intro_en = COALESCE(NULLIF(chat_intro_en, ''), 'The app will first try to answer using the support knowledge base. If the question is unclear, the chat is escalated to the admin.'),
  chat_intro_ru = COALESCE(NULLIF(chat_intro_ru, ''), 'Сначала приложение попробует ответить по базе частых вопросов. Если вопрос окажется сложным, чат будет передан администратору.'),
  chat_intro_uz = COALESCE(NULLIF(chat_intro_uz, ''), 'Ilova avval savolingizga yordam bazasi orqali javob berishga harakat qiladi. Savol murakkab bo‘lsa, chat adminlarga yuboriladi.');
