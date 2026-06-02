-- 134: Add auto_disable column to scheduled_test_plans
-- When enabled, automatically sets the account to error status after
-- consecutive scheduled-test failures (auto-offline); the existing
-- auto_recover path brings it back on a later passing test.

ALTER TABLE scheduled_test_plans ADD COLUMN IF NOT EXISTS auto_disable BOOLEAN NOT NULL DEFAULT false;
