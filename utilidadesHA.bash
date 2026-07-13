#!/bin/bash

# v2.3, Author @danieldiazi
set -Eeuo pipefail

MESSAGE_TITLE="utilidadesHA: tools script for HA Container"
MESSAGE_CONFIG_FAIL="I can't read config file"
MESSAGE_USAGE="Usage"
MESSAGE_HARDWARE_NOT_SUPPORTED="Hardware not supported!"

SYSTEM_LANGUAGE=${LANG:-en}
SYSTEM_LANGUAGE=${SYSTEM_LANGUAGE:0:2}
myPath=$(cd "$(dirname "$0")" && pwd)
SCRIPT=$(basename "$0")
DRY_RUN=0
ACTION=""
UPDATE_TAG=""
LOCK_FILE="/tmp/utilidadesHA.lock"

if [[ -f "${myPath}/locales/${SYSTEM_LANGUAGE}" ]]; then
  # shellcheck disable=SC1090
  source "${myPath}/locales/${SYSTEM_LANGUAGE}"
fi

log_info() {
  printf '[INFO] %s\n' "$*"
  if command -v logger >/dev/null 2>&1; then
    logger "$SCRIPT: $*" || true
  fi
}

log_warn() {
  printf '[WARN] %s\n' "$*" >&2
  if command -v logger >/dev/null 2>&1; then
    logger "$SCRIPT: WARNING: $*" || true
  fi
}

log_error() {
  printf '[ERROR] %s\n' "$*" >&2
  if command -v logger >/dev/null 2>&1; then
    logger "$SCRIPT: ERROR: $*" || true
  fi
}

die() { log_error "$*"; exit 1; }

run_mutating() {
  if (( DRY_RUN )); then
    printf '[DRY-RUN]'; printf ' %q' "$@"; printf '\n'
    return 0
  fi
  "$@"
}

usage() {
  cat <<USAGE
${MESSAGE_TITLE}

${MESSAGE_USAGE}:
  $SCRIPT -i [--dry-run]               Install Home Assistant
  $SCRIPT -u [-f] [-t TAG] [--dry-run] Update Home Assistant
  $SCRIPT -c                           Check local and available versions
  $SCRIPT -b FOLDER [--dry-run]        Create a backup
  $SCRIPT -g FOLDER [--dry-run]        Create an encrypted GPG backup
  $SCRIPT -r                           Show GPG recovery instructions
  $SCRIPT -h                           Show this help

Compatibility: -f and -t TAG without -u still trigger an update.
USAGE
}

require_command() { command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"; }
require_value() { [[ -n "${2:-}" ]] || die "$1 is not configured"; }

load_config() {
  local config="${myPath}/utilidadesHA.config"
  [[ -r "$config" ]] || die "$MESSAGE_CONFIG_FAIL: $config"
  # shellcheck disable=SC1090
  source "$config"
  FORCE=${FORCE:-0}
}

validate_common_config() {
  require_value PATH_HA_CONFIG "${PATH_HA_CONFIG:-}"
  require_value NAME_CONTAINER "${NAME_CONTAINER:-}"
  require_value TAG_DOCKER "${TAG_DOCKER:-}"
  [[ "$PATH_HA_CONFIG" == /* ]] || die "PATH_HA_CONFIG must be an absolute path"
  [[ -z "${PATH_HA_MEDIA:-}" || "$PATH_HA_MEDIA" == /* ]] || die "PATH_HA_MEDIA must be an absolute path"
  [[ -z "${PATH_HA_SSL:-}" || "$PATH_HA_SSL" == /* ]] || die "PATH_HA_SSL must be an absolute path"
}

acquire_lock() {
  require_command flock
  exec 9>"$LOCK_FILE"
  flock -n 9 || die "Another utilidadesHA process is already running"
}

check_hardware() {
  local arch model=""
  arch=$(uname -m)
  case "$arch" in
    x86_64) HARDWARE="x86_64" ;;
    aarch64|arm64)
      [[ -r /proc/device-tree/model ]] && model=$(tr -d '\0' </proc/device-tree/model)
      case "$model" in
        *"Raspberry Pi 3"*) HARDWARE="RPI3" ;;
        *"Raspberry Pi 4"*) HARDWARE="RPI4" ;;
        *) HARDWARE="aarch64" ;;
      esac
      ;;
    *) die "$MESSAGE_HARDWARE_NOT_SUPPORTED ($arch)" ;;
  esac
  log_info "Detected hardware: $HARDWARE"
}

select_image() {
  case "$HARDWARE" in
    RPI3) IMAGE_DOCKER=${IMAGE_DOCKER_RPI3:-} ;;
    RPI4) IMAGE_DOCKER=${IMAGE_DOCKER_RPI4:-} ;;
    x86_64) IMAGE_DOCKER=${IMAGE_DOCKER_x86_64:-} ;;
    aarch64) IMAGE_DOCKER=${IMAGE_DOCKER_aarch64:-} ;;
  esac
  require_value IMAGE_DOCKER "${IMAGE_DOCKER:-}"
}

build_docker_args() {
  docker_args=(
    -d
    --name="$NAME_CONTAINER"
    --restart unless-stopped
    -v "$PATH_HA_CONFIG:/config"
    -v /etc/localtime:/etc/localtime:ro
    --net=host
  )
  [[ -n "${USB_ZIGBEE:-}" ]] && docker_args+=(--device="$USB_ZIGBEE")
  [[ -n "${PATH_HA_MEDIA:-}" ]] && docker_args+=(-v "$PATH_HA_MEDIA:/media")
  [[ -n "${PATH_HA_SSL:-}" && -n "${PATH_HA_SSL_CONTAINER:-}" ]] && docker_args+=(-v "$PATH_HA_SSL:$PATH_HA_SSL_CONTAINER")
  [[ -n "${PATH_HA_DBUS:-}" && -n "${PATH_HA_DBUS_CONTAINER:-}" ]] && docker_args+=(-v "$PATH_HA_DBUS:$PATH_HA_DBUS_CONTAINER:ro")
}

container_exists() { docker inspect "$NAME_CONTAINER" >/dev/null 2>&1; }
container_running() { [[ "$(docker inspect -f '{{.State.Running}}' "$NAME_CONTAINER" 2>/dev/null || true)" == "true" ]]; }

check_version() {
  local image_ref="$IMAGE_DOCKER:$TAG_DOCKER"
  if (( DRY_RUN )); then
    log_info "Dry-run: skipping docker pull for $image_ref"
  else
    docker pull "$image_ref" >/dev/null
  fi
  VERSION_WEB=$(docker image inspect "$image_ref" --format '{{ index .Config.Labels "io.hass.version" }}' 2>/dev/null || true)
  VERSION_INSTALLED="not installed"
  [[ -r "$PATH_HA_CONFIG/.HA_VERSION" ]] && VERSION_INSTALLED=$(<"$PATH_HA_CONFIG/.HA_VERSION")
  [[ -n "$VERSION_WEB" ]] || VERSION_WEB="unknown"
  log_info "Available: $VERSION_WEB | Installed: $VERSION_INSTALLED"
}

rollback_container() {
  local old_image="$1"
  [[ -n "$old_image" ]] || return 1
  log_warn "New container failed; restoring previous image $old_image"
  run_mutating docker rm -f "$NAME_CONTAINER" >/dev/null 2>&1 || true
  run_mutating docker run "${docker_args[@]}" "$old_image"
}

update_home_assistant() {
  local image_ref="$IMAGE_DOCKER:$TAG_DOCKER" old_image="" had_container=0
  check_version
  if [[ "$VERSION_WEB" == "$VERSION_INSTALLED" && "$FORCE" != "1" ]]; then
    log_info "Home Assistant is already up to date"
    return 0
  fi

  build_docker_args
  if container_exists; then
    had_container=1
    old_image=$(docker inspect -f '{{.Image}}' "$NAME_CONTAINER")
  fi

  run_mutating docker pull "$image_ref"
  if (( had_container )); then
    run_mutating docker stop "$NAME_CONTAINER"
    run_mutating docker rm "$NAME_CONTAINER"
  fi

  if ! run_mutating docker run "${docker_args[@]}" "$image_ref"; then
    rollback_container "$old_image" || true
    die "Could not start the new Home Assistant container"
  fi

  if (( ! DRY_RUN )); then
    sleep 3
    if ! container_running; then
      rollback_container "$old_image" || true
      die "The new Home Assistant container is not running"
    fi
  fi
  log_info "Update completed successfully"
}

backup_cleanup() {
  if [[ "${BACKUP_RESTART_NEEDED:-0}" == "1" ]]; then
    run_mutating docker start "$NAME_CONTAINER" >/dev/null || log_error "Could not restart $NAME_CONTAINER"
    BACKUP_RESTART_NEEDED=0
  fi
}

backup_home_assistant() {
  local subfolder="$1" encryption="${2:-}" destination file archive
  require_value FOLDER_BACKUP "${FOLDER_BACKUP:-}"
  [[ "$FOLDER_BACKUP" == /* ]] || die "FOLDER_BACKUP must be an absolute path"
  destination="${FOLDER_BACKUP%/}/$subfolder"
  [[ -d "$destination" ]] || die "Backup folder does not exist: $destination"
  [[ -w "$destination" ]] || die "Backup folder is not writable: $destination"
  [[ -d "$PATH_HA_CONFIG" ]] || die "Home Assistant configuration folder does not exist: $PATH_HA_CONFIG"

  if [[ "$encryption" == "gpg" ]]; then
    require_command gpg
    require_value RECIPIENT_GPG "${RECIPIENT_GPG:-}"
  fi

  file="$(date +'%Y%m%d-%H%M%S')-HA-backup.tgz"
  archive="$destination/$file"
  BACKUP_RESTART_NEEDED=0
  trap backup_cleanup RETURN

  if container_running; then
    run_mutating docker stop "$NAME_CONTAINER"
    BACKUP_RESTART_NEEDED=1
  fi

  run_mutating tar -czf "$archive" -C "$(dirname "$PATH_HA_CONFIG")" "$(basename "$PATH_HA_CONFIG")"
  if [[ "$encryption" == "gpg" ]]; then
    run_mutating gpg --batch --yes --encrypt --recipient "$RECIPIENT_GPG" "$archive"
    run_mutating rm -f "$archive"
    archive="$archive.gpg"
  fi

  backup_cleanup
  trap - RETURN
  log_info "Backup created: $archive"
}

new_install() {
  require_value PATH_HA_MEDIA "${PATH_HA_MEDIA:-}"
  if [[ -f "$PATH_HA_CONFIG/.HA_VERSION" ]]; then
    log_info "Home Assistant is already installed; running update"
  else
    run_mutating mkdir -p "$PATH_HA_CONFIG" "$PATH_HA_MEDIA"
  fi
  FORCE=1
  update_home_assistant
}

parse_args() {
  (( $# > 0 )) || { usage; exit 1; }
  while (( $# )); do
    case "$1" in
      -i) ACTION="install" ;;
      -u) ACTION="update" ;;
      -c) ACTION="check" ;;
      -b) ACTION="backup"; shift; BACKUP_SUBFOLDER=${1:-}; require_value "backup folder" "$BACKUP_SUBFOLDER" ;;
      -g) ACTION="backup_gpg"; shift; BACKUP_SUBFOLDER=${1:-}; require_value "backup folder" "$BACKUP_SUBFOLDER" ;;
      -r) ACTION="recover" ;;
      -f) FORCE=1; [[ -z "$ACTION" ]] && ACTION="update" ;;
      -t) shift; UPDATE_TAG=${1:-}; require_value "tag" "$UPDATE_TAG"; ACTION="update" ;;
      --dry-run) DRY_RUN=1 ;;
      -h|--help) usage; exit 0 ;;
      *) die "Unknown option: $1" ;;
    esac
    shift
  done
}

main() {
  printf '%s\n' '-------------------------------------------' "$MESSAGE_TITLE" '-------------------------------------------'
  load_config
  parse_args "$@"
  validate_common_config
  require_command docker
  acquire_lock
  check_hardware
  select_image
  [[ -n "$UPDATE_TAG" ]] && TAG_DOCKER="$UPDATE_TAG"

  case "$ACTION" in
    install) new_install ;;
    update) update_home_assistant ;;
    check) check_version ;;
    backup) backup_home_assistant "$BACKUP_SUBFOLDER" ;;
    backup_gpg) backup_home_assistant "$BACKUP_SUBFOLDER" gpg ;;
    recover) printf 'gpg --decrypt file.tgz.gpg > backup.tgz\n' ;;
    *) usage; exit 1 ;;
  esac
}

main "$@"
