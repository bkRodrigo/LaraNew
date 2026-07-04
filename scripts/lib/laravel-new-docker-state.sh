#!/usr/bin/env bash

# laravel-new-docker-state.sh
# Scoped Docker Compose state checks for laravel-new.sh. This file is sourced by the main script.

DOCKER_STATE_CONTAINERS=()
DOCKER_STATE_NETWORKS=()
DOCKER_STATE_VOLUMES=()

_docker_state_contains() {
  local wanted="$1"
  shift
  local item=""

  for item in "$@"; do
    if [[ "$item" == "$wanted" ]]; then
      return 0
    fi
  done

  return 1
}

_docker_state_add_container() {
  local name="$1"

  if [[ -n "$name" ]] && ! _docker_state_contains "$name" "${DOCKER_STATE_CONTAINERS[@]}"; then
    DOCKER_STATE_CONTAINERS+=("$name")
  fi
}

_docker_state_add_network() {
  local name="$1"

  if [[ -n "$name" ]] && ! _docker_state_contains "$name" "${DOCKER_STATE_NETWORKS[@]}"; then
    DOCKER_STATE_NETWORKS+=("$name")
  fi
}

_docker_state_add_volume() {
  local name="$1"

  if [[ -n "$name" ]] && ! _docker_state_contains "$name" "${DOCKER_STATE_VOLUMES[@]}"; then
    DOCKER_STATE_VOLUMES+=("$name")
  fi
}

_docker_state_is_generated_container_name() {
  local project="$1"
  local name="$2"
  local dash_prefix="${project}-"
  local underscore_prefix="${project}_"
  local remainder=""

  if [[ "${name:0:${#dash_prefix}}" == "$dash_prefix" ]]; then
    remainder="${name:${#dash_prefix}}"
  elif [[ "${name:0:${#underscore_prefix}}" == "$underscore_prefix" ]]; then
    remainder="${name:${#underscore_prefix}}"
  else
    return 1
  fi

  [[ "$remainder" =~ ^(nginx|fpm|mysql|pgsql|redis|mailpit)[_-][0-9]+$ ]]
}

find_docker_compose_project_state() {
  local project="$1"
  local name=""

  DOCKER_STATE_CONTAINERS=()
  DOCKER_STATE_NETWORKS=()
  DOCKER_STATE_VOLUMES=()

  while IFS= read -r name || [[ -n "$name" ]]; do
    _docker_state_add_container "$name"
  done < <(docker ps -a --filter "label=com.docker.compose.project=${project}" --format '{{.Names}}')

  while IFS= read -r name || [[ -n "$name" ]]; do
    if _docker_state_is_generated_container_name "$project" "$name"; then
      _docker_state_add_container "$name"
    fi
  done < <(docker ps -a --format '{{.Names}}')

  while IFS= read -r name || [[ -n "$name" ]]; do
    _docker_state_add_network "$name"
  done < <(docker network ls --filter "label=com.docker.compose.project=${project}" --format '{{.Name}}')

  while IFS= read -r name || [[ -n "$name" ]]; do
    if [[ "$name" == "${project}_default" ]]; then
      _docker_state_add_network "$name"
    fi
  done < <(docker network ls --format '{{.Name}}')

  while IFS= read -r name || [[ -n "$name" ]]; do
    _docker_state_add_volume "$name"
  done < <(docker volume ls --filter "label=com.docker.compose.project=${project}" --format '{{.Name}}')

  while IFS= read -r name || [[ -n "$name" ]]; do
    if [[ "$name" == "${project}_mysql-data" || "$name" == "${project}_pgsql-data" ]]; then
      _docker_state_add_volume "$name"
    fi
  done < <(docker volume ls --format '{{.Name}}')
}

docker_compose_project_state_is_empty() {
  (( ${#DOCKER_STATE_CONTAINERS[@]} == 0 && ${#DOCKER_STATE_NETWORKS[@]} == 0 && ${#DOCKER_STATE_VOLUMES[@]} == 0 ))
}

print_docker_compose_project_state() {
  local name=""

  if (( ${#DOCKER_STATE_CONTAINERS[@]} > 0 )); then
    echo "  Containers:"
    for name in "${DOCKER_STATE_CONTAINERS[@]}"; do
      echo "    - $name"
    done
  fi

  if (( ${#DOCKER_STATE_NETWORKS[@]} > 0 )); then
    echo "  Networks:"
    for name in "${DOCKER_STATE_NETWORKS[@]}"; do
      echo "    - $name"
    done
  fi

  if (( ${#DOCKER_STATE_VOLUMES[@]} > 0 )); then
    echo "  Volumes:"
    for name in "${DOCKER_STATE_VOLUMES[@]}"; do
      echo "    - $name"
    done
  fi
}

cleanup_docker_compose_project_state() {
  if (( ${#DOCKER_STATE_CONTAINERS[@]} > 0 )); then
    docker rm -f "${DOCKER_STATE_CONTAINERS[@]}" >/dev/null
  fi

  if (( ${#DOCKER_STATE_NETWORKS[@]} > 0 )); then
    docker network rm "${DOCKER_STATE_NETWORKS[@]}" >/dev/null
  fi

  if (( ${#DOCKER_STATE_VOLUMES[@]} > 0 )); then
    docker volume rm "${DOCKER_STATE_VOLUMES[@]}" >/dev/null
  fi
}

ensure_docker_compose_project_state_clean() {
  local project="$1"

  find_docker_compose_project_state "$project"

  if docker_compose_project_state_is_empty; then
    return 0
  fi

  echo "Existing Docker Compose resources were found for project '${project}':"
  print_docker_compose_project_state
  echo ""
  echo "These resources live outside the project directory and can be reused by a new project."
  echo "Cleanup is required before creating '${project}'."

  if [[ ! -t 0 ]]; then
    echo "Error: non-interactive mode cannot approve Docker cleanup." >&2
    echo "      Remove the resources above, or rerun laravel-new interactively to approve scoped cleanup." >&2
    return 1
  fi

  if ! prompt_yes_no "Remove only these Docker resources now?" "no"; then
    return 1
  fi

  if [[ "$PROMPT_RESULT" != "true" ]]; then
    echo "Error: Docker cleanup is required before creating '${project}'." >&2
    return 1
  fi

  if ! cleanup_docker_compose_project_state; then
    echo "Error: failed to clean Docker Compose resources for '${project}'." >&2
    echo "      Remove the resources above and rerun laravel-new." >&2
    return 1
  fi

  echo "      ✓ Docker Compose state cleaned for '${project}'"
}
