#!/bin/bash
set -e
set -x

source ../lib/functions.sh

NEXUS_PORT=8081
PROXY_TO_PORT=$NEXUS_PORT
EXTERNAL_SSL_PORT=443

export BASE_URL=http://$(hostname -f):${EXTERNAL_SSL_PORT}/nexus
export NEXUS_VER=2.3.0-04

function install_Nexus() {
    export NEXUS_NAME_VER=nexus-${NEXUS_VER}
    export NEXUS_TGZ=${NEXUS_NAME_VER}-bundle.tar.gz
    export NEXUS_TGZ_PATH=/tmp/${NEXUS_TGZ}
    export NEXUS_INST_DIR=/usr/local
    export NEXUS_HOME=${NEXUS_INST_DIR}/nexus

    sudo apt-get install -y openjdk-6-jre

    sudo curl -o ${NEXUS_TGZ_PATH} http://www.sonatype.org/downloads/${NEXUS_TGZ}
    sudo tar -zxvf ${NEXUS_TGZ_PATH} -C ${NEXUS_INST_DIR}
    
    sudo useradd -d ${NEXUS_HOME} -c "Nexus user" -s /bin/sh nexus
    sudo chown -R nexus.nexus ${NEXUS_INST_DIR}/${NEXUS_NAME_VER} ${NEXUS_INST_DIR}/sonatype-work
    
    sudo ln -sf ${NEXUS_INST_DIR}/${NEXUS_NAME_VER} ${NEXUS_HOME}
    
    sudo ln -sf ${NEXUS_HOME}/bin/jsw/linux-x86-64/nexus /etc/init.d/nexus
    
    sudo sed -i -e 's/^#RUN_AS_USER=.*/RUN_AS_USER=nexus/' ${NEXUS_HOME}/bin/jsw/linux-x86-64/nexus

    sed -i -e '/^.*<restApi>.*$/,/^.*<\/restApi>.*$/c\  <restApi>\n    <baseUrl>'${BASE_URL}'</baseUrl>\n    <forceBaseUrl>true</forceBaseUrl>\n    <uiTimeout>60000</uiTimeout>\n  </restApi>' ${NEXUS_INST_DIR}/sonatype-work/nexus/conf/nexus.xml

    sudo update-rc.d nexus defaults
    sudo service nexus start
}

setup_firewall_and_nginx ${PROXY_TO_PORT} ${EXTERNAL_SSL_PORT}
install_Nexus
