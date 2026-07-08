/**
 * Parses a human-readable model size string (as returned by the NOMAD models API,
 * e.g. "4.9GB", "500MB") into gigabytes. Returns 0 for unrecognized units so callers
 * can safely sort/compare without NaN propagating.
 */
export function parseModelSizeToGb(size: string): number {
  const trimmed = size.trim()
  const multiplier = trimmed.endsWith('TB')
    ? 1_000
    : trimmed.endsWith('GB')
      ? 1
      : trimmed.endsWith('MB')
        ? 1 / 1_000
        : trimmed.endsWith('KB')
          ? 1 / 1_000_000
          : 0

  const value = Number.parseFloat(trimmed)
  return Number.isFinite(value) ? value * multiplier : 0
}

/**
 * Returns a copy of `models` with each tag's `exceedsRecommendedMemory` flag set
 * against `recommendedMaxModelSizeGb`. Pass undefined to leave models untouched
 * (non-macOS hosts, where the budget isn't known).
 */
export function annotateModelsWithMemoryFit<
  T extends { tags: Array<{ size: string; exceedsRecommendedMemory?: boolean }> },
>(models: T[], recommendedMaxModelSizeGb: number | undefined): T[] {
  if (recommendedMaxModelSizeGb === undefined) {
    return models
  }

  return models.map((model) => ({
    ...model,
    tags: model.tags.map((tag) => ({
      ...tag,
      exceedsRecommendedMemory: parseModelSizeToGb(tag.size) > recommendedMaxModelSizeGb,
    })),
  }))
}
