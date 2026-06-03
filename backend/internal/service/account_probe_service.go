package service

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"

	"log/slog"
)

// AccountProbeService handles automatic detection of upstream capabilities
// (protocol, TLS requirements) when adding new accounts.
type AccountProbeService struct {
	httpUpstream HTTPUpstream
	accountRepo AccountRepository
}

// NewAccountProbeService creates a new probe service.
func NewAccountProbeService(
	httpUpstream HTTPUpstream,
	accountRepo AccountRepository,
) *AccountProbeService {
	return &AccountProbeService{
		httpUpstream: httpUpstream,
		accountRepo: accountRepo,
	}
}

// ProbeResult holds the detection results for an account.
type ProbeResult struct {
	WireAPI     string // "responses", "chat_completions", "both", "unknown"
	TLSRequired bool
	Models      []string
	Status      string // "success", "partial", "failed"
	Error       string
}

// ProbeAccountCapabilities detects upstream protocol and TLS requirements.
// It updates the account's extra fields to drive runtime behavior.
func (s *AccountProbeService) ProbeAccountCapabilities(ctx context.Context, account *Account) (*ProbeResult, error) {
	if account == nil || account.Type != AccountTypeAPIKey {
		return nil, fmt.Errorf("probe only supports apikey accounts")
	}

	baseURL := account.GetOpenAIBaseURL()
	if baseURL == "" {
		return nil, fmt.Errorf("account has no base_url")
	}

	result := &ProbeResult{WireAPI: "unknown", Status: "failed"}

	apiKey := account.GetOpenAIApiKey()
	if apiKey == "" {
		return nil, fmt.Errorf("account has no api_key")
	}

	proxyURL := ""
	if account.ProxyID != nil && account.Proxy != nil {
		proxyURL = account.Proxy.URL()
	}

	// Step 1: Try responses protocol without TLS fingerprint
	ok, err := s.tryProtocol(ctx, account, baseURL, apiKey, proxyURL, "responses", false)
	if ok {
		result.WireAPI = "responses"
		result.Status = "success"
		s.persistResult(ctx, account, result)
		return result, nil
	}

	// Step 2: Try chat completions without TLS fingerprint
	ok, err = s.tryProtocol(ctx, account, baseURL, apiKey, proxyURL, "chat_completions", false)
	if ok {
		result.WireAPI = "chat_completions"
		result.Status = "success"
		s.persistResult(ctx, account, result)
		return result, nil
	}

	// Step 3: If either returned TLS-like block, retry with utls
	if looksLikeTLSBlock(err) {
		ok, _ = s.tryProtocol(ctx, account, baseURL, apiKey, proxyURL, "responses", true)
		if ok {
			result.WireAPI = "responses"
			result.TLSRequired = true
			result.Status = "success"
			s.persistResult(ctx, account, result)
			return result, nil
		}

		ok, _ = s.tryProtocol(ctx, account, baseURL, apiKey, proxyURL, "chat_completions", true)
		if ok {
			result.WireAPI = "chat_completions"
			result.TLSRequired = true
			result.Status = "success"
			s.persistResult(ctx, account, result)
			return result, nil
		}
	}

	if err != nil {
		result.Error = err.Error()
	}
	s.persistResult(ctx, account, result)
	return result, nil
}

func (s *AccountProbeService) tryProtocol(ctx context.Context, account *Account, baseURL, apiKey, proxyURL, protocol string, useTLS bool) (bool, error) {
	var url string
	var body []byte

	probeModel := s.resolveProbeModel(account)

	if protocol == "responses" {
		url = strings.TrimRight(baseURL, "/") + "/responses"
		body = []byte(fmt.Sprintf(`{"model":"%s","input":"hi","max_output_tokens":1,"stream":false}`, probeModel))
	} else {
		url = strings.TrimRight(baseURL, "/") + "/chat/completions"
		body = []byte(fmt.Sprintf(`{"model":"%s","messages":[{"role":"user","content":"hi"}],"max_tokens":1,"stream":false}`, probeModel))
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, url, strings.NewReader(string(body)))
	if err != nil {
		return false, err
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+apiKey)

	var resp *http.Response
	if useTLS {
		resp, err = s.httpUpstream.DoWithTLS(req, proxyURL, account.ID, account.Concurrency, nil)
	} else {
		resp, err = s.httpUpstream.Do(req, proxyURL, account.ID, account.Concurrency)
	}
	if err != nil {
		return false, err
	}
	defer func() { _ = resp.Body.Close() }()

	if resp.StatusCode == 200 || resp.StatusCode == 201 {
		return true, nil
	}

	respBody, _ := io.ReadAll(io.LimitReader(resp.Body, 2048))
	bodyStr := string(respBody)

	if resp.StatusCode == 403 {
		return false, fmt.Errorf("status=403 body=%s", bodyStr)
	}
	if resp.StatusCode == 404 || resp.StatusCode == 405 {
		return false, fmt.Errorf("protocol_not_supported: status=%d", resp.StatusCode)
	}
	return false, fmt.Errorf("status=%d body=%s", resp.StatusCode, bodyStr)
}

func looksLikeTLSBlock(err error) bool {
	if err == nil {
		return false
	}
	msg := strings.ToLower(err.Error())
	return strings.Contains(msg, "tls") ||
		strings.Contains(msg, "tls router") ||
		strings.Contains(msg, "cloudflare") ||
		strings.Contains(msg, "just a moment") ||
		(strings.Contains(msg, "status=403") && !strings.Contains(msg, "insufficient"))
}

func (s *AccountProbeService) persistResult(ctx context.Context, account *Account, result *ProbeResult) {
	updates := map[string]any{
		"probe_wire_api":     result.WireAPI,
		"probe_tls_required": result.TLSRequired,
		"probe_last_run_at":  time.Now().Format(time.RFC3339),
		"probe_last_status":  result.Status,
	}
	if result.Error != "" {
		updates["probe_last_error"] = result.Error
	}

	if result.TLSRequired {
		updates["enable_tls_fingerprint"] = true
	}
	if result.WireAPI == "responses" {
		updates["openai_passthrough"] = true
	} else if result.WireAPI == "chat_completions" {
		updates["openai_passthrough"] = false
	}

	if len(result.Models) > 0 {
		modelsJSON, _ := json.Marshal(result.Models)
		updates["probe_models"] = string(modelsJSON)
	}

	if err := s.accountRepo.UpdateExtra(ctx, account.ID, updates); err != nil {
		slog.Error("probe: failed to persist result",
			"account_id", account.ID,
			"error", err)
	} else {
		slog.Info("probe: capabilities detected",
			"account_id", account.ID,
			"wire_api", result.WireAPI,
			"tls_required", result.TLSRequired,
			"status", result.Status)
	}
}

// ShouldProbe returns true if the account has never been probed or last probe was >24h ago.
func (s *AccountProbeService) ShouldProbe(account *Account) bool {
	if account == nil || account.Extra == nil {
		return true
	}
	lastRun, ok := account.Extra["probe_last_run_at"].(string)
	if !ok || lastRun == "" {
		return true
	}
	t, err := time.Parse(time.RFC3339, lastRun)
	if err != nil {
		return true
	}
	status, _ := account.Extra["probe_last_status"].(string)
	if status == "success" && time.Since(t) < 24*time.Hour {
		return false
	}
	return true
}

func (s *AccountProbeService) resolveProbeModel(account *Account) string {
	if account.Extra != nil {
		if m, ok := account.Extra["probe_model"].(string); ok && m != "" {
			return m
		}
	}
	return "gpt-4o-mini"
}
