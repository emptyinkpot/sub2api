import type { Meta, StoryObj } from '@storybook/vue3-vite'
import { computed, defineComponent, ref } from 'vue'
import BaseDialog from '@/components/common/BaseDialog.vue'
import ConfirmDialog from '@/components/common/ConfirmDialog.vue'
import DataTable from '@/components/common/DataTable.vue'
import EmptyState from '@/components/common/EmptyState.vue'
import Icon from '@/components/icons/Icon.vue'
import Input from '@/components/common/Input.vue'
import LoadingSpinner from '@/components/common/LoadingSpinner.vue'
import Pagination from '@/components/common/Pagination.vue'
import SearchInput from '@/components/common/SearchInput.vue'
import Select from '@/components/common/Select.vue'
import StatCard from '@/components/common/StatCard.vue'
import StatusBadge from '@/components/common/StatusBadge.vue'
import TextArea from '@/components/common/TextArea.vue'
import Toggle from '@/components/common/Toggle.vue'
import type { Column } from '@/components/common/types'

const DesignSystemWorkbench = defineComponent({
  components: {
    BaseDialog,
    ConfirmDialog,
    DataTable,
    EmptyState,
    Icon,
    Input,
    LoadingSpinner,
    Pagination,
    SearchInput,
    Select,
    StatCard,
    StatusBadge,
    TextArea,
    Toggle
  },
  setup() {
    const enabled = ref(true)
    const query = ref('')
    const provider = ref('openai')
    const page = ref(1)
    const pageSize = ref(10)
    const dialogOpen = ref(false)
    const confirmOpen = ref(false)

    const options = [
      { value: 'openai', label: 'OpenAI compatible' },
      { value: 'anthropic', label: 'Anthropic' },
      { value: 'gemini', label: 'Gemini' },
      { value: 'antigravity', label: 'Antigravity' }
    ]

    const columns: Column[] = [
      { key: 'name', label: 'Provider', sortable: true },
      { key: 'platform', label: 'Platform', sortable: true },
      { key: 'status', label: 'Status' },
      { key: 'latency', label: 'Latency', formatter: (value) => `${value} ms` }
    ]

    const rows = [
      { id: 1, name: 'openoneai', platform: 'openai', status: 'active', latency: 842 },
      { id: 2, name: 'gemini-oauth', platform: 'gemini', status: 'warning', latency: 1204 },
      { id: 3, name: 'antigravity-lab', platform: 'antigravity', status: 'inactive', latency: 0 }
    ]

    const filteredRows = computed(() => {
      const needle = query.value.trim().toLowerCase()
      if (!needle) return rows
      return rows.filter((row) => `${row.name} ${row.platform} ${row.status}`.includes(needle))
    })

    const swatches = [
      ['primary-500', 'bg-primary-500'],
      ['primary-700', 'bg-primary-700'],
      ['emerald-500', 'bg-emerald-500'],
      ['amber-500', 'bg-amber-500'],
      ['red-500', 'bg-red-500'],
      ['dark-800', 'bg-dark-800']
    ]

    return {
      columns,
      confirmOpen,
      dialogOpen,
      enabled,
      filteredRows,
      options,
      page,
      pageSize,
      provider,
      query,
      swatches
    }
  },
  template: `
    <main class="min-h-screen bg-gray-50 p-6 text-gray-950 dark:bg-dark-950 dark:text-white">
      <section class="mx-auto grid w-full max-w-7xl gap-6">
        <header class="flex flex-wrap items-end justify-between gap-4">
          <div>
            <p class="text-xs font-semibold uppercase tracking-wider text-primary-600 dark:text-primary-400">Sub2API Design System</p>
            <h1 class="mt-1 text-2xl font-semibold">Frontend component workbench</h1>
          </div>
          <div class="flex flex-wrap items-center gap-2">
            <button class="btn btn-secondary btn-sm" @click="dialogOpen = true">
              <Icon name="grid" size="sm" />
              Dialog
            </button>
            <button class="btn btn-danger btn-sm" @click="confirmOpen = true">
              <Icon name="trash" size="sm" />
              Confirm
            </button>
          </div>
        </header>

        <section class="grid gap-4 md:grid-cols-3">
          <StatCard title="Active accounts" :value="128" icon-variant="primary" :change="8.4" change-type="up" />
          <StatCard title="Daily spend" value="$42.80" icon-variant="success" :change="3.1" change-type="down" />
          <StatCard title="Queue latency" value="842 ms" icon-variant="warning" :change="0" change-type="neutral" />
        </section>

        <section class="grid gap-6 lg:grid-cols-[360px_1fr]">
          <aside class="grid gap-4">
            <div class="card p-5">
              <h2 class="text-sm font-semibold text-gray-900 dark:text-white">Tokens</h2>
              <div class="mt-4 grid grid-cols-2 gap-3">
                <div v-for="[name, colorClass] in swatches" :key="name" class="rounded-xl border border-gray-200 p-3 dark:border-dark-700">
                  <div :class="['h-10 rounded-lg', colorClass]"></div>
                  <p class="mt-2 text-xs text-gray-600 dark:text-dark-300">{{ name }}</p>
                </div>
              </div>
            </div>

            <div class="card p-5">
              <h2 class="text-sm font-semibold text-gray-900 dark:text-white">Form controls</h2>
              <div class="mt-4 grid gap-4">
                <Input model-value="openoneai" label="Name" placeholder="Provider name" hint="Use Input for text values." />
                <Select v-model="provider" :options="options" searchable />
                <TextArea model-value="Primary OpenAI-compatible route" label="Notes" />
                <div class="flex items-center justify-between rounded-xl bg-gray-50 px-4 py-3 dark:bg-dark-800">
                  <span class="text-sm font-medium text-gray-700 dark:text-dark-100">Enabled</span>
                  <Toggle v-model="enabled" />
                </div>
              </div>
            </div>
          </aside>

          <section class="grid gap-4">
            <div class="card p-5">
              <div class="flex flex-wrap items-center justify-between gap-4">
                <div>
                  <h2 class="text-sm font-semibold text-gray-900 dark:text-white">List pattern</h2>
                  <p class="mt-1 text-xs text-gray-500 dark:text-dark-300">Actions, filters, table, pagination, and explicit empty/loading states.</p>
                </div>
                <div class="w-full max-w-xs">
                  <SearchInput v-model="query" placeholder="Search providers" />
                </div>
              </div>

              <div class="mt-4 overflow-hidden rounded-xl border border-gray-200 dark:border-dark-700">
                <DataTable :columns="columns" :data="filteredRows" row-key="id">
                  <template #cell-status="{ row }">
                    <StatusBadge :status="row.status" :label="row.status" />
                  </template>
                  <template #empty>
                    <EmptyState title="No providers" description="Adjust filters or create a provider route." action-text="Create route" />
                  </template>
                </DataTable>
                <Pagination v-model:page="page" v-model:page-size="pageSize" :total="128" />
              </div>
            </div>

            <div class="grid gap-4 md:grid-cols-3">
              <div class="card p-5">
                <StatusBadge status="active" label="Active" />
              </div>
              <div class="card p-5">
                <StatusBadge status="warning" label="Warning" />
              </div>
              <div class="card p-5">
                <div class="flex items-center gap-3">
                  <LoadingSpinner size="sm" />
                  <span class="text-sm text-gray-600 dark:text-dark-300">Loading</span>
                </div>
              </div>
            </div>
          </section>
        </section>
      </section>

      <BaseDialog :show="dialogOpen" title="Standard dialog" width="normal" @close="dialogOpen = false">
        <p class="text-sm text-gray-600 dark:text-dark-300">Use BaseDialog for forms and multi-step interaction surfaces.</p>
        <template #footer>
          <div class="flex justify-end gap-3">
            <button class="btn btn-secondary" @click="dialogOpen = false">Cancel</button>
            <button class="btn btn-primary" @click="dialogOpen = false">Save</button>
          </div>
        </template>
      </BaseDialog>

      <ConfirmDialog
        :show="confirmOpen"
        title="Delete route"
        message="This demonstrates the destructive confirmation pattern."
        confirm-text="Delete"
        cancel-text="Cancel"
        danger
        @confirm="confirmOpen = false"
        @cancel="confirmOpen = false"
      />
    </main>
  `
})

const meta = {
  title: 'Design System/Workbench',
  component: DesignSystemWorkbench,
  parameters: {
    layout: 'fullscreen'
  }
} satisfies Meta<typeof DesignSystemWorkbench>

export default meta

type Story = StoryObj<typeof meta>

export const Overview: Story = {}
