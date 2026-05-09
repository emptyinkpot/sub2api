package coze

type Message struct {
	Role        string `json:"role"`
	Content     string `json:"content"`
	ContentType string `json:"content_type"`
}

type ChatRequest struct {
	BotID              string    `json:"bot_id"`
	UserID             string    `json:"user_id"`
	Stream             bool      `json:"stream"`
	AdditionalMessages []Message `json:"additional_messages"`
}

type StreamEvent struct {
	Event string
	Data  any
}

type APIError struct {
	Code    string `json:"code,omitempty"`
	Message string `json:"message,omitempty"`
}

func (e APIError) Error() string {
	if e.Code != "" && e.Message != "" {
		return e.Code + ": " + e.Message
	}
	if e.Message != "" {
		return e.Message
	}
	if e.Code != "" {
		return e.Code
	}
	return "coze api error"
}
