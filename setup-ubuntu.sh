#!/usr/bin/env bash

set -Eeuo pipefail

ACTION="${1:-install}"
WORKDIR="$(pwd)"
LOG_FILE="${WORKDIR}/xperts-lab-${ACTION}-$(date +%Y%m%d-%H%M%S).log"

PACKAGES=(
  net-tools
  nmap
  docker.io
)

CONTAINERS=(
  "web-dvwa|1000:80|vulnerables/web-dvwa|"
  "demo-web-app|2001:80|benoitbmtl/demo-web-app|-e HOST_MACHINE_NAME=$(hostname)"
  "juice-shop|3000:3000|bkimminich/juice-shop|"
  "petstore3|4000:8080|swaggerapi/petstore3|"
  "speedtest|5000:80|adolfintel/speedtest|"
  "mcp-demo|7000:7000|benoitbmtl/mcp-demo|"
  "darwin2|8080:8080|benoitbmtl/darwin2|"
)

log() {
  local level="$1"
  shift
  local message="$*"
  local timestamp
  timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
  echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
}

step() {
  local message="$*"
  echo "" | tee -a "$LOG_FILE"
  echo "=== $message ===" | tee -a "$LOG_FILE"
}

run_cmd() {
  log INFO "Running: $*"
  "$@" 2>&1 | tee -a "$LOG_FILE"
}

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    log ERROR "This script must be run as root or with sudo."
    exit 1
  fi
}

validate_action() {
  case "$ACTION" in
    install|uninstall)
      ;;
    *)
      log ERROR "Invalid action: $ACTION"
      log INFO "Usage: sudo ./setup-xperts-lab.sh [install|uninstall]"
      exit 1
      ;;
  esac
}

install_packages() {
  step "Updating apt package index"
  run_cmd apt-get update -y

  step "Upgrading installed packages"
  run_cmd apt-get upgrade -y

  step "Installing required packages"
  run_cmd apt-get install -y "${PACKAGES[@]}"
}

enable_docker() {
  step "Enabling and starting Docker service"
  run_cmd systemctl enable docker
  run_cmd systemctl start docker

  step "Validating Docker service"
  if systemctl is-active --quiet docker; then
    log INFO "Docker service is running."
  else
    log ERROR "Docker service is not running."
    exit 1
  fi
}

container_exists() {
  local name="$1"
  docker ps -a --format '{{.Names}}' | grep -Fxq "$name"
}

container_running() {
  local name="$1"
  docker ps --format '{{.Names}}' | grep -Fxq "$name"
}

install_or_replace_container() {
  local name="$1"
  local port_mapping="$2"
  local image="$3"
  local extra_args="$4"

  step "Deploying container: $name"

  if container_exists "$name"; then
    log WARN "Container '$name' already exists. Removing it before redeploying."
    run_cmd docker rm -f "$name"
  fi

  if [[ -n "$extra_args" ]]; then
    # shellcheck disable=SC2086
    run_cmd docker run -d --restart unless-stopped --name "$name" -p "$port_mapping" $extra_args "$image"
  else
    run_cmd docker run -d --restart unless-stopped --name "$name" -p "$port_mapping" "$image"
  fi

  if container_running "$name"; then
    log INFO "Container '$name' is running."
  else
    log ERROR "Container '$name' failed to start."
    exit 1
  fi
}

install_containers() {
  step "Deploying lab containers"

  for entry in "${CONTAINERS[@]}"; do
    IFS='|' read -r name port_mapping image extra_args <<< "$entry"
    install_or_replace_container "$name" "$port_mapping" "$image" "$extra_args"
  done
}

uninstall_containers() {
  step "Removing lab containers"

  for entry in "${CONTAINERS[@]}"; do
    IFS='|' read -r name _ _ _ <<< "$entry"

    if container_exists "$name"; then
      log INFO "Removing container '$name'."
      run_cmd docker rm -f "$name"
    else
      log WARN "Container '$name' does not exist. Skipping."
    fi
  done
}

validate_binaries() {
  step "Validating installed binaries"

  for bin in netstat nmap docker; do
    if command -v "$bin" >/dev/null 2>&1; then
      log INFO "Found binary: $bin -> $(command -v "$bin")"
    else
      log ERROR "Missing required binary: $bin"
      exit 1
    fi
  done
}

validate_versions() {
  step "Collecting version information"

  log INFO "Hostname: $(hostname)"
  log INFO "Ubuntu: $(grep PRETTY_NAME /etc/os-release | cut -d= -f2 | tr -d '"')"
  log INFO "Docker version: $(docker --version)"
  log INFO "Nmap version: $(nmap --version | head -n 1)"
}

validate_containers() {
  step "Validating container status"

  local all_ok=1

  for entry in "${CONTAINERS[@]}"; do
    IFS='|' read -r name port_mapping image _ <<< "$entry"

    if container_running "$name"; then
      log INFO "Running: $name | Port: $port_mapping | Image: $image"
    else
      log ERROR "Not running: $name"
      all_ok=0
    fi
  done

  if [[ "$all_ok" -ne 1 ]]; then
    exit 1
  fi
}

print_summary_install() {
  step "Summary"

  echo "Log file: $LOG_FILE" | tee -a "$LOG_FILE"
  echo "" | tee -a "$LOG_FILE"
  echo "Deployed services:" | tee -a "$LOG_FILE"
  echo "  http://$(hostname -I | awk '{print $1}'):1000  -> DVWA" | tee -a "$LOG_FILE"
  echo "  http://$(hostname -I | awk '{print $1}'):2001  -> Demo Web App" | tee -a "$LOG_FILE"
  echo "  http://$(hostname -I | awk '{print $1}'):3000  -> Juice Shop" | tee -a "$LOG_FILE"
  echo "  http://$(hostname -I | awk '{print $1}'):4000  -> Petstore3" | tee -a "$LOG_FILE"
  echo "  http://$(hostname -I | awk '{print $1}'):5000  -> Speedtest" | tee -a "$LOG_FILE"
  echo "  http://$(hostname -I | awk '{print $1}'):7000  -> MCP Demo" | tee -a "$LOG_FILE"
  echo "  http://$(hostname -I | awk '{print $1}'):8080  -> Darwin2" | tee -a "$LOG_FILE"
}

print_summary_uninstall() {
  step "Summary"
  echo "All lab containers were processed for removal." | tee -a "$LOG_FILE"
  echo "Log file: $LOG_FILE" | tee -a "$LOG_FILE"
}

main_install() {
  install_packages
  enable_docker
  validate_binaries
  validate_versions
  install_containers
  validate_containers
  print_summary_install
}

main_uninstall() {
  enable_docker
  uninstall_containers
  print_summary_uninstall
}

main() {
  : > "$LOG_FILE"
  log INFO "Script started with action: $ACTION"

  require_root
  validate_action

  case "$ACTION" in
    install)
      main_install
      log INFO "Installation completed successfully."
      ;;
    uninstall)
      main_uninstall
      log INFO "Uninstall completed successfully."
      ;;
  esac
}

main "$@"