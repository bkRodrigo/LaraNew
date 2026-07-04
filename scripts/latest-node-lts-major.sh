#!/usr/bin/env bash

# latest-node-lts-major.sh
# Print the latest Node LTS major version from the public Node release index.

set -euo pipefail

release_index_url="${NODE_RELEASE_INDEX_URL:-https://nodejs.org/dist/index.json}"
connect_timeout="${NODE_RELEASE_CONNECT_TIMEOUT:-5}"
max_time="${NODE_RELEASE_MAX_TIME:-15}"
releases=""
release=""
major=""

if ! releases="$(curl -fsSL --connect-timeout "$connect_timeout" --max-time "$max_time" "$release_index_url" 2>/dev/null)"; then
  exit 1
fi

if ! release="$(printf '%s' "$releases" | tr '{' '\n' | grep '"lts"[[:space:]]*:[[:space:]]*"[^"]\+"' | sed -n '1p')"; then
  exit 1
fi

major="$(printf '%s' "$release" | sed -nE 's/.*"version"[[:space:]]*:[[:space:]]*"v([0-9]+)(\.[0-9]+){0,2}".*/\1/p')"

if [[ ! "$major" =~ ^[0-9]+$ ]]; then
  exit 1
fi

printf '%s\n' "$major"
