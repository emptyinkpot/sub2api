import type { Meta, StoryObj } from '@storybook/vue3-vite'
import { computed, defineComponent, ref } from 'vue'
import AccountStatusIndicator from '@/components/account/AccountStatusIndicator.vue'
import AccountTodayStatsCell from '@/components/account/AccountTodayStatsCell.vue'
import AccountCapacityCell from '@/components/account/AccountCapacityCell.vue'
import AccountGroupsCell from '@/components/account/AccountGroupsCell.vue'
import PlatformTypeBadge from '@/components/common/PlatformTypeBadge.vue'
import Icon from '@/components/icons/Icon.vue'
import type { Account, Group, WindowStats } from '@/types'

const now = new Date()
const minutesFromNow = (minutes: number) => new Date(now.getTime() + minutes * 60_000).toISOString()
const hoursAgo = (hours: number) => new Date(now.getTime() - hours * 3_600_000).toISOString()

const groups: Group[] = [
  {
    id: 1,
    name: 'OpenAI Primary',
    description: null,
    platform: 'openai',
    rate_multiplier: 1,
    is_exclusive: false,
    status: 'active',
    subscription_type: 'standard',
    daily_limit_usd: null,
    weekly_limit_usd: null,
    monthly_limit_usd: null,
    image_price_1k: null,
    image_price_2k: null,
    image_price_4k: null,
    claude_code_only: false,
    fallback_group_id: null,
    fallback_group_id_on_invalid_request: null,
    require_oauth_only: false,
    require_privacy_set: false,
    created_at: hoursAgo(48),
    updated_at: hoursAgo(2)
  },
  {
    id: 2,
    name: 'Codex',
    description: null,
    platform: 'openai',
    rate_multiplier: 1.2,
    is_exclusive: false,
    status: 'active',
    subscription_type: 'standard',
    daily_limit_usd: null,
    weekly_limit_usd: null,
    monthly_limit_usd: null,
    image_price_1k: null,
    image_price_2k: null,
    image_price_4k: null,
    claude_code_only: false,
    fallback_group_id: null,
    fallback_group_id_on_invalid_request: null,
    require_oauth_only: false,
    require_privacy_set: false,
    created_at: hoursAgo(48),
    updated_at: hoursAgo(2)
  }
]

const baseAccount = {
  notes: null,
  proxy_id: null,
  concurrency: 5,
  current_concurrency: 1,
  priority: 0,
  rate_multiplier: 1,
  status: 'active' as const,
  error_message: null,
  last_used_at: hoursAgo(1),
  expires_at: null,
  auto_pause_on_expired: false,
  created_at: hoursAgo(72),
  updated_at: hoursAgo(1),
  group_ids: [1, 2],
  groups,
  schedulable: true,
  rate_limited_at: null,
  rate_limit_reset_at: null,
  overload_until: null,
  temp_unschedulable_until: null,
  temp_unschedulable_reason: null,
  session_window_start: null,
  session_window_end: null,
  session_window_status: null,
  quota_limit: 100,
  quota_used: 16,
  quota_daily_limit: 25,
  quota_daily_used: 3.4,
  quota_weekly_limit: 80,
  quota_weekly_used: 12.8
}

const makeAccounts = (state: string): Account[] => {
  const openoneai: Account = {
    ...baseAccount,
    id: 31,
    name: 'openoneai',
    platform: 'openai',
    type: 'apikey',
    credentials: {
      base_url: 'https://openoneapi.com',
      model_mapping: {
        'gpt-5.2': 'gpt-5.2',
        'gpt-5.5': 'gpt-5.5'
      }
    },
    extra: {
      email_address: '1915791855@qq.com',
      openai_apikey_responses_websockets_v2_enabled: false
    }
  }

  const rateLimited: Account = {
    ...baseAccount,
    id: 13,
    name: 'codex-oauth-rate-limited',
    platform: 'openai',
    type: 'oauth',
    credentials: {
      plan_type: 'plus',
      subscription_expires_at: minutesFromNow(60 * 24 * 14)
    },
    extra: {
      email_address: 'jasonkidd3882@outlook.jp',
      privacy_mode: 'training_off',
      model_rate_limits: {
        'gpt-5.5': {
          rate_limited_at: hoursAgo(0.5),
          rate_limit_reset_at: minutesFromNow(45)
        }
      }
    },
    schedulable: state !== 'unschedulable',
    rate_limited_at: hoursAgo(0.5),
    rate_limit_reset_at: minutesFromNow(45),
    error_message: '429 upstream rate limited; waiting for reset window.'
  }

  const errorAccount: Account = {
    ...baseAccount,
    id: 42,
    name: 'anthropic-relay-error',
    platform: 'anthropic',
    type: 'setup-token',
    credentials: {},
    extra: {},
    groups: [{ ...groups[0], id: 3, name: 'Claude Relay', platform: 'anthropic' }],
    status: state === 'error' ? 'error' : 'active',
    schedulable: state !== 'unschedulable',
    error_message: state === 'error' ? 'Stream ended before message_stop' : null,
    concurrency: 3,
    current_concurrency: 3,
    window_cost_limit: 20,
    current_window_cost: 18.7,
    max_sessions: 4,
    active_sessions: 2,
    base_rpm: 60,
    current_rpm: 48
  }

  return [openoneai, rateLimited, errorAccount]
}

const stats: Record<string, WindowStats> = {
  '31': { requests: 183, tokens: 928_400, cost: 3.42, standard_cost: 4.1, user_cost: 4.9 },
  '13': { requests: 42, tokens: 214_100, cost: 1.88, standard_cost: 2.1, user_cost: 2.5 },
  '42': { requests: 11, tokens: 81_300, cost: 0.74, standard_cost: 0.8, user_cost: 1.0 }
}

const getBaseUrl = (account: Account) => {
  const credentials = account.credentials as Record<string, unknown> | undefined
  const value = typeof credentials?.base_url === 'string' ? credentials.base_url.trim() : ''
  return value.replace(/\/+$/, '') || 'Default upstream'
}

const AccountsWorkbench = defineComponent({
  components: {
    AccountStatusIndicator,
    AccountTodayStatsCell,
    AccountCapacityCell,
    AccountGroupsCell,
    PlatformTypeBadge,
    Icon
  },
  props: {
    scenario: { type: String, default: 'normal' },
    compactWidth: { type: Boolean, default: false },
    showBaseUrlGroups: { type: Boolean, default: true }
  },
  setup(props) {
    const selected = ref<number[]>([31])
    const accounts = computed(() => makeAccounts(props.scenario))
    const grouped = computed(() => {
      if (!props.showBaseUrlGroups) return [{ key: 'all', label: 'All accounts', accounts: accounts.value }]
      const map = new Map<string, { key: string; label: string; accounts: Account[] }>()
      for (const account of accounts.value) {
        const baseUrl = getBaseUrl(account)
        const key = `${account.platform}:${baseUrl}`
        const entry = map.get(key) ?? { key, label: `${account.platform} · ${baseUrl}`, accounts: [] }
        entry.accounts.push(account)
        map.set(key, entry)
      }
      return [...map.values()]
    })

    const toggleSelected = (id: number) => {
      selected.value = selected.value.includes(id)
        ? selected.value.filter((item) => item !== id)
        : [...selected.value, id]
    }

    const toggleSchedulable = (account: Account) => {
      account.schedulable = !account.schedulable
    }

    return { selected, grouped, stats, toggleSelected, toggleSchedulable, getBaseUrl }
  },
  template: `
    <main :class="compactWidth ? 'w-[390px]' : 'w-[min(1120px,calc(100vw-48px))]'" class="space-y-4">
      <header class="flex flex-wrap items-start justify-between gap-3">
        <div>
          <p class="text-xs font-semibold uppercase tracking-wider text-primary-600 dark:text-primary-400">Admin accounts</p>
          <h1 class="text-2xl font-semibold text-gray-950 dark:text-white">Accounts workbench</h1>
          <p class="mt-1 max-w-2xl text-sm text-gray-500 dark:text-dark-300">
            Mocked Storybook surface for editing account row layout, upstream grouping, status, quota, and schedulable states.
          </p>
        </div>
        <div class="flex items-center gap-2">
          <button class="btn btn-secondary btn-sm"><Icon name="refresh" size="sm" />Refresh</button>
          <button class="btn btn-primary btn-sm"><Icon name="plus" size="sm" />Create</button>
        </div>
      </header>

      <div class="rounded-xl border border-amber-200 bg-amber-50 px-3 py-2 text-sm text-amber-800 dark:border-amber-700/40 dark:bg-amber-900/20 dark:text-amber-200">
        This story does not call the backend. It uses fixed data for safe visual editing.
      </div>

      <section v-for="group in grouped" :key="group.key" class="rounded-xl border border-gray-200 bg-gray-50/70 p-2 shadow-sm dark:border-dark-700 dark:bg-dark-900/40">
        <div class="mb-2 flex items-center justify-between gap-2 rounded-lg px-2 py-1">
          <span class="min-w-0 truncate text-[12px] font-semibold text-gray-800 dark:text-gray-100">{{ group.label }}</span>
          <span class="rounded-full bg-white px-1.5 py-px text-[10px] font-medium text-gray-500 dark:bg-dark-800 dark:text-dark-300">{{ group.accounts.length }} accounts</span>
        </div>

        <div class="space-y-2.5">
          <article v-for="row in group.accounts" :key="row.id" class="rounded-lg border border-gray-200 bg-white px-3 py-2.5 shadow-sm transition-colors hover:border-gray-300 dark:border-dark-700 dark:bg-dark-800 dark:hover:border-dark-600 sm:px-3.5">
            <div class="grid min-w-0 grid-cols-1 gap-2.5 lg:grid-cols-[minmax(0,1fr)_minmax(0,210px)_minmax(0,220px)_auto] lg:items-start">
              <section class="min-w-0">
                <div class="flex min-w-0 items-start gap-2">
                  <input type="checkbox" :checked="selected.includes(row.id)" @change="toggleSelected(row.id)" class="mt-1 flex-shrink-0 rounded border-gray-300 text-primary-600 focus:ring-primary-500" />
                  <div class="min-w-0 flex-1 overflow-hidden">
                    <div class="flex min-w-0 flex-wrap items-center gap-x-2 gap-y-1">
                      <span class="min-w-0 truncate text-[13px] font-semibold leading-snug text-gray-900 dark:text-white" :title="row.name">{{ row.name }}</span>
                      <span v-if="row.extra?.email_address" class="min-w-0 truncate text-[11px] leading-snug text-gray-500 dark:text-gray-400">{{ row.extra.email_address }}</span>
                    </div>
                    <div class="mt-1 flex min-w-0 flex-wrap items-center gap-1 overflow-hidden">
                      <PlatformTypeBadge :platform="row.platform" :type="row.type" :plan-type="row.credentials?.plan_type" :privacy-mode="row.extra?.privacy_mode" :subscription-expires-at="row.credentials?.subscription_expires_at" />
                    </div>
                    <div class="mt-1 truncate text-[11px] text-gray-400 dark:text-dark-400">{{ getBaseUrl(row) }}</div>
                  </div>
                </div>
              </section>

              <section class="min-w-0">
                <div class="text-[10px] font-medium uppercase tracking-wide text-gray-400 dark:text-dark-400">Status / Schedulable</div>
                <div class="mt-1 min-w-0 space-y-1.5 text-[12px] leading-snug">
                  <AccountStatusIndicator :account="row" />
                  <button @click="toggleSchedulable(row)" class="relative inline-flex h-5 w-9 flex-shrink-0 cursor-pointer rounded-full border-2 border-transparent transition-colors duration-200 ease-in-out focus:outline-none focus:ring-2 focus:ring-primary-500 focus:ring-offset-2 dark:focus:ring-offset-dark-800" :class="[row.schedulable ? 'bg-primary-500 hover:bg-primary-600' : 'bg-gray-200 hover:bg-gray-300 dark:bg-dark-600 dark:hover:bg-dark-500']">
                    <span class="pointer-events-none inline-block h-4 w-4 transform rounded-full bg-white shadow ring-0 transition duration-200 ease-in-out" :class="[row.schedulable ? 'translate-x-4' : 'translate-x-0']" />
                  </button>
                </div>
              </section>

              <section class="min-w-0">
                <div class="text-[10px] font-medium uppercase tracking-wide text-gray-400 dark:text-dark-400">Today / Capacity</div>
                <div class="mt-1 min-w-0 space-y-1.5 text-[11px] leading-snug">
                  <AccountTodayStatsCell :stats="stats[String(row.id)] ?? null" />
                  <AccountCapacityCell :account="row" />
                </div>
              </section>

              <section class="flex min-w-0 items-start justify-start gap-1 lg:justify-end">
                <button class="flex flex-shrink-0 flex-col items-center gap-0.5 rounded-md p-1 text-gray-500 transition-colors hover:bg-gray-100 hover:text-primary-600 dark:hover:bg-dark-700 dark:hover:text-primary-400"><Icon name="edit" size="sm" /><span class="text-[10px]">Edit</span></button>
                <button class="flex flex-shrink-0 flex-col items-center gap-0.5 rounded-md p-1 text-gray-500 transition-colors hover:bg-sky-50 hover:text-sky-600 dark:hover:bg-sky-900/20 dark:hover:text-sky-400"><Icon name="copy" size="sm" /><span class="text-[10px]">Clone</span></button>
                <button class="flex flex-shrink-0 flex-col items-center gap-0.5 rounded-md p-1 text-gray-500 transition-colors hover:bg-gray-100 hover:text-gray-900 dark:hover:bg-dark-700 dark:hover:text-white"><Icon name="more" size="sm" /><span class="text-[10px]">More</span></button>
              </section>
            </div>

            <dl class="mt-2 grid min-w-0 grid-cols-2 gap-x-3 gap-y-1.5 border-t border-gray-100 pt-2 text-[11px] leading-snug text-gray-600 dark:border-dark-700 dark:text-gray-300 sm:grid-cols-3 xl:grid-cols-6">
              <div><dt class="text-[10px] font-medium uppercase tracking-wide text-gray-400 dark:text-dark-400">Groups</dt><dd class="mt-0.5"><AccountGroupsCell :groups="row.groups" :max-display="3" /></dd></div>
              <div><dt class="text-[10px] font-medium uppercase tracking-wide text-gray-400 dark:text-dark-400">Proxy</dt><dd class="mt-0.5">{{ row.proxy?.name ?? '-' }}</dd></div>
              <div><dt class="text-[10px] font-medium uppercase tracking-wide text-gray-400 dark:text-dark-400">Priority</dt><dd class="mt-0.5">{{ row.priority }}</dd></div>
              <div><dt class="text-[10px] font-medium uppercase tracking-wide text-gray-400 dark:text-dark-400">Multiplier</dt><dd class="mt-0.5">{{ row.rate_multiplier }}x</dd></div>
              <div><dt class="text-[10px] font-medium uppercase tracking-wide text-gray-400 dark:text-dark-400">Quota</dt><dd class="mt-0.5">{{ row.quota_used ?? 0 }} / {{ row.quota_limit ?? '-' }}</dd></div>
              <div><dt class="text-[10px] font-medium uppercase tracking-wide text-gray-400 dark:text-dark-400">Notes</dt><dd class="mt-0.5 truncate">{{ row.notes ?? '-' }}</dd></div>
            </dl>
          </article>
        </div>
      </section>
    </main>
  `
})

const meta = {
  title: 'Views/Admin/Accounts Workbench',
  component: AccountsWorkbench,
  parameters: {
    layout: 'fullscreen'
  },
  argTypes: {
    scenario: { control: 'select', options: ['normal', 'error', 'unschedulable'] }
  }
} satisfies Meta<typeof AccountsWorkbench>

export default meta

type Story = StoryObj<typeof meta>

export const Normal: Story = {
  args: {
    scenario: 'normal',
    compactWidth: false,
    showBaseUrlGroups: true
  }
}

export const ErrorState: Story = {
  args: {
    scenario: 'error',
    compactWidth: false,
    showBaseUrlGroups: true
  }
}

export const MobileWidth: Story = {
  args: {
    scenario: 'normal',
    compactWidth: true,
    showBaseUrlGroups: true
  }
}