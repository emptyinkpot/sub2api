//go:build unit

package service

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/Wei-Shaw/sub2api/internal/config"
	"github.com/gin-gonic/gin"
	"github.com/stretchr/testify/require"
)

func TestAccountIsCoze(t *testing.T) {
	t.Parallel()

	require.True(t, (&Account{Platform: PlatformCoze}).IsCoze())
	require.False(t, (&Account{Platform: PlatformOpenAI}).IsCoze())
}

func TestAccountTestService_CozeSuccessUsesNativeV3Chat(t *testing.T) {
	gin.SetMode(gin.TestMode)

	var gotAuth string
	var gotReq struct {
		BotID              string `json:"bot_id"`
		UserID             string `json:"user_id"`
		Stream             bool   `json:"stream"`
		AdditionalMessages []struct {
			Role        string `json:"role"`
			Content     string `json:"content"`
			ContentType string `json:"content_type"`
		} `json:"additional_messages"`
	}
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		gotAuth = r.Header.Get("Authorization")
		require.Equal(t, "/v3/chat", r.URL.Path)
		require.NoError(t, json.NewDecoder(r.Body).Decode(&gotReq))
		w.Header().Set("Content-Type", "text/event-stream")
		_, _ = w.Write([]byte("event: conversation.message.delta\ndata: {\"type\":\"answer\",\"content_type\":\"text\",\"content\":\"native ok\"}\n\n"))
	}))
	defer server.Close()

	account := &Account{
		ID:       7,
		Platform: PlatformCoze,
		Type:     AccountTypeAPIKey,
		Credentials: map[string]any{
			"coze_api_base":  server.URL,
			"coze_api_token": "test-token",
			"coze_bot_id":    "bot-123",
			"coze_user_id":   "user-123",
		},
	}
	cfg := &config.Config{}
	cfg.Security.URLAllowlist.AllowInsecureHTTP = true
	ctx, recorder := newTestContext()
	svc := &AccountTestService{cfg: cfg}

	err := svc.testCozeAccountConnection(ctx, account, "", "hello")
	require.NoError(t, err)
	require.Equal(t, "Bearer test-token", gotAuth)
	require.Equal(t, "bot-123", gotReq.BotID)
	require.Equal(t, "user-123", gotReq.UserID)
	require.True(t, gotReq.Stream)
	require.Len(t, gotReq.AdditionalMessages, 1)
	require.Equal(t, "hello", gotReq.AdditionalMessages[0].Content)
	require.Contains(t, recorder.Body.String(), "native ok")
	require.Contains(t, recorder.Body.String(), "test_complete")
}

func TestAccountTestService_RoutesCozeBeforeOpenAI(t *testing.T) {
	gin.SetMode(gin.TestMode)

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		_, _ = w.Write([]byte("event: conversation.message.delta\ndata: {\"type\":\"answer\",\"content_type\":\"text\",\"content\":\"routed\"}\n\n"))
	}))
	defer server.Close()

	account := &Account{
		ID:       8,
		Platform: PlatformCoze,
		Type:     AccountTypeAPIKey,
		Credentials: map[string]any{
			"coze_api_base":  server.URL,
			"coze_api_token": "test-token",
			"coze_bot_id":    "bot-123",
		},
	}
	repo := &cozeAccountTestRepo{account: account}
	cfg := &config.Config{}
	cfg.Security.URLAllowlist.AllowInsecureHTTP = true
	ctx, recorder := newTestContext()
	svc := &AccountTestService{accountRepo: repo, cfg: cfg}

	err := svc.TestAccountConnection(ctx, account.ID, "", "", AccountTestModeDefault)
	require.NoError(t, err)
	require.Contains(t, recorder.Body.String(), "routed")
}

type cozeAccountTestRepo struct {
	mockAccountRepoForGemini
	account *Account
}

func (r *cozeAccountTestRepo) GetByID(_ context.Context, id int64) (*Account, error) {
	return r.account, nil
}
