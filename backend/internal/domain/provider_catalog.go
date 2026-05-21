package domain

// ProviderCatalogEntry describes a first-class upstream vendor preset for API-key accounts.
// Platform is the scheduler family; credentials use OpenAI-compatible api_key + base_url + model_mapping.
type ProviderCatalogEntry struct {
	ID              string            `json:"id"`
	DisplayName     string            `json:"display_name"`
	DisplayNameZh   string            `json:"display_name_zh"`
	Platform        string            `json:"platform"`
	AccountType     string            `json:"account_type"`
	DefaultBaseURL  string            `json:"default_base_url"`
	DefaultTestModel string           `json:"default_test_model"`
	ModelMapping    map[string]string `json:"model_mapping"`
	DocsURL         string            `json:"docs_url,omitempty"`
	ConsumerTags    []string          `json:"consumer_tags,omitempty"`
}

// ProviderCatalog is the canonical vendor table (no secrets).
var ProviderCatalog = []ProviderCatalogEntry{
	{
		ID: "zhipu", DisplayName: "Zhipu GLM", DisplayNameZh: "智谱 GLM",
		Platform: PlatformGLM, AccountType: "apikey",
		DefaultBaseURL: "https://open.bigmodel.cn/api/paas/v4", DefaultTestModel: "glm-4-flash",
		ModelMapping: map[string]string{"glm-4-flash": "glm-4-flash", "glm-4-plus": "glm-4-plus"},
		DocsURL: "https://open.bigmodel.cn/dev/api",
	},
	{
		ID: "dashscope", DisplayName: "Alibaba DashScope (Qwen)", DisplayNameZh: "通义千问 DashScope",
		Platform: PlatformOpenAI, AccountType: "apikey",
		DefaultBaseURL: "https://dashscope.aliyuncs.com/compatible-mode/v1", DefaultTestModel: "qwen-plus",
		ModelMapping: map[string]string{
			"qwen-plus": "qwen-plus", "qwen-max": "qwen-max", "qwen-turbo": "qwen-turbo",
		},
		DocsURL: "https://help.aliyun.com/zh/model-studio/",
		ConsumerTags: []string{"contentmrs", "novel"},
	},
	{
		ID: "moonshot", DisplayName: "Moonshot (Kimi)", DisplayNameZh: "月之暗面 Kimi",
		Platform: PlatformOpenAI, AccountType: "apikey",
		DefaultBaseURL: "https://api.moonshot.cn/v1", DefaultTestModel: "moonshot-v1-8k",
		ModelMapping: map[string]string{
			"moonshot-v1-8k": "moonshot-v1-8k", "moonshot-v1-32k": "moonshot-v1-32k",
			"kimi-latest": "kimi-latest",
		},
		DocsURL: "https://platform.moonshot.cn/docs",
	},
	{
		ID: "openai", DisplayName: "OpenAI", DisplayNameZh: "OpenAI",
		Platform: PlatformOpenAI, AccountType: "apikey",
		DefaultBaseURL: "https://api.openai.com/v1", DefaultTestModel: "gpt-4o-mini",
		ModelMapping: map[string]string{"gpt-4o-mini": "gpt-4o-mini", "gpt-4o": "gpt-4o"},
		DocsURL: "https://platform.openai.com/docs",
	},
	{
		ID: "coze-proxy", DisplayName: "Coze (OpenAI-compatible proxy)", DisplayNameZh: "Coze 兼容代理",
		Platform: PlatformOpenAI, AccountType: "apikey",
		DefaultBaseURL: "http://coze-openai-proxy:8787/v1", DefaultTestModel: "coze-shell",
		ModelMapping: map[string]string{"coze-shell": "coze-shell"},
		ConsumerTags: []string{"mortis", "bot"},
	},
}

func GetProviderCatalog() []ProviderCatalogEntry {
	out := make([]ProviderCatalogEntry, len(ProviderCatalog))
	copy(out, ProviderCatalog)
	return out
}
