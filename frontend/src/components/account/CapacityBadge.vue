<script setup lang="ts">
defineProps<{
  colorClass: string
  tooltip?: string
  current: string | number
  max: string | number
  suffix?: string
}>()
</script>

<template>
  <span
    :class="[
      'inline-flex max-w-full items-center gap-0.5 overflow-hidden rounded-md px-1 py-px text-[10px] font-medium leading-tight',
      colorClass
    ]"
    :title="tooltip"
  >
    <slot />
    <span class="min-w-0 truncate font-mono">{{ current }}</span>
    <span class="text-gray-400 dark:text-gray-500">/</span>
    <span class="min-w-0 truncate font-mono">{{ max }}</span>
    <span v-if="suffix" class="flex-shrink-0 text-[9px] opacity-60">{{ suffix }}</span>
  </span>
</template>
