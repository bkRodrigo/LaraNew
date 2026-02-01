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
  NODE_VERSION=""

  if [[ -n "$cli_value" ]]; then
    if ! is_valid_node_version "$cli_value"; then
      echo "Error: invalid Node version '$cli_value'. Use 22, 22.12, 22.12.0, lts/*, or lts/<name>." >&2
      return 1
    fi
    NODE_VERSION="$cli_value"
    return 0
  fi

  if [[ -t 0 ]]; then
    while true; do
      read -r -p "Please provide your target Node version for .nvmrc (leave blank to skip): " NODE_VERSION
      NODE_VERSION="$(printf '%s' "$NODE_VERSION" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"

      if [[ -z "$NODE_VERSION" ]]; then
        return 0
      fi

      if is_valid_node_version "$NODE_VERSION"; then
        return 0
      fi

      echo "Invalid Node version. Use 22, 22.12, 22.12.0, lts/*, or lts/<name>." >&2
    done
  fi
}

# Validate a Node version string for .nvmrc.
#
# Accepted formats:
# - 22
# - 22.12
# - 22.12.0
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
