#!/bin/bash

### These need to be set before executing
export STATE=
export CITY=
export ORGANIZATION=
export ORGANIZATIONAL_UNIT="TAK"
export CERT_INTER_CA=
export CA_NAME=

DBHOST=
DBPASSWORD=
FQDN=
EMAIL=

usage() { echo "usage: sudo setupTAKServer.sh -d <DB HOST> -p <DB PASSWORD> -f <FQDN> -e <EMAIL Address>"; exit 1; }

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

if [ -z "${DBHOST}" ] || [ -z "${DBPASSWORD}" ] || [ -z "${FQDN}" ] || [ -z "${EMAIL}" ];
then
    usage
fi

if [ "$USER" != "tak" ];
then
    echo "This script must be executed as the tak user"
    exit 1
fi

echo "export SDKMAN_DIR=/usr/local/sdkman" >> ~/.bash_profile
echo "source /usr/local/sdkman/bin/sdkman-init.sh" >> ~/.bash_profile
echo "sdk use java 17.0.9-amzn" >> ~/.bash_profile

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

## Setup Database Connection
##---------------------------------
sed -i 's#<connection url="jdbc:postgresql://127.0.0.1:5432/cot" username="martiuser" password="" />#<connection url="jdbc:postgresql://'"${DBHOST}"'/cot" username="martiuser" password="'"${DBPASSWORD}"'" />#' CoreConfig.xml

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