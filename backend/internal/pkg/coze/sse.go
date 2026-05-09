package coze

import (
	"bufio"
	"bytes"
	"encoding/json"
	"io"
	"strings"
)

func ParseSSE(r io.Reader) ([]StreamEvent, error) {
	scanner := bufio.NewScanner(r)
	scanner.Buffer(make([]byte, 0, 64*1024), 1024*1024)
	var events []StreamEvent
	var eventName string
	var dataLines []string
	flush := func() {
		if len(dataLines) == 0 {
			eventName = ""
			return
		}
		raw := strings.Join(dataLines, "\n")
		dataLines = nil
		if strings.TrimSpace(raw) == "[DONE]" {
			events = append(events, StreamEvent{Event: eventName})
			eventName = ""
			return
		}
		var payload any
		if err := json.Unmarshal([]byte(raw), &payload); err != nil {
			payload = raw
		}
		events = append(events, StreamEvent{Event: eventName, Data: payload})
		eventName = ""
	}
	for scanner.Scan() {
		line := strings.TrimRight(scanner.Text(), "\r")
		if line == "" {
			flush()
			continue
		}
		switch {
		case strings.HasPrefix(line, "event:"):
			eventName = strings.TrimSpace(strings.TrimPrefix(line, "event:"))
		case strings.HasPrefix(line, "data:"):
			dataLines = append(dataLines, strings.TrimLeft(strings.TrimPrefix(line, "data:"), " "))
		}
	}
	if err := scanner.Err(); err != nil {
		return nil, err
	}
	flush()
	return events, nil
}

func ExtractAnswerDelta(event StreamEvent) string {
	payload, ok := event.Data.(map[string]any)
	if !ok || payload == nil {
		return ""
	}
	eventName := strings.ToLower(event.Event)
	message := mapStringAny(payload["message"])
	eventType := stringValue(payload["type"])
	if eventType == "" {
		eventType = stringValue(message["type"])
	}
	contentType := stringValue(payload["content_type"])
	if contentType == "" {
		contentType = stringValue(message["content_type"])
	}
	content := stringValue(payload["content"])
	if content == "" {
		content = stringValue(message["content"])
	}
	if content == "" {
		if delta := mapStringAny(payload["delta"]); delta != nil {
			content = stringValue(delta["content"])
		}
	}
	if !strings.Contains(eventName, "message.delta") && eventType != "answer" {
		return ""
	}
	if eventType != "" && eventType != "answer" {
		return ""
	}
	if contentType != "" && contentType != "text" {
		return ""
	}
	return content
}

func AccumulateAnswerText(events []StreamEvent) string {
	var b bytes.Buffer
	for _, event := range events {
		b.WriteString(ExtractAnswerDelta(event))
	}
	return b.String()
}

func mapStringAny(value any) map[string]any {
	if value == nil {
		return nil
	}
	if typed, ok := value.(map[string]any); ok {
		return typed
	}
	return nil
}

func stringValue(value any) string {
	if value == nil {
		return ""
	}
	if typed, ok := value.(string); ok {
		return typed
	}
	return ""
}
