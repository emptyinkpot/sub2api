package admin

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"time"

	"github.com/Wei-Shaw/sub2api/internal/pkg/response"
	"github.com/Wei-Shaw/sub2api/internal/service"

	"github.com/gin-gonic/gin"
)

const (
	consumerKeyAuditDefaultLimit = 200
	consumerKeyAuditMaxLimit     = 1000
	consumerKeyAuditDefaultSecs  = 45
	consumerKeyAuditMaxSecs      = 180
	consumerKeyAuditBodyLimit    = 1 << 16
	consumerKeyAuditMaxChatTries = 5
)

// ConsumerKeyAuditHandler exposes admin-only downstream key audit endpoints.
type ConsumerKeyAuditHandler struct {
	apiKeyService *service.APIKeyService
	httpClient    *http.Client
}

// NewConsumerKeyAuditHandler creates a downstream consumer key audit handler.
func NewConsumerKeyAuditHandler(apiKeyService *service.APIKeyService) *ConsumerKeyAuditHandler {
	return &ConsumerKeyAuditHandler{
		apiKeyService: apiKeyService,
		httpClient:    &http.Client{},
	}
}

type ConsumerKeyAuditItem struct {
	ID          int64      `json:"id"`
	UserID      int64      `json:"user_id"`
	UserEmail   string     `json:"user_email,omitempty"`
	Name        string     `json:"name"`
	MaskedKey   string     `json:"masked_key"`
	GroupID     *int64     `json:"group_id"`
	GroupName   string     `json:"group_name,omitempty"`
	Platform    string     `json:"platform,omitempty"`
	Status      string     `json:"status"`
	Usable      bool       `json:"usable"`
	BlockReason string     `json:"block_reason,omitempty"`
	Quota       float64    `json:"quota"`
	QuotaUsed   float64    `json:"quota_used"`
	ExpiresAt   *time.Time `json:"expires_at"`
	LastUsedAt  *time.Time `json:"last_used_at"`
	CreatedAt   time.Time  `json:"created_at"`
	UpdatedAt   time.Time  `json:"updated_at"`

	RateLimit5h float64 `json:"rate_limit_5h"`
	RateLimit1d float64 `json:"rate_limit_1d"`
	RateLimit7d float64 `json:"rate_limit_7d"`
	Usage5h     float64 `json:"usage_5h"`
	Usage1d     float64 `json:"usage_1d"`
	Usage7d     float64 `json:"usage_7d"`
}

type ConsumerKeyAuditTestRequest struct {
	Model       string `json:"model"`
	Prompt      string `json:"prompt"`
	ModelsOnly  bool   `json:"models_only"`
	ChatBaseURL string `json:"chat_base_url"`
	TimeoutSec  int    `json:"timeout_sec"`
}

type ConsumerKeyAuditProbe struct {
	Success        bool   `json:"success"`
	StatusCode     int    `json:"status_code,omitempty"`
	DurationMS     int64  `json:"duration_ms"`
	Error          string `json:"error,omitempty"`
	ContentPreview string `json:"content_preview,omitempty"`
}

type ConsumerKeyAuditTestResult struct {
	Key           ConsumerKeyAuditItem   `json:"key"`
	Success       bool                   `json:"success"`
	ChatBaseURL   string                 `json:"chat_base_url"`
	SelectedModel string                 `json:"selected_model,omitempty"`
	Models        []string               `json:"models,omitempty"`
	ModelCount    int                    `json:"model_count"`
	ModelList     ConsumerKeyAuditProbe  `json:"model_list"`
	Chat          *ConsumerKeyAuditProbe `json:"chat,omitempty"`
	ModelsOnly    bool                   `json:"models_only"`
	DurationMS    int64                  `json:"duration_ms"`
}

type consumerKeyGatewayProbe struct {
	result ConsumerKeyAuditProbe
	body   []byte
}

// List returns masked downstream key metadata for audit scripts.
// GET /api/v1/admin/consumer-keys
func (h *ConsumerKeyAuditHandler) List(c *gin.Context) {
	if h == nil || h.apiKeyService == nil {
		response.Error(c, http.StatusServiceUnavailable, "Consumer key audit service unavailable")
		return
	}

	limit := parseConsumerKeyAuditLimit(c.Query("limit"))
	keyword := strings.TrimSpace(c.Query("q"))
	if len(keyword) > 100 {
		keyword = keyword[:100]
	}
	status := strings.TrimSpace(c.Query("status"))

	keys, err := h.apiKeyService.SearchAPIKeys(c.Request.Context(), 0, keyword, limit+1)
	if err != nil {
		response.ErrorFrom(c, err)
		return
	}

	truncated := len(keys) > limit
	if truncated {
		keys = keys[:limit]
	}

	items := make([]ConsumerKeyAuditItem, 0, len(keys))
	for i := range keys {
		if status != "" && keys[i].Status != status {
			continue
		}
		items = append(items, consumerKeyAuditItemFromService(&keys[i]))
	}

	response.Success(c, gin.H{
		"items":     items,
		"count":     len(items),
		"limit":     limit,
		"truncated": truncated,
	})
}

// Test performs a server-side gateway audit for one downstream key without exposing the raw key.
// POST /api/v1/admin/consumer-keys/:id/test
func (h *ConsumerKeyAuditHandler) Test(c *gin.Context) {
	if h == nil || h.apiKeyService == nil {
		response.Error(c, http.StatusServiceUnavailable, "Consumer key audit service unavailable")
		return
	}

	keyID, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		response.BadRequest(c, "Invalid consumer key ID")
		return
	}

	var req ConsumerKeyAuditTestRequest
	if err := c.ShouldBindJSON(&req); err != nil && !errors.Is(err, io.EOF) {
		response.BadRequest(c, "Invalid request: "+err.Error())
		return
	}

	apiKey, err := h.apiKeyService.GetByID(c.Request.Context(), keyID)
	if err != nil {
		response.ErrorFrom(c, err)
		return
	}

	chatBaseURL, err := deriveConsumerKeyAuditChatBaseURL(c.Request, req.ChatBaseURL)
	if err != nil {
		response.BadRequest(c, err.Error())
		return
	}

	timeout := parseConsumerKeyAuditTimeout(req.TimeoutSec)
	ctx, cancel := context.WithTimeout(c.Request.Context(), timeout)
	defer cancel()

	startedAt := time.Now()
	result := h.testConsumerKey(ctx, apiKey, chatBaseURL, req)
	result.DurationMS = time.Since(startedAt).Milliseconds()
	response.Success(c, result)
}

func (h *ConsumerKeyAuditHandler) testConsumerKey(ctx context.Context, apiKey *service.APIKey, chatBaseURL string, req ConsumerKeyAuditTestRequest) ConsumerKeyAuditTestResult {
	result := ConsumerKeyAuditTestResult{
		Key:         consumerKeyAuditItemFromService(apiKey),
		ChatBaseURL: chatBaseURL,
		ModelsOnly:  req.ModelsOnly,
	}

	modelProbe := h.gatewayRequest(ctx, http.MethodGet, chatBaseURL+"/models", apiKey.Key, nil, "application/json")
	result.ModelList = modelProbe.result
	if !modelProbe.result.Success {
		return result
	}

	models := extractConsumerKeyAuditModelIDs(modelProbe.body)
	result.ModelCount = len(models)
	result.Models = capConsumerKeyAuditModels(models, 50)

	if req.ModelsOnly {
		result.Success = len(models) > 0
		if !result.Success {
			result.ModelList.Success = false
			result.ModelList.Error = "model list returned no usable model ids"
		}
		return result
	}

	candidateModels := consumerKeyAuditCandidateModels(req.Model, models)
	if len(candidateModels) == 0 {
		result.ModelList.Success = false
		result.ModelList.Error = "model list returned no usable model ids"
		return result
	}

	prompt := strings.TrimSpace(req.Prompt)
	if prompt == "" {
		prompt = "Reply with a short confirmation that sub2api consumer key audit is OK."
	}
	for _, model := range candidateModels {
		chatBody, _ := json.Marshal(gin.H{
			"model":       model,
			"messages":    []gin.H{{"role": "user", "content": prompt}},
			"temperature": 0,
			"max_tokens":  32,
			"stream":      false,
		})

		chatProbe := h.gatewayRequest(ctx, http.MethodPost, chatBaseURL+"/chat/completions", apiKey.Key, chatBody, "application/json")
		chatResult := chatProbe.result
		if chatResult.Success {
			content := extractConsumerKeyAuditChatContent(chatProbe.body)
			if strings.TrimSpace(content) == "" {
				chatResult.Success = false
				chatResult.Error = "chat completion returned no assistant content"
			} else {
				chatResult.ContentPreview = truncateConsumerKeyAuditText(content, 160)
			}
		}
		result.SelectedModel = model
		result.Chat = &chatResult
		if chatResult.Success {
			result.Success = result.ModelList.Success
			return result
		}
	}
	return result
}

func (h *ConsumerKeyAuditHandler) gatewayRequest(ctx context.Context, method, rawURL, apiKey string, body []byte, accept string) consumerKeyGatewayProbe {
	startedAt := time.Now()
	probe := consumerKeyGatewayProbe{
		result: ConsumerKeyAuditProbe{},
	}

	var bodyReader io.Reader
	if body != nil {
		bodyReader = strings.NewReader(string(body))
	}
	req, err := http.NewRequestWithContext(ctx, method, rawURL, bodyReader)
	if err != nil {
		probe.result.DurationMS = time.Since(startedAt).Milliseconds()
		probe.result.Error = err.Error()
		return probe
	}
	req.Header.Set("Authorization", "Bearer "+apiKey)
	req.Header.Set("Accept", accept)
	req.Header.Set("User-Agent", "sub2api-consumer-key-audit/1.0")
	if body != nil {
		req.Header.Set("Content-Type", "application/json")
	}

	resp, err := h.httpClient.Do(req)
	probe.result.DurationMS = time.Since(startedAt).Milliseconds()
	if err != nil {
		probe.result.Error = err.Error()
		return probe
	}
	defer resp.Body.Close()

	probe.result.StatusCode = resp.StatusCode
	limited := io.LimitReader(resp.Body, consumerKeyAuditBodyLimit+1)
	respBody, err := io.ReadAll(limited)
	if err != nil {
		probe.result.Error = err.Error()
		return probe
	}
	probe.body = respBody

	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		probe.result.Error = fmt.Sprintf("HTTP %d: %s", resp.StatusCode, truncateConsumerKeyAuditText(redactConsumerKeyAuditSecret(string(respBody), apiKey), 240))
		return probe
	}

	probe.result.Success = true
	return probe
}

func consumerKeyAuditItemFromService(k *service.APIKey) ConsumerKeyAuditItem {
	if k == nil {
		return ConsumerKeyAuditItem{}
	}
	item := ConsumerKeyAuditItem{
		ID:          k.ID,
		UserID:      k.UserID,
		Name:        k.Name,
		MaskedKey:   maskConsumerKeyAuditSecret(k.Key),
		GroupID:     k.GroupID,
		Status:      k.Status,
		Quota:       k.Quota,
		QuotaUsed:   k.QuotaUsed,
		ExpiresAt:   k.ExpiresAt,
		LastUsedAt:  k.LastUsedAt,
		CreatedAt:   k.CreatedAt,
		UpdatedAt:   k.UpdatedAt,
		RateLimit5h: k.RateLimit5h,
		RateLimit1d: k.RateLimit1d,
		RateLimit7d: k.RateLimit7d,
		Usage5h:     k.EffectiveUsage5h(),
		Usage1d:     k.EffectiveUsage1d(),
		Usage7d:     k.EffectiveUsage7d(),
	}
	if k.User != nil {
		item.UserEmail = k.User.Email
	}
	if k.Group != nil {
		item.GroupName = k.Group.Name
		item.Platform = k.Group.Platform
	}
	item.Usable, item.BlockReason = consumerKeyAuditUsability(k)
	return item
}

func consumerKeyAuditUsability(k *service.APIKey) (bool, string) {
	if k == nil {
		return false, "missing key"
	}
	if k.Status != service.StatusAPIKeyActive {
		return false, k.Status
	}
	if k.GroupID == nil {
		return false, "missing group"
	}
	if k.IsExpired() {
		return false, service.StatusAPIKeyExpired
	}
	if k.IsQuotaExhausted() {
		return false, service.StatusAPIKeyQuotaExhausted
	}
	if k.User == nil || !k.User.IsActive() {
		return false, "user_inactive"
	}
	return true, ""
}

func parseConsumerKeyAuditLimit(raw string) int {
	limit := consumerKeyAuditDefaultLimit
	if strings.TrimSpace(raw) != "" {
		if parsed, err := strconv.Atoi(raw); err == nil {
			limit = parsed
		}
	}
	if limit < 1 {
		return 1
	}
	if limit > consumerKeyAuditMaxLimit {
		return consumerKeyAuditMaxLimit
	}
	return limit
}

func parseConsumerKeyAuditTimeout(raw int) time.Duration {
	seconds := raw
	if seconds <= 0 {
		seconds = consumerKeyAuditDefaultSecs
	}
	if seconds > consumerKeyAuditMaxSecs {
		seconds = consumerKeyAuditMaxSecs
	}
	return time.Duration(seconds) * time.Second
}

func deriveConsumerKeyAuditChatBaseURL(r *http.Request, override string) (string, error) {
	if strings.TrimSpace(override) != "" {
		return normalizeConsumerKeyAuditChatBaseURL(override, requestHostForConsumerKeyAudit(r))
	}

	scheme := firstConsumerKeyAuditForwardedValue(r.Header.Get("X-Forwarded-Proto"))
	if scheme == "" {
		if r.TLS != nil {
			scheme = "https"
		} else {
			scheme = "http"
		}
	}
	host := requestHostForConsumerKeyAudit(r)
	if host == "" {
		return "", errors.New("request host is required to derive chat base URL")
	}
	return normalizeConsumerKeyAuditChatBaseURL(scheme+"://"+host+"/v1", host)
}

func normalizeConsumerKeyAuditChatBaseURL(raw, requestHost string) (string, error) {
	parsed, err := url.Parse(strings.TrimSpace(raw))
	if err != nil {
		return "", fmt.Errorf("invalid chat_base_url: %w", err)
	}
	if parsed.Scheme != "http" && parsed.Scheme != "https" {
		return "", errors.New("chat_base_url must use http or https")
	}
	if parsed.Host == "" {
		return "", errors.New("chat_base_url host is required")
	}
	if parsed.User != nil {
		return "", errors.New("chat_base_url must not contain userinfo")
	}
	if requestHost != "" && !sameConsumerKeyAuditHost(parsed.Host, requestHost) {
		return "", errors.New("chat_base_url host must match the current request host")
	}

	parsed.RawQuery = ""
	parsed.Fragment = ""
	parsed.Path = strings.TrimRight(parsed.Path, "/")
	if parsed.Path == "" {
		parsed.Path = "/v1"
	} else if !strings.HasSuffix(parsed.Path, "/v1") {
		parsed.Path += "/v1"
	}
	return strings.TrimRight(parsed.String(), "/"), nil
}

func requestHostForConsumerKeyAudit(r *http.Request) string {
	if r == nil {
		return ""
	}
	if host := firstConsumerKeyAuditForwardedValue(r.Header.Get("X-Forwarded-Host")); host != "" {
		return host
	}
	return r.Host
}

func firstConsumerKeyAuditForwardedValue(raw string) string {
	raw = strings.TrimSpace(raw)
	if raw == "" {
		return ""
	}
	if idx := strings.Index(raw, ","); idx >= 0 {
		raw = raw[:idx]
	}
	return strings.TrimSpace(raw)
}

func sameConsumerKeyAuditHost(a, b string) bool {
	return strings.EqualFold(stripConsumerKeyAuditDefaultPort(a), stripConsumerKeyAuditDefaultPort(b))
}

func stripConsumerKeyAuditDefaultPort(host string) string {
	hostname, port, err := net.SplitHostPort(host)
	if err != nil {
		return strings.ToLower(host)
	}
	if port == "80" || port == "443" {
		return strings.ToLower(hostname)
	}
	return strings.ToLower(hostname + ":" + port)
}

func extractConsumerKeyAuditModelIDs(body []byte) []string {
	var payload struct {
		Data []struct {
			ID   string `json:"id"`
			Name string `json:"name"`
		} `json:"data"`
	}
	if err := json.Unmarshal(body, &payload); err != nil {
		return nil
	}

	out := make([]string, 0, len(payload.Data))
	seen := make(map[string]struct{}, len(payload.Data))
	for _, item := range payload.Data {
		id := strings.TrimSpace(item.ID)
		if id == "" {
			id = strings.TrimSpace(item.Name)
		}
		if id == "" {
			continue
		}
		if _, ok := seen[id]; ok {
			continue
		}
		seen[id] = struct{}{}
		out = append(out, id)
	}
	return out
}

func capConsumerKeyAuditModels(models []string, limit int) []string {
	if len(models) <= limit {
		return models
	}
	out := make([]string, limit)
	copy(out, models[:limit])
	return out
}

func consumerKeyAuditCandidateModels(requestedModel string, models []string) []string {
	requestedModel = strings.TrimSpace(requestedModel)
	if requestedModel != "" {
		return []string{requestedModel}
	}
	return capConsumerKeyAuditModels(models, consumerKeyAuditMaxChatTries)
}

func extractConsumerKeyAuditChatContent(body []byte) string {
	var payload struct {
		Choices []struct {
			Message struct {
				Content any `json:"content"`
			} `json:"message"`
			Delta struct {
				Content any `json:"content"`
			} `json:"delta"`
			Text string `json:"text"`
		} `json:"choices"`
	}
	if err := json.Unmarshal(body, &payload); err != nil {
		return ""
	}
	for _, choice := range payload.Choices {
		if text := consumerKeyAuditContentToString(choice.Message.Content); text != "" {
			return text
		}
		if text := consumerKeyAuditContentToString(choice.Delta.Content); text != "" {
			return text
		}
		if strings.TrimSpace(choice.Text) != "" {
			return choice.Text
		}
	}
	return ""
}

func consumerKeyAuditContentToString(value any) string {
	switch typed := value.(type) {
	case string:
		return typed
	case []any:
		var parts []string
		for _, part := range typed {
			switch p := part.(type) {
			case string:
				parts = append(parts, p)
			case map[string]any:
				if text, ok := p["text"].(string); ok {
					parts = append(parts, text)
				}
			}
		}
		return strings.Join(parts, "")
	default:
		return ""
	}
}

func maskConsumerKeyAuditSecret(secret string) string {
	if secret == "" {
		return ""
	}
	if len(secret) <= 12 {
		return "***"
	}
	return secret[:6] + "..." + secret[len(secret)-4:]
}

func redactConsumerKeyAuditSecret(text, secret string) string {
	if secret == "" {
		return text
	}
	return strings.ReplaceAll(text, secret, maskConsumerKeyAuditSecret(secret))
}

func truncateConsumerKeyAuditText(text string, limit int) string {
	text = strings.Join(strings.Fields(text), " ")
	if len(text) <= limit {
		return text
	}
	return text[:limit] + "..."
}
