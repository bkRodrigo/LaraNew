#!/usr/bin/env bash

# laravel-new-host-ports.sh
# Host port selection helpers for laravel-new.sh. This file is sourced by the main script.

HOST_PORT_RESERVATIONS=()

reset_host_port_reservations() {
  HOST_PORT_RESERVATIONS=()
}

_is_valid_host_port() {
  local port="$1"

  if [[ ! "$port" =~ ^[0-9]+$ ]]; then
    return 1
  fi

  if (( port < 1 || port > 65535 )); then
    return 1
  fi
}

_host_port_is_reserved() {
  local port="$1"
  local reserved=""

  for reserved in "${HOST_PORT_RESERVATIONS[@]}"; do
    if [[ "$reserved" == "$port" ]]; then
      return 0
    fi
  done

  return 1
}

_host_port_is_available() {
  local port="$1"

  if ! _is_valid_host_port "$port"; then
    return 1
  fi

  if _host_port_is_reserved "$port"; then
    return 1
  fi

  if _port_in_use "$port"; then
    return 1
  fi

  return 0
}

_reserve_host_port() {
  local port="$1"

  HOST_PORT_RESERVATIONS+=("$port")
}

_find_candidate_host_port() {
  local candidate_start="$1"
  local candidate=""
  local offset=""

  for offset in $(seq 0 49); do
    candidate="$((candidate_start + offset))"
    if _host_port_is_available "$candidate"; then
      printf '%s' "$candidate"
      return 0
    fi
  done

  return 1
}

resolve_host_port() {
  local label="$1"
  local env_var="$2"
  local default_port="$3"
  local candidate_start="$4"
  local requested_port="${5:-}"
  local selected_port=""
  local candidate_port=""

  RESOLVED_HOST_PORT=""

  if [[ -n "$requested_port" ]]; then
    if ! _is_valid_host_port "$requested_port"; then
      echo "Error: ${label} host port must be a number between 1 and 65535." >&2
      return 1
    fi
    if ! _host_port_is_available "$requested_port"; then
      echo "Error: ${label} host port ${requested_port} is already in use or already selected." >&2
      echo "      Choose a free port and rerun with ${env_var} or the matching CLI option." >&2
      return 1
    fi

    RESOLVED_HOST_PORT="$requested_port"
    _reserve_host_port "$RESOLVED_HOST_PORT"
    return 0
  fi

  if _host_port_is_available "$default_port"; then
    RESOLVED_HOST_PORT="$default_port"
    _reserve_host_port "$RESOLVED_HOST_PORT"
    return 0
  fi

  candidate_port="$(_find_candidate_host_port "$candidate_start" || true)"
  if [[ -n "$candidate_port" ]]; then
    echo "${label} host port ${default_port} is already in use. Using ${candidate_port}."
    RESOLVED_HOST_PORT="$candidate_port"
    _reserve_host_port "$RESOLVED_HOST_PORT"
    return 0
  fi

  if [[ ! -t 0 ]]; then
    echo "Error: ${label} host port ${default_port} is already in use and no free ${env_var} candidate was found." >&2
    echo "      Free a port or rerun interactively to enter ${env_var}." >&2
    return 1
  fi

  echo "${label} host port ${default_port} is already in use, and no free automatic candidate was found."
  while true; do
    read -r -p "${label} host port (${env_var}): " selected_port

    if ! _is_valid_host_port "$selected_port"; then
      echo "Enter a port number between 1 and 65535."
      continue
    fi

    if ! _host_port_is_available "$selected_port"; then
      echo "Port ${selected_port} is already in use or already selected. Choose another port."
      continue
    fi

    RESOLVED_HOST_PORT="$selected_port"
    _reserve_host_port "$RESOLVED_HOST_PORT"
    return 0
  done
}
