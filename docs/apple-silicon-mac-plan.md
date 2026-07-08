# Plan: Apple Silicon (macOS) Support for Project N.O.M.A.D.

Goal: let someone with an Apple Silicon Mac (e.g. an M-series Mac Mini) install
N.O.M.A.D. with a single copy-paste command — same "simple install" experience as
Debian — while the local LLM runs **natively on macOS with Metal acceleration**
instead of inside a container.

## The one architectural decision that shapes everything

**On macOS, Docker containers run inside a Linux VM and have no access to the
Apple GPU.** There is no Metal equivalent of the NVIDIA Container Toolkit — an
`ollama/ollama` container on a Mac is CPU-only, full stop. So the current model
("the admin container installs an Ollama container via the Docker socket") cannot
deliver good LLM performance on a Mac.

The fix does not require re-architecting anything, because the escape hatch
already exists: the admin supports an external Ollama/OpenAI-compatible endpoint
via the `ai.remoteOllamaUrl` KV setting (`admin/app/services/ollama_service.ts:64`,
settings UI in `admin/inertia/pages/settings/models.tsx`, Easy Setup wizard in
`admin/inertia/pages/easy-setup/index.tsx:382`). Model pulls from the NOMAD UI
still work against a native Ollama because `OllamaService` detects a real Ollama
API (`isOllamaNative`, `ollama_service.ts:723`) — only non-Ollama backends like
LM Studio lose UI-driven pulls.

**Target macOS architecture:**

| Component | Where it runs |
|---|---|
| Ollama (LLM) | **Native macOS app/service** — Metal acceleration automatic |
| Admin, MySQL, Redis, updater, Kiwix, Kolibri, Qdrant, all Supply Depot apps | Docker containers (linux/arm64), unchanged |
| Admin → Ollama connection | `ai.remoteOllamaUrl = http://host.docker.internal:11434`, pre-configured by the installer |

Everything except Ollama stays containerized, so the orchestration model
(admin talks to the Docker socket, `docker_service.ts`) is untouched.

---

## Workstream A — Publish arm64 images (prerequisite for everything)

The three NOMAD-built images are currently amd64-only: none of
`build-primary-image.yml`, `build-sidecar-updater.yml`, or
`build-disk-collector.yml` pass a `platforms:` input to `docker/build-push-action`.
The admin `Dockerfile` is already arm64-aware (per-arch `TARGETARCH` handling and
a pinned arm64 SHA for go-pmtiles), so most of this work is CI plumbing.
This overlaps with the ARM64 effort already referenced by the installer's
architecture warning (`install_nomad.sh:89`, "tracked in PR #419") — coordinate
rather than duplicate.

1. Add `platforms: linux/amd64,linux/arm64` (+ QEMU/buildx setup, or native
   `ubuntu-24.04-arm` runners for speed) to all three build workflows so
   `ghcr.io/crosstalk-solutions/project-nomad{,-sidecar-updater,-disk-collector}`
   become multi-arch manifests. `:latest` pulls then Just Work on a Mac.
2. Verify native-module deps build on arm64 in the admin image: `sharp`/libvips,
   `graphicsmagick`, anything with a postinstall compile step.
3. Audit the seeded app catalog (`admin/database/seeders/service_seeder.ts`) for
   arm64 availability of each pinned tag (kiwix-serve, qdrant, cyberchef,
   flatnotes, kolibri, s-pdf, filebrowser, calibre-web, it-tools, excalidraw,
   meshtastic/meshcore web, homebox, vaultwarden, jellyfin). Most are multi-arch;
   for any amd64-only stragglers, either bump to a multi-arch tag or rely on
   Docker Desktop's Rosetta 2 x86 emulation (fine for these lightweight web UIs)
   and flag them in the UI as emulated.

## Workstream B — macOS installer: `install/install_nomad_macos.sh`

A sibling script to `install_nomad.sh`, keeping the same UX (one curl command,
confirmation, license acceptance, success banner). The Linux script cannot be
reused as-is: it checks `/etc/debian_version`, uses `apt-get`, `systemctl`,
`hostname -I`, GNU `sed -i`, `get.docker.com`, and the NVIDIA toolkit flow —
all Linux-isms. New script responsibilities:

1. **Pre-flight**: assert `uname -s` = Darwin and `uname -m` = arm64; assert
   macOS ≥ 14; no sudo required for the happy path.
2. **Docker runtime**: detect `docker` CLI + a running daemon. If absent, install
   via Homebrew (`brew install --cask docker` — installing Homebrew first if
   needed) and prompt the user through Docker Desktop's one-time first launch
   (it needs GUI consent for its privileged helper; a script can't fully silence
   that). Support OrbStack/Colima transparently by only checking "does
   `docker info` work", not which product provides it.
3. **Native Ollama with Metal**: `brew install ollama && brew services start ollama`
   (registers a launchd service so it survives reboots). Metal is used
   automatically by the native binary — no configuration needed. Verify with a
   `curl http://localhost:11434/api/version` check. Skip entirely if Ollama is
   already installed/running (the Linux port-conflict headache in
   `docker_service.ts:497` becomes the *expected* state on macOS).
4. **Install directory**: default to `~/nomad` (or
   `~/Library/Application Support/project-nomad`) instead of `/opt/project-nomad`.
   This matters beyond permissions: Docker Desktop's VirtioFS file sharing only
   covers `/Users`, `/Volumes`, `/private`, `/tmp` by default — bind mounts from
   `/opt` fail until the user manually adds it in Docker Desktop settings.
   Staying under `$HOME` keeps the install zero-config. Set
   `NOMAD_STORAGE_PATH` accordingly (the compose file and admin already support
   relocated storage — see `management_compose.yaml:21-28`).
5. **Compose file rendering**: same download-and-substitute flow, but with BSD
   `sed -i ''` syntax (or switch both platforms to a `sed`-free approach), local
   IP via `ipconfig getifaddr en0` (falling back through interfaces) instead of
   `hostname -I`, and a macOS compose overlay (see Workstream C).
6. **GPU marker**: write `metal` to `storage/.nomad-gpu-type` (today the script
   writes `nvidia`/`amd`, `install_nomad.sh:563`) so the admin can present
   accurate acceleration status. Skip all lspci/NVIDIA/ROCm logic.
7. **Pre-wire the AI assistant**: seed `ai.remoteOllamaUrl` to
   `http://host.docker.internal:11434` so the AI Assistant works out of the box
   with the Metal-backed Ollama. Cleanest mechanism: an env var (e.g.
   `NOMAD_DEFAULT_OLLAMA_URL`) in the compose file that the admin reads on first
   boot and persists into the KV store if the key is unset — avoids the installer
   having to poke MySQL directly. `host.docker.internal` resolves to the Mac host
   on Docker Desktop and OrbStack without extra config (the `extra_hosts`
   host-gateway entry in the compose file is only needed on Linux and is harmless
   here).
8. **Start on boot**: Docker Desktop/OrbStack "start at login" plus the existing
   `restart: unless-stopped` policies cover the management stack; `brew services`
   covers Ollama. The installer should verify/instruct on the "start at login"
   setting. Optionally ship a LaunchAgent that runs `start_nomad.sh` at login as
   a belt-and-suspenders (the script itself is portable — plain `docker start`).
9. **Helper scripts**: `start_nomad.sh` / `stop_nomad.sh` are already portable.
   `update_nomad.sh` and `uninstall_nomad.sh` need the same path +
   BSD-sed + no-systemd treatment.

README gets a parallel quick-install block:

```bash
curl -fsSL https://raw.githubusercontent.com/Crosstalk-Solutions/project-nomad/refs/heads/main/install/install_nomad_macos.sh \
  -o install_nomad_macos.sh && bash install_nomad_macos.sh
```

## Workstream C — Admin app: macOS awareness

Small, targeted changes; the orchestration core is untouched.

1. **Host OS signal**: have the macOS installer set `NOMAD_HOST_OS=darwin` in the
   compose environment (detection from inside the Linux VM is otherwise
   unreliable). Expose it via `system_service`.
2. **Easy Setup wizard** (`easy-setup/index.tsx`): when host is macOS, the AI
   Assistant step should default to the pre-configured native Ollama (remote URL
   path) instead of offering to install the Ollama *container*, with copy
   explaining that native = Metal-accelerated. Keep the container as an explicit
   "advanced / CPU-only" fallback rather than the default.
3. **Ollama container guardrail** (`docker_service.ts:715`): `_detectGPUType()`
   on macOS should return a `metal`/host-native indication (from the
   `.nomad-gpu-type` marker) and the install path should warn that a containerized
   Ollama will be CPU-only on this platform.
4. **Copy fixes**: the port-11434-conflict message (`docker_service.ts:497`)
   suggests `sudo systemctl stop ollama` — needs a macOS variant
   (`brew services stop ollama`), and on macOS that conflict usually means
   "you're already set up correctly, use the remote URL".
5. **Model storage/disk UI**: with native Ollama, models live in `~/.ollama` on
   the host, not `storage/ollama` — anywhere the UI reports model disk usage from
   the storage tree needs to handle the remote/native case (it already must for
   the existing remote-Ollama feature, so this is mostly verification).
6. **Benchmark** (`benchmark_service.ts`): verify it measures through the Ollama
   API (works fine remotely) and label results as Metal/Apple Silicon rather than
   CPU-only so leaderboard entries are honest.

## Workstream D — Disk collector on macOS

`nomad_disk_collector` mounts `/:/host:ro,rslave` (`management_compose.yaml:119`).
Inside Docker Desktop that shows the **Linux VM's** filesystem, not the Mac's
disk, and `rslave` propagation is a Linux-ism — numbers would be wrong or the
container may not start. Options, in order of preference:

1. macOS compose overlay drops the `/` mount and the collector reports `statvfs`
   on the storage bind mount only (VirtioFS reports real host-disk capacity
   there). Slightly reduced detail, correct numbers, no host-side agent.
2. Longer-term: a tiny host-side collector (launchd job writing JSON into
   `storage/`) if per-volume detail is wanted.

The admin should degrade gracefully in the UI when only storage-volume stats are
available.

## Workstream E — Docs & requirements

- README: add macOS to supported platforms, quick-install block, and a
  requirements note (Apple Silicon, macOS 14+, 16 GB unified memory minimum /
  32 GB+ recommended, since GPU and system RAM are shared — a 16 GB Mac Mini
  comfortably runs 7–8B Q4 models, 32 GB+ for 13B+).
- FAQ: why Ollama runs natively on macOS (no GPU passthrough into containers),
  how to point NOMAD at LM Studio instead, and Docker Desktop vs OrbStack notes.
- Update the WSL2-style community install guide pattern with a macOS page.

## Suggested sequencing

1. **A** (multi-arch images) — nothing works without it; also unblocks generic
   ARM64 Linux (Raspberry Pi 5, etc.) as a side effect.
2. **B** (installer) + minimum of **C** (remote-URL pre-wiring, port-conflict
   copy) — this alone delivers a working Metal-accelerated Mac install, because
   the remote-Ollama plumbing already exists.
3. **C** polish (wizard defaults, GPU status) + **D** (disk collector).
4. **E** docs alongside each release.

## Risks / open questions

- **Docker Desktop first-run** cannot be fully automated (GUI consent for the
  privileged helper). The installer should detect-and-guide rather than promise
  silent install. OrbStack is friendlier to scripting; worth recommending.
- **amd64-only catalog apps**: Rosetta emulation covers them, but it must be
  enabled in Docker Desktop (default ON in recent versions); the installer should
  check.
- **Colima users**: `host.docker.internal` needs a flag there; document rather
  than support in v1 (Docker Desktop + OrbStack cover the target audience).
- **Bind-mount I/O**: VirtioFS is much slower than native ext4; heavy ZIM/media
  workloads will feel it. Model I/O is unaffected (native Ollama reads
  `~/.ollama` directly). Worth a docs note, not a blocker.
- **Updater sidecar**: rewrites `compose.yml` in `/opt/project-nomad`
  (`management_compose.yaml:109`) — path must follow the relocated install dir;
  verify it has no other Linux assumptions.
