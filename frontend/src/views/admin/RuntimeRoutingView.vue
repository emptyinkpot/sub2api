<template>
  <AppLayout>
    <div class="space-y-5">
      <section class="border-b border-gray-200 pb-4 dark:border-gray-800">
        <div class="flex flex-col gap-4 lg:flex-row lg:items-end lg:justify-between">
          <div>
            <div class="mb-2 flex items-center gap-2">
              <span class="h-2.5 w-2.5 rounded-full" :class="runtimeTone.dot" />
              <span class="text-xs font-semibold uppercase text-gray-500 dark:text-gray-400">Runtime Routing</span>
            </div>
            <h1 class="text-2xl font-semibold text-gray-950 dark:text-white">Routing Graph</h1>
            <p class="mt-1 max-w-2xl text-sm text-gray-600 dark:text-gray-400">
              Current request path, provider pressure, retry signals, and the instrumentation still needed to explain every routing decision.
            </p>
          </div>
          <div class="flex flex-wrap items-center gap-3">
            <div class="w-32">
              <Select v-model="timeRange" :options="timeRangeOptions" @change="loadRuntimeRouting" />
            </div>
            <button class="btn btn-secondary" :disabled="loading" @click="loadRuntimeRouting">
              {{ t('common.refresh') }}
            </button>
            <button class="btn btn-primary" @click="router.push('/admin/ops')">
              <Icon name="terminal" size="sm" class="mr-2" />
              Ops
            </button>
          </div>
        </div>
      </section>

      <div v-if="loading" class="flex items-center justify-center py-12">
        <LoadingSpinner />
      </div>

      <template v-else>
        <section class="grid grid-cols-2 gap-px overflow-hidden rounded-lg border border-gray-200 bg-gray-200 dark:border-gray-800 dark:bg-gray-800 lg:grid-cols-4">
          <div v-for="metric in summaryMetrics" :key="metric.label" class="bg-white p-4 dark:bg-gray-950">
            <div class="flex items-center justify-between gap-3">
              <p class="text-xs font-medium text-gray-500 dark:text-gray-400">{{ metric.label }}</p>
              <Icon :name="metric.icon" size="sm" :class="metric.iconClass" />
            </div>
            <p class="mt-2 text-xl font-semibold text-gray-950 dark:text-white">{{ metric.value }}</p>
            <p class="mt-1 text-xs" :class="metric.hintClass">{{ metric.hint }}</p>
          </div>
        </section>

        <section class="grid grid-cols-1 gap-5 xl:grid-cols-[minmax(0,1.55fr)_minmax(330px,0.85fr)]">
          <div class="rounded-lg border border-gray-200 bg-white p-5 dark:border-gray-800 dark:bg-gray-950">
            <div class="mb-5 flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
              <div>
                <h2 class="text-base font-semibold text-gray-950 dark:text-white">Live Path</h2>
                <p class="text-sm text-gray-500 dark:text-gray-400">Gateway routing topology reconstructed from available runtime telemetry.</p>
              </div>
              <span class="rounded-full px-2 py-1 text-xs font-medium" :class="runtimeTone.badge">
                {{ runtimeTone.label }}
              </span>
            </div>

            <div class="overflow-x-auto">
              <div class="min-w-[820px]">
                <div class="grid grid-cols-[1fr_64px_1fr_64px_1.15fr_64px_1.15fr] items-stretch gap-2">
                  <div v-for="(node, index) in routeNodes" :key="node.label" class="contents">
                    <div class="routing-node" :class="{ 'routing-node-accent': node.accent }">
                      <div class="mb-3 flex items-center justify-between">
                        <p class="text-xs font-semibold uppercase text-gray-500 dark:text-gray-400">{{ node.label }}</p>
                        <Icon :name="node.icon" size="sm" :class="node.iconClass" />
                      </div>
                      <p class="text-lg font-semibold text-gray-950 dark:text-white">{{ node.value }}</p>
                      <p class="mt-1 text-xs text-gray-500 dark:text-gray-400">{{ node.hint }}</p>
                    </div>
                    <div v-if="index < routeNodes.length - 1" class="routing-edge">
                      <span />
                    </div>
                  </div>
                </div>
              </div>
            </div>

            <div class="mt-5 grid grid-cols-1 gap-3 md:grid-cols-3">
              <div v-for="model in topModels" :key="model.model" class="rounded-md border border-gray-200 p-3 dark:border-gray-800">
                <div class="mb-2 flex items-center justify-between gap-2">
                  <p class="truncate text-sm font-medium text-gray-900 dark:text-white">{{ model.model }}</p>
                  <span class="rounded-full bg-gray-100 px-2 py-0.5 text-xs text-gray-600 dark:bg-gray-900 dark:text-gray-400">
                    {{ formatNumber(model.requests || 0) }} req
                  </span>
                </div>
                <div class="h-1.5 rounded-full bg-gray-100 dark:bg-gray-900">
                  <div class="h-1.5 rounded-full bg-cyan-500" :style="{ width: `${model.share}%` }" />
                </div>
                <p class="mt-2 text-xs text-gray-500 dark:text-gray-400">{{ formatTokens(model.total_tokens) }} tokens · {{ model.share }}%</p>
              </div>
            </div>
          </div>

          <div class="space-y-5">
            <div class="rounded-lg border border-gray-200 bg-white p-5 dark:border-gray-800 dark:bg-gray-950">
              <h2 class="text-base font-semibold text-gray-950 dark:text-white">Provider Pressure</h2>
              <div class="mt-4 space-y-4">
                <div v-for="item in pressureItems" :key="item.label">
                  <div class="mb-1 flex items-center justify-between text-sm">
                    <span class="text-gray-600 dark:text-gray-400">{{ item.label }}</span>
                    <span class="font-medium text-gray-950 dark:text-white">{{ item.value }}</span>
                  </div>
                  <div class="h-2 rounded-full bg-gray-100 dark:bg-gray-900">
                    <div class="h-2 rounded-full" :class="item.barClass" :style="{ width: `${item.percent}%` }" />
                  </div>
                </div>
              </div>
            </div>

            <div class="rounded-lg border border-gray-200 bg-white p-5 dark:border-gray-800 dark:bg-gray-950">
              <h2 class="text-base font-semibold text-gray-950 dark:text-white">Routing Explainability</h2>
              <div class="mt-4 space-y-3">
                <div v-for="gap in explainabilityItems" :key="gap.label" class="flex items-start justify-between gap-3 border-b border-gray-100 pb-3 last:border-0 last:pb-0 dark:border-gray-900">
                  <div>
                    <p class="text-sm font-medium text-gray-900 dark:text-white">{{ gap.label }}</p>
                    <p class="text-xs text-gray-500 dark:text-gray-400">{{ gap.hint }}</p>
                  </div>
                  <span class="shrink-0 rounded-full px-2 py-0.5 text-xs font-medium" :class="gap.ready ? 'bg-green-100 text-green-700 dark:bg-green-950 dark:text-green-300' : 'bg-amber-100 text-amber-700 dark:bg-amber-950 dark:text-amber-300'">
                    {{ gap.ready ? 'live' : 'gap' }}
                  </span>
                </div>
              </div>
            </div>
          </div>
        </section>

        <section class="grid grid-cols-1 gap-5 xl:grid-cols-[minmax(330px,0.9fr)_minmax(0,1.1fr)]">
          <div class="rounded-lg border border-gray-200 bg-white p-5 dark:border-gray-800 dark:bg-gray-950">
            <h2 class="text-base font-semibold text-gray-950 dark:text-white">Runtime Timeline</h2>
            <div class="mt-4 space-y-4">
              <div v-for="event in timeline" :key="event.title" class="flex gap-3">
                <div class="mt-1 h-2 w-2 rounded-full" :class="event.dotClass" />
                <div>
                  <p class="text-sm font-medium text-gray-900 dark:text-white">{{ event.title }}</p>
                  <p class="text-xs text-gray-500 dark:text-gray-400">{{ event.detail }}</p>
                </div>
              </div>
            </div>
          </div>

          <div class="rounded-lg border border-gray-200 bg-white p-5 dark:border-gray-800 dark:bg-gray-950">
            <div class="mb-4 flex items-center justify-between">
              <div>
                <h2 class="text-base font-semibold text-gray-950 dark:text-white">Recent Requests</h2>
                <p class="text-sm text-gray-500 dark:text-gray-400">Request samples with model, account, group, and latency context.</p>
              </div>
              <button class="text-sm font-medium text-primary-600 hover:text-primary-700" @click="router.push('/admin/usage')">
                Usage
              </button>
            </div>
            <div class="overflow-x-auto">
              <table class="min-w-full divide-y divide-gray-100 text-sm dark:divide-gray-900">
                <thead>
                  <tr class="text-left text-xs font-medium uppercase text-gray-500 dark:text-gray-400">
                    <th class="pb-2 pr-4">Model</th>
                    <th class="pb-2 pr-4">Provider</th>
                    <th class="pb-2 pr-4">Status</th>
                    <th class="pb-2">Latency</th>
                  </tr>
                </thead>
                <tbody class="divide-y divide-gray-100 dark:divide-gray-900">
                  <tr v-for="request in recentRequests" :key="request.request_id || request.created_at">
                    <td class="py-3 pr-4">
                      <p class="max-w-[220px] truncate font-medium text-gray-900 dark:text-white">{{ request.model || 'unknown' }}</p>
                      <p class="text-xs text-gray-500 dark:text-gray-400">{{ request.platform || 'platform unknown' }}</p>
                    </td>
                    <td class="py-3 pr-4">
                      <p class="max-w-[180px] truncate text-gray-700 dark:text-gray-300">{{ request.account_id ? `#${request.account_id}` : 'not captured' }}</p>
                      <p class="text-xs text-gray-500 dark:text-gray-400">{{ request.group_id ? `group #${request.group_id}` : 'group unknown' }}</p>
                    </td>
                    <td class="py-3 pr-4">
                      <span class="rounded-full px-2 py-0.5 text-xs font-medium" :class="request.kind === 'success' ? 'bg-green-100 text-green-700 dark:bg-green-950 dark:text-green-300' : 'bg-rose-100 text-rose-700 dark:bg-rose-950 dark:text-rose-300'">
                        {{ request.kind }}
                      </span>
                    </td>
                    <td class="py-3 text-gray-700 dark:text-gray-300">{{ formatDuration(request.duration_ms) }}</td>
                  </tr>
                  <tr v-if="recentRequests.length === 0">
                    <td colspan="4" class="py-8 text-center text-gray-500 dark:text-gray-400">{{ t('common.noData') }}</td>
                  </tr>
                </tbody>
              </table>
            </div>
          </div>
        </section>
      </template>
    </div>
  </AppLayout>
</template>

<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { useI18n } from 'vue-i18n'
import { useRouter } from 'vue-router'
import { adminAPI } from '@/api/admin'
import type { OpsDashboardOverview, OpsRequestDetail } from '@/api/admin/ops'
import type { DashboardStats, ModelStat } from '@/types'
import AppLayout from '@/components/layout/AppLayout.vue'
import LoadingSpinner from '@/components/common/LoadingSpinner.vue'
import Select from '@/components/common/Select.vue'
import Icon from '@/components/icons/Icon.vue'

type TimeRange = '5m' | '30m' | '1h' | '6h' | '24h'
type IconName = 'bolt' | 'shield' | 'clock' | 'server' | 'key' | 'sync' | 'cube'

const { t } = useI18n()
const router = useRouter()

const loading = ref(false)
const timeRange = ref<TimeRange>('30m')
const stats = ref<DashboardStats | null>(null)
const overview = ref<OpsDashboardOverview | null>(null)
const models = ref<ModelStat[]>([])
const recentRequests = ref<OpsRequestDetail[]>([])

const timeRangeOptions = [
  { value: '5m', label: '5m' },
  { value: '30m', label: '30m' },
  { value: '1h', label: '1h' },
  { value: '6h', label: '6h' },
  { value: '24h', label: '24h' }
]

const runtimeTone = computed(() => {
  const errorRate = overview.value?.error_rate ?? 0
  const score = overview.value?.health_score ?? 100
  const pressured = pressuredAccounts.value
  if (score < 80 || errorRate >= 0.05 || pressured > 0) {
    return {
      label: 'degraded',
      dot: 'bg-amber-500',
      badge: 'bg-amber-100 text-amber-700 dark:bg-amber-950 dark:text-amber-300'
    }
  }
  return {
    label: 'healthy',
    dot: 'bg-green-500',
    badge: 'bg-green-100 text-green-700 dark:bg-green-950 dark:text-green-300'
  }
})

const pressuredAccounts = computed(() => {
  if (!stats.value) return 0
  return stats.value.error_accounts + stats.value.ratelimit_accounts + stats.value.overload_accounts
})

const summaryMetrics = computed(() => [
  {
    label: 'Routing Health',
    value: overview.value?.health_score === undefined ? runtimeTone.value.label : `${Math.round(overview.value.health_score)}/100`,
    hint: `${formatPercent(overview.value?.error_rate)} error rate`,
    icon: 'shield' as IconName,
    iconClass: 'text-green-500',
    hintClass: (overview.value?.error_rate ?? 0) > 0.03 ? 'text-amber-600 dark:text-amber-400' : 'text-gray-500 dark:text-gray-400'
  },
  {
    label: 'Flow',
    value: `${formatTokens(stats.value?.rpm)} RPM`,
    hint: `${formatTokens(stats.value?.tpm)} TPM`,
    icon: 'bolt' as IconName,
    iconClass: 'text-cyan-500',
    hintClass: 'text-gray-500 dark:text-gray-400'
  },
  {
    label: 'Decision Latency',
    value: formatDuration(overview.value?.duration?.p95_ms ?? stats.value?.average_duration_ms),
    hint: `avg ${formatDuration(stats.value?.average_duration_ms)}`,
    icon: 'clock' as IconName,
    iconClass: 'text-rose-500',
    hintClass: (overview.value?.duration?.p95_ms ?? 0) > 3000 ? 'text-amber-600 dark:text-amber-400' : 'text-gray-500 dark:text-gray-400'
  },
  {
    label: 'Provider Pool',
    value: stats.value ? `${stats.value.normal_accounts}/${stats.value.total_accounts}` : '0/0',
    hint: `${pressuredAccounts.value} pressured`,
    icon: 'server' as IconName,
    iconClass: 'text-emerald-500',
    hintClass: pressuredAccounts.value > 0 ? 'text-amber-600 dark:text-amber-400' : 'text-gray-500 dark:text-gray-400'
  }
])

const routeNodes = computed(() => [
  {
    label: 'Ingress',
    value: `${formatTokens(stats.value?.rpm)} RPM`,
    hint: `${formatNumber(stats.value?.today_requests)} requests today`,
    icon: 'bolt' as IconName,
    iconClass: 'text-cyan-500',
    accent: false
  },
  {
    label: 'Policy',
    value: `${formatNumber(stats.value?.active_api_keys)} active keys`,
    hint: `${formatNumber(stats.value?.active_users)} active users`,
    icon: 'key' as IconName,
    iconClass: 'text-indigo-500',
    accent: false
  },
  {
    label: 'Smart Router',
    value: `${formatPercent(overview.value?.error_rate)} error rate`,
    hint: `p95 ${formatDuration(overview.value?.duration?.p95_ms ?? stats.value?.average_duration_ms)}`,
    icon: 'sync' as IconName,
    iconClass: 'text-cyan-600',
    accent: true
  },
  {
    label: 'Provider Pool',
    value: providerHealthSummary.value,
    hint: `${formatNumber(stats.value?.normal_accounts)} normal / ${pressuredAccounts.value} pressured`,
    icon: 'server' as IconName,
    iconClass: 'text-emerald-500',
    accent: false
  }
])

const providerHealthSummary = computed(() => {
  if (!stats.value?.total_accounts) return 'unknown'
  return `${Math.round((stats.value.normal_accounts / stats.value.total_accounts) * 100)}% healthy`
})

const topModels = computed(() => {
  const total = models.value.reduce((sum, model) => sum + (model.total_tokens || 0), 0)
  return models.value
    .slice()
    .sort((a, b) => (b.total_tokens || 0) - (a.total_tokens || 0))
    .slice(0, 3)
    .map((model) => ({
      ...model,
      share: total > 0 ? Math.max(3, Math.round(((model.total_tokens || 0) / total) * 100)) : 0
    }))
})

const pressureItems = computed(() => {
  const totalAccounts = Math.max(stats.value?.total_accounts ?? 0, 1)
  const providerPressure = Math.min(100, Math.round((pressuredAccounts.value / totalAccounts) * 100))
  const errorPressure = Math.min(100, Math.round((overview.value?.error_rate ?? 0) * 1000))
  const queueDepth = overview.value?.system_metrics?.concurrency_queue_depth ?? 0
  const queuePressure = Math.min(100, queueDepth * 10)
  return [
    { label: 'Provider pressure', value: `${providerPressure}%`, percent: providerPressure, barClass: 'bg-amber-500' },
    { label: 'Retry / error pressure', value: formatPercent(overview.value?.error_rate), percent: errorPressure, barClass: 'bg-rose-500' },
    { label: 'Queue pressure', value: `${queueDepth} queued`, percent: queuePressure, barClass: 'bg-cyan-500' }
  ]
})

const explainabilityItems = computed(() => [
  {
    label: 'Request path telemetry',
    hint: recentRequests.value.length ? 'Recent request samples include model, group, account, and latency context.' : 'Request samples were unavailable for this window.',
    ready: recentRequests.value.length > 0
  },
  {
    label: 'Provider health',
    hint: overview.value ? 'Ops overview is feeding current error, latency, and provider pressure signals.' : 'Ops overview failed to load.',
    ready: !!overview.value
  },
  {
    label: 'Fallback chain events',
    hint: 'Timeout, retry, fallback, and cascade decisions need a dedicated runtime event stream.',
    ready: false
  },
  {
    label: 'Sticky session movement',
    hint: 'Sticky routing state is not yet exposed as runtime objects.',
    ready: false
  }
])

const timeline = computed(() => [
  {
    title: `${formatTokens(stats.value?.rpm)} RPM entering routing layer`,
    detail: `${formatTokens(stats.value?.tpm)} TPM across ${formatNumber(stats.value?.active_users)} active users.`,
    dotClass: 'bg-cyan-500'
  },
  {
    title: `${providerHealthSummary.value} provider health`,
    detail: `${formatNumber(stats.value?.normal_accounts)} normal accounts, ${pressuredAccounts.value} pressured accounts.`,
    dotClass: pressuredAccounts.value > 0 ? 'bg-amber-500' : 'bg-green-500'
  },
  {
    title: `Router p95 ${formatDuration(overview.value?.duration?.p95_ms ?? stats.value?.average_duration_ms)}`,
    detail: overview.value ? 'Measured from ops telemetry.' : 'Falling back to dashboard duration.',
    dotClass: (overview.value?.duration?.p95_ms ?? 0) > 3000 ? 'bg-amber-500' : 'bg-green-500'
  },
  {
    title: 'Fallback chain is still opaque',
    detail: 'Next backend step should persist timeout, fallback, retry, and sticky migration events.',
    dotClass: 'bg-amber-500'
  }
])

const loadRuntimeRouting = async () => {
  loading.value = true
  try {
    const [snapshot, opsOverview, requests] = await Promise.all([
      adminAPI.dashboard.getSnapshotV2({
        include_stats: true,
        include_trend: false,
        include_model_stats: true,
        include_group_stats: false,
        include_users_trend: false
      }),
      adminAPI.ops.getDashboardOverview({ time_range: timeRange.value }),
      adminAPI.ops.listRequestDetails({
        time_range: timeRange.value,
        kind: 'all',
        page: 1,
        page_size: 8,
        sort: 'created_at_desc'
      })
    ])
    stats.value = snapshot.stats ?? null
    models.value = snapshot.models ?? []
    overview.value = opsOverview
    recentRequests.value = requests.items ?? []
  } catch (error) {
    console.error('Error loading runtime routing:', error)
    recentRequests.value = []
  } finally {
    loading.value = false
  }
}

const formatNumber = (value: number | undefined | null): string => (value ?? 0).toLocaleString()

const formatTokens = (value: number | undefined | null): string => {
  const n = value ?? 0
  if (n >= 1_000_000_000) return `${(n / 1_000_000_000).toFixed(2)}B`
  if (n >= 1_000_000) return `${(n / 1_000_000).toFixed(2)}M`
  if (n >= 1_000) return `${(n / 1_000).toFixed(2)}K`
  return n.toLocaleString()
}

const formatDuration = (ms: number | undefined | null): string => {
  const n = ms ?? 0
  if (n >= 1000) return `${(n / 1000).toFixed(2)}s`
  return `${Math.round(n)}ms`
}

const formatPercent = (value: number | undefined | null): string => {
  const n = value ?? 0
  return `${(n <= 1 ? n * 100 : n).toFixed(2)}%`
}

onMounted(() => {
  loadRuntimeRouting()
})
</script>

<style scoped>
.routing-node {
  min-height: 128px;
  border: 1px solid rgb(229 231 235);
  border-radius: 0.5rem;
  padding: 1rem;
}

.dark .routing-node {
  border-color: rgb(31 41 55);
}

.routing-node-accent {
  border-color: rgb(6 182 212 / 0.45);
  background: rgb(236 254 255 / 0.55);
}

.dark .routing-node-accent {
  border-color: rgb(8 145 178 / 0.55);
  background: rgb(8 47 73 / 0.22);
}

.routing-edge {
  display: flex;
  align-items: center;
}

.routing-edge span {
  display: block;
  width: 100%;
  height: 1px;
  background: linear-gradient(90deg, rgb(156 163 175), rgb(6 182 212));
}
</style>
