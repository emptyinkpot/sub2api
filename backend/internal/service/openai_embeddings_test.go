package service

import (
	"bytes"
	"context"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/Wei-Shaw/sub2api/internal/config"
	"github.com/gin-gonic/gin"
	"github.com/stretchr/testify/require"
	"github.com/tidwall/gjson"
)

func TestOpenAIGatewayServiceForwardEmbeddings_APIKeyUsesConfiguredV1BaseURL(t *testing.T) {
	gin.SetMode(gin.TestMode)
	body := []byte(`{"model":"embedding-client","input":"上海 夜景","dimensions":1024}`)

	req := httptest.NewRequest(http.MethodPost, "/v1/embeddings", bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()
	c, _ := gin.CreateTestContext(rec)
	c.Request = req

	svc := &OpenAIGatewayService{
		cfg: &config.Config{},
		httpUpstream: &httpUpstreamRecorder{
			resp: &http.Response{
				StatusCode: http.StatusOK,
				Header: http.Header{
					"Content-Type": []string{"application/json"},
					"X-Request-Id": []string{"req_embed"},
				},
				Body: io.NopCloser(strings.NewReader(`{"object":"list","data":[{"object":"embedding","embedding":[0.1,0.2],"index":0}],"model":"embedding-upstream","usage":{"prompt_tokens":7,"total_tokens":7}}`)),
			},
		},
	}
	parsed, err := ParseOpenAIEmbeddingsRequest(body)
	require.NoError(t, err)

	account := &Account{
		ID:       10,
		Name:     "glm-apikey",
		Platform: PlatformGLM,
		Type:     AccountTypeAPIKey,
		Credentials: map[string]any{
			"api_key":  "glm-test-key",
			"base_url": "https://open.bigmodel.cn/api/paas/v4",
			"model_mapping": map[string]any{
				"embedding-client": "embedding-3",
			},
		},
	}

	result, err := svc.ForwardEmbeddings(context.Background(), c, account, body, parsed, "")
	require.NoError(t, err)
	require.NotNil(t, result)
	require.Equal(t, "embedding-client", result.Model)
	require.Equal(t, 7, result.Usage.InputTokens)

	upstream, ok := svc.httpUpstream.(*httpUpstreamRecorder)
	require.True(t, ok)
	require.NotNil(t, upstream.lastReq)
	require.Equal(t, "https://open.bigmodel.cn/api/paas/v4/embeddings", upstream.lastReq.URL.String())
	require.Equal(t, "Bearer glm-test-key", upstream.lastReq.Header.Get("Authorization"))
	require.Equal(t, "application/json", upstream.lastReq.Header.Get("Content-Type"))
	require.Equal(t, "embedding-3", gjson.GetBytes(upstream.lastBody, "model").String())
	require.Equal(t, "上海 夜景", gjson.GetBytes(upstream.lastBody, "input").String())
	require.Equal(t, int64(1024), gjson.GetBytes(upstream.lastBody, "dimensions").Int())
	require.Equal(t, http.StatusOK, rec.Code)
	require.Equal(t, float64(0.1), gjson.Get(rec.Body.String(), "data.0.embedding.0").Float())
}

func TestBuildOpenAIEmbeddingsURL(t *testing.T) {
	tests := []struct {
		name string
		base string
		want string
	}{
		{"provider root", "https://api.openai.com", "https://api.openai.com/v1/embeddings"},
		{"openai v1 root", "https://api.openai.com/v1", "https://api.openai.com/v1/embeddings"},
		{"glm v4 root", "https://open.bigmodel.cn/api/paas/v4", "https://open.bigmodel.cn/api/paas/v4/embeddings"},
		{"trailing slash", "https://api.openai.com/v1/", "https://api.openai.com/v1/embeddings"},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			require.Equal(t, tt.want, buildOpenAIEmbeddingsURL(tt.base))
		})
	}
}

func TestParseOpenAIEmbeddingsRequestValidation(t *testing.T) {
	_, err := ParseOpenAIEmbeddingsRequest([]byte(`{"input":"x"}`))
	require.ErrorContains(t, err, "model is required")

	_, err = ParseOpenAIEmbeddingsRequest([]byte(`{"model":"embedding-3"}`))
	require.ErrorContains(t, err, "input is required")
}
