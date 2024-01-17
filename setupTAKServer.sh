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

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

. ${SCRIPT_DIR}/setup.sh

usage() { echo "usage: setupTAKServer.sh -d <DB HOST> -p <DB PASSWORD> -f <FQDN> -e <EMAIL Address>"; exit 1; }

while getopts "d:p:f:e:h" arg; do
  case $arg in
    h)
      usage
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
    e)
      EMAIL=$OPTARG
      ;;
  esac
done
shift $((OPTIND-1))

if [ -z "${FQDN}" ] || [ -z "${EMAIL}" ];
then
    usage
fi

if [ "$USER" != "tak" ];
then
    echo "This script must be executed as the tak user"
    exit 1
fi

sdkmanSetup=`grep -c SDKMAN ~/.bash_profile`

if [ ${sdkmanSetup} == 0 ];
then
  echo "export SDKMAN_DIR=/usr/local/sdkman" >> ~/.bash_profile
  echo "source /usr/local/sdkman/bin/sdkman-init.sh" >> ~/.bash_profile
  echo "sdk use java 17.0.9-amzn" >> ~/.bash_profile
fi

export SDKMAN_DIR=/usr/local/sdkman
source /usr/local/sdkman/bin/sdkman-init.sh
sdk use java 17.0.9-amzn


## Setup Certs
##---------------------------------
printf "Setting up certs..."
cd /opt/tak/certs

echo ${CA_NAME} | ./makeRootCa.sh

echo "y" | ./makeCert.sh ca ${CERT_INTER_CA}

./makeCert.sh server ${FQDN}

./makeCert.sh client ${EMAIL}
printf "DONE\n"

## CoreConfig update
printf "Setting up the CoreConfig..."
cd /opt/tak

cp CoreConfig.example.xml CoreConfig.xml

##---------------------------------
## Setup Database Connection, if provided, otherwise we'll use what was setup
##---------------------------------
if [ ! -z "${DBHOST}"] || [ ! -z "${DBPASSWORD}" ];
then
  sed -i 's#<connection url="jdbc:postgresql://127.0.0.1:5432/cot" username="martiuser" password="" />#<connection url="jdbc:postgresql://'"${DBHOST}"'/cot" username="martiuser" password="'"${DBPASSWORD}"'" />#' CoreConfig.xml
fi

sed -i '/\/Configuration/i<certificateSigning CA=\"TAKServer\"> \
        <certificateConfig> \
                <nameEntries> \
                        <nameEntry name="O" value=\"'${ORGANIZATION}'\"/> \
                        <nameEntry name="OU" value=\"TAK\"/> \
                </nameEntries> \
        </certificateConfig> \
        <TAKServerCAConfig \
                keystore=\"JKS\" \
                keystoreFile=\"certs/files/'"${CERT_INTER_CA}"'-signing.jks\" \
                keystorePass=\"atakatak\" \
                validityDays=\"30\" \
                signatureAlg=\"SHA256WithRSA\"/> \
</certificateSigning>' CoreConfig.xml

sed -i 's#<input _name="stdssl" protocol="tls" port="8089" coreVersion="2"/>#<input _name="stdssl" protocol="tls" port="8089" coreVersion="2" auth="x509"/>#' CoreConfig.xml
sed -i 's#<connector port="8446" clientAuth="false" _name="cert_https"/>#<connector port="8446" enableWebtak="false" clientAuth="false" _name="cert_https"/>#' CoreConfig.xml
sed -i 's#keystore="JKS" keystoreFile="certs/files/takserver.jks" keystorePass="atakatak"#keystore="JKS" keystoreFile="certs/files/'"${FQDN}"'.jks" keystorePass="atakatak"#' CoreConfig.xml
sed -i 's#truststore="JKS" truststoreFile="certs/files/truststore-root.jks" truststorePass="atakatak">"#truststore="JKS" truststoreFile="certs/files/truststore-'"${CERT_INTER_CA}"'.jks" truststorePass="atakatak">#' CoreConfig.xml
printf "DONE\n"