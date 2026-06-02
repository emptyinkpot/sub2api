import type { Meta, StoryObj } from '@storybook/vue3-vite'
import { defineComponent, ref } from 'vue'
import Input from '@/components/common/Input.vue'
import Toggle from '@/components/common/Toggle.vue'
import StatusBadge from '@/components/common/StatusBadge.vue'
import LoadingSpinner from '@/components/common/LoadingSpinner.vue'
import Select from '@/components/common/Select.vue'
import PlatformTypeBadge from '@/components/common/PlatformTypeBadge.vue'

const Surface = defineComponent({
  components: { Input, Toggle, StatusBadge, LoadingSpinner, Select, PlatformTypeBadge },
  props: {
    label: { type: String, default: 'Account name' },
    placeholder: { type: String, default: 'openoneai' },
    hint: { type: String, default: 'Editable controls are wired through Storybook args.' },
    error: { type: String, default: '' },
    disabled: { type: Boolean, default: false },
    status: { type: String, default: 'active' },
    statusLabel: { type: String, default: 'Active' },
    platform: { type: String, default: 'openai' },
    accountType: { type: String, default: 'apikey' },
    spinnerSize: { type: String, default: 'md' }
  },
  setup() {
    const value = ref('openoneai')
    const enabled = ref(true)
    const selected = ref('openai')
    const options = [
      { value: 'openai', label: 'OpenAI' },
      { value: 'anthropic', label: 'Anthropic' },
      { value: 'gemini', label: 'Gemini' },
      { value: 'antigravity', label: 'Antigravity' }
    ]
    return { value, enabled, selected, options }
  },
  template: `
    <div class="w-[min(720px,calc(100vw-48px))] space-y-6">
      <div class="space-y-1">
        <h2 class="text-xl font-semibold text-gray-950 dark:text-white">Common component workbench</h2>
        <p class="text-sm text-gray-500 dark:text-dark-300">Use the Controls panel to edit props and inspect states without loading the whole app.</p>
      </div>

      <div class="grid gap-5 rounded-xl border border-gray-200 bg-white p-5 shadow-sm dark:border-dark-700 dark:bg-dark-900 md:grid-cols-2">
        <Input v-model="value" :label="label" :placeholder="placeholder" :hint="hint" :error="error" :disabled="disabled" />
        <div class="space-y-4">
          <div class="flex items-center justify-between rounded-lg bg-gray-50 px-4 py-3 dark:bg-dark-800">
            <span class="text-sm font-medium text-gray-700 dark:text-dark-100">Schedulable</span>
            <Toggle v-model="enabled" />
          </div>
          <Select v-model="selected" :options="options" searchable />
        </div>
      </div>

      <div class="flex flex-wrap items-center gap-6 rounded-xl border border-gray-200 bg-white p-5 shadow-sm dark:border-dark-700 dark:bg-dark-900">
        <StatusBadge :status="status" :label="statusLabel" />
        <PlatformTypeBadge :platform="platform" :type="accountType" plan-type="plus" privacy-mode="training_off" />
        <LoadingSpinner :size="spinnerSize" />
      </div>
    </div>
  `
})

const meta = {
  title: 'Components/Common/Workbench',
  component: Surface,
  argTypes: {
    status: { control: 'select', options: ['active', 'inactive', 'warning', 'error', 'success'] },
    platform: { control: 'select', options: ['openai', 'anthropic', 'gemini', 'antigravity'] },
    accountType: { control: 'select', options: ['apikey', 'oauth', 'setup-token', 'service_account'] },
    spinnerSize: { control: 'select', options: ['sm', 'md', 'lg', 'xl'] }
  }
} satisfies Meta<typeof Surface>

export default meta

type Story = StoryObj<typeof meta>

export const Editable: Story = {
  args: {
    label: 'Account name',
    placeholder: 'openoneai',
    hint: 'This story imports real components from src/components/common.',
    error: '',
    disabled: false,
    status: 'active',
    statusLabel: 'Active',
    platform: 'openai',
    accountType: 'apikey',
    spinnerSize: 'md'
  }
}
