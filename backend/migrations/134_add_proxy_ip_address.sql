-- add proxy ip address for account proxy display
ALTER TABLE proxies ADD COLUMN IF NOT EXISTS ip_address VARCHAR(45);