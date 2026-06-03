package repository

import (
	"context"
	"database/sql"
	"fmt"
	"strings"
	"time"

	"github.com/Wei-Shaw/sub2api/internal/service"
)

type requestTraceRepository struct {
	db *sql.DB
}

func NewRequestTraceRepository(db *sql.DB) service.RequestTraceRepository {
	return &requestTraceRepository{db: db}
}

const requestTraceInsertColumns = `(
  request_id, created_at, user_id, api_key_id, group_id, account_id,
  platform, model, endpoint, stream,
  http_status, upstream_status, latency_ms, upstream_latency_ms, ttft_ms,
  input_tokens, output_tokens,
  error_type, error_message,
  tls_fingerprint, probe_triggered, client_ip
)`

func (r *requestTraceRepository) BatchInsertTraces(ctx context.Context, traces []*service.RequestTrace) (int64, error) {
	if len(traces) == 0 {
		return 0, nil
	}

	var sb strings.Builder
	sb.WriteString("INSERT INTO request_traces ")
	sb.WriteString(requestTraceInsertColumns)
	sb.WriteString(" VALUES ")

	args := make([]interface{}, 0, len(traces)*22)
	for i, t := range traces {
		if i > 0 {
			sb.WriteByte(',')
		}
		base := i * 22
		fmt.Fprintf(&sb, "($%d,$%d,$%d,$%d,$%d,$%d,$%d,$%d,$%d,$%d,$%d,$%d,$%d,$%d,$%d,$%d,$%d,$%d,$%d,$%d,$%d,$%d)",
			base+1, base+2, base+3, base+4, base+5, base+6,
			base+7, base+8, base+9, base+10,
			base+11, base+12, base+13, base+14, base+15,
			base+16, base+17, base+18, base+19, base+20, base+21, base+22)

		args = append(args,
			t.RequestID, t.CreatedAt, t.UserID, t.APIKeyID, t.GroupID, t.AccountID,
			t.Platform, t.Model, t.Endpoint, t.Stream,
			t.HTTPStatus, t.UpstreamStatus, t.LatencyMs, t.UpstreamLatencyMs, t.TTFTMs,
			t.InputTokens, t.OutputTokens,
			emptyToNil(t.ErrorType), emptyToNil(t.ErrorMessage),
			t.TLSFingerprint, t.ProbeTriggered, emptyToNil(t.ClientIP),
		)
	}

	sb.WriteString(" ON CONFLICT (request_id) DO NOTHING")
	result, err := r.db.ExecContext(ctx, sb.String(), args...)
	if err != nil {
		return 0, err
	}
	return result.RowsAffected()
}

func emptyToNil(s string) interface{} {
	if s == "" {
		return nil
	}
	return s
}

func (r *requestTraceRepository) ListTraces(ctx context.Context, filter *service.RequestTraceFilter) ([]*service.RequestTrace, int64, error) {
	if filter == nil {
		filter = &service.RequestTraceFilter{Page: 1, PageSize: 20}
	}
	if filter.Page < 1 {
		filter.Page = 1
	}
	if filter.PageSize < 1 || filter.PageSize > 500 {
		filter.PageSize = 20
	}

	var where []string
	var args []interface{}
	argIdx := 1

	if filter.RequestID != "" {
		where = append(where, fmt.Sprintf("request_id = $%d", argIdx))
		args = append(args, filter.RequestID)
		argIdx++
	}
	if filter.AccountID != nil {
		where = append(where, fmt.Sprintf("account_id = $%d", argIdx))
		args = append(args, *filter.AccountID)
		argIdx++
	}
	if filter.UserID != nil {
		where = append(where, fmt.Sprintf("user_id = $%d", argIdx))
		args = append(args, *filter.UserID)
		argIdx++
	}
	if filter.GroupID != nil {
		where = append(where, fmt.Sprintf("group_id = $%d", argIdx))
		args = append(args, *filter.GroupID)
		argIdx++
	}
	if filter.Model != "" {
		where = append(where, fmt.Sprintf("model = $%d", argIdx))
		args = append(args, filter.Model)
		argIdx++
	}
	if filter.Platform != "" {
		where = append(where, fmt.Sprintf("platform = $%d", argIdx))
		args = append(args, filter.Platform)
		argIdx++
	}
	if filter.Since != nil {
		where = append(where, fmt.Sprintf("created_at >= $%d", argIdx))
		args = append(args, *filter.Since)
		argIdx++
	}
	if filter.Until != nil {
		where = append(where, fmt.Sprintf("created_at <= $%d", argIdx))
		args = append(args, *filter.Until)
		argIdx++
	}

	switch strings.ToLower(filter.Status) {
	case "success":
		where = append(where, "(error_type IS NULL OR error_type = '')")
	case "error":
		where = append(where, "(error_type IS NOT NULL AND error_type <> '')")
	}

	whereClause := ""
	if len(where) > 0 {
		whereClause = " WHERE " + strings.Join(where, " AND ")
	}

	// Count total.
	var total int64
	countSQL := "SELECT COUNT(*) FROM request_traces" + whereClause
	if err := r.db.QueryRowContext(ctx, countSQL, args...).Scan(&total); err != nil {
		return nil, 0, err
	}

	// Page query.
	offset := (filter.Page - 1) * filter.PageSize
	listSQL := `SELECT request_id, created_at, user_id, api_key_id, group_id, account_id,
	  platform, model, endpoint, stream,
	  http_status, upstream_status, latency_ms, upstream_latency_ms, ttft_ms,
	  input_tokens, output_tokens,
	  COALESCE(error_type, ''), COALESCE(error_message, ''),
	  tls_fingerprint, probe_triggered, COALESCE(client_ip, '')
	  FROM request_traces` + whereClause +
		fmt.Sprintf(" ORDER BY created_at DESC LIMIT $%d OFFSET $%d", argIdx, argIdx+1)
	args = append(args, filter.PageSize, offset)

	rows, err := r.db.QueryContext(ctx, listSQL, args...)
	if err != nil {
		return nil, 0, err
	}
	defer rows.Close()

	traces := make([]*service.RequestTrace, 0, filter.PageSize)
	for rows.Next() {
		t := &service.RequestTrace{}
		var ttft sql.NullInt64
		var createdAt time.Time
		if err := rows.Scan(
			&t.RequestID, &createdAt, &t.UserID, &t.APIKeyID, &t.GroupID, &t.AccountID,
			&t.Platform, &t.Model, &t.Endpoint, &t.Stream,
			&t.HTTPStatus, &t.UpstreamStatus, &t.LatencyMs, &t.UpstreamLatencyMs, &ttft,
			&t.InputTokens, &t.OutputTokens,
			&t.ErrorType, &t.ErrorMessage,
			&t.TLSFingerprint, &t.ProbeTriggered, &t.ClientIP,
		); err != nil {
			return nil, 0, err
		}
		t.CreatedAt = createdAt
		if ttft.Valid {
			v := int(ttft.Int64)
			t.TTFTMs = &v
		}
		traces = append(traces, t)
	}
	if err := rows.Err(); err != nil {
		return nil, 0, err
	}
	return traces, total, nil
}
