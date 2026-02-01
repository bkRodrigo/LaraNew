#!/usr/bin/env bash

# render-dockerfile.sh
# Render a Dockerfile from a base template plus optional DB-specific values.
#
# Usage:
#   render-dockerfile.sh <base-template> <variant-file|''> <output-file>

set -euo pipefail

if [[ $# -ne 3 ]]; then
  echo "Usage: render-dockerfile.sh <base-template> <variant-file|''> <output-file>" >&2
  exit 1
fi

BASE_TEMPLATE="$1"
VARIANT_FILE="$2"
OUTPUT_FILE="$3"

if [[ ! -f "$BASE_TEMPLATE" ]]; then
  echo "Error: base template not found: $BASE_TEMPLATE" >&2
  exit 1
fi

DB_DEV_LIBS=()
DB_PDO_EXTS=()

if [[ -n "$VARIANT_FILE" ]]; then
  if [[ ! -f "$VARIANT_FILE" ]]; then
    echo "Error: variant file not found: $VARIANT_FILE" >&2
    exit 1
  fi

  # shellcheck disable=SC1090
  source "$VARIANT_FILE"
fi

normalize_array() {
  local name="$1"
  local decl

  if ! decl=$(declare -p "$name" 2>/dev/null); then
    return
  fi

  if [[ "$decl" != declare\ -a* ]]; then
    local value="${!name}"
    # shellcheck disable=SC2206
    eval "$name=( $value )"
  fi
}

normalize_array DB_DEV_LIBS
normalize_array DB_PDO_EXTS

mkdir -p "$(dirname "$OUTPUT_FILE")"

{
  while IFS= read -r line || [[ -n "$line" ]]; do
    case "$line" in
      "__DB_DEV_LIBS__")
        for item in "${DB_DEV_LIBS[@]}"; do
          printf '        %s \\\n' "$item"
        done
        ;;
      "__DB_PDO_EXTS__")
        for item in "${DB_PDO_EXTS[@]}"; do
          printf '        %s \\\n' "$item"
        done
        ;;
      *)
        printf '%s\n' "$line"
        ;;
    esac
  done < "$BASE_TEMPLATE"
} > "$OUTPUT_FILE"
