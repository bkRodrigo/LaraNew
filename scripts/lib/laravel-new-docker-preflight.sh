#!/usr/bin/env bash

# laravel-new-docker-preflight.sh
# Docker preflight checks for laravel-new.sh. This file is sourced by the main script.

# Ensure Docker has enough free disk for builds.
#
# Uses Docker's root directory to check available filesystem space.
# Set DOCKER_MIN_FREE_GB to override the threshold (default: 5GB).
check_docker_disk_space() {
  local min_gb="${DOCKER_MIN_FREE_GB:-5}"
  local docker_root=""
  local avail_kb=""
  local min_kb=""
  local volume=""
  local probe_output=""
  local checked_target=""

  docker_root="$(docker info --format '{{.DockerRootDir}}' 2>/dev/null || true)"

  if [[ -n "$docker_root" && -d "$docker_root" ]]; then
    avail_kb="$(df -Pk "$docker_root" 2>/dev/null | awk 'NR==2 {print $4}' || true)"
    checked_target="$docker_root"
  else
    volume="laravel-new-disk-check-$$"
    if docker volume create "$volume" >/dev/null 2>&1; then
      probe_output="$(docker run --rm -v "${volume}:/probe" alpine:3.20 df -Pk /probe 2>/dev/null || true)"
      docker volume rm "$volume" >/dev/null 2>&1 || true
      avail_kb="$(printf '%s\n' "$probe_output" | awk 'NR==2 {print $4}' || true)"
      checked_target="Docker volume storage"
    fi
  fi

  if [[ -z "$avail_kb" ]]; then
    echo "Warning: Docker disk-space check could not inspect Docker storage." >&2
    echo "         Continuing because Docker is running, but builds may fail if Docker is low on space." >&2
    return 0
  fi

  min_kb="$((min_gb * 1024 * 1024))"
  if (( avail_kb < min_kb )); then
    echo "Error: not enough free disk for Docker builds (need ~${min_gb}GB free)." >&2
    echo "      Checked:     $checked_target" >&2
    echo "      Free space:  $((avail_kb / 1024 / 1024))GB" >&2
    echo "      Tip: run 'docker system df' and consider 'docker system prune -a'." >&2
    return 1
  fi
}

# Ensure the project directory does not already exist.
#
# Arguments:
#   $1  Project directory path.
check_project_dir_available() {
  local project_dir="$1"

  if [[ -z "$project_dir" ]]; then
    echo "Error: project directory is empty." >&2
    return 1
  fi

  if [[ -e "$project_dir" ]]; then
    echo "Error: path already exists: $project_dir" >&2
    return 1
  fi
}

_port_check_tool_available() {
  command -v ss >/dev/null 2>&1 || command -v lsof >/dev/null 2>&1 || command -v netstat >/dev/null 2>&1
}

_port_in_use() {
  local port="$1"

  if command -v ss >/dev/null 2>&1; then
    ss -ltnH 2>/dev/null | awk '{print $4}' | grep -E ":${port}$" -q
    return $?
  fi

  if command -v lsof >/dev/null 2>&1; then
    lsof -nP -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1
    return $?
  fi

  if command -v netstat >/dev/null 2>&1; then
    netstat -ltn 2>/dev/null | awk '{print $4}' | grep -E ":${port}$" -q
    return $?
  fi

  return 1
}

is_valid_port() {
  local port="$1"

  if [[ ! "$port" =~ ^[0-9]+$ ]]; then
    return 1
  fi

  if (( port < 1024 || port > 65535 )); then
    return 1
  fi
}

suggest_free_port() {
  local port=""

  for port in "$@"; do
    if ! _port_in_use "$port"; then
      printf '%s' "$port"
      return 0
    fi
  done

  return 1
}

resolve_db_host_port() {
  local db_label="$1"
  local default_port="$2"
  local requested_port="$3"
  shift 3
  local suggested_port=""
  local answer=""
  local selected_port=""

  DB_HOST_PORT="$default_port"
  DB_HOST_PORT_OVERRIDDEN="false"

  if [[ -n "$requested_port" ]]; then
    if ! is_valid_port "$requested_port"; then
      echo "Error: --db-host-port must be a number between 1024 and 65535." >&2
      return 1
    fi
    if _port_in_use "$requested_port"; then
      echo "Error: ${db_label} host port ${requested_port} is already in use." >&2
      echo "      Choose a free port and rerun with --db-host-port <port>." >&2
      return 1
    fi

    DB_HOST_PORT="$requested_port"
    if [[ "$DB_HOST_PORT" != "$default_port" ]]; then
      DB_HOST_PORT_OVERRIDDEN="true"
    fi
    return 0
  fi

  if ! _port_in_use "$default_port"; then
    return 0
  fi

  if [[ ! -t 0 ]]; then
    echo "Error: ${db_label} host port ${default_port} is already in use." >&2
    echo "      Stop the conflicting service or rerun with --db-host-port <port>." >&2
    return 1
  fi

  echo "${db_label} host port ${default_port} is already in use."
  while true; do
    read -r -p "Configure this project to use a different host port? [Y/n] " answer
    case "$answer" in
      ""|y|Y|yes|YES|Yes)
        break
        ;;
      n|N|no|NO|No)
        echo "Stopped because ${db_label} host port ${default_port} is already in use." >&2
        echo "Stop the conflicting service or rerun with --db-host-port <port>." >&2
        return 1
        ;;
      *)
        echo "Please answer yes or no."
        ;;
    esac
  done

  suggested_port="$(suggest_free_port "$@" || true)"
  while true; do
    if [[ -n "$suggested_port" ]]; then
      read -r -p "${db_label} host port [${suggested_port}]: " selected_port
      selected_port="${selected_port:-$suggested_port}"
    else
      read -r -p "${db_label} host port: " selected_port
    fi

    if ! is_valid_port "$selected_port"; then
      echo "Enter a port number between 1024 and 65535."
      continue
    fi

    if _port_in_use "$selected_port"; then
      echo "Port ${selected_port} is already in use. Choose another port."
      suggested_port="$(suggest_free_port "$@" || true)"
      continue
    fi

    DB_HOST_PORT="$selected_port"
    if [[ "$DB_HOST_PORT" != "$default_port" ]]; then
      DB_HOST_PORT_OVERRIDDEN="true"
    fi
    echo "Using ${db_label} host port ${DB_HOST_PORT}."
    return 0
  done
}

# Ensure required host ports are free.
#
# Arguments:
#   $@  List of host ports to verify.
check_ports_available() {
  local ports=("$@")
  local unavailable=()
  local have_tool="false"
  local port=""

  if _port_check_tool_available; then
    have_tool="true"
  fi

  if [[ "$have_tool" != "true" ]]; then
    echo "Warning: port checks skipped (ss/lsof/netstat not found)." >&2
    return 0
  fi

  for port in "${ports[@]}"; do
    if _port_in_use "$port"; then
      unavailable+=("$port")
    fi
  done

  if (( ${#unavailable[@]} > 0 )); then
    echo "Error: required host ports already in use: ${unavailable[*]}" >&2
    echo "      Stop the conflicting services or change ports in docker-compose." >&2
    return 1
  fi
}
