# utilidadesHA
A bash script to simplify some maintenance tasks of your Home Assistant Container.
![imagen](https://user-images.githubusercontent.com/3638478/190757510-334883cf-4c50-44f4-b451-5c22b961e649.png)

# Requeriments
* Docker installed
* A Compatible hardware
  * Tested:
    * Raspberry Pi 3
    * Raspberry Pi 4 
    * x86_64

# Features
* Install a new instance of Home Assistant
* Upgrade Home Assistant to a newest version
* Create a backup of Home Assistant config folder
 * Also option for use GPG
* Check if exists a new version
* Force update even if there aren't a new version
* Upgrade to image version tagged with a specific tag 

# Installation
* Download utilidadesHA.bash and utilidadesHA.config to your prefered folder whitin your computer with docker installed.
* On your prefered terminal, set permission of execution to utilidadesHA.bash
   ```bash
     chmod u+x utilidadesHA.bash
    ```
    
# Getting Started
* Run it! 
   ```bash
     ./utilidadesHA.bash
   ```
# Config
utilidadesHA.config is the file to configure your options, you only need to edit it and change what you want.

| PARAMETER | DESCRIPTION | EXAMPLE |
| ------------- | ------------- | ------------- |
| PATH_HA_CONFIG | HA config folder | /srv/ha/hass-config |
| PATH_HA_MEDIA | HA Media folder | /srv/ha/hass-media |
| PATH_HA_SSL | HA SSL folder. Blank if you don't use it.|  |
| PATH_HA_SSL_CONTAINER=| HA SSL container folder. Blank if you don't use it.|  |
| PATH_HA_DBUS | In order to use Bluetooth integration |  /run/dbus|
| PATH_HA_DBUS_CONTAINER| In order to use Bluetooth integration  | /run/dbus |
| NAME_CONTAINER | Name of Home Assitante container managed by this script  | home-assistant |
| USB_ZIGBEE= | If you have a USB zigbee device. Comment if you don't use it. |  /dev/serial/by-id/usb-xxxxxx|
| FOLDER_BACKUP | Folder backup. Must to exists before use this script | /backup  |
| RECIPIENT_GPG|  gpg recipient. Comment if you don't use it |  |
| IMAGE_DOCKER_RPI3| HA URL image available for RPI3 | homeassistant/raspberrypi3-homeassistant  |
| IMAGE_DOCKER_RPI4| HA URL image available for RPI4 | ghcr.io/home-assistant/raspberrypi4-homeassistant |
| IMAGE_DOCKER_x86_64| HA URL image available for x86 64 bits arch |  ghcr.io/home-assistant/home-assistant|
| TAG_DOCKER| Tag to be used  | stable  |
| COLOURS | You can choose to have colours when use this script or not. Values: "si" if you wish colours, another value if you don't |  si |
| FORCE | Is to force upgrade, this value by default is 0. It's used inside script|  0|


# Usage

| OPTION | DESCRIPTION |
| ------ | ----------- |
|  -i | Install HA version. If HA is installed, is the same than -u option | 
|  -u |  Update HA version |
|  -c |  Check if exists a new version |
|  -b X |  create a backup into indicated folder "X" (inside FOLDER_BACKUP variable). Destination folder "X" must exist.|
|  -g Y |  create a backup using gpg into indicated folder "Y" (inside FOLDER_BACKUP variable) Destination folder "Y" must exist. |
|  -r |  explain how to recover a gpg backup|
|  -f |  force an update without check if the available version is already installed |
|  -t tag|  force an update to the image version tagged with tag  (by example 2022.9.0)|
|  -h |  shows this info  |


	

## Show options / help
Only run script without options or add -h option
   ```bash
     ./utilidadesHA.bash
   ```
## Upgrade HA version
![Upgrade](https://github.com/Danieldiazi/utilidadesHA/blob/22be384cdac801e6696830ca026e9e3997c0bb6c/docs/upgrade.gif)
## Check new version
Option "-u" check if exists a new version. It only checks info from html code on home assistant webpage.

## Upgrade to a specified tag
![Tag](https://github.com/Danieldiazi/utilidadesHA/blob/665f912e944af21f0840d3d4d82ec16ef0080054/docs/tag.gif)


## Backup
In order to create a backup, the user running this command need to have permissions on all files into /config folder.
![Backup](https://github.com/Danieldiazi/utilidadesHA/blob/665f912e944af21f0840d3d4d82ec16ef0080054/docs/backup.gif)


## Configure schedule backup 

You can see this examples if you wish to add it in crontab

```
#At 02:00 once a week, backup to folder "weekly" inside folder defined by FOLDER_BACKUP
0 2 * * 1 /opt/scripts/utilidades-HA.bash -b weekly
#At 03:00 every day, backup to folder "diario" inside folder defined by FOLDER_BACKUP
0 3 * * * /opt/scripts/utilidades-HA.bash -b diario
```  

