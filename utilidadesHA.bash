#!/bin/bash

# v2.11 , Author @danieldiazi

MESSAGE_TITLE="utilidadesHA: tools script for HA Container"
MESSAGE_CONFIG_FAIL="I can't read config .config file "
MESSAGE_USAGE="Usage"
MESSAGE_OPTION_INSTALL="Install HA version. If HA is installed, is the same than -u option"
MESSAGE_OPTION_UPDATE="Update HA version"
MESSAGE_OPTION_CHECK="Check if exists a new version"
MESSAGE_OPTION_BACKUP="Create a backup into indicated folder inside: "
MESSAGE_OPTION_BACKUP_GPG="Create a backup using gpg into indicated folder, inside: "
MESSAGE_OPTION_BACKUP_RECOVER_GPG="Explain how to recover a gpg backup "
MESSAGE_OPTION_UPDATE_FORCE="Force an update without check if the available version is already installed"
MESSAGE_OPTION_UPDATE_FORCE_TAG="Force an update to the image version tagged with tag  (by example 2022.9.0)"
MESSAGE_OPTION_HELP="Shows this info"
MESSAGE_INSTALLED="Installed:"
MESSAGE_UPDATE_PROCESS_VERSION="Updating: "
MESSAGE_PROCESS_FINISHED="Process finished."
MESSAGE_FORCE_ENABLED="Force enabled"
MESSAGE_CREATING="Creating"
MESSAGE_STOP_CONTAINER="Stopping container"
MESSAGE_START_CONTAINER="Starting HA container"
MESSAGE_HARDWARE_NOT_SUPPORTED="Hardware not supported!"

#Detecting system language
SYSTEM_LANGUAGE=${LANG:0:2}
myPath=$(dirname "$0") # relative path
myPath=$(cd "$myPath" && pwd) # full path


if [[ -f "${myPath}/locales/${SYSTEM_LANGUAGE}" ]] ; then

source ${myPath}/locales/${SYSTEM_LANGUAGE}


fi



echo "-------------------------------------------"
echo "${MESSAGE_TITLE}"
echo "-------------------------------------------"
echo ""




if [[ ! -f "${myPath}/utilidadesHA.config" ]] ; then
  LOG="${MESSAGE_CONFIG_FAIL} ${myPath}/utilidadesHA.config"
  echo -e $LOG
  #We write on system log
  logger $SCRIPT:$LOG
  exit 1  # fail

else
  . ${myPath}/utilidadesHA.config 

fi



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


##################
# HELP FUNCTION  #
##################

function help () {

echo -e "\n${yellowColour}[+]${endColour} ${grayColour}${MESSAGE_USAGE}:${endColour} \n"
echo -e "\t${redColour}[-i]${endColour}  ${blueColour}${MESSAGE_OPTION_INSTALL}${endColour}"
echo -e "\t${redColour}[-u]${endColour}  ${blueColour}${MESSAGE_OPTION_UPDATE}${endColour}"
echo -e "\t${redColour}[-c]${endColour}  ${blueColour}${MESSAGE_OPTION_CHECK}${endColour}"
echo -e "\t${redColour}[-b folder]${endColour}  ${blueColour}${MESSAGE_OPTION_BACKUP}${FOLDER_BACKUP}${endColour}"
echo -e "\t${redColour}[-g folder]${endColour}  ${blueColour}${MESSAGE_OPTION_BACKUP_GPG}${FOLDER_BACKUP}${endColour}"
echo -e "\t${redColour}[-r]  ${blueColour}${MESSAGE_OPTION_BACKUP_RECOVER_GPG}${endColour}"
echo -e "\t${redColour}[-f]  ${blueColour}${MESSAGE_OPTION_UPDATE_FORCE}${endColour}"
echo -e "\t${redColour}[-t tag] ${blueColour}${MESSAGE_OPTION_UPDATE_FORCE_TAG}${endColour}"
echo -e "\t${redColour}[-h]${endColour}  ${blueColour}${MESSAGE_OPTION_HELP}${endColour}"
echo -e "\n"
exit 1
}



##################
# CHECK HARDWARE #
##################




function checkHardware () {

ARCH=$(arch)

if [[ $ARCH == "x86_64" ]]; then
 HARDWARE="x86_64"
else
 if [[ $ARCH == "aarch64" ]]; then

   MODEL=$(tr -d '\0' </proc/device-tree/model);
   if [[ $MODEL == *"Raspberry Pi 3"* ]]; then
     echo "Hardware: Raspberry PI 3"
     HARDWARE="RPI3"
   elif [[ $MODEL == *"Raspberry Pi 4"* ]]; then
     echo "Hardware: Raspberry PI 4"
     HARDWARE="RPI4"
   elif [[ $MODEL == *"OrangePi Zero3"* ]]; then
     echo "Hardware: Orange Pi Zero3"
     HARDWARE="aarch64"
   else
     HARDWARE="aarch64"


fi


fi

fi

}


##################
# CHECK VERSION  #
##################

function checkVersion () {

#We check this info on home assistant web page
CONTENT=$(curl -s -L https://www.home-assistant.io/)
VERSION_WEB=(`echo $CONTENT | grep -o -P '(?<=Current Version:).*?(?=</h1)' | awk '{$1=$1};1' `)

#We check installed version
VERSION_INSTALLED=(`cat $PATH_HA_CONFIG/.HA_VERSION`)

LOG="\tWeb:......${purpleColour}$VERSION_WEB${endColour}\n\t${MESSAGE_INSTALLED}${turquoiseColour}$VERSION_INSTALLED ${endColour}"
echo -e $LOG
#We write on system log
logger $SCRIPT:$LOG


}

#####################
# HA UPDATE PROCESS #
#####################
function procesoActualizacion () {


#Si es misma version, no hacemos nada
if [ "$VERSION_WEB" = "$VERSION_INSTALLED" ] && [ $FORCE = "0" ]; then
    LOG="Same version."
    echo $SCRIPT:$LOG
    logger $SCRIPT:$LOG

    
else
  if [ $FORCE = "1" ]; then
    LOG=${MESSAGE_FORCE_ENABLED}
  else
   LOG=" ${MESSAGE_UPDATE_PROCESS_VERSION} $VERSION_INSTALLED  :  $VERSION_WEB"

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
    LOG=${MESSAGE_PROCESS_FINISHED}
    echo $SCRIPT:$LOG
    logger $SCRIPT:$LOG

fi
}

##################
# BACKUP PROCESS #
##################

function procesoBackup() {
 echo $1
 FILE=$(date +"%d%m%y-%H%M")-HA-backup.tgz 

 echo ${MESSAGE_CREATING} $FILE....
 
 echo ${MESSAGE_STOP_CONTAINER}
 docker stop $NAME_CONTAINER
 
 echo ${MESSAGE_CREATING} backup...
 tar -czf $FOLDER_BACKUP/$1/$FILE $PATH_HA_CONFIG
 
 if [ "$2" == "gpg" ]; then
  
  gpg --encrypt --recipient $RECIPIENT_GPG $FOLDER_BACKUP/$1/$FILE
  rm  $FOLDER_RAIZ_BACKUP/$1/$FILE
  echo "$FOLDER_BACKUP/$1/$FILE.gpg Ok."
 else
  echo "$FOLDER_BACKUP/$1/$FILE Ok."
 fi
 echo ${MESSAGE_START_CONTAINER}
 docker start $NAME_CONTAINER

}


###################
# BACKUP GPG INFO #
###################

function comoRecuperarBackup() {
 echo "gpg --decrypt file.tgz.gpg > backup.tgz"

}


function newInstall() {
   echo "$PATH_HA_CONFIG/.HA_VERSION" 
   if [ -f "$PATH_HA_CONFIG/.HA_VERSION" ]; then
        echo "Home assistant already installed" 
     else 
        if ! [ -d "$DEST" ]; then
         mkdir -p $PATH_HA_CONFIG
         mkdir -p $PATH_HA_MEDIA
        fi
        FORCE=1
        procesoActualizacion  
     fi

     



}




##################
# MAIN           #
##################



  
checkHardware


#Choose image
if [ $HARDWARE == "RPI4" ]; then
 IMAGE_DOCKER=$IMAGE_DOCKER_RPI4
else
 if [ $HARDWARE == "RPI3" ]; then
  IMAGE_DOCKER=$IMAGE_DOCKER_RPI3
 else
  if [ $HARDWARE == "x86_64" ]; then
   IMAGE_DOCKER=$IMAGE_DOCKER_x86_64
  else
   if [ $HARDWARE == "aarch64" ]; then
     IMAGE_DOCKER=$IMAGE_DOCKER_aarch64
   else
    echo ${MESSAGE_HARDWARE_NOT_SUPPORTED}
    exit 1
   fi
  fi
 fi
fi



#check option
contador_parametros=0; while getopts  "hiucb:g:frt:" opcion; do
 case ${opcion} in
  h) help;;   

  i) #install new version
     let contador_parametros=1
     newInstall;;
     
    

  u) #upgrade
     let contador_parametros=1
     echo "Starting update process"
     checkVersion
     procesoActualizacion;;
  c) #check version
     let contador_parametros=1
     echo "Checking version"
     checkVersion;;
  b) #Create backup
     let contador_parametros=1
     echo "Create backup"
     procesoBackup $OPTARG;;
  g) #Create backup with gpg
     let contador_parametros=1
     echo "Backup with gpg option"
     procesoBackup $OPTARG "gpg";;
  r) #how to revover gpg backup
     let contador_parametros=1
     comoRecuperarBackup;;

  f) #force option
     let contador_parametros+=1
     echo "force option"
     FORCE=1
     checkVersion
     procesoActualizacion;;

  t) #update to a choosen tag
     let contador_parametros+=1
     echo "update to a specified tag"
     FORCE=1 
     TAG_DOCKER=$OPTARG
     echo $TAG_DOCKER
     checkVersion
     procesoActualizacion;;
     
 esac

done




if [ $contador_parametros -ne 1 ]; then
 help
else
 echo "${MESSAGE_END}"
fi



