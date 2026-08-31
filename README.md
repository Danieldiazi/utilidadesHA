# utilidadesHA

Script Bash para instalar, actualizar y crear copias de seguridad de Home Assistant Container mediante Docker.

## Requisitos

- Bash 4 o superior.
- Docker instalado y accesible para el usuario que ejecuta el script.
- `flock` para impedir ejecuciones simultáneas.
- `tar` para las copias de seguridad.
- Arquitectura `x86_64` o `aarch64`/`arm64`. Está probado en Raspberry Pi 3, Raspberry Pi 4 y Orange Pi Zero 3.

## Funciones

- Instalación inicial de Home Assistant Container.
- Actualización a la etiqueta estable o a una etiqueta concreta.
- Confirmación interactiva antes de instalaciones y actualizaciones que modifican el contenedor.
- Comparación de la versión instalada con la disponible.
- Rollback automático cuando el contenedor nuevo no arranca.
- Backup de la configuración con reinicio garantizado del contenedor.
- Bloqueo para evitar que coincidan una actualización y un backup.
- Modo `--dry-run` para mostrar operaciones sin ejecutarlas.

## Instalación

Descarga la versión publicada, extrae los archivos y concede permisos de ejecución:

```bash
chmod u+x utilidadesHA.bash
```

Edita `utilidadesHA.config` antes de la primera ejecución.

## Ayuda

La ayuda completa está disponible con:

```bash
./utilidadesHA.bash --help
```

## Uso

### Instalar Home Assistant

```bash
./utilidadesHA.bash -i
```

Crea las carpetas configuradas y levanta el contenedor. Si Home Assistant ya está instalado, realiza una actualización forzada. Antes de modificar el sistema solicita confirmación explícita.

Para comprobar primero qué comandos ejecutaría:

```bash
./utilidadesHA.bash -i --dry-run
```

### Actualizar Home Assistant

```bash
./utilidadesHA.bash -u
```

Actualiza Home Assistant cuando la versión disponible es distinta de la instalada. Antes de detener o recrear el contenedor muestra una advertencia y solicita confirmación.

#### Forzar una actualización

```bash
./utilidadesHA.bash -u -f
```

La opción `-f` fuerza la descarga y recreación del contenedor aunque la versión instalada coincida con la disponible. Es una opción delicada y la confirmación muestra expresamente que se está forzando la recreación.

#### Actualizar a una etiqueta concreta

```bash
./utilidadesHA.bash -u -t 2026.7.1
```

La opción `-t ETIQUETA` usa una etiqueta de imagen concreta en lugar del valor `TAG_DOCKER` configurado. La etiqueta solo se aplica a esa ejecución y se muestra en la advertencia previa a la confirmación.

#### Simular una actualización

```bash
./utilidadesHA.bash -u --dry-run
```

`--dry-run` muestra los comandos que modificarían el sistema, pero no los ejecuta. No detiene, elimina ni crea contenedores y, por ese motivo, no solicita confirmación.

#### Automatizaciones sin confirmación interactiva

Las opciones `-y` y `--yes` confirman automáticamente una instalación o actualización:

```bash
./utilidadesHA.bash -u --yes
```

Úsalas únicamente en automatizaciones controladas. Si una instalación o actualización se ejecuta sin terminal interactivo y no se ha indicado `-y`/`--yes`, el script aborta en lugar de asumir una respuesta afirmativa.

### Consultar versiones

```bash
./utilidadesHA.bash -c
```

Muestra la versión disponible en la imagen y la versión instalada en la carpeta de configuración. No requiere confirmación porque no recrea el contenedor.

### Crear un backup

```bash
./utilidadesHA.bash -b diario
```

Crea un archivo `.tgz` dentro de:

```text
FOLDER_BACKUP/diario
```

El subdirectorio debe existir y tener permisos de escritura. El script detiene Home Assistant solamente si estaba en ejecución y garantiza que vuelva a iniciarse aunque falle `tar`. El backup no solicita confirmación para permitir su uso normal mediante `cron`.

También puedes simular la operación:

```bash
./utilidadesHA.bash -b diario --dry-run
```

## Resumen de opciones

| Opción | Descripción |
| --- | --- |
| `-i` | Instala Home Assistant. Si ya está instalado, ejecuta una actualización forzada. Solicita confirmación. |
| `-u` | Actualiza Home Assistant. Solicita confirmación antes de modificar el contenedor. |
| `-c` | Muestra la versión instalada y la disponible. |
| `-b CARPETA` | Crea un backup dentro de `FOLDER_BACKUP/CARPETA`. |
| `-f` | Fuerza la actualización aunque la versión sea la misma. |
| `-t ETIQUETA` | Usa una etiqueta concreta para la actualización. |
| `--dry-run` | Muestra las operaciones que modificarían el sistema sin ejecutarlas. |
| `-y`, `--yes` | Confirma automáticamente una instalación o actualización; pensado para automatizaciones controladas. |
| `-h`, `--help` | Muestra la ayuda detallada. |

Por compatibilidad, `-f` y `-t ETIQUETA` también inician una actualización aunque no se indique `-u`.

## Seguridad durante la actualización

Las operaciones de instalación y actualización requieren confirmación interactiva por defecto. La respuesta predeterminada es negativa: pulsar Enter o responder algo distinto de `s`, `si`, `sí`, `y` o `yes` cancela la operación.

Antes de reemplazar el contenedor, el script conserva el identificador de la imagen anterior. Después de crear el contenedor nuevo comprueba que esté en ejecución. Si falla, elimina el contenedor defectuoso y vuelve a crear el anterior con los mismos volúmenes y dispositivos.

El rollback protege el contenedor, pero no sustituye a una copia de seguridad de la configuración.

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
| `IMAGE_DOCKER_RPI3` | Imagen para Raspberry Pi 3. | `homeassistant/raspberrypi3-homeassistant` |
| `IMAGE_DOCKER_RPI4` | Imagen para Raspberry Pi 4. | `ghcr.io/home-assistant/raspberrypi4-homeassistant` |
| `IMAGE_DOCKER_x86_64` | Imagen para x86-64. | `ghcr.io/home-assistant/home-assistant` |
| `IMAGE_DOCKER_aarch64` | Imagen para ARM64 genérico. | `ghcr.io/home-assistant/home-assistant` |
| `TAG_DOCKER` | Etiqueta predeterminada. | `stable` |
| `FORCE` | Fuerza la actualización cuando vale `1`. | `0` |

## Automatización con cron

El bloqueo mediante `flock` evita que dos ejecuciones del script trabajen al mismo tiempo.

Los backups no necesitan `--yes`:

```cron
# Backup semanal a las 02:00
0 2 * * 1 /opt/utilidadesHA/utilidadesHA.bash -b semanal

# Backup diario a las 03:00
0 3 * * * /opt/utilidadesHA/utilidadesHA.bash -b diario
```

Si automatizas una actualización, debes indicarlo expresamente:

```cron
# Ejemplo: actualización automatizada confirmada de forma explícita
0 4 * * 0 /opt/utilidadesHA/utilidadesHA.bash -u --yes
```
