#!/bin/bash
#
# Install system requirements
#
# Copyright (c) 2012 Michael Lujan <mike.lujan@me.com>
#

function lower {
	# helper function
	echo $1 | tr '[:upper:]' '[:lower:]'
}

function system_install_apache_worker {
    aptitude -y install apache2-mpm-worker apache2-dev
}

function system_install_apache_mod_wsgi {
    aptitude -y install libapache2-mod-wsgi
}

function system_apache_cleanup {
    a2dissite default # disable default vhost
}

function system_install_utils {
    aptitude -y install htop iotop bsd-mailx python-software-properties zsh
}

function system_install_build {
    aptitude -y install build-essential gcc
}

function system_install_subversion {
    aptitude -y install subversion
}

function system_install_git {
	aptitude -y install git-core
}

function system_install_mercurial {
	aptitude -y install mercurial
}

function system_install_python {
	aptitude -y install python python-dev build-essential python-pip
	pip install virtualenv virtualenvwrapper
}

function system_install_mongodb {
	aptitude -y install mongodb
}

function system_add_user {
	# system_add_user(username, password, groups, shell=/bin/bash)
	USERNAME=`lower $1`
	PASSWORD=$2
	SUDO_GROUP=$3
	SHELL=$4
	if [ -z "$4" ]; then
        SHELL="/bin/bash"
    fi
    useradd --create-home --shell "$SHELL" --user-group --groups "$SUDO_GROUP" "$USERNAME"
    echo "$USERNAME:$PASSWORD" | chpasswd	
}

function system_add_system_user {
    # system_add_system_user(username, home, shell=/bin/bash)
    USERNAME=`lower $1`
    HOME_DIR=$2
    SHELL=$3
    if [ -z "$3" ]; then
        SHELL="/bin/bash"
    fi
    useradd --system --create-home --home-dir "$HOME_DIR" --shell "$SHELL" --user-group $USERNAME
}

function system_lock_user {
    # system_lock_user(username)
    passwd -l "$1"
}

function system_get_user_home {
    # system_get_user_home(username)
    cat /etc/passwd | grep "^$1:" | cut --delimiter=":" -f6
}

function system_user_add_ssh_key {
    # system_user_add_ssh_key(username, ssh_key)
    USERNAME=`lower $1`
    USER_HOME=`system_get_user_home "$USERNAME"`
    sudo -u "$USERNAME" mkdir "$USER_HOME/.ssh"
    sudo -u "$USERNAME" touch "$USER_HOME/.ssh/authorized_keys"
    sudo -u "$USERNAME" echo "$2" >> "$USER_HOME/.ssh/authorized_keys"
    chmod 0600 "$USER_HOME/.ssh/authorized_keys"
}

function system_sshd_edit_bool {
    # system_sshd_edit_bool (param_name, "Yes"|"No")
    VALUE=`lower $2`
    if [ "$VALUE" == "yes" ] || [ "$VALUE" == "no" ]; then
        sed -i "s/^#*\($1\).*/\1 $VALUE/" /etc/ssh/sshd_config
    fi
}

function system_sshd_permitrootlogin {
    system_sshd_edit_bool "PermitRootLogin" "$1"
}

function system_sshd_passwordauthentication {
    system_sshd_edit_bool "PasswordAuthentication" "$1"
}

function system_update_hostname {
    # system_update_hostname(system hostname)
    if [ -z "$1" ]; then
        echo "system_update_hostname() requires the system hostname as its first argument"
        return 1;
    fi
    echo $1 > /etc/hostname
    hostname -F /etc/hostname
    echo -e "\n127.0.0.1 $1 $1.local\n" >> /etc/hosts
}

function system_security_logcheck {
    aptitude -y install logcheck logcheck-database
    # configure email
    # start after setup
}

function system_security_fail2ban {
    aptitude -y install fail2ban
}

function system_security_ufw_configure_basic {
    # see https://help.ubuntu.com/community/UFW
    ufw logging on

    ufw default deny

    ufw allow ssh/tcp
    ufw limit ssh/tcp

    ufw allow http/tcp
    ufw allow https/tcp

    ufw enable
}

function system_configure_private_network {
    # system_configure_private_network(private_ip)
    PRIVATE_IP=$1
    NETMASK="255.255.128.0"
    cat >>/etc/network/interfaces <<EOF
auto eth0:0
iface eth0:0 inet static
 address $PRIVATE_IP
 netmask $NETMASK
EOF
    touch /tmp/restart_initd-networking
}

function restart_services {
    # restarts upstart services that have a file in /tmp/needs-restart/
    for service_name in $(ls /tmp/ | grep restart-* | cut -d- -f2-10); do
        service $service_name restart
        rm -f /tmp/restart-$service_name
    done
}

function restart_initd_services {
    # restarts upstart services that have a file in /tmp/needs-restart/
    for service_name in $(ls /tmp/ | grep restart_initd-* | cut -d- -f2-10); do
        /etc/init.d/$service_name restart
        rm -f /tmp/restart_initd-$service_name
    done
}

function system_start_etc_dir_versioning {
    hg init /etc
    hg add /etc
    hg commit -u root -m "Started versioning of /etc directory" /etc
    chmod -R go-rwx /etc/.hg
}

function system_record_etc_dir_changes {
    if [ ! -n "$1" ];
        then MESSAGE="Committed /etc changes"
        else MESSAGE="$1"
    fi
    hg addremove /etc
    hg commit -u root -m "$MESSAGE" /etc || echo > /dev/null # catch "nothing changed" return code
}