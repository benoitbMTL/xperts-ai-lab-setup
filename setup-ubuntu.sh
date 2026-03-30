#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_NAME="$(basename "$0")"
ACTION="${1:-install}"
WORKDIR="$(pwd)"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
LOG_FILE="${WORKDIR}/xperts-lab-${ACTION}-${TIMESTAMP}.log"

PACKAGES=(
  net-tools
  nmap
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

on_error() {
  local exit_code=$?
  local line_no="${1:-unknown}"
  log ERROR "Script failed at line ${line_no} with exit code ${exit_code}."
  log ERROR "Check log file: ${LOG_FILE}"
  exit "$exit_code"
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
      log INFO "Usage: sudo ./${SCRIPT_NAME} [install|uninstall]"
      exit 1
      ;;
  esac
}

validate_os() {
  step "Validating operating system"

  if [[ ! -f /etc/os-release ]]; then
    log ERROR "Cannot determine operating system."
    exit 1
  fi

  # shellcheck disable=SC1091
  source /etc/os-release

  if [[ "${ID:-}" != "ubuntu" ]]; then
    log ERROR "This script supports Ubuntu only. Detected: ${ID:-unknown}"
    exit 1
  fi

  log INFO "Detected Ubuntu: ${PRETTY_NAME:-Unknown Ubuntu}"
}

get_primary_ip() {
  hostname -I 2>/dev/null | awk '{print $1}'
}

docker_installed() {
  command -v docker >/dev/null 2>&1
}

docker_ready() {
  docker info >/dev/null 2>&1
}

container_exists() {
  local name="$1"
  docker ps -a --format '{{.Names}}' | grep -Fxq "$name"
}

container_running() {
  local name="$1"
  docker ps --format '{{.Names}}' | grep -Fxq "$name"
}

install_packages() {
  step "Updating apt package index"
  run_cmd apt-get update

  step "Upgrading installed packages"
  run_cmd env DEBIAN_FRONTEND=noninteractive apt-get upgrade -y

  step "Installing required packages"
  run_cmd env DEBIAN_FRONTEND=noninteractive apt-get install -y "${PACKAGES[@]}"
}

install_docker_if_missing() {
  step "Checking Docker installation"

  if docker_installed; then
    log INFO "Docker is already installed: $(docker --version)"
    return 0
  fi

  log WARN "Docker is not installed. Installing docker.io from Ubuntu repository."
  run_cmd env DEBIAN_FRONTEND=noninteractive apt-get install -y docker.io

  if docker_installed; then
    log INFO "Docker installed successfully: $(docker --version)"
  else
    log ERROR "Docker installation failed."
    exit 1
  fi
}

ensure_docker_ready() {
  step "Ensuring Docker is available"

  if ! docker_installed; then
    log ERROR "Docker binary is not installed."
    exit 1
  fi

  if docker_ready; then
    log INFO "Docker daemon is already reachable."
    return 0
  fi

  log WARN "Docker is installed but daemon is not reachable. Trying to start docker service."

  if command -v systemctl >/dev/null 2>&1; then
    if systemctl start docker >/dev/null 2>&1; then
      log INFO "Docker service start command executed."
    elif systemctl restart docker >/dev/null 2>&1; then
      log INFO "Docker service restart command executed."
    else
      log WARN "Unable to start Docker with systemctl."
    fi
  else
    log WARN "systemctl is not available on this system."
  fi

  sleep 3

  if docker_ready; then
    log INFO "Docker daemon is now reachable."
  else
    log ERROR "Docker is installed but the daemon is not reachable."
    log ERROR "Manual check: systemctl status docker --no-pager"
    exit 1
  fi
}

validate_binaries() {
  step "Validating installed binaries"

  local binaries=(netstat nmap docker)
  local bin

  for bin in "${binaries[@]}"; do
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
  log INFO "Kernel: $(uname -r)"
  log INFO "Ubuntu: $(grep PRETTY_NAME /etc/os-release | cut -d= -f2 | tr -d '"')"
  log INFO "Docker version: $(docker --version)"
  log INFO "Nmap version: $(nmap --version | head -n 1)"
}

pull_image_if_needed() {
  local image="$1"

  if docker image inspect "$image" >/dev/null 2>&1; then
    log INFO "Image already present locally: $image"
  else
    step "Pulling image: $image"
    run_cmd docker pull "$image"
  fi
}

deploy_single_container() {
  local name="$1"
  local port_mapping="$2"
  local image="$3"
  local extra_args="$4"

  step "Processing container: $name"

  if container_running "$name"; then
    log INFO "Container '$name' is already running. Skipping to next container."
    return 0
  fi

  if container_exists "$name"; then
    log WARN "Container '$name' exists but is not running. Starting it."
    run_cmd docker start "$name"

    if container_running "$name"; then
      log INFO "Container '$name' started successfully."
      return 0
    else
      log ERROR "Container '$name' exists but failed to start."
      exit 1
    fi
  fi

  pull_image_if_needed "$image"

  if [[ -n "$extra_args" ]]; then
    # shellcheck disable=SC2206
    local extra_args_array=($extra_args)
    run_cmd docker run -d \
      --restart unless-stopped \
      --name "$name" \
      -p "$port_mapping" \
      "${extra_args_array[@]}" \
      "$image"
  else
    run_cmd docker run -d \
      --restart unless-stopped \
      --name "$name" \
      -p "$port_mapping" \
      "$image"
  fi

  if container_running "$name"; then
    log INFO "Container '$name' created and started successfully."
  else
    log ERROR "Container '$name' failed to start after creation."
    exit 1
  fi
}

install_containers() {
  step "Deploying lab containers"

  local name
  local port_mapping
  local image
  local extra_args

  for entry in "${CONTAINERS[@]}"; do
    IFS='|' read -r name port_mapping image extra_args <<< "$entry"
    deploy_single_container "$name" "$port_mapping" "$image" "$extra_args"
  done
}

uninstall_containers() {
  step "Removing lab containers"

  local name

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

validate_containers() {
  step "Validating container status"

  local all_ok=1
  local name
  local port_mapping
  local image

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

  local ip
  ip="$(get_primary_ip)"

  echo "Log file: $LOG_FILE" | tee -a "$LOG_FILE"
  echo "" | tee -a "$LOG_FILE"
  echo "Deployed services:" | tee -a "$LOG_FILE"

  if [[ -n "$ip" ]]; then
    echo "  http://${ip}:1000  -> DVWA" | tee -a "$LOG_FILE"
    echo "  http://${ip}:2001  -> Demo Web App" | tee -a "$LOG_FILE"
    echo "  http://${ip}:3000  -> Juice Shop" | tee -a "$LOG_FILE"
    echo "  http://${ip}:4000  -> Petstore3" | tee -a "$LOG_FILE"
    echo "  http://${ip}:5000  -> Speedtest" | tee -a "$LOG_FILE"
    echo "  http://${ip}:7000  -> MCP Demo" | tee -a "$LOG_FILE"
    echo "  http://${ip}:8080  -> Darwin2" | tee -a "$LOG_FILE"
  else
    echo "  Unable to determine primary IP address." | tee -a "$LOG_FILE"
  fi
}

print_summary_uninstall() {
  step "Summary"
  echo "All lab containers were processed for removal." | tee -a "$LOG_FILE"
  echo "Log file: $LOG_FILE" | tee -a "$LOG_FILE"
}

main_install() {
  validate_os
  install_packages
  install_docker_if_missing
  ensure_docker_ready
  validate_binaries
  validate_versions
  install_containers
  validate_containers
  print_summary_install
}

main_uninstall() {
  validate_os

  if ! docker_installed; then
    log WARN "Docker is not installed. Nothing to uninstall."
    print_summary_uninstall
    return 0
  fi

  ensure_docker_ready
  uninstall_containers
  print_summary_uninstall
}

main() {
  : > "$LOG_FILE"
  trap 'on_error $LINENO' ERR

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
