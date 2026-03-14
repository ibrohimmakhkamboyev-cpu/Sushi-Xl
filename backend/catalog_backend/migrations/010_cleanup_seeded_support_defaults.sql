UPDATE admin_settings
SET support_phone = ''
WHERE support_phone = '+998977722279';

DELETE FROM admin_faq
WHERE question = 'How long does delivery usually take?'
  AND answer = 'Most orders arrive within 30-45 minutes. During peak hours delivery can take up to 60 minutes.'
  AND sort_order = 1;
