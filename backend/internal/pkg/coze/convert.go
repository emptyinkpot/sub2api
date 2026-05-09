package coze

import (
	"encoding/json"
	"strings"

	"github.com/Wei-Shaw/sub2api/internal/pkg/apicompat"
)

func MessagesFromChat(req *apicompat.ChatCompletionsRequest) []Message {
	if req == nil {
		return nil
	}
	messages := make([]Message, 0, len(req.Messages)+1)
	if text := strings.TrimSpace(req.Instructions); text != "" {
		messages = append(messages, Message{Role: "user", Content: text, ContentType: "text"})
	}
	for _, msg := range req.Messages {
		content := normalizeRawContent(msg.Content, "text")
		if content == "" {
			continue
		}
		messages = append(messages, Message{
			Role:        cozeRole(msg.Role),
			Content:     content,
			ContentType: "text",
		})
	}
	return messages
}

func MessagesFromResponses(req *apicompat.ResponsesRequest) []Message {
	if req == nil {
		return nil
	}
	messages := make([]Message, 0, 4)
	if text := strings.TrimSpace(req.Instructions); text != "" {
		messages = append(messages, Message{Role: "user", Content: text, ContentType: "text"})
	}
	input := req.Input
	if len(input) == 0 {
		return messages
	}
	var inputString string
	if err := json.Unmarshal(input, &inputString); err == nil {
		if text := strings.TrimSpace(inputString); text != "" {
			messages = append(messages, Message{Role: "user", Content: text, ContentType: "text"})
		}
		return messages
	}
	var items []apicompat.ResponsesInputItem
	if err := json.Unmarshal(input, &items); err != nil {
		return messages
	}
	for _, item := range items {
		if item.Type != "" && item.Role == "" {
			continue
		}
		content := normalizeRawContent(item.Content, "input_text")
		if content == "" {
			continue
		}
		messages = append(messages, Message{
			Role:        cozeRole(item.Role),
			Content:     content,
			ContentType: "text",
		})
	}
	return messages
}

func BuildChatRequest(botID string, userID string, messages []Message) ChatRequest {
	return ChatRequest{
		BotID:              strings.TrimSpace(botID),
		UserID:             strings.TrimSpace(userID),
		Stream:             true,
		AdditionalMessages: messages,
	}
}

func normalizeRawContent(raw json.RawMessage, textPartType string) string {
	if len(raw) == 0 {
		return ""
	}
	var text string
	if err := json.Unmarshal(raw, &text); err == nil {
		return strings.TrimSpace(text)
	}
	var parts []map[string]any
	if err := json.Unmarshal(raw, &parts); err != nil {
		return ""
	}
	values := make([]string, 0, len(parts))
	for _, part := range parts {
		partType, _ := part["type"].(string)
		if partType != "text" && partType != "input_text" && partType != "output_text" && partType != textPartType {
			continue
		}
		if text, _ := part["text"].(string); strings.TrimSpace(text) != "" {
			values = append(values, strings.TrimSpace(text))
			continue
		}
		if text, _ := part["content"].(string); strings.TrimSpace(text) != "" {
			values = append(values, strings.TrimSpace(text))
		}
	}
	return strings.Join(values, "\n")
}

func cozeRole(role string) string {
	switch strings.ToLower(strings.TrimSpace(role)) {
	case "assistant":
		return "assistant"
	default:
		return "user"
	}
}
