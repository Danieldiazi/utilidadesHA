#!/bin/bash

# v2.4, Author @danieldiazi
set -Eeuo pipefail

MESSAGE_TITLE="utilidadesHA: script para Home Assistant Container"
MESSAGE_CONFIG_FAIL="No se puede leer el fichero de configuración"
MESSAGE_USAGE="Uso"
MESSAGE_HARDWARE_NOT_SUPPORTED="Hardware no compatible"

SYSTEM_LANGUAGE=${LANG:-es}
SYSTEM_LANGUAGE=${SYSTEM_LANGUAGE:0:2}
myPath=$(cd "$(dirname "$0")" && pwd)
SCRIPT=$(basename "$0")
DRY_RUN=0
ACTION=""
UPDATE_TAG=""
BACKUP_SUBFOLDER=""
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

die() {
  log_error "$*"
  exit 1
}

run_mutating() {
  if (( DRY_RUN )); then
    printf '[DRY-RUN]'
    printf ' %q' "$@"
    printf '\n'
    return 0
  fi
  "$@"
}

usage() {
  cat <<USAGE
${MESSAGE_TITLE}

${MESSAGE_USAGE}:
  $SCRIPT -i [--dry-run]
      Instala Home Assistant Container.
      Crea las carpetas configuradas y levanta el contenedor.
      Si Home Assistant ya está instalado, realiza una actualización forzada.

  $SCRIPT -u [-f] [-t ETIQUETA] [--dry-run]
      Actualiza Home Assistant usando la imagen configurada.

      -f
          Fuerza la recreación del contenedor aunque la versión instalada
          coincida con la versión disponible.

      -t ETIQUETA
          Usa una versión concreta de la imagen en lugar de TAG_DOCKER.
          Ejemplo: -t 2026.7.1

      --dry-run
          Muestra los comandos que modificarían el sistema, pero no los ejecuta.
          Es recomendable usarlo antes de una instalación o actualización real.

  $SCRIPT -c
      Descarga la información de la imagen y muestra la versión disponible
      y la versión instalada.

  $SCRIPT -b CARPETA [--dry-run]
      Crea una copia comprimida de PATH_HA_CONFIG en:
      FOLDER_BACKUP/CARPETA

      La carpeta indicada debe existir y tener permisos de escritura.
      Home Assistant se detiene durante la copia y se vuelve a iniciar,
      incluso si la creación del archivo falla.

  $SCRIPT -h | --help
      Muestra esta ayuda.

Ejemplos:
  $SCRIPT -u --dry-run
  $SCRIPT -u
  $SCRIPT -u -f
  $SCRIPT -u -t 2026.7.1
  $SCRIPT -b diario
USAGE
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "No se encontró el comando requerido: $1"
}

require_value() {
  [[ -n "${2:-}" ]] || die "$1 no está configurado"
}

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

  [[ "$PATH_HA_CONFIG" == /* ]] || die "PATH_HA_CONFIG debe ser una ruta absoluta"
  [[ -z "${PATH_HA_MEDIA:-}" || "$PATH_HA_MEDIA" == /* ]] || die "PATH_HA_MEDIA debe ser una ruta absoluta"
  [[ -z "${PATH_HA_SSL:-}" || "$PATH_HA_SSL" == /* ]] || die "PATH_HA_SSL debe ser una ruta absoluta"
  [[ -z "${PATH_HA_DBUS:-}" || "$PATH_HA_DBUS" == /* ]] || die "PATH_HA_DBUS debe ser una ruta absoluta"
}

acquire_lock() {
  require_command flock
  exec 9>"$LOCK_FILE"
  flock -n 9 || die "Ya hay otro proceso de utilidadesHA en ejecución"
}

check_hardware() {
  local arch model=""
  arch=$(uname -m)

  case "$arch" in
    x86_64)
      HARDWARE="x86_64"
      ;;
    aarch64|arm64)
      if [[ -r /proc/device-tree/model ]]; then
        model=$(tr -d '\0' </proc/device-tree/model)
      fi
      case "$model" in
        *"Raspberry Pi 3"*) HARDWARE="RPI3" ;;
        *"Raspberry Pi 4"*) HARDWARE="RPI4" ;;
        *) HARDWARE="aarch64" ;;
      esac
      ;;
    *)
      die "$MESSAGE_HARDWARE_NOT_SUPPORTED ($arch)"
      ;;
  esac

  log_info "Hardware detectado: $HARDWARE"
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
  [[ -n "${PATH_HA_SSL:-}" && -n "${PATH_HA_SSL_CONTAINER:-}" ]] \
    && docker_args+=(-v "$PATH_HA_SSL:$PATH_HA_SSL_CONTAINER")
  [[ -n "${PATH_HA_DBUS:-}" && -n "${PATH_HA_DBUS_CONTAINER:-}" ]] \
    && docker_args+=(-v "$PATH_HA_DBUS:$PATH_HA_DBUS_CONTAINER:ro")
}

container_exists() {
  docker inspect "$NAME_CONTAINER" >/dev/null 2>&1
}

container_running() {
  [[ "$(docker inspect -f '{{.State.Running}}' "$NAME_CONTAINER" 2>/dev/null || true)" == "true" ]]
}

check_version() {
  local image_ref="$IMAGE_DOCKER:$TAG_DOCKER"

  if (( DRY_RUN )); then
    log_info "Simulación: no se descarga la imagen $image_ref"
  else
    docker pull "$image_ref" >/dev/null
  fi

  VERSION_WEB=$(docker image inspect "$image_ref" \
    --format '{{ index .Config.Labels "io.hass.version" }}' 2>/dev/null || true)

  VERSION_INSTALLED="no instalado"
  if [[ -r "$PATH_HA_CONFIG/.HA_VERSION" ]]; then
    VERSION_INSTALLED=$(<"$PATH_HA_CONFIG/.HA_VERSION")
  fi

  [[ -n "$VERSION_WEB" ]] || VERSION_WEB="desconocida"
  log_info "Disponible: $VERSION_WEB | Instalada: $VERSION_INSTALLED"
}

rollback_container() {
  local old_image="$1"
  [[ -n "$old_image" ]] || return 1

  log_warn "El contenedor nuevo falló; restaurando la imagen anterior $old_image"
  run_mutating docker rm -f "$NAME_CONTAINER" >/dev/null 2>&1 || true
  run_mutating docker run "${docker_args[@]}" "$old_image"
}

update_home_assistant() {
  local image_ref="$IMAGE_DOCKER:$TAG_DOCKER"
  local old_image=""
  local had_container=0

  check_version

  if [[ "$VERSION_WEB" == "$VERSION_INSTALLED" && "$FORCE" != "1" ]]; then
    log_info "Home Assistant ya está actualizado"
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
    die "No se pudo iniciar el contenedor nuevo de Home Assistant"
  fi

  if (( ! DRY_RUN )); then
    sleep 3
    if ! container_running; then
      rollback_container "$old_image" || true
      die "El contenedor nuevo de Home Assistant no está en ejecución"
    fi
  fi

  log_info "Actualización completada correctamente"
}

backup_cleanup() {
  if [[ "${BACKUP_RESTART_NEEDED:-0}" == "1" ]]; then
    run_mutating docker start "$NAME_CONTAINER" >/dev/null \
      || log_error "No se pudo reiniciar $NAME_CONTAINER"
    BACKUP_RESTART_NEEDED=0
  fi
}

backup_home_assistant() {
  local subfolder="$1"
  local destination file archive

  require_command tar
  require_value FOLDER_BACKUP "${FOLDER_BACKUP:-}"
  [[ "$FOLDER_BACKUP" == /* ]] || die "FOLDER_BACKUP debe ser una ruta absoluta"

  destination="${FOLDER_BACKUP%/}/$subfolder"
  [[ -d "$destination" ]] || die "La carpeta de backup no existe: $destination"
  [[ -w "$destination" ]] || die "La carpeta de backup no permite escritura: $destination"
  [[ -d "$PATH_HA_CONFIG" ]] \
    || die "No existe la carpeta de configuración: $PATH_HA_CONFIG"

  file="$(date +'%Y%m%d-%H%M%S')-HA-backup.tgz"
  archive="$destination/$file"
  BACKUP_RESTART_NEEDED=0
  trap backup_cleanup RETURN

  if container_running; then
    run_mutating docker stop "$NAME_CONTAINER"
    BACKUP_RESTART_NEEDED=1
  fi

  run_mutating tar -czf "$archive" \
    -C "$(dirname "$PATH_HA_CONFIG")" "$(basename "$PATH_HA_CONFIG")"

  backup_cleanup
  trap - RETURN
  log_info "Backup creado: $archive"
}

new_install() {
  require_value PATH_HA_MEDIA "${PATH_HA_MEDIA:-}"

  if [[ -f "$PATH_HA_CONFIG/.HA_VERSION" ]]; then
    log_info "Home Assistant ya está instalado; se realizará una actualización"
  else
    run_mutating mkdir -p "$PATH_HA_CONFIG" "$PATH_HA_MEDIA"
  fi

  FORCE=1
  update_home_assistant
}

parse_args() {
  (( $# > 0 )) || {
    usage
    exit 1
  }

  while (( $# )); do
    case "$1" in
      -i)
        ACTION="install"
        ;;
      -u)
        ACTION="update"
        ;;
      -c)
        ACTION="check"
        ;;
      -b)
        ACTION="backup"
        shift
        BACKUP_SUBFOLDER=${1:-}
        require_value "La carpeta de backup" "$BACKUP_SUBFOLDER"
        ;;
      -f)
        FORCE=1
        [[ -z "$ACTION" ]] && ACTION="update"
        ;;
      -t)
        shift
        UPDATE_TAG=${1:-}
        require_value "La etiqueta" "$UPDATE_TAG"
        ACTION="update"
        ;;
      --dry-run)
        DRY_RUN=1
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        die "Opción desconocida: $1"
        ;;
    esac
    shift
  done
}

main() {
  printf '%s\n' \
    '-------------------------------------------' \
    "$MESSAGE_TITLE" \
    '-------------------------------------------'

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
    *) usage; exit 1 ;;
  esac
}

main "$@"
