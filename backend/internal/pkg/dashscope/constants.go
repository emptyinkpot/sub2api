// Package dashscope provides defaults for Alibaba DashScope OpenAI-compatible API.
package dashscope

type Model struct {
	ID          string `json:"id"`
	Object      string `json:"object"`
	OwnedBy     string `json:"owned_by"`
	Type        string `json:"type"`
	DisplayName string `json:"display_name"`
}

const (
	DefaultBaseURL   = "https://dashscope.aliyuncs.com/compatible-mode/v1"
	DefaultTestModel = "qwen-plus"
)

var DefaultModels = []Model{
	{ID: "qwen-turbo", Object: "model", OwnedBy: "dashscope", Type: "model", DisplayName: "Qwen Turbo"},
	{ID: "qwen-plus", Object: "model", OwnedBy: "dashscope", Type: "model", DisplayName: "Qwen Plus"},
	{ID: "qwen-max", Object: "model", OwnedBy: "dashscope", Type: "model", DisplayName: "Qwen Max"},
	{ID: "qwen-long", Object: "model", OwnedBy: "dashscope", Type: "model", DisplayName: "Qwen Long"},
}
