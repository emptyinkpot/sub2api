/**
 * Upstream vendor presets — keep aligned with backend/internal/domain/provider_catalog.go
 */
import type { GroupPlatform } from '@/types'

export interface ProviderCatalogEntry {
  id: string
  display_name: string
  display_name_zh: string
  platform: GroupPlatform
  account_type: 'apikey'
  default_base_url: string
  default_test_model: string
  model_mapping: Record<string, string>
  docs_url?: string
  consumer_tags?: string[]
}

export const PROVIDER_CATALOG: ProviderCatalogEntry[] = [
  {
    id: 'zhipu',
    display_name: 'Zhipu GLM',
    display_name_zh: '智谱 GLM',
    platform: 'glm',
    account_type: 'apikey',
    default_base_url: 'https://open.bigmodel.cn/api/paas/v4',
    default_test_model: 'glm-4-flash',
    model_mapping: { 'glm-4-flash': 'glm-4-flash', 'glm-4-plus': 'glm-4-plus' },
    docs_url: 'https://open.bigmodel.cn/dev/api',
  },
  {
    id: 'dashscope',
    display_name: 'Alibaba DashScope (Qwen)',
    display_name_zh: '通义千问 DashScope',
    platform: 'openai',
    account_type: 'apikey',
    default_base_url: 'https://dashscope.aliyuncs.com/compatible-mode/v1',
    default_test_model: 'qwen-plus',
    model_mapping: { 'qwen-plus': 'qwen-plus', 'qwen-max': 'qwen-max', 'qwen-turbo': 'qwen-turbo' },
    docs_url: 'https://help.aliyun.com/zh/model-studio/',
    consumer_tags: ['contentmrs', 'novel'],
  },
  {
    id: 'moonshot',
    display_name: 'Moonshot (Kimi)',
    display_name_zh: '月之暗面 Kimi',
    platform: 'openai',
    account_type: 'apikey',
    default_base_url: 'https://api.moonshot.cn/v1',
    default_test_model: 'moonshot-v1-8k',
    model_mapping: {
      'moonshot-v1-8k': 'moonshot-v1-8k',
      'moonshot-v1-32k': 'moonshot-v1-32k',
      'kimi-latest': 'kimi-latest',
    },
    docs_url: 'https://platform.moonshot.cn/docs',
  },
  {
    id: 'openai',
    display_name: 'OpenAI',
    display_name_zh: 'OpenAI',
    platform: 'openai',
    account_type: 'apikey',
    default_base_url: 'https://api.openai.com/v1',
    default_test_model: 'gpt-4o-mini',
    model_mapping: { 'gpt-4o-mini': 'gpt-4o-mini', 'gpt-4o': 'gpt-4o' },
    docs_url: 'https://platform.openai.com/docs',
  },
  {
    id: 'coze-proxy',
    display_name: 'Coze (OpenAI-compatible proxy)',
    display_name_zh: 'Coze 兼容代理',
    platform: 'openai',
    account_type: 'apikey',
    default_base_url: 'http://coze-openai-proxy:8787/v1',
    default_test_model: 'coze-shell',
    model_mapping: { 'coze-shell': 'coze-shell' },
    consumer_tags: ['mortis', 'bot'],
  },
]

export function getProviderPreset(id: string): ProviderCatalogEntry | undefined {
  return PROVIDER_CATALOG.find((p) => p.id === id)
}
