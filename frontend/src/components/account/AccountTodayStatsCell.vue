<template>
  <div class="max-w-full overflow-hidden">
    <!-- Loading state -->
    <div v-if="props.loading && !props.stats" class="space-y-0.5">
      <div class="h-3 w-12 animate-pulse rounded bg-gray-200 dark:bg-gray-700"></div>
      <div class="h-3 w-16 animate-pulse rounded bg-gray-200 dark:bg-gray-700"></div>
      <div class="h-3 w-10 animate-pulse rounded bg-gray-200 dark:bg-gray-700"></div>
    </div>

    <!-- Error state -->
    <div v-else-if="props.error && !props.stats" class="max-w-full truncate text-xs text-red-500" :title="props.error">
      {{ props.error }}
    </div>

    <!-- Stats data -->
    <div v-else-if="props.stats && props.compact" class="flex max-w-full flex-wrap items-center gap-1 overflow-hidden text-[10px] leading-tight">
      <span class="rounded bg-gray-100 px-1 py-px font-medium text-gray-700 dark:bg-dark-700 dark:text-gray-300" :title="t('admin.accounts.stats.requests')">
        {{ formatNumber(props.stats.requests) }} req
      </span>
      <span class="rounded bg-gray-100 px-1 py-px font-medium text-gray-700 dark:bg-dark-700 dark:text-gray-300" :title="t('admin.accounts.stats.tokens')">
        {{ formatTokens(props.stats.tokens) }}
      </span>
      <span class="rounded bg-emerald-50 px-1 py-px font-medium text-emerald-600 dark:bg-emerald-900/30 dark:text-emerald-400" :title="t('usage.accountBilled')">
        A {{ formatCurrency(props.stats.cost) }}
      </span>
      <span
        v-if="props.stats.user_cost != null"
        class="rounded bg-gray-100 px-1 py-px font-medium text-gray-700 dark:bg-dark-700 dark:text-gray-300"
        :title="t('usage.userBilled')"
      >
        U {{ formatCurrency(props.stats.user_cost) }}
      </span>
    </div>

    <div v-else-if="props.stats" class="max-w-full space-y-0.5 overflow-hidden text-xs">
      <!-- Requests -->
      <div class="flex min-w-0 items-center gap-1">
        <span class="flex-shrink-0 text-gray-500 dark:text-gray-400"
          >{{ t('admin.accounts.stats.requests') }}:</span
        >
        <span class="min-w-0 truncate font-medium text-gray-700 dark:text-gray-300">{{
          formatNumber(props.stats.requests)
        }}</span>
      </div>
      <!-- Tokens -->
      <div class="flex min-w-0 items-center gap-1">
        <span class="flex-shrink-0 text-gray-500 dark:text-gray-400"
          >{{ t('admin.accounts.stats.tokens') }}:</span
        >
        <span class="min-w-0 truncate font-medium text-gray-700 dark:text-gray-300">{{
          formatTokens(props.stats.tokens)
        }}</span>
      </div>
      <!-- Cost (Account) -->
      <div class="flex min-w-0 items-center gap-1">
        <span class="flex-shrink-0 text-gray-500 dark:text-gray-400">{{ t('usage.accountBilled') }}:</span>
        <span class="min-w-0 truncate font-medium text-emerald-600 dark:text-emerald-400">{{
          formatCurrency(props.stats.cost)
        }}</span>
      </div>
      <!-- Cost (User/API Key) -->
      <div v-if="props.stats.user_cost != null" class="flex min-w-0 items-center gap-1">
        <span class="flex-shrink-0 text-gray-500 dark:text-gray-400">{{ t('usage.userBilled') }}:</span>
        <span class="min-w-0 truncate font-medium text-gray-700 dark:text-gray-300">{{
          formatCurrency(props.stats.user_cost)
        }}</span>
      </div>
    </div>

    <!-- No data -->
    <div v-else class="text-xs text-gray-400">-</div>
  </div>
</template>

<script setup lang="ts">
import { useI18n } from 'vue-i18n'
import type { WindowStats } from '@/types'
import { formatNumber, formatCurrency } from '@/utils/format'

const props = withDefaults(
  defineProps<{
    stats?: WindowStats | null
    loading?: boolean
    error?: string | null
    compact?: boolean
  }>(),
  {
    stats: null,
    loading: false,
    error: null,
    compact: false
  }
)

const { t } = useI18n()

// Format large token numbers (e.g., 1234567 -> 1.23M)
const formatTokens = (tokens: number): string => {
  if (tokens >= 1000000) {
    return `${(tokens / 1000000).toFixed(2)}M`
  } else if (tokens >= 1000) {
    return `${(tokens / 1000).toFixed(1)}K`
  }
  return tokens.toString()
}
</script>
