#!/bin/bash

# Project N.O.M.A.D. macOS Update Script

###################################################################################################################################################################################################

# Script                | Project N.O.M.A.D. macOS Update Script
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
local_ip_address=''

###################################################################################################################################################################################################
#                                                                                                                                                                                                 #
#                                                                                           Functions                                                                                             #
#                                                                                                                                                                                                 #
###################################################################################################################################################################################################

check_is_macos() {
  if [[ "$(uname -s)" != "Darwin" ]]; then
    echo -e "${RED}#${RESET} This script is designed to run on macOS only. Use update_nomad.sh on Linux."
    exit 1
  fi
  echo -e "${GREEN}#${RESET} This script is running on macOS.\\n"
}

get_update_confirmation(){
  read -p "This script will update Project N.O.M.A.D. and its dependencies on your Mac. No data loss is expected, but you should always back up your data before proceeding. Are you sure you want to continue? (y/n): " choice
  case "$choice" in
    y|Y )
      echo -e "${GREEN}#${RESET} User chose to continue with the update."
      ;;
    * )
      echo -e "${RED}#${RESET} User chose not to continue with the update."
      exit 0
      ;;
  esac
}

ensure_docker_installed_and_running() {
  if ! command -v docker &> /dev/null; then
    echo -e "${RED}#${RESET} Docker is not installed. This is unexpected, as Project N.O.M.A.D. requires Docker to run. Did you mean to use install_nomad_macos.sh instead?"
    exit 1
  fi

  if docker info &> /dev/null; then
    return
  fi

  echo -e "${YELLOW}#${RESET} Docker is not running. Attempting to start Docker Desktop...\\n"
  open -a Docker 2>/dev/null || true

  local waited=0
  local max_wait=120
  while ! docker info &> /dev/null; do
    sleep 5
    waited=$((waited + 5))
    if [[ $waited -ge $max_wait ]]; then
      echo -e "${RED}#${RESET} Docker did not become ready after ${max_wait} seconds. Please start Docker Desktop manually and try again."
      exit 1
    fi
  done
}

check_docker_compose() {
  if ! docker compose version &>/dev/null; then
    echo -e "${RED}#${RESET} Docker Compose v2 is not available. Please make sure Docker Desktop is fully started and try again."
    exit 1
  fi
}

ensure_docker_compose_file_exists() {
  if [ ! -f "${NOMAD_DIR}/compose.yml" ]; then
    echo -e "${RED}#${RESET} compose.yml file not found. Please ensure it exists at ${NOMAD_DIR}/compose.yml."
    exit 1
  fi
}

ensure_ollama_updated() {
  if ! command -v ollama &> /dev/null; then
    echo -e "${YELLOW}#${RESET} No native Ollama installation found via Homebrew — skipping Ollama update (you may be using a remote/custom AI backend).\\n"
    return
  fi

  echo -e "${YELLOW}#${RESET} Updating native Ollama via Homebrew...\\n"
  brew upgrade ollama 2>/dev/null || echo -e "${YELLOW}#${RESET} Ollama is already up to date (or upgrade skipped).\\n"
  brew services restart ollama &> /dev/null || true
}

force_recreate() {
  echo -e "${YELLOW}#${RESET} Pulling the latest Docker images...\\n"
  if ! docker compose -p project-nomad -f "${NOMAD_DIR}/compose.yml" pull; then
    echo -e "${RED}#${RESET} Failed to pull the latest Docker images. Please check your network connection and the Docker registry status, then try again."
    exit 1
  fi

  echo -e "${YELLOW}#${RESET} Forcing recreation of containers...\\n"
  if ! docker compose -p project-nomad -f "${NOMAD_DIR}/compose.yml" up -d --force-recreate; then
    echo -e "${RED}#${RESET} Failed to recreate containers. Please check the Docker logs for more details."
    exit 1
  fi
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
  [[ -z "$local_ip_address" ]] && local_ip_address="localhost"
}

success_message() {
  echo -e "${GREEN}#${RESET} Project N.O.M.A.D update completed successfully!\\n"
  echo -e "${GREEN}#${RESET} Installation files are located at ${NOMAD_DIR}\\n\n"
  echo -e "${GREEN}#${RESET} You can now access the management interface at http://localhost:8080 or http://${local_ip_address}:8080\\n"
  echo -e "${GREEN}#${RESET} Thank you for supporting Project N.O.M.A.D!\\n"
}

###################################################################################################################################################################################################
#                                                                                                                                                                                                 #
#                                                                                           Main Script                                                                                             #
#                                                                                                                                                                                                 #
###################################################################################################################################################################################################

check_is_macos

get_update_confirmation
ensure_docker_installed_and_running
check_docker_compose
ensure_docker_compose_file_exists
ensure_ollama_updated
force_recreate
get_local_ip
success_message
