#!/bin/bash
#######
## TAK Server Setup
#######

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

RPM=
DBHOST=
DBPASSWORD=
FQDN=
SWAP=0
EMAIL=
PASSWORD=

usage() { echo "usage: sudo installTAKServer.sh -r <RPM to INSTALL> -d <DB HOST> -p <DB PASSWORD> -f <FQDN> -s"; exit 1; }

while getopts "r:d:p:f:sh" arg; do
  case $arg in
    h)
      usage
      ;;
    r)
      RPM=$OPTARG
      ;;
    d)
      DBHOST=$OPTARG
      ;;
    p)
      DBPASSWORD=$OPTARG
      ;;
    f)
      FQDN=$OPTARG
      ;;
    s)
      SWAP=1
      ;;
  esac
done
shift $((OPTIND-1))

if [ -z "${RPM}" ] || [ -z "${DBHOST}" ] || [ -z "${DBPASSWORD}" ] || [ -z "${FQDN}" ];
then
  usage
fi

if [ -Z "${EMAIL}" ] || [ -z "${PASSWORD}" ];
then
  echo "EMAIL and/or PASSWORD are not set"
  exit 1;
fi

## Must run this script as root
if [ "$EUID" -ne 0 ];
then
    echo "This script must be executed with sudo"
    usage
fi

## Create Swap File of 4GB
if [ ${SWAP} -eq 1 ];
then
  printf "Building swap space..."
  sudo dd if=/dev/zero of=/swapfile bs=128M count=32
  sudo chmod 0600 /swapfile
  sudo mkswap /swapfile
  sudo swapon /swapfile
  sudo su - -c 'echo "/swapfile    swap    swap    defaults    0 0" >> /etc/fstab'
  printf "DONE\n"
fi

## Create the TAK user
##---------------------------------
printf "Adding tak user and group...DONE\n"
sudo groupadd tak 
sudo useradd -d /opt/tak -g tak -s /bin/bash tak

## Install Pre-Reqs
sudo yum install -y epel-release
sudo yum install -y https://download.postgresql.org/pub/repos/yum/reporpms/EL-7-x86_64/pgdg-redhat-repo-latest.noarch.rpm
sudo yum install -y postgis33_15 postgis33_15-utils postgresql15 postgres15-contrib

## Install TAK Server
## Ignore dependancies as we are install on AL2023 and it doesn't have openjdk-17
##---------------------------------
printf "Installing RPM ${RPM}"
sudo rpm -ivh --nodeps ${RPM}

## RPM installs some files as root
sudo chown -R tak:tak /opt/tak
printf "...DONE\n"

## Setup Java 17
##---------------------------------
printf "Setting up java 17..."
sudo su - root -c 'export SDKMAN_DIR="/usr/local/sdkman" && curl -s "https://get.sdkman.io" | bash'
sudo su - root -c 'source "/usr/local/sdkman/bin/sdkman-init.sh" && sdk install java 17.0.9-amzn'
sudo rm -f /usr/bin/java
sudo ln -s /usr/local/sdkman/candidates/java/17.0.9-amzn/bin/java /usr/bin/java
# sudo su -  -c 'echo "export SDKMAN_DIR=/usr/local/sdkman;source ${SDKMAN_DIR}/bin/sdkman-init.sh" >> /etc/bashrc'
printf "DONE\n"

sudo su - tak -c "${SCRIPT_DIR}/setupTAKServer.sh -d ${DBHOST} -p ${DBPASSWORD} -f ${FQDN} -e ${EMAIL}"

## Setup TAK Service
printf "Setting up services..."
sudo systemctl daemon-reload
sudo systemctl enable takserver
sudo systemctl start takserver
printf "DONE\n"

printf "Waiting for TAK Server to come up fully..."
x=1
while [ ${x} -lt 45 ]
do  
  sleep 1
  printf "."
  x=$(($x+1))
done
printf "DONE\n"

printf "Assigning admin cert and password..."
sudo java -jar /opt/tak/utils/UserManager.jar certmod -A /opt/tak/certs/files/${EMAIL}.pem
sudo java -jar /opt/tak/utils/UserManager.jar usermod -p ${PASSWORD} admin
printf "DONE\n"

