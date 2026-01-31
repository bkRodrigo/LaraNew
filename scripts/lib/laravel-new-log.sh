#!/usr/bin/env bash

# laravel-new-log.sh
# Logging helpers for laravel-new.sh. This file is sourced by the main script.

# Initialize log paths and reset the logging state.
#
# Arguments:
#   $1  Root directory where the project will be created.
#   $2  App name used for the final log path.
init_log() {
  local root_dir="$1"
  local app_name="$2"

  LOG_ROOT_DIR="$root_dir"
  LOG_APP_NAME="$app_name"
  LOG_TARGET="${root_dir}/${app_name}/.laravel-new.log"
  LOG_TMP="$(mktemp -t laravel-new.XXXXXX.log)"
  LOG_KEEP="false"
}

# Append a readable marker to the log.
log_note() {
  local note="$1"
  echo "== ${note} ==" >>"$LOG_TMP"
}

# Show the last 40 lines of the log with indentation.
show_log_tail() {
  echo "      Last 40 lines of log:"
  tail -n 40 "$LOG_TMP" | sed 's/^/      | /'
}

# Persist the log when needed, otherwise delete it.
finalize_log() {
  if [[ "$LOG_KEEP" == "true" ]]; then
    mkdir -p "$(dirname "$LOG_TARGET")"
    mv "$LOG_TMP" "$LOG_TARGET"
    echo "      Log saved to: $LOG_TARGET"
  else
    rm -f "$LOG_TMP"
  fi
}

# Run a command (as a string) and capture output to the log.
# Prints the last 40 lines on failure and keeps the log.
#
# Arguments:
#   $1  Description for the log.
#   $2  Command string to execute.
run_logged() {
  local desc="$1"
  local cmd="$2"

  log_note "$desc"
  if ! bash -c "$cmd" >>"$LOG_TMP" 2>&1; then
    echo "      ✗ $desc failed"
    show_log_tail
    LOG_KEEP="true"
    finalize_log
    return 1
  fi
}
