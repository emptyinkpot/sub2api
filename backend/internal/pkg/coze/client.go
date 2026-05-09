package coze

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"
)

type Client struct {
	BaseURL    string
	APIToken   string
	HTTPClient *http.Client
}

func (c *Client) CreateChatStream(ctx context.Context, req ChatRequest) (*http.Response, error) {
	if strings.TrimSpace(c.APIToken) == "" {
		return nil, fmt.Errorf("coze api token is required")
	}
	if strings.TrimSpace(req.BotID) == "" {
		return nil, fmt.Errorf("coze bot id is required")
	}
	body, err := json.Marshal(req)
	if err != nil {
		return nil, err
	}
	httpReq, err := http.NewRequestWithContext(ctx, http.MethodPost, c.chatURL(), bytes.NewReader(body))
	if err != nil {
		return nil, err
	}
	httpReq.Header.Set("Authorization", "Bearer "+strings.TrimSpace(c.APIToken))
	httpReq.Header.Set("Content-Type", "application/json")
	resp, err := c.httpClient().Do(httpReq)
	if err != nil {
		return nil, err
	}
	if resp.StatusCode >= 200 && resp.StatusCode < 300 && resp.Body != nil {
		return resp, nil
	}
	defer resp.Body.Close()
	data, _ := io.ReadAll(io.LimitReader(resp.Body, 64*1024))
	return nil, fmt.Errorf("coze api error status=%d body=%s", resp.StatusCode, strings.TrimSpace(string(data)))
}

func (c *Client) chatURL() string {
	base := strings.TrimRight(strings.TrimSpace(c.BaseURL), "/")
	if base == "" {
		base = "https://api.coze.cn"
	}
	return base + "/v3/chat"
}

func (c *Client) httpClient() *http.Client {
	if c.HTTPClient != nil {
		return c.HTTPClient
	}
	return &http.Client{Timeout: 60 * time.Second}
}
