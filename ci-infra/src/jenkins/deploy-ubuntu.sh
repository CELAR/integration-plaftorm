#!/bin/bash
set -e
set -x

source ../lib/functions.sh

JENKINS_PORT=8080
PROXY_TO_PORT=$JENKINS_PORT
EXTERNAL_SSL_PORT=443

function install_worker_deps() {
	export WORKER_DEPS="git maven openjdk-6-jdk"
	sudo apt-get -y install $WORKER_DEPS
}

function add_nexus_cert_to_javakeystore() {
    sudo cat > nexus-cert.pem << EOF
-----BEGIN CERTIFICATE-----

NB! Nexus certificate goes here.

-----END CERTIFICATE-----
EOF
    _add_cert_to_javakeystore nexus-cert.pem
    sudo rm -f nexus-cert.pem
}

function install_Jenkins() {
    wget -q -O - http://pkg.jenkins-ci.org/debian/jenkins-ci.org.key | sudo apt-key add -
    sudo sh -c 'echo deb http://pkg.jenkins-ci.org/debian binary/ > /etc/apt/sources.list.d/jenkins.list'
    sudo apt-get -y update
	sudo apt-get -y install sendmail
    sudo apt-get -y install jenkins
    	
    add_nexus_cert_to_javakeystore
    install_worker_deps
}

setup_firewall_and_nginx ${PROXY_TO_PORT} ${EXTERNAL_SSL_PORT}
install_Jenkins
