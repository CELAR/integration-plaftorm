#!/bin/bash
set -e
set -x

source ../lib/functions.sh

PORTS_TO_ENABLE="22 80"

function setup_apt_repo() {
    sudo apt-get -y update
    sudo apt-get -y install apache2 dpkg-dev

    APT_DIR=/var/www/apt
    sudo mkdir -p $APT_DIR/{releases,snapshots}

    # Create repo update script
    #/usr/bin/celar-apt-repo-generate
    dpkg-scanpackages $APT_DIR/releases /dev/null | gzip -9c > $APT_DIR/releases/Packages.gz
    dpkg-scanpackages $APT_DIR/snapshots /dev/null | gzip -9c > $APT_DIR/snapshots/Packages.gz

    HOSTNAME=$(hostname -f)

    cat > $APT_DIR/HEADER.html << EOF
<h1>http://$HOSTNAME/apt/</h1>
<dl>
<dt>Add this repository to /etc/apt/sources.list.d/celar.list
 <dd><kbd>deb http://$HOSTNAME/apt/ binary/  # CELAR</kbd>
<dt>Import verification key with:
 <dd><kbd>wget -q http://$HOSTNAME/apt/public.gpg -O- | sudo apt-key add -</kbd>
</dl>
EOF
}

_setup_firewall ${PORTS_TO_ENABLE}
setup_apt_repo
