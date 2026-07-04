#!/usr/bin/env bash

# laravel-new-compose-recovery.sh
# Recovery helpers for transient apt/network failures during docker compose builds.
# shellcheck disable=SC2034

compose_append_file_to_log() {
  local file="$1"
  local line=""

  while IFS= read -r line || [[ -n "$line" ]]; do
    printf '%s\n' "$line" >>"$LOG_TMP"
  done <"$file"
}

compose_run_logged_attempt() {
  local desc="$1"
  local cmd="$2"
  local attempt_log="$3"
  local status=0

  log_note "$desc"
  if bash -c "$cmd" >"$attempt_log" 2>&1; then
    compose_append_file_to_log "$attempt_log"
    return 0
  else
    status=$?
    compose_append_file_to_log "$attempt_log"
    return "$status"
  fi
}

compose_log_has_transient_apt_failure() {
  local attempt_log="$1"
  local pattern=""

  while IFS= read -r pattern || [[ -n "$pattern" ]]; do
    if grep -qi -- "$pattern" "$attempt_log"; then
      return 0
    fi
  done <<'EOF'
Mirror sync in progress
File has unexpected size
Hash Sum mismatch
Failed to fetch
Unable to fetch some archives
Temporary failure resolving
Connection timed out
EOF

  return 1
}

compose_fail_with_log() {
  local message="$1"

  echo "      ✗ $message"
  show_log_tail
  LOG_KEEP="true"
  finalize_log
  return 1
}

compose_up_with_recovery() {
  local compose_cmd="docker compose up -d --build"
  local retry_cmd="APT_INSTALL_FLAGS=--fix-missing docker compose up -d --build"
  local normal_attempts=2
  local retry_delay=3
  local attempt=1
  local desc=""
  local attempt_log=""

  while (( attempt <= normal_attempts )); do
    attempt_log="$(mktemp -t laravel-new-compose.XXXXXX.log)"
    desc="Compose up"
    if (( normal_attempts > 1 )); then
      desc="Compose up (attempt ${attempt}/${normal_attempts})"
    fi

    if compose_run_logged_attempt "$desc" "$compose_cmd" "$attempt_log"; then
      rm -f "$attempt_log"
      if (( attempt > 1 )); then
        echo "      ✓ Compose up succeeded on retry ${attempt}"
      fi
      return 0
    fi

    if ! compose_log_has_transient_apt_failure "$attempt_log"; then
      rm -f "$attempt_log"
      compose_fail_with_log "Compose up failed"
      return 1
    fi

    rm -f "$attempt_log"

    if (( attempt < normal_attempts )); then
      echo "      - Compose build failed during apt/package download; retrying (${attempt}/${normal_attempts})..."
      sleep "$retry_delay"
    fi

    attempt=$((attempt + 1))
  done

  echo "      - Compose build still appears to be failing during apt/package download."

  if [[ ! -t 0 ]]; then
    echo "      Non-interactive mode: not trying apt-get --fix-missing. Rerun later, or run interactively to review the recovery prompt."
    compose_fail_with_log "Compose up failed"
    return 1
  fi

  echo "      A one-time apt-get --fix-missing retry may help with transient mirror issues."
  echo "      It can also mask package-resolution problems or produce confusing follow-up errors."
  if ! prompt_yes_no "Try once with apt-get --fix-missing?" "no"; then
    compose_fail_with_log "Compose up failed"
    return 1
  fi

  if [[ "$PROMPT_RESULT" != "true" ]]; then
    echo "      Skipped apt-get --fix-missing recovery."
    compose_fail_with_log "Compose up failed"
    return 1
  fi

  attempt_log="$(mktemp -t laravel-new-compose.XXXXXX.log)"
  if compose_run_logged_attempt "Compose up (--fix-missing recovery)" "$retry_cmd" "$attempt_log"; then
    rm -f "$attempt_log"
    echo "      ✓ Compose up succeeded with one-time apt-get --fix-missing recovery"
    return 0
  fi

  rm -f "$attempt_log"
  compose_fail_with_log "Compose up failed"
  return 1
}
