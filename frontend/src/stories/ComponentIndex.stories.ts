import type { Meta, StoryObj } from '@storybook/vue3-vite'
import { computed, defineComponent, ref } from 'vue'

const componentModules = import.meta.glob('../components/**/*.vue')
const components = Object.keys(componentModules)
  .map((path) => path.replace('../components/', ''))
  .sort((a, b) => a.localeCompare(b))

const ComponentIndex = defineComponent({
  setup() {
    const query = ref('')
    const filtered = computed(() => {
      const needle = query.value.trim().toLowerCase()
      if (!needle) return components
      return components.filter((path) => path.toLowerCase().includes(needle))
    })

    return { query, filtered, total: components.length }
  },
  template: `
    <section class="w-[min(920px,calc(100vw-48px))] space-y-5">
      <div class="space-y-1">
        <p class="text-xs font-semibold uppercase tracking-wider text-primary-600 dark:text-primary-400">Sub2API Frontend</p>
        <h1 class="text-2xl font-semibold text-gray-950 dark:text-white">Component import map</h1>
        <p class="max-w-2xl text-sm text-gray-600 dark:text-dark-300">
          Storybook is loading the Vue component tree from <code class="rounded bg-gray-100 px-1.5 py-0.5 dark:bg-dark-800">src/components/**/*.vue</code>.
        </p>
      </div>

      <input
        v-model="query"
        class="input max-w-md"
        placeholder="Filter components by path"
      />

      <div class="rounded-xl border border-gray-200 bg-white shadow-sm dark:border-dark-700 dark:bg-dark-900">
        <div class="border-b border-gray-200 px-4 py-3 text-sm text-gray-500 dark:border-dark-700 dark:text-dark-300">
          {{ filtered.length }} / {{ total }} components
        </div>
        <div class="max-h-[560px] divide-y divide-gray-100 overflow-auto dark:divide-dark-800">
          <div v-for="path in filtered" :key="path" class="flex items-center justify-between gap-4 px-4 py-2.5 text-sm">
            <code class="text-gray-800 dark:text-dark-100">{{ path }}</code>
            <span class="rounded-full bg-gray-100 px-2 py-0.5 text-xs text-gray-500 dark:bg-dark-800 dark:text-dark-300">Vue</span>
          </div>
        </div>
      </div>
    </section>
  `
})

const meta = {
  title: 'Project/Component Import Map',
  component: ComponentIndex,
  parameters: {
    layout: 'fullscreen'
  }
} satisfies Meta<typeof ComponentIndex>

export default meta

type Story = StoryObj<typeof meta>

export const AllComponents: Story = {}
