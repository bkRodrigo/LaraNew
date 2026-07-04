#!/usr/bin/env bash

# laravel-new-node.sh
# Node version prompt helpers for laravel-new.sh. This file is sourced by the main script.

# Resolve the Node version for .nvmrc.
#
# Arguments:
#   $1  CLI node version (may be empty).
#
# Outputs (globals):
#   NODE_VERSION  Node version string or empty if skipped.
resolve_node_version() {
  local cli_value="$1"
  local lts_major=""
  local prompt_message=""
  NODE_VERSION=""

  if [[ -n "$cli_value" ]]; then
    if ! is_valid_node_version "$cli_value"; then
      echo "Error: invalid Node version '$cli_value'. Use 24, 24.12, 24.12.0, lts/*, or lts/<name>." >&2
      return 1
    fi
    NODE_VERSION="$cli_value"
    return 0
  fi

  if [[ -t 0 ]]; then
    if lts_major="$(latest_node_lts_major)"; then
      prompt_message="Please provide your target Node version for .nvmrc (latest LTS major: ${lts_major}; blank skips .nvmrc creation)"
    else
      prompt_message="Please provide your target Node version for .nvmrc (for example 24, lts/*, or lts/<name>; blank skips .nvmrc creation)"
    fi

    while true; do
      if ! prompt_input "$prompt_message"; then
        return 0
      fi
      NODE_VERSION="$PROMPT_RESULT"
      NODE_VERSION="$(printf '%s' "$NODE_VERSION" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"

      if [[ -z "$NODE_VERSION" ]]; then
        return 0
      fi

      if is_valid_node_version "$NODE_VERSION"; then
        return 0
      fi

      echo "Invalid Node version. Use 24, 24.12, 24.12.0, lts/*, or lts/<name>." >&2
    done
  fi
}

# Best-effort lookup of the latest Node LTS major version.
latest_node_lts_major() {
  local releases=""
  local release=""
  local major=""

  if ! releases="$(curl -fsSL --connect-timeout 2 --max-time 5 https://nodejs.org/dist/index.json 2>/dev/null)"; then
    return 1
  fi

  if ! release="$(printf '%s' "$releases" | tr '{' '\n' | grep -m1 '"lts"[[:space:]]*:[[:space:]]*"[^"]\+"')"; then
    return 1
  fi

  major="$(printf '%s' "$release" | sed -nE 's/.*"version"[[:space:]]*:[[:space:]]*"v([0-9]+)(\.[0-9]+){0,2}".*/\1/p')"

  if [[ ! "$major" =~ ^[0-9]+$ ]]; then
    return 1
  fi

  printf '%s' "$major"
}

# Validate a Node version string for .nvmrc.
#
# Accepted formats:
# - 24
# - 24.12
# - 24.12.0
# - lts/*
# - lts/<name>
is_valid_node_version() {
  local value="$1"

  if [[ "$value" =~ ^[0-9]+$ ]]; then
    return 0
  fi

  if [[ "$value" =~ ^[0-9]+\.[0-9]+$ ]]; then
    return 0
  fi

  if [[ "$value" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    return 0
  fi

  if [[ "$value" =~ ^lts/\*$ ]]; then
    return 0
  fi

  if [[ "$value" =~ ^lts/[a-z0-9-]+$ ]]; then
    return 0
  fi

  return 1
}

# Write .nvmrc if a version is provided.
#
# Arguments:
#   $1  Node version string.
write_nvmrc() {
  local version="$1"

  if [[ -z "$version" ]]; then
    return 0
  fi

  printf '%s\n' "$version" > .nvmrc
}
