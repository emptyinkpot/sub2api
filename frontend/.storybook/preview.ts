import type { Preview } from '@storybook/vue3-vite'
import { setup } from '@storybook/vue3-vite'
import { createPinia } from 'pinia'
import i18n, { initI18n } from '../src/i18n'
import '../src/style.css'

const pinia = createPinia()

window.__APP_CONFIG__ = {
  site_name: 'Sub2API Storybook',
  site_logo: '',
  site_version: 'storybook',
  contact_info: '',
  api_base_url: '',
  doc_url: '',
  backend_mode_enabled: false
}

setup(async (app) => {
  app.use(pinia)
  await initI18n()
  app.use(i18n)
})

const preview: Preview = {
  parameters: {
    controls: {
      matchers: {
        color: /(background|color)$/i,
        date: /Date$/i
      }
    },
    layout: 'centered'
  },
  globalTypes: {
    theme: {
      description: 'Preview theme',
      defaultValue: 'light',
      toolbar: {
        title: 'Theme',
        icon: 'circlehollow',
        items: [
          { value: 'light', title: 'Light' },
          { value: 'dark', title: 'Dark' }
        ],
        dynamicTitle: true
      }
    }
  },
  decorators: [
    (story, context) => {
      document.documentElement.classList.toggle('dark', context.globals.theme === 'dark')
      return {
        components: { story },
        template: '<div class="min-h-screen min-w-[360px] bg-gray-50 p-6 text-gray-900 dark:bg-dark-950 dark:text-gray-100"><story /></div>'
      }
    }
  ]
}

export default preview
