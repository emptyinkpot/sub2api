package handler

import (
	"strings"
	"time"

	"github.com/Wei-Shaw/sub2api/internal/pkg/ctxkey"
	"github.com/Wei-Shaw/sub2api/internal/pkg/ip"
	middleware2 "github.com/Wei-Shaw/sub2api/internal/server/middleware"
	"github.com/Wei-Shaw/sub2api/internal/service"
	"github.com/gin-gonic/gin"
)

// RequestTraceMiddleware records a trace for every gateway request (success + failure).
// The actual persistence is non-blocking via RequestTraceService.Record().
func RequestTraceMiddleware(traceSvc *service.RequestTraceService) gin.HandlerFunc {
	return func(c *gin.Context) {
		if traceSvc == nil {
			c.Next()
			return
		}

		startTime := time.Now()
		c.Next()

		// Build trace from context values set by upstream middlewares/handlers.
		trace := &service.RequestTrace{
			CreatedAt:  startTime,
			HTTPStatus: c.Writer.Status(),
			LatencyMs:  int(time.Since(startTime).Milliseconds()),
			Endpoint:   c.Request.URL.Path,
			ClientIP:   strings.TrimSpace(ip.GetClientIP(c)),
		}

		// request_id: prefer response header (set by RequestLogger middleware).
		if rid := c.Writer.Header().Get("X-Request-Id"); rid != "" {
			trace.RequestID = rid
		} else if v, _ := c.Request.Context().Value(ctxkey.RequestID).(string); v != "" {
			trace.RequestID = v
		}

		// model (set by setOpsRequestContext in handlers)
		if v, ok := c.Get(opsModelKey); ok {
			if s, ok := v.(string); ok {
				trace.Model = s
			}
		}

		// stream
		if v, ok := c.Get(opsStreamKey); ok {
			if b, ok := v.(bool); ok {
				trace.Stream = b
			}
		}

		// account_id: prefer ops account key, fall back to ctx.AccountID.
		if v, ok := c.Get(opsAccountIDKey); ok {
			if id, ok := v.(int64); ok && id > 0 {
				trace.AccountID = &id
			}
		}
		if trace.AccountID == nil && c.Request != nil {
			if id, ok := c.Request.Context().Value(ctxkey.AccountID).(int64); ok && id > 0 {
				trace.AccountID = &id
			}
		}

		// platform: prefer api-key group; fall back to ctx Platform; then path-based guess.
		apiKey, _ := middleware2.GetAPIKeyFromContext(c)
		if apiKey != nil {
			if apiKey.User != nil {
				trace.UserID = &apiKey.User.ID
			}
			trace.APIKeyID = &apiKey.ID
			if apiKey.GroupID != nil {
				trace.GroupID = apiKey.GroupID
			}
			if apiKey.Group != nil && apiKey.Group.Platform != "" {
				trace.Platform = apiKey.Group.Platform
			}
		}
		if trace.Platform == "" && c.Request != nil {
			if p, ok := c.Request.Context().Value(ctxkey.Platform).(string); ok {
				trace.Platform = p
			}
		}
		if trace.Platform == "" {
			trace.Platform = guessPlatformFromPath(c.Request.URL.Path)
		}

		// upstream status
		if v, ok := c.Get(service.OpsUpstreamStatusCodeKey); ok {
			switch t := v.(type) {
			case int:
				trace.UpstreamStatus = t
			case int64:
				trace.UpstreamStatus = int(t)
			}
		}

		// upstream latency
		if v, ok := c.Get(service.OpsUpstreamLatencyMsKey); ok {
			switch t := v.(type) {
			case int:
				trace.UpstreamLatencyMs = t
			case int64:
				trace.UpstreamLatencyMs = int(t)
			case float64:
				trace.UpstreamLatencyMs = int(t)
			}
		}

		// time-to-first-token
		if v, ok := c.Get(service.OpsTimeToFirstTokenMsKey); ok {
			var ttft int
			switch t := v.(type) {
			case int:
				ttft = t
			case int64:
				ttft = int(t)
			case float64:
				ttft = int(t)
			}
			if ttft > 0 {
				trace.TTFTMs = &ttft
			}
		}

		// error message: prefer ops upstream error message context value.
		if v, ok := c.Get(service.OpsUpstreamErrorMessageKey); ok {
			if s, ok := v.(string); ok {
				trace.ErrorMessage = strings.TrimSpace(s)
			}
		}
		if trace.ErrorMessage == "" && trace.HTTPStatus >= 400 {
			if v, ok := c.Get(service.OpsUpstreamErrorDetailKey); ok {
				if s, ok := v.(string); ok {
					trace.ErrorMessage = strings.TrimSpace(s)
				}
			}
		}

		// error_type: classify by status when not otherwise set.
		if trace.HTTPStatus >= 500 {
			trace.ErrorType = "upstream_error"
		} else if trace.HTTPStatus == 429 {
			trace.ErrorType = "rate_limit_error"
		} else if trace.HTTPStatus >= 400 {
			trace.ErrorType = "api_error"
		}

		traceSvc.Record(trace)
	}
}
