#!/usr/bin/env bash

# laravel-new-args.sh
# Argument parsing for laravel-new.sh. This file is sourced by the main script.

# Parse CLI arguments and expose them as global variables.
#
# Outputs (globals):
#   APP_NAME       Project directory name to create.
#   DB_ENABLED     "true" if a database was requested.
#   DB_TYPE_RAW    Raw database value (e.g. MySQL, PostgreSQL).
#   CACHE_ENABLED  "true" if Redis cache was requested.
#   MAIL_ENABLED   "true" if Mailpit was requested.
#   NODE_VERSION_RAW Raw Node version value for .nvmrc (optional).
#   SHOW_HELP      "true" if help was requested.
#   PARSE_ERROR    Non-empty when a parsing error occurs.
parse_args() {
  # Reset all outputs for clean re-runs in the same shell.
  APP_NAME=""
  DB_ENABLED="false"
  DB_TYPE_RAW=""
  CACHE_ENABLED="false"
  MAIL_ENABLED="false"
  NODE_VERSION_RAW=""
  SHOW_HELP="false"
  PARSE_ERROR=""

  # Walk through the arguments in order.
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help|help)
        # Help can be requested anywhere and short-circuits validation.
        SHOW_HELP="true"
        shift
        ;;
      -d|-database|--database)
        # Database flag requires a value (MySQL or PostgreSQL).
        if [[ -z "${2:-}" || "${2:-}" == -* ]]; then
          PARSE_ERROR="Database flag requires a value (MySQL or PostgreSQL)."
          return 1
        fi
        DB_ENABLED="true"
        DB_TYPE_RAW="$2"
        shift 2
        ;;
      -c|-cache|--cache)
        # Cache flag enables Redis.
        CACHE_ENABLED="true"
        shift
        ;;
      -m|-mail|--mail)
        # Mail flag enables Mailpit.
        MAIL_ENABLED="true"
        shift
        ;;
      -n|--node|--node-version)
        # Optional Node version for .nvmrc.
        if [[ -z "${2:-}" || "${2:-}" == -* ]]; then
          PARSE_ERROR="Node flag requires a version value (e.g. 22, 22.12.0, lts/*, lts/<name>)."
          return 1
        fi
        NODE_VERSION_RAW="$2"
        shift 2
        ;;
      -* )
        # Any other switch is considered unsupported.
        PARSE_ERROR="Unknown option: $1"
        return 1
        ;;
      *)
        # First non-flag argument is the app name.
        if [[ -z "$APP_NAME" ]]; then
          APP_NAME="$1"
          shift
        else
          PARSE_ERROR="Unexpected argument: $1"
          return 1
        fi
        ;;
    esac
  done

  # If help is requested, skip further validation.
  if [[ "$SHOW_HELP" == "true" ]]; then
    return 0
  fi

  # Require an app name for non-help invocations.
  if [[ -z "$APP_NAME" ]]; then
    PARSE_ERROR="AppName is required."
    return 1
  fi
}
