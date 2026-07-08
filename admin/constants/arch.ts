/**
 * Catalog images with no published linux/arm64 manifest, audited manually against
 * their registries (Docker Hub / GHCR) on 2026-07-08. Every other pinned image in
 * service_seeder.ts is already multi-arch. Re-audit when bumping a pinned tag here.
 *
 * excalidraw/excalidraw: the only non-`latest` tags on Docker Hub are old `sha-*`
 * CI builds (2021, amd64-only) — there's no versioned multi-arch tag to pin to instead.
 * On Apple Silicon / arm64 hosts, Docker Desktop's Rosetta 2 emulation runs it fine
 * (it's a lightweight static web UI), just slower to start than a native image.
 */
export const AMD64_ONLY_CATALOG_IMAGES = ['excalidraw/excalidraw']

export function isAmd64OnlyImage(containerImage: string | null | undefined): boolean {
  if (!containerImage) {
    return false
  }
  return AMD64_ONLY_CATALOG_IMAGES.some((image) => containerImage.startsWith(`${image}:`))
}
