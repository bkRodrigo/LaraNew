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
      print_node_version_prompt_options "$lts_major"
    else
      print_node_version_prompt_options ""
    fi

    while true; do
      if ! prompt_input "Node version"; then
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

# Print readable interactive choices for the optional .nvmrc version.
print_node_version_prompt_options() {
  local lts_major="$1"

  echo "Choose a Node version for .nvmrc:"
  if [[ -n "$lts_major" ]]; then
    echo "- Type ${lts_major} to pin the current latest LTS major."
  fi
  echo "- Type lts/* to always use the latest LTS supported by nvm."
  if [[ -n "$lts_major" ]]; then
    echo "- Type a specific patch version like ${lts_major}.12.0."
  else
    echo "- Type a specific version like 24, 24.12, or 24.12.0."
  fi
  echo "- Press Enter to skip .nvmrc creation."
  echo ""
}

# Best-effort lookup of the latest Node LTS major version.
latest_node_lts_major() {
  local node_lib_dir=""
  local lookup_script=""

  node_lib_dir="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  lookup_script="${node_lib_dir}/../latest-node-lts-major.sh"

  if [[ ! -x "$lookup_script" ]]; then
    return 1
  fi

  "$lookup_script"
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
