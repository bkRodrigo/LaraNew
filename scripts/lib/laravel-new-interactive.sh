#!/usr/bin/env bash

# laravel-new-interactive.sh
# Interactive service selection helpers for laravel-new.sh. This file is sourced by the main script.
# shellcheck disable=SC2034

prompt_for_optional_services() {
  local db_choice=""

  if [[ ! -t 0 ]]; then
    return 0
  fi

  if [[ "$DB_OPTION_SET" == "true" && "$CACHE_OPTION_SET" == "true" && "$MAIL_OPTION_SET" == "true" ]]; then
    return 0
  fi

  echo "Configure optional services:"
  echo ""

  if [[ "$DB_OPTION_SET" != "true" ]]; then
    if ! prompt_choice "Database" "1" "None" "MySQL" "PostgreSQL"; then
      return 1
    fi
    db_choice="$PROMPT_RESULT"
    case "$db_choice" in
      None)
        DB_ENABLED="false"
        DB_TYPE_RAW=""
        ;;
      MySQL)
        DB_ENABLED="true"
        DB_TYPE_RAW="MySQL"
        ;;
      PostgreSQL)
        DB_ENABLED="true"
        DB_TYPE_RAW="PostgreSQL"
        ;;
    esac
  fi

  if [[ "$CACHE_OPTION_SET" != "true" ]]; then
    if ! prompt_yes_no "Enable Redis cache?" "no"; then
      return 1
    fi
    if [[ "$PROMPT_RESULT" == "true" ]]; then
      CACHE_ENABLED="true"
    else
      CACHE_ENABLED="false"
    fi
  fi

  if [[ "$MAIL_OPTION_SET" != "true" ]]; then
    if ! prompt_yes_no "Enable Mailpit?" "no"; then
      return 1
    fi
    if [[ "$PROMPT_RESULT" == "true" ]]; then
      MAIL_ENABLED="true"
    else
      MAIL_ENABLED="false"
    fi
  fi

  echo ""
}

confirm_selected_options() {
  if [[ ! -t 0 ]]; then
    return 0
  fi

  if ! prompt_yes_no "Continue?" "yes"; then
    return 1
  fi

  if [[ "$PROMPT_RESULT" != "true" ]]; then
    echo "Stopped."
    return 1
  fi
}
