package admin

import (
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/Wei-Shaw/sub2api/internal/pkg/response"
	"github.com/Wei-Shaw/sub2api/internal/service"
	"github.com/gin-gonic/gin"
)

// RequestTraceHandler serves the request traces query API.
type RequestTraceHandler struct {
	traceService *service.RequestTraceService
}

func NewRequestTraceHandler(traceService *service.RequestTraceService) *RequestTraceHandler {
	return &RequestTraceHandler{traceService: traceService}
}

// ListRequestTraces handles GET /api/v1/admin/ops/request-traces
func (h *RequestTraceHandler) ListRequestTraces(c *gin.Context) {
	if h.traceService == nil {
		response.Error(c, http.StatusServiceUnavailable, "Request trace service not available")
		return
	}

	page, pageSize := response.ParsePagination(c)
	if pageSize > 500 {
		pageSize = 500
	}

	filter := &service.RequestTraceFilter{
		Page:     page,
		PageSize: pageSize,
		Status:   strings.ToLower(strings.TrimSpace(c.Query("status"))),
	}

	if v := strings.TrimSpace(c.Query("request_id")); v != "" {
		filter.RequestID = v
	}
	if v := strings.TrimSpace(c.Query("account_id")); v != "" {
		id, err := strconv.ParseInt(v, 10, 64)
		if err != nil || id <= 0 {
			response.BadRequest(c, "Invalid account_id")
			return
		}
		filter.AccountID = &id
	}
	if v := strings.TrimSpace(c.Query("user_id")); v != "" {
		id, err := strconv.ParseInt(v, 10, 64)
		if err != nil || id <= 0 {
			response.BadRequest(c, "Invalid user_id")
			return
		}
		filter.UserID = &id
	}
	if v := strings.TrimSpace(c.Query("group_id")); v != "" {
		id, err := strconv.ParseInt(v, 10, 64)
		if err != nil || id <= 0 {
			response.BadRequest(c, "Invalid group_id")
			return
		}
		filter.GroupID = &id
	}
	if v := strings.TrimSpace(c.Query("model")); v != "" {
		filter.Model = v
	}
	if v := strings.TrimSpace(c.Query("platform")); v != "" {
		filter.Platform = v
	}
	if v := strings.TrimSpace(c.Query("since")); v != "" {
		t, err := time.Parse(time.RFC3339, v)
		if err != nil {
			response.BadRequest(c, "Invalid since (must be RFC3339)")
			return
		}
		filter.Since = &t
	}
	if v := strings.TrimSpace(c.Query("until")); v != "" {
		t, err := time.Parse(time.RFC3339, v)
		if err != nil {
			response.BadRequest(c, "Invalid until (must be RFC3339)")
			return
		}
		filter.Until = &t
	}

	// If only the most recent page is requested without filters, serve from Redis ring buffer.
	if useRedisFastPath(filter) {
		offset := int64((filter.Page - 1) * filter.PageSize)
		traces, err := h.traceService.ListRecentFromRedis(c.Request.Context(), offset, int64(filter.PageSize))
		if err == nil && len(traces) > 0 {
			response.Paginated(c, traces, int64(len(traces)), filter.Page, filter.PageSize)
			return
		}
	}

	traces, total, err := h.traceService.ListTraces(c.Request.Context(), filter)
	if err != nil {
		response.ErrorFrom(c, err)
		return
	}
	response.Paginated(c, traces, total, filter.Page, filter.PageSize)
}

// useRedisFastPath returns true when the query targets only recent traces with no filters.
func useRedisFastPath(f *service.RequestTraceFilter) bool {
	if f == nil {
		return false
	}
	if f.RequestID != "" || f.AccountID != nil || f.UserID != nil || f.GroupID != nil {
		return false
	}
	if f.Model != "" || f.Platform != "" {
		return false
	}
	if f.Since != nil || f.Until != nil {
		return false
	}
	if f.Status != "" && f.Status != "all" {
		return false
	}
	if f.Page*f.PageSize > 10000 {
		return false
	}
	return true
}