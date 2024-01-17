#!/bin/bash
#----------------------------------------------------------------------------------------
# Copyright 2024 Adeptus Cyber Solutions, LLC. or its affiliates. All Rights Reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License"). You
# may not use this file except in compliance with the License. A copy of
# the License is located at
#
#    https://www.apache.org/licenses/LICENSE-2.0.html
#
# or in the "license" file accompanying this file. This file is
# distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF
# ANY KIND, either express or implied. See the License for the specific
# language governing permissions and limitations under the License.
#----------------------------------------------------------------------------------------

#######
## TAK Server Setup
#######

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

. ${SCRIPT_DIR}/setup.sh

SWAP=0

usage() { echo "usage: sudo installTAKServer.sh -r <RPM to INSTALL> -s"; exit 1; }

while getopts "r:sh" arg; do
  case $arg in
    h)
      usage
      ;;
    r)
      RPM=$OPTARG
      ;;
    s)
      SWAP=1
      ;;
  esac
done
shift $((OPTIND-1))

if [ -z "${RPM}" ]; 
then
  usage
fi

if [ -z "${EMAIL}" ] || [ -z "${PASSWORD}" ] || [ -z "${FQDN}" ]  || [ -z "${STATE}" ]  || [ -z "${CITY}" ]  || [ -z "${ORGANIZATION}" ]  || [ -z "${CERT_INTER_CA}" ]  || [ -z "${CA_NAME}" ];
then
  echo "Required Variables are not set, please fill out the setup.sh file"
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
  dd if=/dev/zero of=/swapfile bs=128M count=32
  chmod 0600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  su - -c 'echo "/swapfile    swap    swap    defaults    0 0" >> /etc/fstab'
  printf "DONE\n"
fi

## Create the TAK user
##---------------------------------
printf "Adding tak user and group...DONE\n"
groupadd tak 
useradd -d /opt/tak -g tak -s /bin/bash tak

## Install Pre-Reqs
yum install -y epel-release
yum install -y https://download.postgresql.org/pub/repos/yum/reporpms/EL-7-x86_64/pgdg-redhat-repo-latest.noarch.rpm
yum install -y postgis33_15 postgis33_15-utils postgresql15 postgres15-contrib

## Install TAK Server
## Ignore dependancies as we are install on AL2023 and it doesn't have openjdk-17
##---------------------------------
printf "Installing RPM ${RPM}"
rpm -ivh --nodeps ${RPM}

## RPM installs some files as root
chown -R tak:tak /opt/tak
printf "...DONE\n"

## Setup Java 17
##---------------------------------
printf "Setting up java 17..."
su - root -c 'export SDKMAN_DIR="/usr/local/sdkman" && curl -s "https://get.sdkman.io" | bash'
su - root -c 'source "/usr/local/sdkman/bin/sdkman-init.sh" && sdk install java 17.0.9-amzn'
rm -f /usr/bin/java
ln -s /usr/local/sdkman/candidates/java/17.0.9-amzn/bin/java /usr/bin/java
# su -  -c 'echo "export SDKMAN_DIR=/usr/local/sdkman;source ${SDKMAN_DIR}/bin/sdkman-init.sh" >> /etc/bashrc'
printf "DONE\n"

su - tak -c "${SCRIPT_DIR}/setupTAKServer.sh -d ${DBHOST} -p ${DBPASSWORD} -f ${FQDN} -e ${EMAIL}"

## Setup TAK Service
printf "Setting up services..."
systemctl daemon-reload
systemctl enable takserver
systemctl start takserver
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
java -jar /opt/tak/utils/UserManager.jar certmod -A /opt/tak/certs/files/${EMAIL}.pem
java -jar /opt/tak/utils/UserManager.jar usermod -p ${PASSWORD} admin
printf "DONE\n"

