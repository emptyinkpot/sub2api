package service

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"strings"
	"time"

	"github.com/Wei-Shaw/sub2api/internal/pkg/apicompat"
	"github.com/Wei-Shaw/sub2api/internal/pkg/coze"
	"github.com/gin-gonic/gin"
)

func (s *GatewayService) forwardCozeAsChatCompletions(ctx context.Context, c *gin.Context, account *Account, body []byte, startTime time.Time) (*ForwardResult, error) {
	var req apicompat.ChatCompletionsRequest
	if err := json.Unmarshal(body, &req); err != nil {
		return nil, fmt.Errorf("parse chat completions request: %w", err)
	}
	originalModel := strings.TrimSpace(req.Model)
	mappedModel := account.GetMappedModel(originalModel)
	messages := coze.MessagesFromChat(&req)
	if len(messages) == 0 {
		writeGatewayCCError(c, http.StatusBadRequest, "invalid_request_error", "Coze requires at least one text message")
		return nil, fmt.Errorf("coze chat request has no text messages")
	}

	answer, err := s.callCoze(ctx, account, messages)
	if err != nil {
		writeGatewayCCError(c, http.StatusBadGateway, "upstream_error", "Coze upstream request failed")
		return nil, err
	}

	if req.Stream {
		writeCozeChatCompletionsStream(c, originalModel, answer, req.StreamOptions != nil && req.StreamOptions.IncludeUsage)
	} else {
		resp := buildCozeResponsesResponse(originalModel, answer)
		c.JSON(http.StatusOK, apicompat.ResponsesToChatCompletions(resp, originalModel))
	}

	return &ForwardResult{Model: originalModel, UpstreamModel: mappedModel, Stream: req.Stream, Duration: time.Since(startTime)}, nil
}

func (s *GatewayService) forwardCozeAsResponses(ctx context.Context, c *gin.Context, account *Account, body []byte, startTime time.Time) (*ForwardResult, error) {
	var req apicompat.ResponsesRequest
	if err := json.Unmarshal(body, &req); err != nil {
		return nil, fmt.Errorf("parse responses request: %w", err)
	}
	originalModel := strings.TrimSpace(req.Model)
	mappedModel := account.GetMappedModel(originalModel)
	messages := coze.MessagesFromResponses(&req)
	if len(messages) == 0 {
		writeResponsesError(c, http.StatusBadRequest, "invalid_request_error", "Coze requires at least one text input")
		return nil, fmt.Errorf("coze responses request has no text input")
	}

	answer, err := s.callCoze(ctx, account, messages)
	if err != nil {
		writeResponsesError(c, http.StatusBadGateway, "server_error", "Coze upstream request failed")
		return nil, err
	}

	resp := buildCozeResponsesResponse(originalModel, answer)
	if req.Stream {
		writeCozeResponsesStream(c, resp, answer)
	} else {
		c.JSON(http.StatusOK, resp)
	}

	return &ForwardResult{Model: originalModel, UpstreamModel: mappedModel, Stream: req.Stream, Duration: time.Since(startTime)}, nil
}

func (s *GatewayService) callCoze(ctx context.Context, account *Account, messages []coze.Message) (string, error) {
	apiToken := strings.TrimSpace(account.GetCredential("coze_api_token"))
	if apiToken == "" {
		apiToken = strings.TrimSpace(account.GetCredential("api_key"))
	}
	if apiToken == "" {
		return "", fmt.Errorf("coze api token is required")
	}
	botID := strings.TrimSpace(account.GetCredential("coze_bot_id"))
	if botID == "" {
		return "", fmt.Errorf("coze bot id is required")
	}
	userID := strings.TrimSpace(account.GetCredential("coze_user_id"))
	if userID == "" {
		userID = "sub2api"
	}
	baseURL := strings.TrimSpace(account.GetCredential("coze_api_base"))
	if baseURL == "" {
		baseURL = strings.TrimSpace(account.GetCredential("base_url"))
	}
	if baseURL == "" {
		baseURL = coze.DefaultBaseURL
	}

	client := &coze.Client{BaseURL: baseURL, APIToken: apiToken}
	resp, err := client.CreateChatStream(ctx, coze.BuildChatRequest(botID, userID, messages))
	if err != nil {
		return "", err
	}
	defer func() { _ = resp.Body.Close() }()
	events, err := coze.ParseSSE(resp.Body)
	if err != nil {
		return "", err
	}
	answer := coze.AccumulateAnswerText(events)
	if strings.TrimSpace(answer) == "" {
		return "", fmt.Errorf("coze stream ended without answer content")
	}
	return answer, nil
}

func buildCozeResponsesResponse(model string, text string) *apicompat.ResponsesResponse {
	return &apicompat.ResponsesResponse{
		ID:     "resp_" + fmt.Sprintf("%d", time.Now().UnixNano()),
		Object: "response",
		Model:  model,
		Status: "completed",
		Output: []apicompat.ResponsesOutput{{
			Type:   "message",
			ID:     "msg_" + fmt.Sprintf("%d", time.Now().UnixNano()),
			Role:   "assistant",
			Status: "completed",
			Content: []apicompat.ResponsesContentPart{{
				Type: "output_text",
				Text: text,
			}},
		}},
		Usage: &apicompat.ResponsesUsage{},
	}
}

func writeCozeChatCompletionsStream(c *gin.Context, model string, text string, includeUsage bool) {
	c.Writer.Header().Set("Content-Type", "text/event-stream")
	c.Writer.Header().Set("Cache-Control", "no-cache")
	c.Writer.Header().Set("Connection", "keep-alive")
	c.Writer.Header().Set("X-Accel-Buffering", "no")
	c.Writer.WriteHeader(http.StatusOK)
	state := apicompat.NewResponsesEventToChatState()
	state.Model = model
	state.IncludeUsage = includeUsage
	events := []apicompat.ResponsesStreamEvent{
		{Type: "response.created", Response: buildCozeResponsesResponse(model, "")},
		{Type: "response.output_text.delta", Delta: text},
		{Type: "response.completed", Response: buildCozeResponsesResponse(model, text)},
	}
	for _, event := range events {
		for _, chunk := range apicompat.ResponsesEventToChatChunks(&event, state) {
			line, err := apicompat.ChatChunkToSSE(chunk)
			if err == nil {
				_, _ = c.Writer.Write([]byte(line))
			}
		}
	}
	_, _ = c.Writer.Write([]byte("data: [DONE]\n\n"))
	c.Writer.Flush()
}

func writeCozeResponsesStream(c *gin.Context, resp *apicompat.ResponsesResponse, text string) {
	c.Writer.Header().Set("Content-Type", "text/event-stream")
	c.Writer.Header().Set("Cache-Control", "no-cache")
	c.Writer.Header().Set("Connection", "keep-alive")
	c.Writer.Header().Set("X-Accel-Buffering", "no")
	c.Writer.WriteHeader(http.StatusOK)
	writeResponsesSSE(c, "response.created", apicompat.ResponsesStreamEvent{Type: "response.created", Response: buildCozeResponsesResponse(resp.Model, "")})
	writeResponsesSSE(c, "response.output_text.delta", apicompat.ResponsesStreamEvent{Type: "response.output_text.delta", Delta: text})
	writeResponsesSSE(c, "response.completed", apicompat.ResponsesStreamEvent{Type: "response.completed", Response: resp})
	_, _ = c.Writer.Write([]byte("data: [DONE]\n\n"))
	c.Writer.Flush()
}

func writeResponsesSSE(c *gin.Context, eventName string, payload apicompat.ResponsesStreamEvent) {
	data, err := json.Marshal(payload)
	if err != nil {
		return
	}
	_, _ = c.Writer.Write([]byte("event: " + eventName + "\n"))
	_, _ = c.Writer.Write([]byte("data: "))
	_, _ = c.Writer.Write(data)
	_, _ = c.Writer.Write([]byte("\n\n"))
}
