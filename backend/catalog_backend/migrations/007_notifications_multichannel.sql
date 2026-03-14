ALTER TABLE admin_notifications ADD COLUMN delivery_types_json TEXT NOT NULL DEFAULT '["in_app"]';
ALTER TABLE admin_notifications ADD COLUMN image_url TEXT;

UPDATE admin_notifications
SET delivery_types_json = '["in_app"]'
WHERE delivery_types_json IS NULL OR trim(delivery_types_json) = '';

CREATE TABLE IF NOT EXISTS admin_notification_delivery_logs (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  notification_id INTEGER NOT NULL REFERENCES admin_notifications(id) ON DELETE CASCADE,
  channel TEXT NOT NULL,
  status TEXT NOT NULL,
  message TEXT,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_notification_delivery_logs_notification
ON admin_notification_delivery_logs(notification_id, created_at DESC);
