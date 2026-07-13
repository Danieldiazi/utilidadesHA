# utilidadesHA

Script Bash para instalar, actualizar y respaldar Home Assistant Container mediante Docker.

## Requisitos

- Bash 4 o superior.
- Docker instalado y accesible para el usuario que ejecuta el script.
- `flock` para impedir ejecuciones simultáneas.
- `tar` para las copias de seguridad.
- GnuPG únicamente para las copias cifradas.
- Arquitectura `x86_64` o `aarch64`/`arm64`. Está probado en Raspberry Pi 3, Raspberry Pi 4 y Orange Pi Zero 3.

## Funciones

- Instalación inicial de Home Assistant Container.
- Actualización a la etiqueta estable o a una etiqueta concreta.
- Comparación de la versión instalada con la disponible.
- Rollback automático cuando el contenedor nuevo no arranca.
- Backup de la configuración con reinicio garantizado del contenedor.
- Backup cifrado con GPG.
- Bloqueo para evitar que coincidan una actualización y un backup.
- Modo `--dry-run` para mostrar operaciones sin ejecutarlas.

## Instalación

Descarga la versión publicada, extrae los archivos y concede permisos de ejecución:

```bash
chmod u+x utilidadesHA.bash
```

Edita `utilidadesHA.config` antes de la primera ejecución.

## Uso

| Opción | Descripción |
| --- | --- |
| `-i` | Instala Home Assistant. Si ya está instalado, ejecuta una actualización forzada. |
| `-u` | Actualiza Home Assistant. |
| `-c` | Muestra la versión instalada y la disponible. |
| `-b CARPETA` | Crea un backup dentro de `FOLDER_BACKUP/CARPETA`. La carpeta debe existir. |
| `-g CARPETA` | Crea un backup cifrado con GPG. |
| `-r` | Muestra cómo descifrar un backup GPG. |
| `-f` | Fuerza la actualización aunque la versión sea la misma. |
| `-t ETIQUETA` | Actualiza a una etiqueta concreta. |
| `--dry-run` | Muestra las operaciones que modificarían el sistema sin ejecutarlas. |
| `-h`, `--help` | Muestra la ayuda. |

Ejemplos:

```bash
./utilidadesHA.bash -i
./utilidadesHA.bash -u
./utilidadesHA.bash -u -f
./utilidadesHA.bash -u -t 2026.7.1
./utilidadesHA.bash -b diario
./utilidadesHA.bash -g semanal
./utilidadesHA.bash -u --dry-run
```

Por compatibilidad, `-f` y `-t ETIQUETA` también inician una actualización aunque no se indique `-u`.

## Seguridad durante la actualización

Antes de reemplazar el contenedor, el script conserva el identificador de la imagen anterior. Después de crear el contenedor nuevo comprueba que esté en ejecución. Si falla, elimina el contenedor defectuoso y vuelve a crear el anterior con los mismos volúmenes y dispositivos.

El rollback protege el contenedor, pero no sustituye a una copia de seguridad de la configuración.

## Copias de seguridad

El subdirectorio indicado debe existir dentro de `FOLDER_BACKUP` y ser escribible. El script detiene Home Assistant solamente si estaba en ejecución y registra una función de limpieza para volver a iniciarlo aunque `tar` o GPG fallen.

Para descifrar una copia:

```bash
gpg --decrypt archivo.tgz.gpg > backup.tgz
```

## Configuración

| Variable | Descripción | Ejemplo |
| --- | --- | --- |
| `PATH_HA_CONFIG` | Carpeta de configuración de Home Assistant. Debe ser una ruta absoluta. | `/srv/ha/hass-config` |
| `PATH_HA_MEDIA` | Carpeta de medios. | `/srv/ha/hass-media` |
| `PATH_HA_SSL` | Carpeta SSL del host. | `/srv/ha/ssl` |
| `PATH_HA_SSL_CONTAINER` | Ruta SSL dentro del contenedor. | `/ssl` |
| `PATH_HA_DBUS` | Socket DBus del host para Bluetooth. | `/run/dbus` |
| `PATH_HA_DBUS_CONTAINER` | Ruta DBus dentro del contenedor. | `/run/dbus` |
| `NAME_CONTAINER` | Nombre del contenedor. | `home-assistant` |
| `USB_ZIGBEE` | Dispositivo USB Zigbee opcional. | `/dev/serial/by-id/usb-...` |
| `FOLDER_BACKUP` | Carpeta raíz de backups. | `/backup` |
| `RECIPIENT_GPG` | Identificador del destinatario GPG. | `usuario@example.com` |
| `IMAGE_DOCKER_RPI3` | Imagen para Raspberry Pi 3. | `homeassistant/raspberrypi3-homeassistant` |
| `IMAGE_DOCKER_RPI4` | Imagen para Raspberry Pi 4. | `ghcr.io/home-assistant/raspberrypi4-homeassistant` |
| `IMAGE_DOCKER_x86_64` | Imagen para x86-64. | `ghcr.io/home-assistant/home-assistant` |
| `IMAGE_DOCKER_aarch64` | Imagen para ARM64 genérico. | `ghcr.io/home-assistant/home-assistant` |
| `TAG_DOCKER` | Etiqueta predeterminada. | `stable` |
| `FORCE` | Fuerza la actualización cuando vale `1`. | `0` |

## Automatización con cron

El bloqueo mediante `flock` evita que dos ejecuciones del script trabajen al mismo tiempo.

```cron
# Backup semanal a las 02:00
0 2 * * 1 /opt/utilidadesHA/utilidadesHA.bash -b semanal

# Backup diario a las 03:00
0 3 * * * /opt/utilidadesHA/utilidadesHA.bash -b diario
```
