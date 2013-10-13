#!/bin/bash
set -e
set -x

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
	# Move given directory under given raw device
    export WORKING_DIR=$1
    export WORKING_DIR_NAME=$(basename $1)
    export WORKING_DIR_BASE=$(dirname $1)

    export EXTRA_DISK=${2:-$(_find_extra_disk)}

    sudo mkfs.ext3 -F -m 0 $EXTRA_DISK
    export MOUNT_POINT=/mnt/extra_disk
    sudo mkdir -p $MOUNT_POINT
    sudo chmod 777 $MOUNT_POINT
    sudo mount $EXTRA_DISK $MOUNT_POINT
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


### Deploy APT

PORTS_TO_ENABLE="22 80"

function setup_apt_repo() {
    sudo apt-get -y update
    sudo apt-get -y install apache2 dpkg-dev

    APT_DIR=/var/www/apt
    sudo mkdir -p $APT_DIR/{releases,snapshots}

    _move_under_extra_disk $APT_DIR

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
