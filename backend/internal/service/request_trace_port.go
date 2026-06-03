package service

import (
	"context"
	"time"
)

// RequestTraceRepository persists request traces to Postgres.
type RequestTraceRepository interface {
	BatchInsertTraces(ctx context.Context, traces []*RequestTrace) (int64, error)
	ListTraces(ctx context.Context, filter *RequestTraceFilter) ([]*RequestTrace, int64, error)
}

// RequestTrace represents a single API request lifecycle record.
type RequestTrace struct {
	RequestID  string    `json:"request_id"`
	CreatedAt  time.Time `json:"created_at"`
	UserID     *int64    `json:"user_id"`
	APIKeyID   *int64    `json:"api_key_id"`
	GroupID    *int64    `json:"group_id"`
	AccountID  *int64    `json:"account_id"`
	Platform   string    `json:"platform"`
	Model      string    `json:"model"`
	Endpoint   string    `json:"endpoint"`
	Stream     bool      `json:"stream"`

	HTTPStatus      int  `json:"http_status"`
	UpstreamStatus  int  `json:"upstream_status"`
	LatencyMs       int  `json:"latency_ms"`
	UpstreamLatencyMs int `json:"upstream_latency_ms"`
	TTFTMs          *int `json:"ttft_ms"`

	InputTokens  int `json:"input_tokens"`
	OutputTokens int `json:"output_tokens"`

	ErrorType    string `json:"error_type"`
	ErrorMessage string `json:"error_message"`

	TLSFingerprint bool   `json:"tls_fingerprint"`
	ProbeTriggered bool   `json:"probe_triggered"`
	ClientIP       string `json:"client_ip"`
}

// RequestTraceFilter for querying traces.
type RequestTraceFilter struct {
	Page     int
	PageSize int

	RequestID string
	AccountID *int64
	UserID    *int64
	GroupID   *int64
	Model     string
	Platform  string
	Status    string // "success", "error", "all"
	Since     *time.Time
	Until     *time.Time
}
