-- Request Traces: full request lifecycle tracking (success + error).
-- Designed for high-write throughput with async batch INSERT.

SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '10min';

CREATE TABLE IF NOT EXISTS request_traces (
    request_id VARCHAR(64) PRIMARY KEY,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    user_id BIGINT,
    api_key_id BIGINT,
    group_id BIGINT,
    account_id BIGINT,

    platform VARCHAR(32),
    model VARCHAR(100),
    endpoint VARCHAR(128),
    stream BOOLEAN NOT NULL DEFAULT false,

    http_status INT,
    upstream_status INT,
    latency_ms INT,
    upstream_latency_ms INT,
    ttft_ms INT,

    input_tokens INT,
    output_tokens INT,

    error_type VARCHAR(64),
    error_message TEXT,

    tls_fingerprint BOOLEAN NOT NULL DEFAULT false,
    probe_triggered BOOLEAN NOT NULL DEFAULT false,
    client_ip VARCHAR(45)
);

CREATE INDEX IF NOT EXISTS idx_request_traces_created_at
    ON request_traces (created_at DESC);

CREATE INDEX IF NOT EXISTS idx_request_traces_account_time
    ON request_traces (account_id, created_at DESC)
    WHERE account_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_request_traces_model_time
    ON request_traces (model, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_request_traces_error_type_time
    ON request_traces (error_type, created_at DESC)
    WHERE error_type IS NOT NULL AND error_type <> '';

CREATE INDEX IF NOT EXISTS idx_request_traces_user_time
    ON request_traces (user_id, created_at DESC)
    WHERE user_id IS NOT NULL;
