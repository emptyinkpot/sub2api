<template>
  <AppLayout>
    <div class="space-y-5">
      <div v-if="loading" class="flex items-center justify-center py-12">
        <LoadingSpinner />
      </div>

      <template v-else-if="stats">
        <section class="border-b border-gray-200 pb-4 dark:border-gray-800">
          <div class="flex flex-col gap-4 lg:flex-row lg:items-end lg:justify-between">
            <div>
              <div class="mb-2 flex items-center gap-2">
                <span class="h-2.5 w-2.5 rounded-full" :class="runtimeStatus.dotClass" />
                <span class="text-xs font-semibold uppercase text-gray-500 dark:text-gray-400">
                  AI Gateway Runtime
                </span>
              </div>
              <h1 class="text-2xl font-semibold text-gray-950 dark:text-white">Runtime Surface</h1>
              <p class="mt-1 max-w-2xl text-sm text-gray-600 dark:text-gray-400">
                Live gateway posture across routing, provider health, token pressure, and request flow.
              </p>
            </div>
            <div class="flex flex-wrap items-center gap-3">
              <DateRangePicker
                v-model:start-date="startDate"
                v-model:end-date="endDate"
                @change="onDateRangeChange"
              />
              <button @click="loadDashboardStats" :disabled="chartsLoading || opsLoading" class="btn btn-secondary">
                {{ t('common.refresh') }}
              </button>
              <button @click="router.push('/admin/ops')" class="btn btn-primary">
                <Icon name="terminal" size="sm" class="mr-2" />
                Ops
              </button>
            </div>
          </div>
        </section>

        <section class="grid grid-cols-2 gap-px overflow-hidden rounded-lg border border-gray-200 bg-gray-200 dark:border-gray-800 dark:bg-gray-800 lg:grid-cols-5">
          <div v-for="metric in runtimeMetrics" :key="metric.label" class="bg-white p-4 dark:bg-gray-950">
            <div class="flex items-center justify-between gap-3">
              <p class="text-xs font-medium text-gray-500 dark:text-gray-400">{{ metric.label }}</p>
              <Icon :name="metric.icon" size="sm" :class="metric.iconClass" />
            </div>
            <p class="mt-2 text-xl font-semibold text-gray-950 dark:text-white">{{ metric.value }}</p>
            <p class="mt-1 text-xs" :class="metric.hintClass">{{ metric.hint }}</p>
          </div>
        </section>

        <section class="grid grid-cols-1 gap-5 xl:grid-cols-[minmax(0,1.7fr)_minmax(320px,0.8fr)]">
          <div class="rounded-lg border border-gray-200 bg-white p-5 dark:border-gray-800 dark:bg-gray-950">
            <div class="mb-5 flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
              <div>
                <h2 class="text-base font-semibold text-gray-950 dark:text-white">Routing Graph</h2>
                <p class="text-sm text-gray-500 dark:text-gray-400">
                  Active flow reconstructed from current usage and ops telemetry.
                </p>
              </div>
              <div class="flex items-center gap-2 text-xs text-gray-500 dark:text-gray-400">
                <span class="h-2 w-2 rounded-full bg-green-500" />
                {{ runtimeStatus.label }}
              </div>
            </div>

            <div class="overflow-x-auto">
              <div class="min-w-[720px]">
                <div class="grid grid-cols-[1fr_70px_1fr_70px_1.2fr_70px_1.1fr] items-center gap-2">
                  <div class="runtime-node">
                    <p class="runtime-node-label">Ingress</p>
                    <p class="runtime-node-value">{{ formatTokens(stats.rpm) }} RPM</p>
                    <p class="runtime-node-hint">{{ formatNumber(stats.today_requests) }} requests today</p>
                  </div>
                  <div class="runtime-edge"><span /></div>
                  <div class="runtime-node">
                    <p class="runtime-node-label">Policy</p>
                    <p class="runtime-node-value">{{ stats.active_api_keys }} active keys</p>
                    <p class="runtime-node-hint">{{ stats.active_users }} active users</p>
                  </div>
                  <div class="runtime-edge"><span /></div>
                  <div class="runtime-node runtime-node-accent">
                    <p class="runtime-node-label">Smart Router</p>
                    <p class="runtime-node-value">{{ formatPercent(currentErrorRate) }} error rate</p>
                    <p class="runtime-node-hint">p95 {{ formatDuration(currentP95Latency) }}</p>
                  </div>
                  <div class="runtime-edge"><span /></div>
                  <div class="runtime-node">
                    <p class="runtime-node-label">Provider Pool</p>
                    <p class="runtime-node-value">{{ providerHealthSummary }}</p>
                    <p class="runtime-node-hint">
                      {{ stats.normal_accounts }} normal / {{ pressuredAccounts }} pressured
                    </p>
                  </div>
                </div>

                <div class="mt-6 grid grid-cols-1 gap-3 md:grid-cols-3">
                  <div
                    v-for="model in topRuntimeModels"
                    :key="model.model"
                    class="rounded-md border border-gray-200 p-3 dark:border-gray-800"
                  >
                    <div class="mb-2 flex items-center justify-between gap-2">
                      <p class="truncate text-sm font-medium text-gray-900 dark:text-white">{{ model.model }}</p>
                      <span class="rounded-full bg-gray-100 px-2 py-0.5 text-xs text-gray-600 dark:bg-gray-900 dark:text-gray-400">
                        {{ model.requests }} req
                      </span>
                    </div>
                    <div class="h-1.5 rounded-full bg-gray-100 dark:bg-gray-900">
                      <div class="h-1.5 rounded-full bg-cyan-500" :style="{ width: `${model.share}%` }" />
                    </div>
                    <p class="mt-2 text-xs text-gray-500 dark:text-gray-400">
                      {{ formatTokens(model.total_tokens) }} tokens · {{ model.share }}%
                    </p>
                  </div>
                </div>
              </div>
            </div>
          </div>

          <div class="space-y-5">
            <div class="rounded-lg border border-gray-200 bg-white p-5 dark:border-gray-800 dark:bg-gray-950">
              <h2 class="text-base font-semibold text-gray-950 dark:text-white">Pressure</h2>
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
              <h2 class="text-base font-semibold text-gray-950 dark:text-white">Instrumentation</h2>
              <div class="mt-4 space-y-3">
                <div
                  v-for="item in instrumentationItems"
                  :key="item.label"
                  class="flex items-start justify-between gap-3 border-b border-gray-100 pb-3 last:border-0 last:pb-0 dark:border-gray-900"
                >
                  <div>
                    <p class="text-sm font-medium text-gray-900 dark:text-white">{{ item.label }}</p>
                    <p class="text-xs text-gray-500 dark:text-gray-400">{{ item.hint }}</p>
                  </div>
                  <span
                    class="shrink-0 rounded-full px-2 py-0.5 text-xs font-medium"
                    :class="item.ready ? 'bg-green-100 text-green-700 dark:bg-green-950 dark:text-green-300' : 'bg-amber-100 text-amber-700 dark:bg-amber-950 dark:text-amber-300'"
                  >
                    {{ item.ready ? 'live' : 'gap' }}
                  </span>
                </div>
              </div>
            </div>
          </div>
        </section>

        <section class="grid grid-cols-1 gap-5 xl:grid-cols-[minmax(320px,0.8fr)_minmax(0,1.2fr)]">
          <div class="rounded-lg border border-gray-200 bg-white p-5 dark:border-gray-800 dark:bg-gray-950">
            <div class="mb-4 flex items-center justify-between">
              <div>
                <h2 class="text-base font-semibold text-gray-950 dark:text-white">Runtime Timeline</h2>
                <p class="text-sm text-gray-500 dark:text-gray-400">Recent inferred runtime events.</p>
              </div>
              <button @click="router.push('/admin/ops')" class="text-sm font-medium text-primary-600 hover:text-primary-700">
                Details
              </button>
            </div>
            <div class="space-y-4">
              <div v-for="event in runtimeTimeline" :key="event.title" class="flex gap-3">
                <div class="mt-1 h-2 w-2 rounded-full" :class="event.dotClass" />
                <div>
                  <p class="text-sm font-medium text-gray-900 dark:text-white">{{ event.title }}</p>
                  <p class="text-xs text-gray-500 dark:text-gray-400">{{ event.detail }}</p>
                </div>
              </div>
            </div>
          </div>

          <div class="rounded-lg border border-gray-200 bg-white p-5 dark:border-gray-800 dark:bg-gray-950">
            <div class="mb-4 flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
              <div>
                <h2 class="text-base font-semibold text-gray-950 dark:text-white">Token Flow</h2>
                <p class="text-sm text-gray-500 dark:text-gray-400">Request and token volume for the selected window.</p>
              </div>
              <div class="w-28">
                <Select v-model="granularity" :options="granularityOptions" @change="loadChartData" />
              </div>
            </div>
            <TokenUsageTrend :trend-data="trendData" :loading="chartsLoading" />
          </div>
        </section>

        <section class="grid grid-cols-1 gap-5 lg:grid-cols-2">
          <div class="rounded-lg border border-gray-200 bg-white p-5 dark:border-gray-800 dark:bg-gray-950">
            <ModelDistributionChart
              :model-stats="modelStats"
              :enable-ranking-view="true"
              :ranking-items="rankingItems"
              :ranking-total-actual-cost="rankingTotalActualCost"
              :ranking-total-requests="rankingTotalRequests"
              :ranking-total-tokens="rankingTotalTokens"
              :ranking-loading="rankingLoading"
              :ranking-error="rankingError"
              @user-click="goToUserUsage"
            />
          </div>

          <div class="rounded-lg border border-gray-200 bg-white p-5 dark:border-gray-800 dark:bg-gray-950">
            <h2 class="mb-4 text-base font-semibold text-gray-950 dark:text-white">Workspace Demand</h2>
            <div v-if="userTrendLoading" class="flex h-64 items-center justify-center">
              <LoadingSpinner />
            </div>
            <div v-else-if="userTrendChartData" class="h-64">
              <Line :data="userTrendChartData" :options="lineOptions" />
            </div>
            <div v-else class="flex h-64 items-center justify-center text-gray-500 dark:text-gray-400">
              {{ t('common.noData') }}
            </div>
          </div>
        </section>
      </template>
    </div>
  </AppLayout>
</template>

<script setup lang="ts">
import { ref, computed, onMounted } from 'vue'
import { useI18n } from 'vue-i18n'
import { useRouter } from 'vue-router'
import { Line } from 'vue-chartjs'
import {
  Chart as ChartJS,
  CategoryScale,
  LinearScale,
  PointElement,
  LineElement,
  Tooltip,
  Legend,
  Filler
} from 'chart.js'
import { useAppStore } from '@/stores/app'
import { adminAPI } from '@/api/admin'
import type { OpsDashboardOverview } from '@/api/admin/ops'
import type {
  DashboardStats,
  TrendDataPoint,
  ModelStat,
  UserUsageTrendPoint,
  UserSpendingRankingItem
} from '@/types'
import AppLayout from '@/components/layout/AppLayout.vue'
import LoadingSpinner from '@/components/common/LoadingSpinner.vue'
import Icon from '@/components/icons/Icon.vue'
import DateRangePicker from '@/components/common/DateRangePicker.vue'
import Select from '@/components/common/Select.vue'
import ModelDistributionChart from '@/components/charts/ModelDistributionChart.vue'
import TokenUsageTrend from '@/components/charts/TokenUsageTrend.vue'

ChartJS.register(CategoryScale, LinearScale, PointElement, LineElement, Tooltip, Legend, Filler)

const { t } = useI18n()
const appStore = useAppStore()
const router = useRouter()

const stats = ref<DashboardStats | null>(null)
const opsOverview = ref<OpsDashboardOverview | null>(null)
const loading = ref(false)
const chartsLoading = ref(false)
const opsLoading = ref(false)
const userTrendLoading = ref(false)
const rankingLoading = ref(false)
const rankingError = ref(false)

const trendData = ref<TrendDataPoint[]>([])
const modelStats = ref<ModelStat[]>([])
const userTrend = ref<UserUsageTrendPoint[]>([])
const rankingItems = ref<UserSpendingRankingItem[]>([])
const rankingTotalActualCost = ref(0)
const rankingTotalRequests = ref(0)
const rankingTotalTokens = ref(0)
let chartLoadSeq = 0
let usersTrendLoadSeq = 0
let rankingLoadSeq = 0
const rankingLimit = 12
type RuntimeIconName = 'shield' | 'bolt' | 'clock' | 'cube' | 'server'
interface RuntimeMetric {
  label: string
  value: string
  hint: string
  icon: RuntimeIconName
  iconClass: string
  hintClass: string
}

const formatLocalDate = (date: Date): string => {
  return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}-${String(date.getDate()).padStart(2, '0')}`
}

const defaultEnd = new Date()
const defaultStart = new Date(defaultEnd.getTime() - 24 * 60 * 60 * 1000)
const granularity = ref<'day' | 'hour'>('hour')
const startDate = ref(formatLocalDate(defaultStart))
const endDate = ref(formatLocalDate(defaultEnd))

const granularityOptions = computed(() => [
  { value: 'day', label: t('admin.dashboard.day') },
  { value: 'hour', label: t('admin.dashboard.hour') }
])

const isDarkMode = computed(() => document.documentElement.classList.contains('dark'))
const chartColors = computed(() => ({
  text: isDarkMode.value ? '#e5e7eb' : '#374151',
  grid: isDarkMode.value ? '#374151' : '#e5e7eb'
}))

const lineOptions = computed(() => ({
  responsive: true,
  maintainAspectRatio: false,
  interaction: { intersect: false, mode: 'index' as const },
  plugins: {
    legend: {
      position: 'top' as const,
      labels: {
        color: chartColors.value.text,
        usePointStyle: true,
        pointStyle: 'circle',
        padding: 15,
        font: { size: 11 }
      }
    },
    tooltip: {
      itemSort: (a: any, b: any) => {
        const aValue = typeof a?.raw === 'number' ? a.raw : Number(a?.parsed?.y ?? 0)
        const bValue = typeof b?.raw === 'number' ? b.raw : Number(b?.parsed?.y ?? 0)
        return bValue - aValue
      },
      callbacks: {
        label: (context: any) => `${context.dataset.label}: ${formatTokens(context.raw)}`
      }
    }
  },
  scales: {
    x: {
      grid: { color: chartColors.value.grid },
      ticks: { color: chartColors.value.text, font: { size: 10 } }
    },
    y: {
      grid: { color: chartColors.value.grid },
      ticks: {
        color: chartColors.value.text,
        font: { size: 10 },
        callback: (value: string | number) => formatTokens(Number(value))
      }
    }
  }
}))

const currentErrorRate = computed(() => opsOverview.value?.error_rate ?? 0)
const currentP95Latency = computed(() => opsOverview.value?.duration?.p95_ms ?? stats.value?.average_duration_ms ?? 0)
const healthScore = computed(() => opsOverview.value?.health_score ?? null)
const pressuredAccounts = computed(() => {
  if (!stats.value) return 0
  return stats.value.error_accounts + stats.value.ratelimit_accounts + stats.value.overload_accounts
})

const runtimeStatus = computed(() => {
  const score = healthScore.value
  const errorRate = currentErrorRate.value
  if ((score !== null && score < 80) || errorRate >= 0.05 || pressuredAccounts.value > 0) {
    return { label: 'degraded', dotClass: 'bg-amber-500' }
  }
  return { label: 'healthy', dotClass: 'bg-green-500' }
})

const providerHealthSummary = computed(() => {
  if (!stats.value) return 'unknown'
  const total = Math.max(stats.value.total_accounts, 1)
  return `${Math.round((stats.value.normal_accounts / total) * 100)}% healthy`
})

const topRuntimeModels = computed(() => {
  const total = modelStats.value.reduce((sum, model) => sum + (model.total_tokens || 0), 0)
  return modelStats.value
    .slice()
    .sort((a, b) => (b.total_tokens || 0) - (a.total_tokens || 0))
    .slice(0, 3)
    .map((model) => ({
      ...model,
      share: total > 0 ? Math.max(3, Math.round(((model.total_tokens || 0) / total) * 100)) : 0
    }))
})

const runtimeMetrics = computed<RuntimeMetric[]>(() => {
  if (!stats.value) return []
  return [
    {
      label: 'Health',
      value: healthScore.value === null ? runtimeStatus.value.label : `${Math.round(healthScore.value)}/100`,
      hint: `${formatPercent(currentErrorRate.value)} error rate`,
      icon: 'shield',
      iconClass: 'text-green-500',
      hintClass: currentErrorRate.value > 0.03 ? 'text-amber-600 dark:text-amber-400' : 'text-gray-500 dark:text-gray-400'
    },
    {
      label: 'Traffic',
      value: `${formatTokens(stats.value.rpm)} RPM`,
      hint: `${formatTokens(stats.value.tpm)} TPM`,
      icon: 'bolt',
      iconClass: 'text-cyan-500',
      hintClass: 'text-gray-500 dark:text-gray-400'
    },
    {
      label: 'Latency',
      value: formatDuration(currentP95Latency.value),
      hint: `avg ${formatDuration(stats.value.average_duration_ms)}`,
      icon: 'clock',
      iconClass: 'text-rose-500',
      hintClass: currentP95Latency.value > 3000 ? 'text-amber-600 dark:text-amber-400' : 'text-gray-500 dark:text-gray-400'
    },
    {
      label: 'Token Pressure',
      value: formatTokens(stats.value.today_tokens),
      hint: `$${formatCost(stats.value.today_actual_cost)} actual today`,
      icon: 'cube',
      iconClass: 'text-indigo-500',
      hintClass: 'text-gray-500 dark:text-gray-400'
    },
    {
      label: 'Provider Pool',
      value: `${stats.value.normal_accounts}/${stats.value.total_accounts}`,
      hint: `${pressuredAccounts.value} pressured`,
      icon: 'server',
      iconClass: 'text-emerald-500',
      hintClass: pressuredAccounts.value > 0 ? 'text-amber-600 dark:text-amber-400' : 'text-gray-500 dark:text-gray-400'
    }
  ]
})

const pressureItems = computed(() => {
  if (!stats.value) return []
  const accountPressure = Math.min(100, Math.round((pressuredAccounts.value / Math.max(stats.value.total_accounts, 1)) * 100))
  const tokenPressure = Math.min(100, Math.round((stats.value.tpm / Math.max(stats.value.today_tokens / 60, 1)) * 20))
  const errorPressure = Math.min(100, Math.round(currentErrorRate.value * 1000))
  return [
    { label: 'Provider pressure', value: `${accountPressure}%`, percent: accountPressure, barClass: 'bg-amber-500' },
    { label: 'Token throughput', value: `${formatTokens(stats.value.tpm)} TPM`, percent: tokenPressure, barClass: 'bg-cyan-500' },
    { label: 'Retry / error pressure', value: formatPercent(currentErrorRate.value), percent: errorPressure, barClass: 'bg-rose-500' }
  ]
})

const instrumentationItems = computed(() => [
  {
    label: 'Routing telemetry',
    hint: opsOverview.value ? 'Ops overview is feeding health, QPS, TPS, and latency.' : 'Ops overview unavailable for this dashboard load.',
    ready: !!opsOverview.value
  },
  {
    label: 'Fallback chain',
    hint: 'Fallback events are inferred from error pressure; dedicated event stream is not instrumented yet.',
    ready: false
  },
  {
    label: 'Sticky sessions',
    hint: 'Sticky migration state needs a runtime session endpoint.',
    ready: false
  },
  {
    label: 'Workspace runtime',
    hint: 'Current dashboard only sees users/API keys, not workspace runtime objects.',
    ready: false
  }
])

const runtimeTimeline = computed(() => {
  if (!stats.value) return []
  const events = [
    {
      title: `${formatTokens(stats.value.rpm)} RPM flowing through gateway`,
      detail: `${formatTokens(stats.value.tpm)} tokens per minute, ${stats.value.active_users} active users.`,
      dotClass: 'bg-cyan-500'
    },
    {
      title: `${providerHealthSummary.value} provider pool health`,
      detail: `${stats.value.normal_accounts} normal accounts, ${pressuredAccounts.value} pressured accounts.`,
      dotClass: pressuredAccounts.value > 0 ? 'bg-amber-500' : 'bg-green-500'
    },
    {
      title: `p95 latency ${formatDuration(currentP95Latency.value)}`,
      detail: opsOverview.value ? 'Measured from ops telemetry.' : 'Falling back to dashboard average duration.',
      dotClass: currentP95Latency.value > 3000 ? 'bg-amber-500' : 'bg-green-500'
    },
    {
      title: 'Fallback chain not fully instrumented',
      detail: 'Add dedicated runtime events to explain timeout, fallback, retry, and sticky migration decisions.',
      dotClass: 'bg-amber-500'
    }
  ]
  return events
})

const userTrendChartData = computed(() => {
  if (!userTrend.value?.length) return null
  const userGroups = new Map<number, { name: string; data: Map<string, number> }>()
  const allDates = new Set<string>()
  userTrend.value.forEach((point) => {
    allDates.add(point.date)
    const name = point.username?.trim() || point.email?.trim() || t('admin.redeem.userPrefix', { id: point.user_id })
    if (!userGroups.has(point.user_id)) {
      userGroups.set(point.user_id, { name, data: new Map() })
    }
    userGroups.get(point.user_id)!.data.set(point.date, point.tokens)
  })
  const sortedDates = Array.from(allDates).sort()
  const colors = ['#0891b2', '#16a34a', '#f59e0b', '#dc2626', '#7c3aed', '#db2777']
  return {
    labels: sortedDates,
    datasets: Array.from(userGroups.values()).map((group, idx) => ({
      label: group.name,
      data: sortedDates.map((date) => group.data.get(date) || 0),
      borderColor: colors[idx % colors.length],
      backgroundColor: `${colors[idx % colors.length]}20`,
      fill: false,
      tension: 0.3
    }))
  }
})

const formatTokens = (value: number | undefined | null): string => {
  if (value === undefined || value === null) return '0'
  if (value >= 1_000_000_000) return `${(value / 1_000_000_000).toFixed(2)}B`
  if (value >= 1_000_000) return `${(value / 1_000_000).toFixed(2)}M`
  if (value >= 1_000) return `${(value / 1_000).toFixed(2)}K`
  return value.toLocaleString()
}

const formatNumber = (value: number): string => value.toLocaleString()

const formatCost = (value: number): string => {
  if (value >= 1000) return `${(value / 1000).toFixed(2)}K`
  if (value >= 1) return value.toFixed(2)
  if (value >= 0.01) return value.toFixed(3)
  return value.toFixed(4)
}

const formatDuration = (ms: number | undefined | null): string => {
  if (!ms) return '0ms'
  if (ms >= 1000) return `${(ms / 1000).toFixed(2)}s`
  return `${Math.round(ms)}ms`
}

const formatPercent = (value: number | undefined | null): string => `${(((value ?? 0) <= 1 ? (value ?? 0) * 100 : value ?? 0)).toFixed(2)}%`

const goToUserUsage = (item: UserSpendingRankingItem) => {
  void router.push({
    path: '/admin/usage',
    query: {
      user_id: String(item.user_id),
      start_date: startDate.value,
      end_date: endDate.value
    }
  })
}

const onDateRangeChange = (range: { startDate: string; endDate: string }) => {
  const start = new Date(range.startDate)
  const end = new Date(range.endDate)
  const daysDiff = Math.ceil((end.getTime() - start.getTime()) / (1000 * 60 * 60 * 24))
  granularity.value = daysDiff <= 1 ? 'hour' : 'day'
  loadChartData()
}

const loadOpsOverview = async () => {
  opsLoading.value = true
  try {
    opsOverview.value = await adminAPI.ops.getDashboardOverview({ time_range: '30m' })
  } catch (error) {
    console.error('Error loading ops overview:', error)
    opsOverview.value = null
  } finally {
    opsLoading.value = false
  }
}

const loadDashboardSnapshot = async (includeStats: boolean) => {
  const currentSeq = ++chartLoadSeq
  if (includeStats && !stats.value) loading.value = true
  chartsLoading.value = true
  try {
    const response = await adminAPI.dashboard.getSnapshotV2({
      start_date: startDate.value,
      end_date: endDate.value,
      granularity: granularity.value,
      include_stats: includeStats,
      include_trend: true,
      include_model_stats: true,
      include_group_stats: false,
      include_users_trend: false
    })
    if (currentSeq !== chartLoadSeq) return
    if (includeStats && response.stats) stats.value = response.stats
    trendData.value = response.trend || []
    modelStats.value = response.models || []
  } catch (error) {
    if (currentSeq !== chartLoadSeq) return
    appStore.showError(t('admin.dashboard.failedToLoad'))
    console.error('Error loading dashboard snapshot:', error)
  } finally {
    if (currentSeq === chartLoadSeq) {
      loading.value = false
      chartsLoading.value = false
    }
  }
}

const loadUsersTrend = async () => {
  const currentSeq = ++usersTrendLoadSeq
  userTrendLoading.value = true
  try {
    const response = await adminAPI.dashboard.getUserUsageTrend({
      start_date: startDate.value,
      end_date: endDate.value,
      granularity: granularity.value,
      limit: 8
    })
    if (currentSeq !== usersTrendLoadSeq) return
    userTrend.value = response.trend || []
  } catch (error) {
    if (currentSeq !== usersTrendLoadSeq) return
    console.error('Error loading users trend:', error)
    userTrend.value = []
  } finally {
    if (currentSeq === usersTrendLoadSeq) userTrendLoading.value = false
  }
}

const loadUserSpendingRanking = async () => {
  const currentSeq = ++rankingLoadSeq
  rankingLoading.value = true
  rankingError.value = false
  try {
    const response = await adminAPI.dashboard.getUserSpendingRanking({
      start_date: startDate.value,
      end_date: endDate.value,
      limit: rankingLimit
    })
    if (currentSeq !== rankingLoadSeq) return
    rankingItems.value = response.ranking || []
    rankingTotalActualCost.value = response.total_actual_cost || 0
    rankingTotalRequests.value = response.total_requests || 0
    rankingTotalTokens.value = response.total_tokens || 0
  } catch (error) {
    if (currentSeq !== rankingLoadSeq) return
    console.error('Error loading user spending ranking:', error)
    rankingItems.value = []
    rankingTotalActualCost.value = 0
    rankingTotalRequests.value = 0
    rankingTotalTokens.value = 0
    rankingError.value = true
  } finally {
    if (currentSeq === rankingLoadSeq) rankingLoading.value = false
  }
}

const loadDashboardStats = async () => {
  await Promise.all([
    loadDashboardSnapshot(true),
    loadUsersTrend(),
    loadUserSpendingRanking(),
    loadOpsOverview()
  ])
}

const loadChartData = async () => {
  await Promise.all([
    loadDashboardSnapshot(false),
    loadUsersTrend(),
    loadUserSpendingRanking(),
    loadOpsOverview()
  ])
}

onMounted(() => {
  loadDashboardStats()
})
</script>

<style scoped>
.runtime-node {
  min-height: 116px;
  border: 1px solid rgb(229 231 235);
  border-radius: 0.5rem;
  padding: 1rem;
}

.dark .runtime-node {
  border-color: rgb(31 41 55);
}

.runtime-node-accent {
  border-color: rgb(6 182 212 / 0.45);
  background: rgb(236 254 255 / 0.5);
}

.dark .runtime-node-accent {
  border-color: rgb(8 145 178 / 0.55);
  background: rgb(8 47 73 / 0.2);
}

.runtime-node-label {
  font-size: 0.75rem;
  font-weight: 600;
  color: rgb(107 114 128);
}

.runtime-node-value {
  margin-top: 0.5rem;
  font-size: 1rem;
  font-weight: 700;
  color: rgb(17 24 39);
}

.dark .runtime-node-value {
  color: white;
}

.runtime-node-hint {
  margin-top: 0.25rem;
  font-size: 0.75rem;
  color: rgb(107 114 128);
}

.runtime-edge {
  display: flex;
  align-items: center;
}

.runtime-edge span {
  display: block;
  width: 100%;
  height: 1px;
  background: linear-gradient(90deg, rgb(156 163 175), rgb(6 182 212));
}
</style>
