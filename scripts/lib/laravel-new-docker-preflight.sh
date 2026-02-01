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

  docker_root="$(docker info --format '{{.DockerRootDir}}' 2>/dev/null || true)"
  if [[ -z "$docker_root" ]]; then
    return 0
  fi

  avail_kb="$(df -Pk "$docker_root" 2>/dev/null | awk 'NR==2 {print $4}')"
  if [[ -z "$avail_kb" ]]; then
    return 0
  fi

  min_kb="$((min_gb * 1024 * 1024))"
  if (( avail_kb < min_kb )); then
    echo "Error: not enough free disk for Docker builds (need ~${min_gb}GB free)." >&2
    echo "      Docker root: $docker_root" >&2
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

# Ensure required host ports are free.
#
# Arguments:
#   $@  List of host ports to verify.
check_ports_available() {
  local ports=("$@")
  local unavailable=()
  local have_tool="false"
  local port=""

  if command -v ss >/dev/null 2>&1 || command -v lsof >/dev/null 2>&1 || command -v netstat >/dev/null 2>&1; then
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
