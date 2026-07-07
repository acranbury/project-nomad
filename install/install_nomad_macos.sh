#!/bin/bash

# Project N.O.M.A.D. macOS (Apple Silicon) Installation Script
#
# Unlike the Debian installer, this script keeps Ollama OUTSIDE of Docker and
# installs it natively via Homebrew. Docker containers on macOS run inside a
# Linux VM with no access to the Apple GPU, so a containerized Ollama would be
# CPU-only. A native Ollama binary uses Metal automatically. Everything else
# (admin, MySQL, Redis, Kiwix, etc.) still runs in Docker exactly as on Linux.

###################################################################################################################################################################################################

# Script                | Project N.O.M.A.D. macOS Installation Script
# Version               | 1.0.0
# Author                | Crosstalk Solutions, LLC
# Website               | https://crosstalksolutions.com

###################################################################################################################################################################################################
#                                                                                                                                                                                                 #
#                                                                                           Color Codes                                                                                           #
#                                                                                                                                                                                                 #
###################################################################################################################################################################################################

RESET='\033[0m'
YELLOW='\033[1;33m'
WHITE_R='\033[39m'
RED='\033[1;31m'
GREEN='\033[1;32m'

###################################################################################################################################################################################################
#                                                                                                                                                                                                 #
#                                                                                  Constants & Variables                                                                                          #
#                                                                                                                                                                                                 #
###################################################################################################################################################################################################

NOMAD_DIR="${NOMAD_DIR:-$HOME/nomad}"
MANAGEMENT_COMPOSE_FILE_URL="https://raw.githubusercontent.com/Crosstalk-Solutions/project-nomad/refs/heads/main/install/management_compose.yaml"
START_SCRIPT_URL="https://raw.githubusercontent.com/Crosstalk-Solutions/project-nomad/refs/heads/main/install/start_nomad.sh"
STOP_SCRIPT_URL="https://raw.githubusercontent.com/Crosstalk-Solutions/project-nomad/refs/heads/main/install/stop_nomad.sh"
UPDATE_SCRIPT_URL="https://raw.githubusercontent.com/Crosstalk-Solutions/project-nomad/refs/heads/main/install/update_nomad_macos.sh"
OLLAMA_URL="http://host.docker.internal:11434"
script_option_debug='true'
accepted_terms='false'
local_ip_address=''

###################################################################################################################################################################################################
#                                                                                                                                                                                                 #
#                                                                                           Functions                                                                                             #
#                                                                                                                                                                                                 #
###################################################################################################################################################################################################

header() {
  if [[ "${script_option_debug}" != 'true' ]]; then clear; clear; fi
  echo -e "${GREEN}#########################################################################${RESET}\\n"
}

header_red() {
  if [[ "${script_option_debug}" != 'true' ]]; then clear; clear; fi
  echo -e "${RED}#########################################################################${RESET}\\n"
}

check_is_bash() {
  if [[ -z "$BASH_VERSION" ]]; then
    header_red
    echo -e "${RED}#${RESET} This script requires bash to run. Please run the script using bash.\\n"
    echo -e "${RED}#${RESET} For example: bash $(basename "$0")"
    exit 1
  fi
  echo -e "${GREEN}#${RESET} This script is running in bash.\\n"
}

check_is_macos() {
  if [[ "$(uname -s)" != "Darwin" ]]; then
    header_red
    echo -e "${RED}#${RESET} This script is designed to run on macOS only.\\n"
    echo -e "${RED}#${RESET} For Debian-based Linux, use install_nomad.sh instead."
    exit 1
  fi
  echo -e "${GREEN}#${RESET} This script is running on macOS.\\n"
}

check_is_apple_silicon() {
  local arch
  arch="$(uname -m)"
  if [[ "${arch}" != "arm64" ]]; then
    echo -e "${YELLOW}#${RESET} WARNING: Detected architecture '${arch}'. This script is tuned for Apple Silicon (arm64).\\n"
    echo -e "${YELLOW}#${RESET} On an Intel Mac, Ollama will still run natively via Homebrew, but without the Apple\\n"
    echo -e "${YELLOW}#${RESET} Neural/Metal acceleration benefits of Apple Silicon. Continuing in 10 seconds... press Ctrl+C now to abort.\\n"
    sleep 10
    return
  fi
  echo -e "${GREEN}#${RESET} Architecture check passed (${arch}).\\n"
}

check_is_debug_mode(){
  if [[ "${script_option_debug}" == 'true' ]]; then
    echo -e "${YELLOW}#${RESET} Debug mode is enabled, the script will not clear the screen...\\n"
  else
    clear; clear
  fi
}

generateRandomPass() {
  local length="${1:-32}"
  local password
  password=$(LC_ALL=C tr -dc 'A-Za-z0-9' < /dev/urandom | head -c "$length")
  echo "$password"
}

ensure_homebrew_installed() {
  if command -v brew &> /dev/null; then
    echo -e "${GREEN}#${RESET} Homebrew is already installed.\\n"
    return
  fi

  echo -e "${YELLOW}#${RESET} Homebrew not found. Installing Homebrew (you may be prompted for your password)...\\n"
  if ! /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"; then
    echo -e "${RED}#${RESET} Failed to install Homebrew. Please install it manually from https://brew.sh and try again."
    exit 1
  fi

  # Homebrew installs to /opt/homebrew on Apple Silicon and isn't necessarily on PATH yet in this shell
  if ! command -v brew &> /dev/null; then
    if [[ -x /opt/homebrew/bin/brew ]]; then
      eval "$(/opt/homebrew/bin/brew shellenv)"
    elif [[ -x /usr/local/bin/brew ]]; then
      eval "$(/usr/local/bin/brew shellenv)"
    fi
  fi

  if ! command -v brew &> /dev/null; then
    echo -e "${RED}#${RESET} Homebrew installation finished but 'brew' is still not on PATH. Please restart your terminal and re-run this script."
    exit 1
  fi

  echo -e "${GREEN}#${RESET} Homebrew installed successfully.\\n"
}

ensure_docker_installed() {
  if ! command -v docker &> /dev/null; then
    echo -e "${YELLOW}#${RESET} Docker not found. Installing Docker Desktop via Homebrew...\\n"
    if ! brew install --cask docker-desktop; then
      echo -e "${RED}#${RESET} Failed to install Docker Desktop. Please install it manually from https://www.docker.com/products/docker-desktop/ and try again."
      exit 1
    fi
  else
    echo -e "${GREEN}#${RESET} Docker is already installed.\\n"
  fi

  if docker info &> /dev/null; then
    echo -e "${GREEN}#${RESET} Docker daemon is already running.\\n"
    return
  fi

  echo -e "${YELLOW}#${RESET} Starting Docker Desktop...\\n"
  open -a Docker 2>/dev/null || true

  echo -e "${YELLOW}#${RESET} Waiting for Docker to finish starting up. If this is the first time running Docker Desktop,\\n"
  echo -e "${YELLOW}#${RESET} you may need to complete a one-time setup dialog and grant privileged helper permissions.\\n"

  local waited=0
  local max_wait=180
  while ! docker info &> /dev/null; do
    sleep 5
    waited=$((waited + 5))
    if [[ $waited -ge $max_wait ]]; then
      echo -e "${RED}#${RESET} Docker did not become ready after ${max_wait} seconds."
      echo -e "${RED}#${RESET} Please open Docker Desktop manually, complete any setup prompts, and re-run this script."
      exit 1
    fi
  done

  echo -e "${GREEN}#${RESET} Docker is up and running.\\n"
}

check_docker_compose() {
  if ! docker compose version &>/dev/null; then
    echo -e "${RED}#${RESET} Docker Compose v2 is not available. Docker Desktop bundles this automatically —"
    echo -e "${YELLOW}#${RESET} please make sure Docker Desktop is fully started and try again."
    exit 1
  fi
}

ensure_ollama_native() {
  echo -e "${YELLOW}#${RESET} Checking for a native Ollama installation (for Metal-accelerated inference)...\\n"

  if curl -sf http://localhost:11434/api/version &> /dev/null; then
    echo -e "${GREEN}#${RESET} Ollama is already installed and running natively on this Mac. Skipping install.\\n"
    return
  fi

  if command -v ollama &> /dev/null && ! brew list ollama &> /dev/null; then
    # 'ollama' CLI is present but not managed by Homebrew — most likely Ollama.app installed
    # directly from ollama.com (its installer also drops a CLI symlink). 'brew services start'
    # would fail here since there's no brew-managed formula/service to start.
    echo -e "${YELLOW}#${RESET} Found an existing Ollama installation not managed by Homebrew. Attempting to launch it...\\n"
    open -a Ollama 2>/dev/null || echo -e "${YELLOW}#${RESET} Could not auto-launch the Ollama app. Please start Ollama manually, then re-run this script.\\n"
  else
    if ! command -v ollama &> /dev/null; then
      echo -e "${YELLOW}#${RESET} Installing Ollama via Homebrew...\\n"
      if ! brew install ollama; then
        echo -e "${RED}#${RESET} Failed to install Ollama. Please install it manually from https://ollama.com/download and try again."
        exit 1
      fi
    fi

    echo -e "${YELLOW}#${RESET} Starting Ollama as a background service (brew services)...\\n"
    if ! brew services start ollama; then
      echo -e "${RED}#${RESET} Failed to start the Ollama service. Please run 'brew services start ollama' manually."
      exit 1
    fi
  fi

  local waited=0
  local max_wait=30
  while ! curl -sf http://localhost:11434/api/version &> /dev/null; do
    sleep 2
    waited=$((waited + 2))
    if [[ $waited -ge $max_wait ]]; then
      echo -e "${RED}#${RESET} Ollama did not respond on port 11434 after ${max_wait} seconds."
      echo -e "${RED}#${RESET} Check 'brew services list' and 'brew services info ollama' for details."
      exit 1
    fi
  done

  echo -e "${GREEN}#${RESET} Ollama is installed and running natively — Metal acceleration is used automatically.\\n"
}

get_install_confirmation(){
  echo -e "${YELLOW}#${RESET} This script will install Project N.O.M.A.D. and its dependencies on your Mac."
  echo -e "${YELLOW}#${RESET} If you already have Project N.O.M.A.D. installed with customized config or data, please be aware that running this installation script may overwrite existing files and configurations. It is highly recommended to back up any important data/configs before proceeding."
  read -p "Are you sure you want to continue? (y/N): " choice
  case "$choice" in
    y|Y )
      echo -e "${GREEN}#${RESET} User chose to continue with the installation."
      ;;
    * )
      echo "User chose not to continue with the installation."
      exit 0
      ;;
  esac
}

accept_terms() {
  printf "\n\n"
  echo "License Agreement & Terms of Use"
  echo "__________________________"
  printf "\n\n"
  echo "Project N.O.M.A.D. is licensed under the Apache License 2.0. The full license can be found at https://www.apache.org/licenses/LICENSE-2.0 or in the LICENSE file of this repository."
  printf "\n"
  echo "By accepting this agreement, you acknowledge that you have read and understood the terms and conditions of the Apache License 2.0 and agree to be bound by them while using Project N.O.M.A.D."
  echo -e "\n\n"
  read -p "I have read and accept License Agreement & Terms of Use (y/N)? " choice
  case "$choice" in
    y|Y )
      accepted_terms='true'
      ;;
    * )
      echo "License Agreement & Terms of Use not accepted. Installation cannot continue."
      exit 1
      ;;
  esac
}

create_nomad_directory(){
  if [[ ! -d "$NOMAD_DIR" ]]; then
    echo -e "${YELLOW}#${RESET} Creating directory for Project N.O.M.A.D at $NOMAD_DIR...\\n"
    mkdir -p "$NOMAD_DIR"
    echo -e "${GREEN}#${RESET} Directory created successfully.\\n"
  else
    echo -e "${GREEN}#${RESET} Directory $NOMAD_DIR already exists.\\n"
  fi

  mkdir -p "${NOMAD_DIR}/storage/logs"
  touch "${NOMAD_DIR}/storage/logs/admin.log"
}

download_management_compose_file() {
  local compose_file_path="${NOMAD_DIR}/compose.yml"

  echo -e "${YELLOW}#${RESET} Downloading docker-compose file for management...\\n"
  if ! curl -fsSL "$MANAGEMENT_COMPOSE_FILE_URL" -o "$compose_file_path"; then
    echo -e "${RED}#${RESET} Failed to download the docker compose file. Please check the URL and try again."
    exit 1
  fi
  echo -e "${GREEN}#${RESET} Docker compose file downloaded successfully to $compose_file_path.\\n"

  local app_key=$(generateRandomPass)
  local db_root_password=$(generateRandomPass)
  local db_user_password=$(generateRandomPass)

  if [[ -d "${NOMAD_DIR}/mysql" ]]; then
    echo -e "${YELLOW}#${RESET} Removing existing MySQL data directory to ensure credentials match...\\n"
    rm -rf "${NOMAD_DIR}/mysql"
  fi

  echo -e "${YELLOW}#${RESET} Configuring docker-compose file for this Mac...\\n"

  # The upstream compose file hardcodes /opt/project-nomad host paths (Linux default
  # install dir). Retarget every occurrence to this Mac's install directory. Using '#'
  # as the sed delimiter since NOMAD_DIR itself contains slashes.
  sed -i '' "s#/opt/project-nomad#${NOMAD_DIR}#g" "$compose_file_path"

  # The global retarget above also rewrote the updater sidecar's bind mount to
  # "${NOMAD_DIR}:${NOMAD_DIR}". But the updater IMAGE hardcodes the container-side
  # path (install/sidecar-updater/update-watcher.sh: COMPOSE_FILE="/opt/project-nomad/compose.yml")
  # with no env override, so leaving it rewritten would make every in-app update fail at
  # "Applying image tag to compose.yml" once it can't find that path inside the container.
  # Fix the container side back to the canonical path — the host side (already retargeted)
  # is all `docker compose` needs to resolve the bind correctly against the host daemon.
  awk -v nomad_dir="$NOMAD_DIR" '
    /# Writable access required so the updater can set the correct image tag/ {
      print "      - " nomad_dir ":/opt/project-nomad # Writable access required so the updater can set the correct image tag in compose.yml. This needs to be the same location that the compose file is located at on the host for the updater to work correctly"
      next
    }
    { print }
  ' "$compose_file_path" > "${compose_file_path}.tmp" && mv "${compose_file_path}.tmp" "$compose_file_path"

  sed -i '' "s#URL=replaceme#URL=http://${local_ip_address}:8080#g" "$compose_file_path"
  sed -i '' "s#APP_KEY=replaceme#APP_KEY=${app_key}#g" "$compose_file_path"
  sed -i '' "s#DB_PASSWORD=replaceme#DB_PASSWORD=${db_user_password}#g" "$compose_file_path"
  sed -i '' "s#MYSQL_ROOT_PASSWORD=replaceme#MYSQL_ROOT_PASSWORD=${db_root_password}#g" "$compose_file_path"
  sed -i '' "s#MYSQL_PASSWORD=replaceme#MYSQL_PASSWORD=${db_user_password}#g" "$compose_file_path"

  # Tell the admin container it's on macOS and where to find the native, Metal-accelerated
  # Ollama on the host. The admin seeds ai.remoteOllamaUrl from NOMAD_DEFAULT_OLLAMA_URL on
  # first boot (see MacosOllamaAutoconfigProvider) if that setting hasn't been set already.
  awk -v ollama_url="$OLLAMA_URL" '
    { print }
    /- HOST=0\.0\.0\.0/ {
      print "      - NOMAD_HOST_OS=darwin"
      print "      - NOMAD_DEFAULT_OLLAMA_URL=" ollama_url
    }
  ' "$compose_file_path" > "${compose_file_path}.tmp" && mv "${compose_file_path}.tmp" "$compose_file_path"

  # The anchor above depends on "- HOST=0.0.0.0" staying unique to the admin service in the
  # upstream compose file. Fail loudly instead of silently shipping a config where the AI
  # Assistant isn't actually pre-wired to the native Ollama.
  if ! grep -q 'NOMAD_HOST_OS=darwin' "$compose_file_path"; then
    echo -e "${RED}#${RESET} Failed to inject macOS environment variables into compose.yml. The compose file format may have changed upstream."
    exit 1
  fi

  # The disk-collector's "/:/host:ro,rslave" mount reflects Docker Desktop's Linux VM
  # filesystem, not the Mac's actual disk, and rslave propagation doesn't carry real
  # meaning across the VM boundary. Drop it — the collector still reports usable stats
  # from the storage volume mount.
  sed -i '' "\#- /:/host:ro,rslave#d" "$compose_file_path"

  echo -e "${GREEN}#${RESET} Docker compose file configured successfully.\\n"
}

download_helper_scripts() {
  local start_script_path="${NOMAD_DIR}/start_nomad.sh"
  local stop_script_path="${NOMAD_DIR}/stop_nomad.sh"
  local update_script_path="${NOMAD_DIR}/update_nomad.sh"

  echo -e "${YELLOW}#${RESET} Downloading helper scripts...\\n"
  if ! curl -fsSL --retry 5 --retry-delay 3 "$START_SCRIPT_URL" -o "$start_script_path"; then
    echo -e "${RED}#${RESET} Failed to download the start script. Please check the URL and try again."
    exit 1
  fi
  chmod +x "$start_script_path"

  if ! curl -fsSL --retry 5 --retry-delay 3 "$STOP_SCRIPT_URL" -o "$stop_script_path"; then
    echo -e "${RED}#${RESET} Failed to download the stop script. Please check the URL and try again."
    exit 1
  fi
  chmod +x "$stop_script_path"

  if ! curl -fsSL --retry 5 --retry-delay 3 "$UPDATE_SCRIPT_URL" -o "$update_script_path"; then
    echo -e "${RED}#${RESET} Failed to download the update script. Please check the URL and try again."
    exit 1
  fi
  chmod +x "$update_script_path"

  echo -e "${GREEN}#${RESET} Helper scripts downloaded successfully to $start_script_path, $stop_script_path, and $update_script_path.\\n"
}

start_management_containers() {
  echo -e "${YELLOW}#${RESET} Starting management containers using docker compose...\\n"
  if ! docker compose -p project-nomad -f "${NOMAD_DIR}/compose.yml" up -d; then
    echo -e "${RED}#${RESET} Failed to start management containers. Please check the logs and try again."
    exit 1
  fi
  echo -e "${GREEN}#${RESET} Management containers started successfully.\\n"
}

get_local_ip() {
  local iface
  iface=$(route get default 2>/dev/null | awk '/interface: /{print $2}')
  if [[ -n "$iface" ]]; then
    local_ip_address=$(ipconfig getifaddr "$iface" 2>/dev/null)
  fi

  if [[ -z "$local_ip_address" ]]; then
    for iface in en0 en1; do
      local_ip_address=$(ipconfig getifaddr "$iface" 2>/dev/null)
      [[ -n "$local_ip_address" ]] && break
    done
  fi

  if [[ -z "$local_ip_address" ]]; then
    echo -e "${YELLOW}#${RESET} Unable to determine local IP address. Falling back to localhost.\\n"
    local_ip_address="localhost"
  fi
}

write_gpu_marker() {
  # Informational only — lets the admin UI report "Metal" instead of "CPU-only"
  # even though no GPU is passed through to any container.
  echo 'metal' > "${NOMAD_DIR}/storage/.nomad-gpu-type" 2>/dev/null || true
}

success_message() {
  echo -e "${GREEN}#${RESET} Project N.O.M.A.D installation completed successfully!\\n"
  echo -e "${GREEN}#${RESET} Installation files are located at ${NOMAD_DIR}\\n\n"
  echo -e "${GREEN}#${RESET} Ollama is running natively on this Mac with Metal acceleration, and the AI Assistant is\\n"
  echo -e "${GREEN}#${RESET} already pre-configured to use it at ${OLLAMA_URL}.\\n"
  echo -e "${GREEN}#${RESET} Docker Desktop needs to be running for N.O.M.A.D. to work — enable \"Start Docker Desktop when you log in\"\\n"
  echo -e "${GREEN}#${RESET} in Docker Desktop's settings so everything comes back up automatically after a reboot. You can\\n"
  echo -e "${GREEN}#${RESET} always start/stop the management containers manually with: ${WHITE_R}${NOMAD_DIR}/start_nomad.sh${RESET} / ${WHITE_R}${NOMAD_DIR}/stop_nomad.sh${RESET}\\n"
  echo -e "${GREEN}#${RESET} You can now access the management interface at http://localhost:8080 or http://${local_ip_address}:8080\\n"
  echo -e "${GREEN}#${RESET} Thank you for supporting Project N.O.M.A.D!\\n"
}

###################################################################################################################################################################################################
#                                                                                                                                                                                                 #
#                                                                                           Main Script                                                                                             #
#                                                                                                                                                                                                 #
###################################################################################################################################################################################################

# Pre-flight checks
# check_is_bash runs first since check_is_macos/check_is_apple_silicon use [[ ]], a bashism
# that emits "not found" errors (and silently falls through) under sh/dash.
check_is_bash
check_is_macos
check_is_apple_silicon
check_is_debug_mode

# Main install
get_install_confirmation
accept_terms
ensure_homebrew_installed
ensure_docker_installed
check_docker_compose
ensure_ollama_native
get_local_ip
create_nomad_directory
download_helper_scripts
download_management_compose_file
start_management_containers
write_gpu_marker
success_message
