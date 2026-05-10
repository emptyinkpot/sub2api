package service

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"

	"github.com/Wei-Shaw/sub2api/internal/config"
	"github.com/Wei-Shaw/sub2api/internal/pkg/logger"
	"github.com/Wei-Shaw/sub2api/internal/util/responseheaders"
	"github.com/gin-gonic/gin"
	"go.uber.org/zap"
)

type OpenAIEmbeddingsRequest struct {
	Model string `json:"model"`
	Input any    `json:"input"`
}

func ParseOpenAIEmbeddingsRequest(body []byte) (*OpenAIEmbeddingsRequest, error) {
	var req OpenAIEmbeddingsRequest
	if err := json.Unmarshal(body, &req); err != nil {
		return nil, fmt.Errorf("parse embeddings request: %w", err)
	}
	if strings.TrimSpace(req.Model) == "" {
		return nil, fmt.Errorf("model is required")
	}
	if req.Input == nil {
		return nil, fmt.Errorf("input is required")
	}
	return &req, nil
}

func (s *OpenAIGatewayService) SelectEmbeddingAccount(
	ctx context.Context,
	groupID *int64,
	model string,
	excludedIDs map[int64]struct{},
) (*AccountSelectionResult, error) {
	platforms := []string{PlatformOpenAI, PlatformGLM, PlatformCoze}
	var accounts []Account
	var err error
	if s.accountRepo == nil {
		return nil, ErrNoAvailableAccounts
	}
	if s.cfg != nil && s.cfg.RunMode == config.RunModeSimple {
		accounts, err = s.accountRepo.ListSchedulableByPlatforms(ctx, platforms)
	} else if groupID != nil {
		accounts, err = s.accountRepo.ListSchedulableByGroupIDAndPlatforms(ctx, *groupID, platforms)
	} else {
		accounts, err = s.accountRepo.ListSchedulableUngroupedByPlatforms(ctx, platforms)
	}
	if err != nil {
		return nil, fmt.Errorf("query embedding accounts failed: %w", err)
	}

	candidates := make([]*Account, 0, len(accounts))
	for i := range accounts {
		acc := &accounts[i]
		if acc.Type != AccountTypeAPIKey || !isOpenAICompatiblePlatformForEmbeddings(acc.Platform) {
			continue
		}
		if excludedIDs != nil {
			if _, excluded := excludedIDs[acc.ID]; excluded {
				continue
			}
		}
		if !acc.IsSchedulable() || !acc.IsModelSupported(model) {
			continue
		}
		candidates = append(candidates, acc)
	}
	if len(candidates) == 0 {
		return nil, ErrNoAvailableAccounts
	}
	sortAccountsByPriorityAndLastUsed(candidates, false)
	for i := range candidates {
		acc := candidates[i]
		result, err := s.tryAcquireAccountSlot(ctx, acc.ID, acc.Concurrency)
		if err != nil {
			continue
		}
		if result != nil && result.Acquired {
			return s.newSelectionResult(ctx, acc, true, result.ReleaseFunc, nil)
		}
	}
	acc := candidates[0]
	return s.newSelectionResult(ctx, acc, false, nil, &AccountWaitPlan{
		AccountID:      acc.ID,
		MaxConcurrency: acc.Concurrency,
		Timeout:        0,
		MaxWaiting:     0,
	})
}

func isOpenAICompatiblePlatformForEmbeddings(platform string) bool {
	switch platform {
	case PlatformOpenAI, PlatformGLM, PlatformCoze:
		return true
	default:
		return false
	}
}

func (s *OpenAIGatewayService) ForwardEmbeddings(
	ctx context.Context,
	c *gin.Context,
	account *Account,
	body []byte,
	parsed *OpenAIEmbeddingsRequest,
	channelMappedModel string,
) (*OpenAIForwardResult, error) {
	if parsed == nil {
		return nil, fmt.Errorf("parsed embeddings request is required")
	}
	if account == nil {
		return nil, fmt.Errorf("account is required")
	}
	if account.Type != AccountTypeAPIKey {
		return nil, fmt.Errorf("embeddings supports API-key OpenAI-compatible accounts only")
	}

	startTime := time.Now()
	requestModel := strings.TrimSpace(parsed.Model)
	if mapped := strings.TrimSpace(channelMappedModel); mapped != "" {
		requestModel = mapped
	}
	upstreamModel := account.GetMappedModel(requestModel)
	forwardBody, err := rewriteOpenAIEmbeddingsModel(body, upstreamModel)
	if err != nil {
		return nil, err
	}
	setOpsUpstreamRequestBody(c, forwardBody)

	token, _, err := s.GetAccessToken(ctx, account)
	if err != nil {
		return nil, fmt.Errorf("get access token: %w", err)
	}
	upstreamReq, err := s.buildOpenAIEmbeddingsRequest(ctx, account, forwardBody, token)
	if err != nil {
		return nil, err
	}

	proxyURL := ""
	if account.ProxyID != nil && account.Proxy != nil {
		proxyURL = account.Proxy.URL()
	}
	upstreamStart := time.Now()
	resp, err := s.httpUpstream.Do(upstreamReq, proxyURL, account.ID, account.Concurrency)
	SetOpsLatencyMs(c, OpsUpstreamLatencyMsKey, time.Since(upstreamStart).Milliseconds())
	if err != nil {
		safeErr := sanitizeUpstreamErrorMessage(err.Error())
		setOpsUpstreamError(c, 0, safeErr, "")
		appendOpsUpstreamError(c, OpsUpstreamErrorEvent{
			Platform:           account.Platform,
			AccountID:          account.ID,
			AccountName:        account.Name,
			UpstreamStatusCode: 0,
			UpstreamURL:        safeUpstreamURL(upstreamReq.URL.String()),
			Kind:               "request_error",
			Message:            safeErr,
		})
		return nil, fmt.Errorf("upstream request failed: %s", safeErr)
	}
	defer func() { _ = resp.Body.Close() }()

	bodyBytes, err := ReadUpstreamResponseBody(resp.Body, s.cfg, c, openAITooLargeError)
	if err != nil {
		return nil, err
	}
	if resp.StatusCode >= 400 {
		upstreamMsg := strings.TrimSpace(extractUpstreamErrorMessage(bodyBytes))
		upstreamMsg = sanitizeUpstreamErrorMessage(upstreamMsg)
		appendOpsUpstreamError(c, OpsUpstreamErrorEvent{
			Platform:           account.Platform,
			AccountID:          account.ID,
			AccountName:        account.Name,
			UpstreamStatusCode: resp.StatusCode,
			UpstreamRequestID:  resp.Header.Get("x-request-id"),
			UpstreamURL:        safeUpstreamURL(upstreamReq.URL.String()),
			Kind:               "upstream_error",
			Message:            upstreamMsg,
		})
		if s.rateLimitService != nil {
			_ = s.rateLimitService.HandleUpstreamError(ctx, account, resp.StatusCode, resp.Header, bodyBytes)
		}
	}

	responseheaders.WriteFilteredHeaders(c.Writer.Header(), resp.Header, s.responseHeaderFilter)
	contentType := "application/json"
	if s.cfg != nil && !s.cfg.Security.ResponseHeaders.Enabled {
		if upstreamType := resp.Header.Get("Content-Type"); upstreamType != "" {
			contentType = upstreamType
		}
	}
	c.Data(resp.StatusCode, contentType, bodyBytes)

	logger.L().Debug("openai embeddings: request forwarded",
		zap.Int64("account_id", account.ID),
		zap.String("request_model", strings.TrimSpace(parsed.Model)),
		zap.String("upstream_model", upstreamModel),
		zap.Int("status", resp.StatusCode),
	)

	return &OpenAIForwardResult{
		RequestID:     resp.Header.Get("x-request-id"),
		Model:         requestModel,
		UpstreamModel: upstreamModel,
		Usage: OpenAIUsage{
			InputTokens: extractEmbeddingsPromptTokens(bodyBytes),
		},
		ResponseHeaders: resp.Header.Clone(),
		Duration:        time.Since(startTime),
	}, nil
}

func (s *OpenAIGatewayService) buildOpenAIEmbeddingsRequest(ctx context.Context, account *Account, body []byte, token string) (*http.Request, error) {
	baseURL := account.GetOpenAIBaseURL()
	if baseURL == "" {
		baseURL = "https://api.openai.com"
	}
	validatedURL, err := s.validateUpstreamBaseURL(baseURL)
	if err != nil {
		return nil, err
	}
	targetURL := buildOpenAIEmbeddingsURL(validatedURL)
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, targetURL, bytes.NewReader(body))
	if err != nil {
		return nil, err
	}
	req.Header.Set("authorization", "Bearer "+token)
	req.Header.Set("content-type", "application/json")
	if ua := account.GetOpenAIUserAgent(); ua != "" {
		req.Header.Set("user-agent", ua)
	}
	return req, nil
}

func buildOpenAIEmbeddingsURL(baseURL string) string {
	trimmed := strings.TrimRight(strings.TrimSpace(baseURL), "/")
	if strings.HasSuffix(trimmed, "/v1") || strings.HasSuffix(trimmed, "/v4") {
		return trimmed + "/embeddings"
	}
	return trimmed + "/v1/embeddings"
}

func rewriteOpenAIEmbeddingsModel(body []byte, model string) ([]byte, error) {
	var payload map[string]any
	if err := json.Unmarshal(body, &payload); err != nil {
		return nil, err
	}
	payload["model"] = strings.TrimSpace(model)
	return json.Marshal(payload)
}

func extractEmbeddingsPromptTokens(body []byte) int {
	if len(body) == 0 {
		return 0
	}
	var payload struct {
		Usage struct {
			PromptTokens int `json:"prompt_tokens"`
			TotalTokens  int `json:"total_tokens"`
		} `json:"usage"`
	}
	if err := json.Unmarshal(body, &payload); err != nil && err != io.EOF {
		return 0
	}
	if payload.Usage.PromptTokens > 0 {
		return payload.Usage.PromptTokens
	}
	return payload.Usage.TotalTokens
}
