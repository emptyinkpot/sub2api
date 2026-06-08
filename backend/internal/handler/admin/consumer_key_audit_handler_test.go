package admin

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/Wei-Shaw/sub2api/internal/service"
	"github.com/stretchr/testify/require"
)

func TestConsumerKeyAuditTriesNextModelWhenFirstVisibleModelFails(t *testing.T) {
	var requestedModels []string
	upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/v1/models":
			w.Header().Set("Content-Type", "application/json")
			_, _ = w.Write([]byte(`{"data":[{"id":"bad-model"},{"id":"good-model"}]}`))
		case "/v1/chat/completions":
			var body struct {
				Model string `json:"model"`
			}
			require.NoError(t, json.NewDecoder(r.Body).Decode(&body))
			requestedModels = append(requestedModels, body.Model)
			if body.Model != "good-model" {
				http.Error(w, `{"error":{"message":"model not found"}}`, http.StatusNotFound)
				return
			}
			w.Header().Set("Content-Type", "application/json")
			_, _ = w.Write([]byte(`{"choices":[{"message":{"content":"ok"}}]}`))
		default:
			t.Fatalf("unexpected path: %s", r.URL.Path)
		}
	}))
	t.Cleanup(upstream.Close)

	handler := &ConsumerKeyAuditHandler{httpClient: upstream.Client()}

	result := handler.testConsumerKey(context.Background(), activeConsumerKey(), upstream.URL+"/v1", ConsumerKeyAuditTestRequest{})

	require.True(t, result.Success)
	require.Equal(t, "good-model", result.SelectedModel)
	require.Equal(t, []string{"bad-model", "good-model"}, requestedModels)
	require.NotNil(t, result.Chat)
	require.True(t, result.Chat.Success)
}

func TestConsumerKeyAuditForcedModelDoesNotFallback(t *testing.T) {
	var requestedModels []string
	upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/v1/models":
			w.Header().Set("Content-Type", "application/json")
			_, _ = w.Write([]byte(`{"data":[{"id":"good-model"}]}`))
		case "/v1/chat/completions":
			var body struct {
				Model string `json:"model"`
			}
			require.NoError(t, json.NewDecoder(r.Body).Decode(&body))
			requestedModels = append(requestedModels, body.Model)
			http.Error(w, `{"error":{"message":"forced model failed"}}`, http.StatusNotFound)
		default:
			t.Fatalf("unexpected path: %s", r.URL.Path)
		}
	}))
	t.Cleanup(upstream.Close)

	handler := &ConsumerKeyAuditHandler{httpClient: upstream.Client()}

	result := handler.testConsumerKey(context.Background(), activeConsumerKey(), upstream.URL+"/v1", ConsumerKeyAuditTestRequest{
		Model: "forced-model",
	})

	require.False(t, result.Success)
	require.Equal(t, "forced-model", result.SelectedModel)
	require.Equal(t, []string{"forced-model"}, requestedModels)
	require.NotNil(t, result.Chat)
	require.Contains(t, result.Chat.Error, "forced model failed")
}

func activeConsumerKey() *service.APIKey {
	groupID := int64(1)
	return &service.APIKey{
		ID:      1,
		UserID:  1,
		Key:     "sk-test-consumer-key-audit",
		Name:    "test key",
		GroupID: &groupID,
		Status:  service.StatusAPIKeyActive,
		User: &service.User{
			ID:     1,
			Email:  "user@example.com",
			Status: service.StatusActive,
		},
		Group: &service.Group{
			ID:       groupID,
			Name:     "OpenAI Pool",
			Platform: service.PlatformOpenAI,
			Status:   service.StatusActive,
		},
	}
}
