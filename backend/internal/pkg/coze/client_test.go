package coze

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/stretchr/testify/require"
)

func TestCreateChatStream(t *testing.T) {
	var gotAuth string
	var gotReq ChatRequest
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		gotAuth = r.Header.Get("Authorization")
		require.Equal(t, "/v3/chat", r.URL.Path)
		require.NoError(t, json.NewDecoder(r.Body).Decode(&gotReq))
		w.Header().Set("Content-Type", "text/event-stream")
		_, _ = w.Write([]byte("event: conversation.message.delta\ndata: {\"type\":\"answer\",\"content_type\":\"text\",\"content\":\"ok\"}\n\n"))
	}))
	defer server.Close()

	client := &Client{BaseURL: server.URL, APIToken: "token", HTTPClient: server.Client()}
	resp, err := client.CreateChatStream(context.Background(), ChatRequest{
		BotID:  "bot",
		UserID: "user",
		Stream: true,
		AdditionalMessages: []Message{
			{Role: "user", Content: "hi", ContentType: "text"},
		},
	})
	require.NoError(t, err)
	defer resp.Body.Close()
	require.Equal(t, "Bearer token", gotAuth)
	require.Equal(t, "bot", gotReq.BotID)
	require.True(t, gotReq.Stream)
	events, err := ParseSSE(resp.Body)
	require.NoError(t, err)
	require.Equal(t, "ok", AccumulateAnswerText(events))
}

func TestCreateChatStreamRequiresConfig(t *testing.T) {
	_, err := (&Client{}).CreateChatStream(context.Background(), ChatRequest{BotID: "bot"})
	require.ErrorContains(t, err, "coze api token is required")

	_, err = (&Client{APIToken: "token"}).CreateChatStream(context.Background(), ChatRequest{})
	require.ErrorContains(t, err, "coze bot id is required")
}
