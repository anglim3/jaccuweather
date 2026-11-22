-- City-level page views. No IP addresses or raw user agents.
CREATE TABLE IF NOT EXISTS visits (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  ts TEXT NOT NULL,
  path TEXT,
  city TEXT,
  region TEXT,
  region_code TEXT,
  country TEXT,
  postal_code TEXT,
  latitude REAL,
  longitude REAL,
  timezone TEXT,
  colo TEXT,
  device_type TEXT
);

CREATE INDEX IF NOT EXISTS idx_visits_ts ON visits(ts);
