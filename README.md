# utilidadesHA
Es un script que simplifica las tareas con la versión de contenedor de Home Assistant
![imagen](https://user-images.githubusercontent.com/3638478/190757510-334883cf-4c50-44f4-b451-5c22b961e649.png)

Para mi es cómodo, porque no tengo más que usarlo cada vez que quiero actualizar o instalarlo. Y puedo además programar tareas con el crontab para hacer backups periódicos.

# Requerimientos
* Docker instalado
* Un hardware compatible
  * Testeado:
    * Raspberry Pi 3
    * Raspberry Pi 4 
    * x86_64
    * Orange Pi Zero3

# Funcionalidades
* Instala una nueva instancia de Home Assistant
* Actualiza Home Assistant a una versión nueva
* Hace un backup de la carpeta de Home Assistant
* Comprueba si hay una nueva versión
* Permite forzar la actualización incluso si no hay nueva versión (Actualiza sobre la misma)
* Permite actualizar indicando la etiqueta de la versión (ej: 2023.4.0) 

# Instalación
* En "Releases" descargate utilidadesHA.zip en una carpeta en tu servidor de Home Assistant (ej: /opt/utilidadesHA)
* Dale permisos de ejecución
   ```bash
     chmod u+x utilidadesHA.bash
    ```

# Primeros pasos
* Ejecútalo! 
   ```bash
     ./utilidadesHA.bash
   ```
Ahí verás las opciones que hay.

* Si aún no está instalado HA, usa la opción -i. Creará la carpeta dónde se va a almacenar la configuración de HA. Esa carpeta la puedes cambiar en el fichero .config. Por defecto se guarda en /srv/ha/hass-config para el caso de la carpeta de configuración.

   ```bash
     ./utilidadesHA.bash -i
   ```

# Uso

| OPCIÓN | DESCRIPCIÓN |
| ------ | ----------- |
|  -i | Instala HA. Crea las carpetas si lo necesita | 
|  -u |  Actualiza HA |
|  -c |  Comprueba y muestra por pantalla la información de versión local y la existente en la web |
|  -b X |  Crea un backup en la carpeta "X" (dentro a su vez de la variable FOLDER_BACKUP). Debe existir.|
|  -g X |  Crea un backup con gpg en la carpeta "X" (dentro a su vez de la variable FOLDER_BACKUP). Debe existir.|
|  -r |  explica como recuperar de un backup gpg|
|  -f |  fuerza a actualizar incluso si no hay nueva versión|
|  -t tag|  actualiza a la versión indicada en la etiqueta  (por ejemplo 2022.9.0)|


## Ejemplo de actualizar HA
![Upgrade](https://github.com/Danieldiazi/utilidadesHA/blob/22be384cdac801e6696830ca026e9e3997c0bb6c/docs/upgrade.gif)
## Chequear nueva versión
Sólo chequea contra la información que se muestra en la página de HA. Puede que en la página ya anuncien nueva versión y no haya imagen disponible.

## Uso de actualizar a una etiqueta determinada
![Tag](https://github.com/Danieldiazi/utilidadesHA/blob/665f912e944af21f0840d3d4d82ec16ef0080054/docs/tag.gif)


## Backup
Ten en cuenta que el usuario con el que hace backup debe tener permisos en la carpeta de configuración.
![Backup](https://github.com/Danieldiazi/utilidadesHA/blob/665f912e944af21f0840d3d4d82ec16ef0080054/docs/backup.gif)


# Configuración
En utilidadesHA.config puedes cambiar las configuraciones que necesites. 

| PARAMETER | DESCRIPTION | EJEMPLO |
| ------------- | ------------- | ------------- |
| PATH_HA_CONFIG | Carpeta de configuración HA  | /srv/ha/hass-config |
| PATH_HA_MEDIA | Carpeta de mediso de HA | /srv/ha/hass-media |
| PATH_HA_SSL | Carpeta HA SSL. Déjala en blanco si no la usas. |  |
| PATH_HA_SSL_CONTAINER=| carpeta del contenedor HA SSL. Déjala en blanco si no la usas.|  |
| PATH_HA_DBUS | Para que funcione la integración Bluetooth |  /run/dbus|
| PATH_HA_DBUS_CONTAINER| Para que funcione la integración Bluetooth  | /run/dbus |
| NAME_CONTAINER | Nombre que tendrá el contenedor  | home-assistant |
| USB_ZIGBEE= | Si tienes un dispositivo Zigbee por USB. Coméntalo si no lo usas. |  /dev/serial/by-id/usb-xxxxxx|
| FOLDER_BACKUP | Carpeta donde guardar el backup. Debes crearla previamente para poder usarla | /backup  |
| RECIPIENT_GPG|  Recipiente gpg  |  |
| IMAGE_DOCKER_RPI3| La imagen para RPI3 | homeassistant/raspberrypi3-homeassistant  |
| IMAGE_DOCKER_RPI4| La imagen para RPI4 | ghcr.io/home-assistant/raspberrypi4-homeassistant |
| IMAGE_DOCKER_x86_64| La imagen para x86_64 |  ghcr.io/home-assistant/home-assistant|
| IMAGE_DOCKER_aarch64| La imagen para aarch64 |  ghcr.io/home-assistant/home-assistant|
| TAG_DOCKER| Tag a usar en la instalación.  | stable  |
| COLOURS | Si quieres que este script se muestre o no con colores."si" si es así. |  si |
| FORCE | Para forzar la actualizción. 1 que si, 0 que no|  0|




	

## Programar el backup con crontab

```
#At 02:00 once a week, backup to folder "weekly" inside folder defined by FOLDER_BACKUP
0 2 * * 1 /opt/scripts/utilidades-HA.bash -b weekly
#At 03:00 every day, backup to folder "diario" inside folder defined by FOLDER_BACKUP
0 3 * * * /opt/scripts/utilidades-HA.bash -b diario
```  

