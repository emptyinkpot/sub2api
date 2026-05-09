// Package coze provides helpers and types for Coze OpenAI-compatible proxy integration.
package coze

// Model represents a Coze-backed model in the same shape used by admin model selectors.
type Model struct {
	ID          string `json:"id"`
	Object      string `json:"object"`
	Created     int64  `json:"created"`
	OwnedBy     string `json:"owned_by"`
	Type        string `json:"type"`
	DisplayName string `json:"display_name"`
}

const (
	// DefaultBaseURL is the default Coze v3 API root for native provider calls.
	DefaultBaseURL = "https://api.coze.cn"
	// DefaultTestModel is the model used when a Coze account has no selected test model.
	DefaultTestModel = "coze-shell"
)

// DefaultModels is the default Coze model list shown for Coze accounts without
// an explicit model_mapping.
var DefaultModels = []Model{
	{ID: "coze-shell", Object: "model", OwnedBy: "coze", Type: "model", DisplayName: "Coze Shell"},
}
