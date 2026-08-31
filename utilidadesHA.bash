#!/bin/bash

# Author @danieldiazi
set -Eeuo pipefail

VERSION="2.6.0"
MESSAGE_TITLE="utilidadesHA: script para Home Assistant Container"
MESSAGE_CONFIG_FAIL="No se puede leer el fichero de configuración"
MESSAGE_USAGE="Uso"
MESSAGE_HARDWARE_NOT_SUPPORTED="Hardware no compatible"

# Exit codes
EXIT_OK=0
EXIT_GENERAL=1
EXIT_CONFIG=2
EXIT_DOCKER=3
EXIT_CANCELLED=4
EXIT_UPDATE=5
EXIT_BACKUP=6
EXIT_LOCK=7
EXIT_DIAGNOSE=8

SYSTEM_LANGUAGE=${LANG:-es}
SYSTEM_LANGUAGE=${SYSTEM_LANGUAGE:0:2}
myPath=$(cd "$(dirname "$0")" && pwd)
SCRIPT=$(basename "$0")
DRY_RUN=0
AUTO_CONFIRM=0
BACKUP_BEFORE_UPDATE=0
ACTION=""
UPDATE_TAG=""
BACKUP_SUBFOLDER=""
LOCK_FILE="/tmp/utilidadesHA.lock"
START_TIME=$(date +%s)

if [[ -f "${myPath}/locales/${SYSTEM_LANGUAGE}" ]]; then
  # shellcheck disable=SC1090
  source "${myPath}/locales/${SYSTEM_LANGUAGE}"
fi

timestamp() { date '+%Y-%m-%d %H:%M:%S'; }

log_info() {
  printf '[%s] [INFO] %s\n' "$(timestamp)" "$*"
  if command -v logger >/dev/null 2>&1; then
    logger "$SCRIPT: $*" || true
  fi
}

log_warn() {
  printf '[%s] [WARN] %s\n' "$(timestamp)" "$*" >&2
  if command -v logger >/dev/null 2>&1; then
    logger "$SCRIPT: WARNING: $*" || true
  fi
}

log_error() {
  printf '[%s] [ERROR] %s\n' "$(timestamp)" "$*" >&2
  if command -v logger >/dev/null 2>&1; then
    logger "$SCRIPT: ERROR: $*" || true
  fi
}

die() {
  local code=${1:-$EXIT_GENERAL}
  shift || true
  log_error "$*"
  exit "$code"
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
${MESSAGE_USAGE}:
  $SCRIPT -i [--dry-run] [-y|--yes]
      Instala Home Assistant Container.

  $SCRIPT -u [-f] [-t ETIQUETA] [--backup-before-update] [--dry-run] [-y|--yes]
      Actualiza Home Assistant.

      -f
          Fuerza la recreación aunque la versión instalada coincida.

      -t ETIQUETA
          Usa una etiqueta concreta en lugar de TAG_DOCKER.

      --backup-before-update
          Antes de actualizar crea un backup en FOLDER_BACKUP/pre-update.

      --dry-run
          Muestra operaciones que modificarían el sistema sin ejecutarlas.

      -y, --yes
          Confirma automáticamente instalaciones y actualizaciones.
          Recomendado únicamente para automatizaciones controladas.

  $SCRIPT -c
      Muestra la versión instalada y la disponible.

  $SCRIPT -b CARPETA [--dry-run]
      Crea un backup en FOLDER_BACKUP/CARPETA.

  $SCRIPT --diagnose
      Ejecuta comprobaciones no destructivas de Docker, configuración,
      rutas, hardware, dispositivos y estado del contenedor.

  $SCRIPT --version
      Muestra la versión del script.

  $SCRIPT -h | --help
      Muestra esta ayuda.

Ejemplos:
  $SCRIPT -u --dry-run
  $SCRIPT -u --backup-before-update
  $SCRIPT -u -t 2026.8.4
  $SCRIPT -u -y
  $SCRIPT --diagnose
  $SCRIPT --version
USAGE
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "$EXIT_CONFIG" "No se encontró el comando requerido: $1"
}

require_value() {
  [[ -n "${2:-}" ]] || die "$EXIT_CONFIG" "$1 no está configurado"
}

load_config() {
  local config="${myPath}/utilidadesHA.config"
  [[ -r "$config" ]] || die "$EXIT_CONFIG" "$MESSAGE_CONFIG_FAIL: $config"
  # shellcheck disable=SC1090
  source "$config"
  FORCE=${FORCE:-0}
}

validate_common_config() {
  require_value PATH_HA_CONFIG "${PATH_HA_CONFIG:-}"
  require_value NAME_CONTAINER "${NAME_CONTAINER:-}"
  require_value TAG_DOCKER "${TAG_DOCKER:-}"

  [[ "$PATH_HA_CONFIG" == /* ]] || die "$EXIT_CONFIG" "PATH_HA_CONFIG debe ser una ruta absoluta"
  [[ -z "${PATH_HA_MEDIA:-}" || "$PATH_HA_MEDIA" == /* ]] || die "$EXIT_CONFIG" "PATH_HA_MEDIA debe ser una ruta absoluta"
  [[ -z "${PATH_HA_SSL:-}" || "$PATH_HA_SSL" == /* ]] || die "$EXIT_CONFIG" "PATH_HA_SSL debe ser una ruta absoluta"
  [[ -z "${PATH_HA_DBUS:-}" || "$PATH_HA_DBUS" == /* ]] || die "$EXIT_CONFIG" "PATH_HA_DBUS debe ser una ruta absoluta"
}

validate_docker() {
  require_command docker
  docker info >/dev/null 2>&1 || die "$EXIT_DOCKER" "Docker no está disponible o el usuario no tiene permisos para acceder al daemon"
}

acquire_lock() {
  require_command flock
  if [[ ! -e "$LOCK_FILE" ]]; then
    (umask 022; : >"$LOCK_FILE") 2>/dev/null || true
  fi
  [[ -r "$LOCK_FILE" ]] || die "$EXIT_LOCK" "No se puede leer el fichero de bloqueo: $LOCK_FILE"
  exec 9<"$LOCK_FILE"
  flock -n 9 || die "$EXIT_LOCK" "Ya hay otro proceso de utilidadesHA en ejecución"
}

check_hardware() {
  local arch model=""
  arch=$(uname -m)
  case "$arch" in
    x86_64) HARDWARE="x86_64" ;;
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
    *) die "$EXIT_CONFIG" "$MESSAGE_HARDWARE_NOT_SUPPORTED ($arch)" ;;
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
  [[ -n "${PATH_HA_SSL:-}" && -n "${PATH_HA_SSL_CONTAINER:-}" ]] && docker_args+=(-v "$PATH_HA_SSL:$PATH_HA_SSL_CONTAINER")
  [[ -n "${PATH_HA_DBUS:-}" && -n "${PATH_HA_DBUS_CONTAINER:-}" ]] && docker_args+=(-v "$PATH_HA_DBUS:$PATH_HA_DBUS_CONTAINER:ro")
}

container_exists() { docker inspect "$NAME_CONTAINER" >/dev/null 2>&1; }
container_running() { [[ "$(docker inspect -f '{{.State.Running}}' "$NAME_CONTAINER" 2>/dev/null || true)" == "true" ]]; }

installed_version() {
  if [[ -r "$PATH_HA_CONFIG/.HA_VERSION" ]]; then
    cat "$PATH_HA_CONFIG/.HA_VERSION"
  else
    printf 'no instalada'
  fi
}

current_container_image() {
  docker inspect -f '{{.Config.Image}}' "$NAME_CONTAINER" 2>/dev/null || printf 'no existe'
}

show_operation_summary() {
  local target="$IMAGE_DOCKER:$TAG_DOCKER"
  local current_image
  current_image=$(current_container_image)

  printf '\nResumen de la operación\n'
  printf '%s\n' '-----------------------'
  printf 'Acción:              %s\n' "$ACTION"
  printf 'Contenedor:          %s\n' "$NAME_CONTAINER"
  printf 'Versión instalada:   %s\n' "$(installed_version)"
  printf 'Imagen actual:       %s\n' "$current_image"
  printf 'Imagen destino:      %s\n' "$target"
  printf 'Configuración:       %s\n' "$PATH_HA_CONFIG"
  [[ -n "${PATH_HA_MEDIA:-}" ]] && printf 'Media:               %s\n' "$PATH_HA_MEDIA"
  (( FORCE )) && printf 'Forzar recreación:   sí\n'
  (( BACKUP_BEFORE_UPDATE )) && printf 'Backup previo:       %s/pre-update\n' "${FOLDER_BACKUP:-<no configurado>}"
  (( DRY_RUN )) && printf 'Modo:                simulación (sin cambios)\n'
  printf '\n'
}

confirm_dangerous_action() {
  local response=""
  (( DRY_RUN )) && return 0
  (( AUTO_CONFIRM )) && return 0

  case "$ACTION" in
    install|update) ;;
    *) return 0 ;;
  esac

  if [[ ! -t 0 ]]; then
    die "$EXIT_CANCELLED" "La operación requiere confirmación. Usa -y o --yes para una ejecución no interactiva controlada"
  fi

  printf '¿Continuar? [s/N]: '
  if ! read -r response; then
    die "$EXIT_CANCELLED" "No se pudo leer la confirmación"
  fi
  case "${response,,}" in
    s|si|sí|y|yes) log_info "Operación confirmada" ;;
    *) log_warn "Operación cancelada por el usuario"; exit "$EXIT_CANCELLED" ;;
  esac
}

check_version() {
  local image_ref="$IMAGE_DOCKER:$TAG_DOCKER"
  if (( DRY_RUN )); then
    log_info "Simulación: no se descarga la imagen $image_ref"
  else
    docker pull "$image_ref" >/dev/null
  fi
  VERSION_WEB=$(docker image inspect "$image_ref" --format '{{ index .Config.Labels "io.hass.version" }}' 2>/dev/null || true)
  VERSION_INSTALLED=$(installed_version)
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

backup_cleanup() {
  if [[ "${BACKUP_RESTART_NEEDED:-0}" == "1" ]]; then
    run_mutating docker start "$NAME_CONTAINER" >/dev/null || log_error "No se pudo reiniciar $NAME_CONTAINER"
    BACKUP_RESTART_NEEDED=0
  fi
}

backup_home_assistant() {
  local subfolder="$1"
  local create_destination=${2:-0}
  local destination file archive

  require_command tar
  require_value FOLDER_BACKUP "${FOLDER_BACKUP:-}"
  [[ "$FOLDER_BACKUP" == /* ]] || die "$EXIT_CONFIG" "FOLDER_BACKUP debe ser una ruta absoluta"

  destination="${FOLDER_BACKUP%/}/$subfolder"
  if (( create_destination )); then
    run_mutating mkdir -p "$destination"
  fi
  [[ -d "$destination" || "$DRY_RUN" == "1" ]] || die "$EXIT_BACKUP" "La carpeta de backup no existe: $destination"
  [[ -w "$destination" || "$DRY_RUN" == "1" ]] || die "$EXIT_BACKUP" "La carpeta de backup no permite escritura: $destination"
  [[ -d "$PATH_HA_CONFIG" ]] || die "$EXIT_BACKUP" "No existe la carpeta de configuración: $PATH_HA_CONFIG"

  file="$(date +'%Y%m%d-%H%M%S')-HA-backup.tgz"
  archive="$destination/$file"
  BACKUP_RESTART_NEEDED=0
  trap backup_cleanup RETURN

  if container_running; then
    run_mutating docker stop "$NAME_CONTAINER"
    BACKUP_RESTART_NEEDED=1
  fi

  if ! run_mutating tar -czf "$archive" -C "$(dirname "$PATH_HA_CONFIG")" "$(basename "$PATH_HA_CONFIG")"; then
    backup_cleanup
    trap - RETURN
    die "$EXIT_BACKUP" "Falló la creación del backup"
  fi

  backup_cleanup
  trap - RETURN
  log_info "Backup creado: $archive"
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

  if (( BACKUP_BEFORE_UPDATE )); then
    log_info "Creando backup previo a la actualización"
    backup_home_assistant "pre-update" 1
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
    die "$EXIT_UPDATE" "No se pudo iniciar el contenedor nuevo de Home Assistant"
  fi

  if (( ! DRY_RUN )); then
    sleep 3
    if ! container_running; then
      rollback_container "$old_image" || true
      die "$EXIT_UPDATE" "El contenedor nuevo de Home Assistant no está en ejecución"
    fi
  fi
  log_info "Actualización completada correctamente"
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

diag_ok() { printf '[OK]   %s\n' "$*"; }
diag_warn() { printf '[WARN] %s\n' "$*"; }
diag_fail() { printf '[FAIL] %s\n' "$*"; DIAG_FAILURES=$((DIAG_FAILURES + 1)); }

run_diagnostics() {
  local image_ref="$IMAGE_DOCKER:$TAG_DOCKER"
  DIAG_FAILURES=0
  printf 'Diagnóstico de utilidadesHA %s\n' "$VERSION"
  printf '%s\n' '--------------------------------'

  command -v docker >/dev/null 2>&1 && diag_ok "Docker instalado" || diag_fail "Docker no encontrado"
  command -v flock >/dev/null 2>&1 && diag_ok "flock instalado" || diag_fail "flock no encontrado"
  command -v tar >/dev/null 2>&1 && diag_ok "tar instalado" || diag_fail "tar no encontrado"

  if command -v docker >/dev/null 2>&1; then
    docker info >/dev/null 2>&1 && diag_ok "Acceso al daemon Docker" || diag_fail "Sin acceso al daemon Docker"
  fi

  [[ -d "$PATH_HA_CONFIG" ]] && diag_ok "PATH_HA_CONFIG existe: $PATH_HA_CONFIG" || diag_fail "PATH_HA_CONFIG no existe: $PATH_HA_CONFIG"
  [[ -z "${PATH_HA_MEDIA:-}" || -d "$PATH_HA_MEDIA" ]] && diag_ok "PATH_HA_MEDIA válido" || diag_warn "PATH_HA_MEDIA no existe: $PATH_HA_MEDIA"
  [[ -z "${PATH_HA_SSL:-}" || -d "$PATH_HA_SSL" ]] && diag_ok "PATH_HA_SSL válido" || diag_warn "PATH_HA_SSL no existe: $PATH_HA_SSL"
  [[ -z "${PATH_HA_DBUS:-}" || -e "$PATH_HA_DBUS" ]] && diag_ok "PATH_HA_DBUS válido" || diag_warn "PATH_HA_DBUS no existe: $PATH_HA_DBUS"
  [[ -z "${USB_ZIGBEE:-}" || -e "$USB_ZIGBEE" ]] && diag_ok "USB_ZIGBEE válido" || diag_warn "USB_ZIGBEE no existe: $USB_ZIGBEE"
  [[ -z "${FOLDER_BACKUP:-}" || -d "$FOLDER_BACKUP" ]] && diag_ok "FOLDER_BACKUP válido" || diag_warn "FOLDER_BACKUP no existe: ${FOLDER_BACKUP:-}"

  diag_ok "Hardware: $HARDWARE"
  diag_ok "Imagen seleccionada: $image_ref"

  if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
    if container_exists; then
      diag_ok "Contenedor $NAME_CONTAINER existe"
      container_running && diag_ok "Contenedor $NAME_CONTAINER en ejecución" || diag_warn "Contenedor $NAME_CONTAINER detenido"
      diag_ok "Imagen actual: $(current_container_image)"
    else
      diag_warn "Contenedor $NAME_CONTAINER no existe"
    fi
  fi
  diag_ok "Versión instalada: $(installed_version)"

  if (( DIAG_FAILURES > 0 )); then
    log_error "Diagnóstico terminado con $DIAG_FAILURES fallo(s) crítico(s)"
    exit "$EXIT_DIAGNOSE"
  fi
  log_info "Diagnóstico completado sin fallos críticos"
}

set_action() {
  local requested="$1"
  if [[ -n "$ACTION" && "$ACTION" != "$requested" ]]; then
    die "$EXIT_CONFIG" "Solo puede indicarse una acción principal por ejecución"
  fi
  ACTION="$requested"
}

parse_args() {
  (( $# > 0 )) || { usage; exit "$EXIT_CONFIG"; }
  while (( $# )); do
    case "$1" in
      -i) set_action install ;;
      -u) set_action update ;;
      -c) set_action check ;;
      -b)
        set_action backup
        shift
        BACKUP_SUBFOLDER=${1:-}
        require_value "La carpeta de backup" "$BACKUP_SUBFOLDER"
        ;;
      -f)
        FORCE=1
        [[ -z "$ACTION" ]] && ACTION="update"
        [[ "$ACTION" == "update" ]] || die "$EXIT_CONFIG" "-f solo puede usarse con actualización"
        ;;
      -t)
        shift
        UPDATE_TAG=${1:-}
        require_value "La etiqueta" "$UPDATE_TAG"
        [[ -z "$ACTION" || "$ACTION" == "update" ]] || die "$EXIT_CONFIG" "-t solo puede usarse con actualización"
        ACTION="update"
        ;;
      --backup-before-update)
        BACKUP_BEFORE_UPDATE=1
        [[ -z "$ACTION" || "$ACTION" == "update" ]] || die "$EXIT_CONFIG" "--backup-before-update solo puede usarse con actualización"
        ACTION="update"
        ;;
      --dry-run) DRY_RUN=1 ;;
      -y|--yes) AUTO_CONFIRM=1 ;;
      --diagnose) set_action diagnose ;;
      --version) printf 'utilidadesHA %s\n' "$VERSION"; exit "$EXIT_OK" ;;
      -h|--help) usage; exit "$EXIT_OK" ;;
      *) die "$EXIT_CONFIG" "Opción desconocida: $1" ;;
    esac
    shift
  done
}

finish_timing() {
  local end elapsed
  end=$(date +%s)
  elapsed=$((end - START_TIME))
  log_info "Duración total: ${elapsed}s"
}

main() {
  printf '%s\n' '-------------------------------------------' "$MESSAGE_TITLE v$VERSION" '-------------------------------------------'

  parse_args "$@"
  load_config
  validate_common_config
  check_hardware
  select_image
  [[ -n "$UPDATE_TAG" ]] && TAG_DOCKER="$UPDATE_TAG"

  if [[ "$ACTION" == "diagnose" ]]; then
    run_diagnostics
    finish_timing
    exit "$EXIT_OK"
  fi

  acquire_lock
  validate_docker

  case "$ACTION" in
    install|update)
      show_operation_summary
      confirm_dangerous_action
      ;;
  esac

  case "$ACTION" in
    install) new_install ;;
    update) update_home_assistant ;;
    check) check_version ;;
    backup) backup_home_assistant "$BACKUP_SUBFOLDER" ;;
    *) usage; exit "$EXIT_CONFIG" ;;
  esac

  finish_timing
}

main "$@"
