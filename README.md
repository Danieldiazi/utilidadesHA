# utilidadesHA

Script Bash para instalar, actualizar, diagnosticar y crear copias de seguridad de Home Assistant Container mediante Docker.

## Funciones principales

- Instalación y actualización de Home Assistant Container.
- Confirmación antes de operaciones delicadas y `-y` / `--yes` para automatizaciones controladas.
- Resumen previo de la operación: contenedor, versión, imagen actual, imagen destino, rutas y opciones especiales.
- Actualización a una etiqueta concreta con `-t ETIQUETA`.
- Recreación forzada con `-f`.
- Backup manual y backup automático antes de actualizar con `--backup-before-update`.
- Rollback a la imagen anterior si el contenedor nuevo no arranca.
- Diagnóstico no destructivo con `--diagnose`.
- Simulación con `--dry-run`.
- Bloqueo con `flock` para impedir ejecuciones simultáneas.
- Logs con fecha y hora.
- Códigos de salida documentados.
- Validación automática mediante GitHub Actions, `bash -n` y ShellCheck.

## Requisitos

- Bash 4 o superior.
- Docker instalado y accesible para el usuario que ejecuta el script.
- `flock`.
- `tar` para backups.
- Arquitectura `x86_64` o `aarch64`/`arm64`.

## Uso

```bash
./utilidadesHA.bash --help
```

### Instalar

```bash
./utilidadesHA.bash -i
```

Antes de modificar el sistema muestra un resumen y solicita confirmación. Para automatización controlada:

```bash
./utilidadesHA.bash -i --yes
```

### Actualizar

```bash
./utilidadesHA.bash -u
```

Forzar la recreación aunque la versión coincida:

```bash
./utilidadesHA.bash -u -f
```

Actualizar a una etiqueta concreta:

```bash
./utilidadesHA.bash -u -t 2026.8.4
```

En cron o cualquier ejecución no interactiva debe usarse `-y` / `--yes`:

```bash
./utilidadesHA.bash -u --yes
```

### Backup automático antes de actualizar

```bash
./utilidadesHA.bash -u --backup-before-update
```

Crea automáticamente una copia en:

```text
FOLDER_BACKUP/pre-update
```

El subdirectorio `pre-update` se crea si no existe. Puede combinarse con cron:

```bash
./utilidadesHA.bash -u --backup-before-update --yes
```

### Backup manual

```bash
./utilidadesHA.bash -b diario
```

Crea un `.tgz` en `FOLDER_BACKUP/diario`. En backups manuales el subdirectorio indicado debe existir. Si Home Assistant estaba arrancado, se reinicia aunque falle `tar`.

### Simulación

```bash
./utilidadesHA.bash -u --dry-run
```

`--dry-run` muestra los comandos que modificarían el sistema sin ejecutarlos y no solicita confirmación.

### Diagnóstico

```bash
./utilidadesHA.bash --diagnose
```

No modifica el sistema. Comprueba:

- disponibilidad de `docker`, `flock` y `tar`;
- acceso al daemon Docker;
- existencia de configuración, media, SSL y DBus;
- dispositivo Zigbee si está configurado;
- carpeta de backups;
- arquitectura e imagen seleccionada;
- existencia y estado del contenedor;
- imagen actual y versión instalada.

Los fallos críticos terminan con código `8`.

### Consultar versión

```bash
./utilidadesHA.bash --version
```

Ejemplo:

```text
utilidadesHA 2.6.0
```

La versión está centralizada en la variable `VERSION` del script.

## Resumen de opciones

| Opción | Descripción |
| --- | --- |
| `-i` | Instala Home Assistant. |
| `-u` | Actualiza Home Assistant. |
| `-c` | Muestra versión instalada y disponible. |
| `-b CARPETA` | Crea un backup manual. |
| `-f` | Fuerza la recreación aunque coincida la versión. |
| `-t ETIQUETA` | Usa una etiqueta Docker concreta. |
| `--backup-before-update` | Crea un backup en `FOLDER_BACKUP/pre-update` antes de actualizar. |
| `--dry-run` | Simula las operaciones destructivas. |
| `-y`, `--yes` | Confirma automáticamente instalaciones y actualizaciones. |
| `--diagnose` | Ejecuta diagnóstico no destructivo. |
| `--version` | Muestra la versión de utilidadesHA. |
| `-h`, `--help` | Muestra la ayuda. |

## Resumen antes de confirmar

Una actualización interactiva muestra un bloque similar a:

```text
Resumen de la operación
-----------------------
Acción:              update
Contenedor:          home-assistant
Versión instalada:   2026.8.3
Imagen actual:       ghcr.io/home-assistant/home-assistant:stable
Imagen destino:      ghcr.io/home-assistant/home-assistant:stable
Configuración:       /srv/ha/hass-config
Media:               /srv/ha/hass-media
Backup previo:       /backup/pre-update

¿Continuar? [s/N]:
```

La respuesta predeterminada es **no**.

## Duración y logs

Los mensajes incluyen fecha y hora:

```text
[2026-08-31 21:30:15] [INFO] Actualización completada correctamente
[2026-08-31 21:30:15] [INFO] Duración total: 18s
```

## Códigos de salida

| Código | Significado |
| ---: | --- |
| `0` | Operación correcta. |
| `1` | Error general. |
| `2` | Configuración, parámetros o dependencia inválidos. |
| `3` | Docker no disponible o sin permisos para acceder al daemon. |
| `4` | Operación cancelada o falta confirmación en ejecución no interactiva. |
| `5` | Fallo durante actualización/arranque/rollback. |
| `6` | Fallo de backup. |
| `7` | No se pudo adquirir o usar el bloqueo `flock`. |
| `8` | Diagnóstico terminado con fallos críticos. |

## Configuración

| Variable | Descripción | Ejemplo |
| --- | --- | --- |
| `PATH_HA_CONFIG` | Carpeta de configuración de Home Assistant. | `/srv/ha/hass-config` |
| `PATH_HA_MEDIA` | Carpeta de medios. | `/srv/ha/hass-media` |
| `PATH_HA_SSL` | Carpeta SSL del host. | `/srv/ha/ssl` |
| `PATH_HA_SSL_CONTAINER` | Ruta SSL dentro del contenedor. | `/ssl` |
| `PATH_HA_DBUS` | Socket DBus del host. | `/run/dbus` |
| `PATH_HA_DBUS_CONTAINER` | Ruta DBus dentro del contenedor. | `/run/dbus` |
| `NAME_CONTAINER` | Nombre del contenedor. | `home-assistant` |
| `USB_ZIGBEE` | Dispositivo Zigbee opcional. | `/dev/serial/by-id/usb-...` |
| `FOLDER_BACKUP` | Carpeta raíz de backups. | `/backup` |
| `IMAGE_DOCKER_RPI3` | Imagen Raspberry Pi 3. | `homeassistant/raspberrypi3-homeassistant` |
| `IMAGE_DOCKER_RPI4` | Imagen Raspberry Pi 4. | `ghcr.io/home-assistant/raspberrypi4-homeassistant` |
| `IMAGE_DOCKER_x86_64` | Imagen x86-64. | `ghcr.io/home-assistant/home-assistant` |
| `IMAGE_DOCKER_aarch64` | Imagen ARM64 genérico. | `ghcr.io/home-assistant/home-assistant` |
| `TAG_DOCKER` | Etiqueta predeterminada. | `stable` |
| `FORCE` | Fuerza actualización cuando vale `1`. | `0` |

## Cron

Actualización automática con backup previo:

```cron
0 4 * * * /opt/scripts/utilidadesHA.bash -u --backup-before-update --yes >> /var/log/utilidadesHA.log 2>&1
```

Backup diario:

```cron
0 3 * * * /opt/scripts/utilidadesHA.bash -b diario >> /var/log/utilidadesHA.log 2>&1
```

## GitHub Actions

El workflow `.github/workflows/shellcheck.yml` valida cada `push` y `pull_request` mediante:

```bash
bash -n utilidadesHA.bash
shellcheck utilidadesHA.bash
```
