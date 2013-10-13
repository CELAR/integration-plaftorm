#!/bin/bash
set -e
set -x

# Functions to setup firewall and nginx as proxy.
# Entry function is setup_firewall_and_nginx()

function _echoerr() { echo "$@" 1>&2; }

function _exit() { _echoerr "$@"; exit 1; }

function _find_extra_disk() {
    if [ -b /dev/vdc ]; then
    	echo /dev/vdc
    elif [ -b /dev/sdc ]; then
    	echo /dev/sdc
    else
        _exit "No extra disk on /dev/{s,v}dc. Exiting..."
    fi
}

function _move_under_extra_disk() {
	# $1 required
    # Move given directory under given raw device
    export WORKING_DIR=${1:?"Directory must be provided."}
    export WORKING_DIR_NAME=$(basename $1)
    export WORKING_DIR_BASE=$(dirname $1)

    export EXTRA_DISK=${2:-$(_find_extra_disk)}
    export PART_TYPE=ext3

    sudo mkfs.${PART_TYPE} -F -m 0 $EXTRA_DISK
    export MOUNT_POINT=/mnt/extra_disk
    sudo mkdir -p $MOUNT_POINT
    sudo chmod 777 $MOUNT_POINT
    sudo mount $EXTRA_DISK $MOUNT_POINT
    sudo sed -i '$a\'"$EXTRA_DISK $MOUNT_POINT $PART_TYPE defaults 0 0" /etc/fstab
    sudo mv $WORKING_DIR $MOUNT_POINT
    sudo ln -sf $MOUNT_POINT/$WORKING_DIR_NAME $WORKING_DIR_BASE
}

function _setup_firewall() {
    _PORTS_TO_ENABLE=$@
    sudo cat > /etc/iptables.rules << EOF
*filter
:INPUT ACCEPT [0:0]
:FORWARD ACCEPT [0:0]
:OUTPUT ACCEPT [0:0]
-A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
-A INPUT -p icmp -j ACCEPT
-A INPUT -i lo -j ACCEPT
EOF
    for PORT in ${_PORTS_TO_ENABLE}; do
        sudo cat >> /etc/iptables.rules << EOF
-A INPUT -m state --state NEW -m tcp -p tcp --dport ${PORT} -j ACCEPT
EOF
    done
    sudo cat >> /etc/iptables.rules << EOF
-A INPUT -j REJECT --reject-with icmp-host-prohibited
-A FORWARD -j REJECT --reject-with icmp-host-prohibited
COMMIT
EOF
    sudo iptables-restore < /etc/iptables.rules
    sudo cat > /etc/network/if-pre-up.d/iptablesload << EOF
#!/bin/sh
iptables-restore < /etc/iptables.rules
exit 0
EOF
    sudo chmod +x /etc/network/if-pre-up.d/iptablesload
}

function _generate_and_install_server_certificate() {
    _SERVER_CERT=$1
    _SERVER_KEY=$2

    # generate serf-signed server certificate
    export PASSWORD=jenkinscred
    cd ~
    cat > openssl.cfg << EOF
[ req ]
distinguished_name     = req_distinguished_name
x509_extensions        = v3_ca
prompt                 = no
input_password         = $PASSWORD
output_password        = $PASSWORD

dirstring_type = nobmp

[ req_distinguished_name ]
C = EU
CN = $(hostname -f)

[ v3_ca ]
basicConstraints = CA:false
nsCertType=client, email, objsign
keyUsage=critical, digitalSignature, nonRepudiation, keyEncipherment, dataEncipherment, keyAgreement
subjectKeyIdentifier=hash
authorityKeyIdentifier=keyid:always,issuer:always
EOF

    KEYPASS=env:PASSWORD
    openssl genrsa -passout $KEYPASS -des3 -out server.key 2048
    openssl req -new -key server.key -out server.csr -config openssl.cfg
    cp server.key server.key.org
    openssl rsa -in server.key.org -out server.key -passin $KEYPASS
    openssl x509 -req -days 365 -in server.csr -signkey server.key -out server.crt

    # install the server certificate
    sudo cp server.crt ${_SERVER_CERT}
    sudo chmod 400 ${_SERVER_CERT}
    sudo cp server.key ${_SERVER_KEY}
    sudo chmod 400 ${_SERVER_KEY}
}

function _install_and_configure_nginx() {
    # Set up proxy from HTTPS:${_EXTERNAL_SSL_PORT} to HTTP:${_PROXY_TO_PORT} with nginx

    _PROXY_TO_PORT=$1
    _EXTERNAL_SSL_PORT=$2

    # install nginx
    sudo aptitude -y install nginx

    local SERVER_CERT=/etc/ssl/certs/server.crt
    local SERVER_KEY=/etc/ssl/private/server.key

    _generate_and_install_server_certificate ${SERVER_CERT} ${SERVER_KEY}

    # configure nginx to proxy from HTTPS:${_EXTERNAL_SSL_PORT} to HTTP:${PROXY_TO_PORT}
    sudo rm -f /etc/nginx/sites-{available,enabled}/default
    sudo cat > /etc/nginx/sites-available/jenkins << EOF
upstream app_server {
    server 127.0.0.1:${_PROXY_TO_PORT} fail_timeout=0;
}

server {
    listen ${_EXTERNAL_SSL_PORT} default ssl;
    listen [::]:${_EXTERNAL_SSL_PORT} default ipv6only=on;
    server_name $(hostname -f);

    ssl_certificate           ${SERVER_CERT};
    ssl_certificate_key       ${SERVER_KEY};

    ssl_session_timeout  5m;
    ssl_protocols  SSLv3 TLSv1;
    ssl_ciphers HIGH:!ADH:!MD5;
    ssl_prefer_server_ciphers on;

    location / {
        proxy_set_header Host \$http_host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_redirect http:// https://;

        add_header Pragma "no-cache";

        proxy_pass http://app_server;
    }
}
EOF
    sudo ln -s /etc/nginx/sites-available/jenkins /etc/nginx/sites-enabled/

    sudo service nginx start
}

function _add_cert_to_javakeystore() {
    # Linux and Ubuntu only.
    CERT_FILE=$1

    KEYSTORE=/etc/ssl/certs/java/cacerts
    STOREPASS=changeit

    sudo keytool -import -noprompt -alias CELAR-Nexus \
    	-file $CERT_FILE \
    	-keystore $KEYSTORE -storepass $STOREPASS  
}

function setup_firewall_and_nginx() {
    _PROXY_TO_PORT=$1
    _EXTERNAL_SSL_PORT=$2

    local PORTS_TO_ENABLE="22 ${_EXTERNAL_SSL_PORT}"

    _setup_firewall ${PORTS_TO_ENABLE}
    _install_and_configure_nginx ${_PROXY_TO_PORT} ${_EXTERNAL_SSL_PORT}
}

### Jenkins deployment

JENKINS_PORT=8080
PROXY_TO_PORT=$JENKINS_PORT
EXTERNAL_SSL_PORT=443

function install_worker_deps() {
    # decision-module needs java 1.7
	export WORKER_DEPS="git maven openjdk-6-jdk openjdk-7-jdk openjdk-7-jre"
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

function move_Jenkins_under_extra_disk() {
    sudo service jenkins stop
    _move_under_extra_disk /var/lib/jenkins 
    sudo service jenkins start
}

function install_Jenkins() {
    wget -q -O - http://pkg.jenkins-ci.org/debian/jenkins-ci.org.key | sudo apt-key add -
    sudo sh -c 'echo deb http://pkg.jenkins-ci.org/debian binary/ > /etc/apt/sources.list.d/jenkins.list'
    sudo apt-get -y update
    sudo apt-get -y install jenkins

	move_Jenkins_under_extra_disk

    add_nexus_cert_to_javakeystore
}

setup_firewall_and_nginx ${PROXY_TO_PORT} ${EXTERNAL_SSL_PORT}
install_Jenkins

install_worker_deps

# decision-module needs java 1.7. Update default to 1.7.
update-alternatives --config java
update-alternatives --config javac
