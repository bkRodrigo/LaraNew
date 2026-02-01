#!/usr/bin/env bash

# laravel-new-cleanup.sh
# Cleanup helpers for laravel-new.sh. This file is sourced by the main script.

# Clean up a failed project creation attempt.
#
# Arguments:
#   $1  Project directory to clean.
#   $2  Short reason for cleanup (optional).
cleanup_failed_setup() {
  local project_dir="$1"
  local reason="${2:-Preflight checks failed}"
  local log_target=""

  echo "      ✗ ${reason}"

  if [[ -n "${LOG_TMP:-}" && -f "${LOG_TMP:-}" ]]; then
    LOG_KEEP="true"
    if [[ -n "${LOG_ROOT_DIR:-}" && -n "${LOG_APP_NAME:-}" ]]; then
      log_target="${LOG_ROOT_DIR}/.laravel-new.${LOG_APP_NAME}.log"
      LOG_TARGET="$log_target"
    fi
    finalize_log
  fi

  if [[ -z "$project_dir" ]]; then
    return 1
  fi

  if [[ "$project_dir" == "/" || "$project_dir" == "$HOME" ]]; then
    echo "      Cleanup skipped (unsafe target): $project_dir" >&2
    return 1
  fi

  if [[ -d "$project_dir" ]]; then
    (
      cd "$project_dir" || exit 0
      docker compose down -v >/dev/null 2>&1 || true
    )
    rm -rf "$project_dir"
    echo "      Cleanup complete: removed $project_dir"
  fi
}
