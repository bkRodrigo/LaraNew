#!/usr/bin/env bash

# laravel-new-prompt.sh
# Reusable interactive prompt helpers. This file is sourced by the main script.
# shellcheck disable=SC2034

prompt_input() {
  local message="$1"
  local default_value="${2:-}"
  local answer=""

  PROMPT_RESULT=""

  if [[ ! -t 0 ]]; then
    return 1
  fi

  if [[ -n "$default_value" ]]; then
    read -r -p "${message} [${default_value}]: " answer
    PROMPT_RESULT="${answer:-$default_value}"
  else
    read -r -p "${message}: " answer
    PROMPT_RESULT="$answer"
  fi
}

prompt_yes_no() {
  local message="$1"
  local default_value="$2"
  local prompt_suffix=""
  local answer=""

  PROMPT_RESULT=""

  if [[ ! -t 0 ]]; then
    return 1
  fi

  case "$default_value" in
    y|Y|yes|YES|Yes|true)
      prompt_suffix="[Y/n]"
      default_value="true"
      ;;
    n|N|no|NO|No|false)
      prompt_suffix="[y/N]"
      default_value="false"
      ;;
    *)
      echo "Error: prompt_yes_no default must be yes or no." >&2
      return 1
      ;;
  esac

  while true; do
    read -r -p "${message} ${prompt_suffix} " answer
    case "$answer" in
      "")
        PROMPT_RESULT="$default_value"
        return 0
        ;;
      y|Y|yes|YES|Yes)
        PROMPT_RESULT="true"
        return 0
        ;;
      n|N|no|NO|No)
        PROMPT_RESULT="false"
        return 0
        ;;
      *)
        echo "Please answer yes or no."
        ;;
    esac
  done
}

prompt_choice() {
  local message="$1"
  local default_index="$2"
  shift 2
  local options=("$@")
  local option_count="${#options[@]}"
  local index=""
  local answer=""

  PROMPT_RESULT=""

  if [[ ! -t 0 ]]; then
    return 1
  fi

  if [[ ! "$default_index" =~ ^[0-9]+$ ]] || (( default_index < 1 || default_index > option_count )); then
    echo "Error: prompt_choice default index is out of range." >&2
    return 1
  fi

  echo "$message"
  for index in $(seq 1 "$option_count"); do
    echo "  ${index}) ${options[$((index - 1))]}"
  done

  while true; do
    read -r -p "Choose ${message} [${default_index}]: " answer
    answer="${answer:-$default_index}"

    if [[ ! "$answer" =~ ^[0-9]+$ ]] || (( answer < 1 || answer > option_count )); then
      echo "Choose a number between 1 and ${option_count}."
      continue
    fi

    PROMPT_RESULT="${options[$((answer - 1))]}"
    return 0
  done
}
