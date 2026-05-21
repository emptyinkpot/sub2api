// Package moonshot provides defaults for Moonshot (Kimi) OpenAI-compatible API.
package moonshot

type Model struct {
	ID          string `json:"id"`
	Object      string `json:"object"`
	OwnedBy     string `json:"owned_by"`
	Type        string `json:"type"`
	DisplayName string `json:"display_name"`
}

const (
	DefaultBaseURL   = "https://api.moonshot.cn/v1"
	DefaultTestModel = "moonshot-v1-8k"
)

var DefaultModels = []Model{
	{ID: "moonshot-v1-8k", Object: "model", OwnedBy: "moonshot", Type: "model", DisplayName: "Moonshot 8K"},
	{ID: "moonshot-v1-32k", Object: "model", OwnedBy: "moonshot", Type: "model", DisplayName: "Moonshot 32K"},
	{ID: "moonshot-v1-128k", Object: "model", OwnedBy: "moonshot", Type: "model", DisplayName: "Moonshot 128K"},
	{ID: "kimi-latest", Object: "model", OwnedBy: "moonshot", Type: "model", DisplayName: "Kimi Latest"},
}
