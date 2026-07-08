import { readFile } from 'node:fs/promises'

export type MacHostSpecs = {
  chip: string
  memoryBytes: number
  cpuCores: number
  recommendedMaxModelSizeGb: number
}

const HOST_SPECS_MARKER_PATH = '/app/storage/.nomad-host-specs'

// Docker Desktop's Linux VM, the admin/MySQL/Redis stack, and macOS itself all
// stand between "unified memory installed" and "memory Ollama can actually use
// for weights" — this is a rough reservation, not a measured value, since the
// admin container has no visibility into the host's real memory pressure.
const RESERVED_OVERHEAD_BYTES = 4 * 1024 ** 3
// Beyond raw weight size, inference needs headroom for KV cache/context — quantized
// models also compress unevenly, so this stays a conservative rule of thumb.
const USABLE_MEMORY_FRACTION = 0.6

/**
 * Reads the host hardware marker written by install_nomad_macos.sh
 * (chip name + true unified memory, captured via `sysctl` at install time).
 * Returns undefined on Linux installs, where the file doesn't exist.
 */
export async function getMacHostSpecs(): Promise<MacHostSpecs | undefined> {
  try {
    const raw = await readFile(HOST_SPECS_MARKER_PATH, 'utf8')
    const parsed = JSON.parse(raw) as { chip?: string; memoryBytes?: number; cpuCores?: number }

    if (!parsed.memoryBytes || parsed.memoryBytes <= 0) {
      return undefined
    }

    const usableBytes =
      Math.max(parsed.memoryBytes - RESERVED_OVERHEAD_BYTES, 0) * USABLE_MEMORY_FRACTION

    return {
      chip: parsed.chip || 'Apple Silicon',
      memoryBytes: parsed.memoryBytes,
      cpuCores: parsed.cpuCores || 0,
      recommendedMaxModelSizeGb: Math.round((usableBytes / 1024 ** 3) * 10) / 10,
    }
  } catch {
    return undefined
  }
}
