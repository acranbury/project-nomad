#!/bin/bash

# Project N.O.M.A.D. macOS Uninstall Script

###################################################################################################################################################################################################

# Script                | Project N.O.M.A.D. macOS Uninstall Script
# Version               | 1.0.0
# Author                | Crosstalk Solutions, LLC
# Website               | https://crosstalksolutions.com

###################################################################################################################################################################################################
#                                                                                                                                                                                                 #
#                                                                                  Constants & Variables                                                                                          #
#                                                                                                                                                                                                 #
###################################################################################################################################################################################################

NOMAD_DIR="${NOMAD_DIR:-$HOME/nomad}"
MANAGEMENT_COMPOSE_FILE="${NOMAD_DIR}/compose.yml"

###################################################################################################################################################################################################
#                                                                                                                                                                                                 #
#                                                                                     Functions                                                                                                   #
#                                                                                                                                                                                                 #
###################################################################################################################################################################################################

check_is_macos() {
  if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "This script is designed to run on macOS only. Use uninstall_nomad.sh on Linux."
    exit 1
  fi
}

check_current_directory(){
  if [ "$(pwd)" == "${NOMAD_DIR}" ]; then
    echo "Please run this script from a directory other than ${NOMAD_DIR}."
    exit 1
  fi
}

ensure_management_compose_file_exists(){
  if [ ! -f "${MANAGEMENT_COMPOSE_FILE}" ]; then
    echo "Unable to find the management Docker Compose file at ${MANAGEMENT_COMPOSE_FILE}. There may be a problem with your Project N.O.M.A.D. installation."
    exit 1
  fi
}

get_uninstall_confirmation(){
  read -p "This script will remove ALL Project N.O.M.A.D. containers and (optionally) files. THIS CANNOT BE UNDONE. Are you sure you want to continue? (y/n): " choice
  case "$choice" in
    y|Y )
      echo -e "User chose to continue with the uninstallation."
      ;;
    * )
      echo -e "User chose not to continue with the uninstallation."
      exit 0
      ;;
  esac
}

ensure_docker_installed() {
  if ! command -v docker &> /dev/null; then
    echo "Unable to find Docker. There may be a problem with your Docker installation."
    exit 1
  fi
}

check_docker_compose() {
  if ! docker compose version &>/dev/null; then
    echo "Docker Compose v2 is not available. Please make sure Docker Desktop is fully started and try again."
    exit 1
  fi
}

ollama_cleanup() {
  if ! command -v ollama &> /dev/null; then
    return
  fi

  read -p "Do you also want to stop and uninstall the native Ollama service (installed via Homebrew)? This will remove any downloaded models. (y/N): " ollama_choice
  case "$ollama_choice" in
    y|Y )
      brew services stop ollama 2>/dev/null || true
      brew uninstall ollama 2>/dev/null || true
      echo "Ollama service stopped and uninstalled."
      ;;
    * )
      echo "Leaving native Ollama installation in place."
      ;;
  esac
}

storage_cleanup() {
  read -p "Do you want to delete the Project N.O.M.A.D. directory (${NOMAD_DIR})? This is best if you want to start a completely fresh install. This will PERMANENTLY DELETE all stored Nomad data and can't be undone! (y/N): " delete_dir_choice
  case "$delete_dir_choice" in
      y|Y )
          echo "Removing Project N.O.M.A.D. files..."
          if rm -rf "${NOMAD_DIR}"; then
              echo "Project N.O.M.A.D. files removed."
          else
              echo "Warning: Failed to fully remove ${NOMAD_DIR}. You may need to remove it manually."
          fi
          ;;
      * )
          echo "Skipping removal of ${NOMAD_DIR}."
          ;;
  esac
}

uninstall_nomad() {
    echo "Stopping and removing Project N.O.M.A.D. management containers..."
    docker compose -p project-nomad -f "${MANAGEMENT_COMPOSE_FILE}" down
    echo "Allowing some time for management containers to stop..."
    sleep 5

    echo "Stopping and removing all Project N.O.M.A.D. app containers..."
    docker ps -a --filter "name=^nomad_" --format "{{.Names}}" | xargs -I{} docker rm -f {}
    echo "Allowing some time for app containers to stop..."
    sleep 5

    echo "Containers should be stopped now."

    echo "Removing project-nomad_default network if it exists..."
    docker network rm project-nomad_default 2>/dev/null && echo "Network removed." || echo "Network already removed or not found."

    echo "Removing project-nomad_nomad-update-shared volume if it exists..."
    docker volume rm project-nomad_nomad-update-shared 2>/dev/null && echo "Volume removed." || echo "Volume already removed or not found."

    ollama_cleanup
    storage_cleanup

    echo "Project N.O.M.A.D. has been uninstalled. We hope to see you again soon!"
}

###################################################################################################################################################################################################
#                                                                                                                                                                                                 #
#                                                                                       Main                                                                                                      #
#                                                                                                                                                                                                 #
###################################################################################################################################################################################################
check_is_macos
check_current_directory
ensure_management_compose_file_exists
ensure_docker_installed
check_docker_compose
get_uninstall_confirmation
uninstall_nomad
