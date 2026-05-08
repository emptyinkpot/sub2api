// Package glm provides helpers and types for GLM-compatible API integration.
package glm

// Model represents a GLM model in the same shape used by admin model selectors.
type Model struct {
	ID          string `json:"id"`
	Object      string `json:"object"`
	Created     int64  `json:"created"`
	OwnedBy     string `json:"owned_by"`
	Type        string `json:"type"`
	DisplayName string `json:"display_name"`
}

const (
	// DefaultBaseURL is the default GLM OpenAI-compatible API root.
	DefaultBaseURL = "https://open.bigmodel.cn/api/paas/v4"
	// DefaultTestModel is the model used when a GLM account has no selected
	// test model.
	DefaultTestModel = "glm-4.6"
)

// DefaultModels is the default GLM model list shown for GLM accounts without
// an explicit model_mapping.
var DefaultModels = []Model{
	{ID: "glm-4.6", Object: "model", OwnedBy: "zhipu", Type: "model", DisplayName: "GLM-4.6"},
	{ID: "glm-4.5", Object: "model", OwnedBy: "zhipu", Type: "model", DisplayName: "GLM-4.5"},
	{ID: "glm-4-plus", Object: "model", OwnedBy: "zhipu", Type: "model", DisplayName: "GLM-4 Plus"},
	{ID: "glm-4-air", Object: "model", OwnedBy: "zhipu", Type: "model", DisplayName: "GLM-4 Air"},
	{ID: "glm-4-airx", Object: "model", OwnedBy: "zhipu", Type: "model", DisplayName: "GLM-4 AirX"},
	{ID: "glm-4-long", Object: "model", OwnedBy: "zhipu", Type: "model", DisplayName: "GLM-4 Long"},
	{ID: "glm-4-flash", Object: "model", OwnedBy: "zhipu", Type: "model", DisplayName: "GLM-4 Flash"},
	{ID: "glm-4v-plus", Object: "model", OwnedBy: "zhipu", Type: "model", DisplayName: "GLM-4V Plus"},
	{ID: "glm-4v", Object: "model", OwnedBy: "zhipu", Type: "model", DisplayName: "GLM-4V"},
	{ID: "glm-4", Object: "model", OwnedBy: "zhipu", Type: "model", DisplayName: "GLM-4"},
	{ID: "glm-3-turbo", Object: "model", OwnedBy: "zhipu", Type: "model", DisplayName: "GLM-3 Turbo"},
}
