-- Migration v18: App metadata table for v1.0.1 early-adopter grandfathering
CREATE TABLE IF NOT EXISTS app_meta (
  key TEXT NOT NULL PRIMARY KEY,
  value TEXT NOT NULL,
  updated_at INTEGER NOT NULL DEFAULT (CAST(strftime('%s', CURRENT_TIMESTAMP) AS INTEGER))
);

-- Executed only during v17 -> v18 upgrade (never on fresh v1.1.0 installs):
-- If SELECT COUNT(*) AS cnt FROM routines > 0:
-- INSERT OR REPLACE INTO app_meta (key, value, updated_at)
-- VALUES ('legacy_pro_grandfathered', 'true', CAST(strftime('%s', CURRENT_TIMESTAMP) AS INTEGER));
