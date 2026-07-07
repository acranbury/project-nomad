import logger from '@adonisjs/core/services/logger'
import type { ApplicationService } from '@adonisjs/core/types'
import env from '#start/env'

/**
 * Pre-wires the AI Assistant to use the native, Metal-accelerated Ollama running on
 * the macOS host, so a fresh install "just works" without a manual settings trip.
 *
 * On macOS, Docker containers have no access to the Apple GPU, so install_nomad_macos.sh
 * installs Ollama natively via Homebrew instead of as a container, and sets
 * NOMAD_DEFAULT_OLLAMA_URL (typically http://host.docker.internal:11434) in compose.yml.
 * This provider seeds that value into the existing ai.remoteOllamaUrl KV setting — the
 * same setting the Settings page and Easy Setup wizard use for any remote/custom AI
 * backend — the first time the admin boots with no value already set.
 *
 * One-shot in effect: once ai.remoteOllamaUrl has any value (including one the user
 * later clears or changes), this provider never overwrites it again.
 */
export default class MacosOllamaAutoconfigProvider {
  constructor(protected app: ApplicationService) {}

  async boot() {
    if (this.app.getEnvironment() !== 'web') return

    const defaultOllamaUrl = env.get('NOMAD_DEFAULT_OLLAMA_URL')
    if (!defaultOllamaUrl) return

    setImmediate(async () => {
      try {
        const KVStore = (await import('#models/kv_store')).default

        const existing = await KVStore.getValue('ai.remoteOllamaUrl')
        if (existing) {
          logger.info(
            '[MacosOllamaAutoconfigProvider] ai.remoteOllamaUrl already set — leaving it untouched.'
          )
          return
        }

        await KVStore.setValue('ai.remoteOllamaUrl', defaultOllamaUrl)
        logger.info(
          `[MacosOllamaAutoconfigProvider] Pre-configured AI Assistant to use native Ollama at ${defaultOllamaUrl}`
        )
      } catch (err: any) {
        logger.error(
          `[MacosOllamaAutoconfigProvider] Failed to seed ai.remoteOllamaUrl: ${err?.message ?? err}`
        )
      }
    })
  }
}
