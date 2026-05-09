package coze

import (
	"encoding/json"
	"testing"

	"github.com/Wei-Shaw/sub2api/internal/pkg/apicompat"
	"github.com/stretchr/testify/require"
)

func TestMessagesFromChat(t *testing.T) {
	req := &apicompat.ChatCompletionsRequest{
		Instructions: "system prompt",
		Messages: []apicompat.ChatMessage{
			{Role: "system", Content: raw(`"be terse"`)},
			{Role: "user", Content: raw(`[{"type":"text","text":"hello"},{"type":"image_url","image_url":{"url":"ignored"}}]`)},
			{Role: "assistant", Content: raw(`"hi"`)},
		},
	}

	got := MessagesFromChat(req)
	require.Equal(t, []Message{
		{Role: "user", Content: "system prompt", ContentType: "text"},
		{Role: "user", Content: "be terse", ContentType: "text"},
		{Role: "user", Content: "hello", ContentType: "text"},
		{Role: "assistant", Content: "hi", ContentType: "text"},
	}, got)
}

func TestMessagesFromResponsesStringInput(t *testing.T) {
	req := &apicompat.ResponsesRequest{
		Instructions: "instructions",
		Input:        raw(`"question"`),
	}

	got := MessagesFromResponses(req)
	require.Equal(t, []Message{
		{Role: "user", Content: "instructions", ContentType: "text"},
		{Role: "user", Content: "question", ContentType: "text"},
	}, got)
}

func TestMessagesFromResponsesItems(t *testing.T) {
	req := &apicompat.ResponsesRequest{
		Input: raw(`[
			{"role":"user","content":[{"type":"input_text","text":"first"},{"type":"input_image","image_url":"ignored"}]},
			{"role":"assistant","content":"second"},
			{"type":"function_call","name":"ignored","arguments":"{}"}
		]`),
	}

	got := MessagesFromResponses(req)
	require.Equal(t, []Message{
		{Role: "user", Content: "first", ContentType: "text"},
		{Role: "assistant", Content: "second", ContentType: "text"},
	}, got)
}

func TestBuildChatRequest(t *testing.T) {
	got := BuildChatRequest(" bot ", " user ", []Message{{Role: "user", Content: "hi", ContentType: "text"}})
	require.Equal(t, "bot", got.BotID)
	require.Equal(t, "user", got.UserID)
	require.True(t, got.Stream)
	require.Len(t, got.AdditionalMessages, 1)
}

func raw(s string) json.RawMessage {
	return json.RawMessage(s)
}
