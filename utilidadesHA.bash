#!/bin/bash

# v2 , Author @danieldiazi
echo "-------------------------------------------"
echo "utilidadesHA: tools script for HA Container"
echo "-------------------------------------------"
echo ""


myPath=$(dirname "$0") # relative path
myPath=$(cd "$myPath" && pwd) # full path
if [[ -z "$myPath" ]] ; then
  LOG="\t${$myPath} doesn't exist. I can't read config .config file"
  echo -e $LOG
  #We write on system log
  logger $SCRIPT:$LOG
  exit 1  # fail
fi


echo Loading config from ${myPath}/utilidadesHA.config
. ${myPath}/utilidadesHA.config


#colores
if [ $COLOURS == "si" ]; then
greenColour="\e[0;32m\033[1m"
endColour="\033[0m\e[0m"
redColour="\e[0;31m\033[1m"
blueColour="\e[0;34m\033[1m"
yellowColour="\e[0;33m\033[1m"
purpleColour="\e[0;35m\033[1m"
turquoiseColour="\e[0;36m\033[1m"
grayColour="\e[0;37m\033[1m"


else
greenColour=""
endColour=""
redColour=""
blueColour=""
yellowColour=""
purpleColour=""
turquoiseColour=""
grayColour=""

fi


#funcion help
function help () {

echo -e "\n${yellowColour}[+]${endColour} ${grayColour}Usage:${endColour} \n"
echo -e "\t${redColour}[-i]${endColour}  ${blueColour}Install HA version. If HA is installed, is the same than -u option${endColour}"
echo -e "\t${redColour}[-u]${endColour}  ${blueColour}Update HA version${endColour}"
echo -e "\t${redColour}[-c]${endColour}  ${blueColour}Check if exists a new version${endColour}"
echo -e "\t${redColour}[-b folder]${endColour}  ${blueColour}create a backup into indicated folder (inside $FOLDER_BACKUP)${endColour}"
echo -e "\t${redColour}[-g folder]${endColour}  ${blueColour}crate a backup using gpg into indicated folder (inside $FOLDER_BACKUP)${endColour}"
echo -e "\t${redColour}[-r]  ${blueColour}explain how to recover a gpg backup ${endColour}"
echo -e "\t${redColour}[-f]  ${blueColour}force an update without check if the available version is already installed${endColour}"
echo -e "\t${redColour}[-t tag] ${blueColour}force an update to the image version tagged with tag  (by example 2022.9.0)${endColour}"
echo -e "\t${redColour}[-h]${endColour}  ${blueColour}shows this info${endColour}"
echo -e "\n"
exit 1
}

function checkHardware () {

ARCH=$(arch)

if [[ $ARCH == "x86_64" ]]; then
 HARDWARE="x86_64"
else

MODEL=$(tr -d '\0' </proc/device-tree/model);


if [[ $MODEL == *"Raspberry Pi 3"* ]]; then
  echo "Hardware: Raspberry PI 3"
  HARDWARE="RPI3"

elif [[ $MODEL == *"Raspberry Pi 4"* ]]; then
  echo "Hardware: Raspberry PI 4"
  HARDWARE="RPI4"

fi

fi

}

function checkVersion () {

#We check this info on home assistant web page
CONTENT=$(curl -s -L https://www.home-assistant.io/)
VERSION_WEB=(`echo $CONTENT | grep -o -P '(?<=Current Version:).*?(?=</h1)' | awk '{$1=$1};1' `)

#We check installed version
VERSION_INSTALLED=(`cat $PATH_HA_CONFIG/.HA_VERSION`)

LOG="\tWeb:......${purpleColour}$VERSION_WEB${endColour}\n\tInstalled:${turquoiseColour}$VERSION_INSTALLED ${endColour}"
echo -e $LOG
#We write on system log
logger $SCRIPT:$LOG


}


#proceso de actualizacion
function procesoActualizacion () {

checkVersion

#Si es misma version, no hacemos nada
if [ "$VERSION_WEB" = "$VERSION_INSTALLED" ] && [ $FORCE = "0" ]; then
    LOG="Same version."
    echo $SCRIPT:$LOG
    logger $SCRIPT:$LOG

    
else
  if [ $FORCE = "1" ]; then
    LOG="Force update enabled"
  else
   LOG="We will update from $VERSION_INSTALLED to $VERSION_WEB"

  fi
    echo $SCRIPT:$LOG
    logger $SCRIPT:$LOG

    #Pull new image
    docker pull $IMAGE_DOCKER:$TAG_DOCKER

    #stop HA container
    docker stop $NAME_CONTAINER

    #Delete HA container
    docker rm $NAME_CONTAINER

    #Options to add
    if [ ! -z  $USB_ZIGBEE  ] ; then CADENA_ZIGBEE="--device=$USB_ZIGBEE"; else CADENA_ZIGBEE=""; fi
    if [ ! -z  $PATH_HA_MEDIA  ] ; then CADENA_HA_MEDIA="-v $PATH_HA_MEDIA:/media"; else CADENA_HA_MEDIA=""; fi
    if [ ! -z  $PATH_HA_SSL  ] && [ ! -z  $PATH_HA_SSL_CONTAINER ] ; then CADENA_HA_SSL="-v $PATH_HA_SSL:$PATH_HA_SSL_CONTAINER"; else CADENA_HA_SSL=""; fi
    if [ ! -z  $PATH_HA_DBUS  ] && [ ! -z  $PATH_HA_DBUS_CONTAINER ] ; then CADENA_HA_DBUS="-v $PATH_HA_DBUS:$PATH_HA_DBUS_CONTAINER:ro"; else CADENA_HA_DBUS=""; fi



   
    docker run -d --name="$NAME_CONTAINER" $CADENA_ZIGBEE  --restart unless-stopped -v $PATH_HA_CONFIG:/config $CADENA_HA_MEDIA $CADENA_HA_SSL $CADENA_HA_DBUS -v /etc/localtime:/etc/localtime:ro --net=host $IMAGE_DOCKER:$TAG_DOCKER
    LOG="Process finished."
    echo $SCRIPT:$LOG
    logger $SCRIPT:$LOG

fi
}


function procesoBackup() {
 echo $1
 FILE=$(date +"%d%m%y-%H%M")-HA-backup.tgz 
 echo Creating $FILE....
 echo Stoping container
 docker stop $NAME_CONTAINER
 echo Creating backup...
 tar -czf $FOLDER_BACKUP/$1/$FILE $PATH_HA_CONFIG
 echo Generating GPG
 if [ "$2" == "gpg" ]; then
  gpg --encrypt --recipient $RECIPIENT_GPG $FOLDER_BACKUP/$1/$FILE
  rm  $FOLDER_RAIZ_BACKUP/$1/$FILE
  chown pi: $FOLDER_BACKUP/$1/$FILE.gpg
  echo "file $FOLDER_BACKUP/$1/$FILE.gpg created."
 else
  echo "file $FOLDER_BACKUP/$1/$FILE created."
 fi
 echo Starting HA container
 docker start $NAME_CONTAINER

}

function comoRecuperarBackup() {
echo "You must to run: gpg --decrypt file.tgz.gpg > backup.tgz and then umcompress"


}


#Inicio del proceso
  
checkHardware
if [ $HARDWARE == "RPI4" ]; then
 IMAGE_DOCKER=$IMAGE_DOCKER_RPI4
else
if [ $HARDWARE == "RPI3" ]; then
 IMAGE_DOCKER=$IMAGE_DOCKER_RPI3
else

if [ $HARDWARE == "x86_64" ]; then
 IMAGE_DOCKER=$IMAGE_DOCKER_x86_64
else

echo "Hardware not supported!"
exit 1
fi
fi

fi


#control de opciones
contador_parametros=0; while getopts  "hiucb:g:frt:" opcion; do
 case ${opcion} in
  h) ayuda;;   

  i) #opciones
     let contador_parametros=1
     if ! [ -d "$DEST" ]; then
      mkdir -p $PATH_HA_CONFIG
      mkdir -p $PATH_HA_MEDIA
     fi
     procesoActualizacion;;
    

  u) #opciones
     let contador_parametros=1
     echo "Starting update process"
     procesoActualizacion;;
  c) let contador_parametros=1
     echo "Checking version"
     checkVersion;;
  b) let contador_parametros=1
     echo "Create backup"
     procesoBackup $OPTARG;;
  g) let contador_parametros=1
     echo "Backup with gpg option"
     procesoBackup $OPTARG "gpg";;
  r) let contador_parametros=1
     comoRecuperarBackup;;

  f) let contador_parametros+=1
     echo "force option"
     FORCE=1
     procesoActualizacion;;

  t) let contador_parametros+=1
     echo "update to a specified tag"
     FORCE=1 
     TAG_DOCKER=$OPTARG
     echo $TAG_DOCKER
     procesoActualizacion;;
     
 esac

done




if [ $contador_parametros -ne 1 ]; then
 help
else
 echo "Have a nice day!"
fi



