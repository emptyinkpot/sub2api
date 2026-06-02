import type { StorybookConfig } from "@storybook/vue3-vite"
import { mergeConfig } from "vite"
import { fileURLToPath } from "url"
import { dirname, resolve } from "path"

const storybookDir = dirname(fileURLToPath(import.meta.url))

const config: StorybookConfig = {
  core: {
    allowedHosts: ["localhost", "127.0.0.1"]
  },
  stories: ["../src/**/*.stories.ts", "../src/**/*.stories.tsx", "../src/**/*.stories.js", "../src/**/*.stories.mjs"],
  framework: {
    name: "@storybook/vue3-vite",
    options: {}
  },
  viteFinal: async (config) => {
    config.plugins = config.plugins?.filter((plugin) => {
      if (!plugin || typeof plugin !== "object" || !("name" in plugin)) {
        return true
      }

      const name = (plugin as { name?: string }).name
      return name !== "vite-plugin-checker"
    })

    return mergeConfig(config, {
      server: {
        allowedHosts: ["localhost", "127.0.0.1"]
      },
      resolve: {
        alias: {
          "@": resolve(storybookDir, "../src"),
          "vue-i18n": "vue-i18n/dist/vue-i18n.runtime.esm-bundler.js"
        }
      },
      define: {
        __INTLIFY_JIT_COMPILATION__: true
      }
    })
  }
}

export default config
