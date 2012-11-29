#!/bin/bash
#
# Installs a complete web environment with Apache, Django-nonrel and MongoDb.
#
# Copyright (c) 2012 Michael Lujan <mike.lujan@me.com>.
#

# <UDF name="notify_email" Label="Send email notification to" example="Email address to send notification and system alerts." />
# <UDF name="user_name" label="Unprivileged user account name" example="This is the account that you will be using to log in." />
# <UDF name="user_password" label="Unprivileged user password" />
# <UDF name="user_sshkey" label="Public Key for user" default="" example="Recommended method of authentication. It is more secure than password log in." />
# <UDF name="sshd_passwordauth" label="Use SSH password authentication" oneof="Yes,No" default="No" example="Turn off password authentication if you have added a Public Key." />
# <UDF name="sshd_permitrootlogin" label="Permit SSH root login" oneof="No,Yes" default="No" example="Root account should not be exposed." />

# <UDF name="user_shell" label="Shell" oneof="/bin/zsh,/bin/bash" default="/bin/bash" />

# <UDF name="sys_hostname" label="System hostname" default="myvps" example="Name of your server, i.e. linode1." />

# <UDF name="setup_django_project" label="Configure sample django/mod_wsgi project?" oneof="Standalone,InUserHome,InUserHomeRoot" default="Standalone" example="Standalone: project will be created in /srv/project_name directory under new user account; InUserHome: project will be created in /home/$user/project_name; InUserHomeRoot: project will be created in user's home directory (/home/$user)." />
# <UDF name="django_domain" label="Django domain" default="" example="Your server domain configured in the DNS. Leave blank for RDNS (*.members.linode.com)." />
# <UDF name="django_project_name" label="Django project name" default="my_project" example="Name of your django project (if 'Create sample project' is selected), i.e. my_website." />
# <UDF name="django_user" label="Django project owner user" default="django" example="System user that will be used to run the mod-wsgi project process in the 'Standalone' setup mode." />

# <UDF name="sys_private_ip" Label="Private IP" default="" example="Configure network card to listen on this Private IP (if enabled in Linode/Remote Access settings tab). See http://library.linode.com/networking/configuring-static-ip-interfaces" />

set -e
set -u

USER_GROUPS=sudo

exec &> /root/stackscript.log

source <ssinclude StackScriptID="1"> # StackScript Bash Library
system_update

source <ssinclude StackScriptID="5770"> # lib-system-requirements
system_install_mercurial
system_start_etc_dir_versioning #start recording changes of /etc config files

# Configure system
system_update_hostname "$SYS_HOSTNAME"
system_record_etc_dir_changes "Updated hostname" #SS5770

# Create user account
system_add_user "$USER_NAME" "$USER_PASSWORD" "$USER_GROUPS" "$USER_SHELL"
if [ "$USER_SSHKEY" ]; then
    system_user_add_ssh_key "$USER_NAME" "$USER_SSHKEY"
fi
system_record_etc_dir_changes "Added unprivileged user account" # SS5770

# Configure sshd
system_sshd_permitrootlogin "$SSHD_PERMITROOTLOGIN"
system_sshd_passwordauthentication "$SSHD_PASSWORDAUTH"
touch /tmp/restart-ssh
system_record_etc_dir_changes "Configured sshd" # SS5770

# Lock user account if not used for login
if [ "SSHD_PERMITROOTLOGIN" == "No" ]; then
    system_lock_user "root"
    system_record_etc_dir_changes "Locked root account" # SS5770
fi

# Install Postfix
postfix_install_loopback_only # SS1
system_record_etc_dir_changes "Installed postfix loopback" # SS5770

# Setup logcheck
system_security_logcheck
system_record_etc_dir_changes "Installed logcheck" # SS5770

# Setup fail2ban
system_security_fail2ban
system_record_etc_dir_changes "Installed fail2ban" # SS5770

# Setup firewall
system_security_ufw_configure_basic
system_record_etc_dir_changes "Configured UFW" # SS5770

# Setup python
system_install_python
system_record_etc_dir_changes "Installed python" # SS5770

# Install Common Utils
system_install_utils
system_install_build
system_install_subversion
system_install_git
system_record_etc_dir_changes "Installed common utils" #SS5770

# Install and configure apache and mod_wsgi
system_install_apache_worker
system_record_etc_dir_changes "Installed apache" # SS5770
system_install_apache_mod_wsgi
system_record_etc_dir_changes "Installed mod-wsgi" # SS5770
system_apache_cleanup
system_record_etc_dir_changes "Cleaned up apache config" # SS5770

# Install MongoDB
system_install_mongodb
system_record_etc_dir_changes "Installed MongoDB" # SS5770

# Setup and configure sample django project
RDNS=$(get_rdns_primary_ip)
DJANGO_PROJECT_PATH=""

source <ssinclude StackScriptID="5769"> # lib-django-nonrel
if [ -z "$DJANGO_DOMAIN" ]; then DJANGO_DOMAIN=$RDNS; fi

case "$SETUP_DJANGO_PROJECT" in
Standalone)
    DJANGO_PROJECT_PATH="/srv/$DJANGO_PROJECT_NAME"
    if [ -n "$DJANGO_USER" ]; then
        if [ "$DJANGO_USER" != "$USER_NAME" ]; then
            system_add_system_user "$DJANGO_USER" "$DJANGO_PROJECT_PATH" "$USER_SHELL"
        else
            mkdir -p "$DJANGO_PROJECT_PATH"
        fi
    else
        DJANGO_USER="www-data"
    fi
  ;;
InUserHome)
    DJANGO_USER=$USER_NAME
    DJANGO_PROJECT_PATH=$(system_get_user_home "$USER_NAME")/$DJANGO_PROJECT_NAME
  ;;
InUserHomeRoot)
    DJANGO_USER=$USER_NAME
    DJANGO_PROJECT_PATH=$(system_get_user_home "$USER_NAME")
  ;;
esac

django_create_project "$DJANGO_PROJECT_PATH"
django_change_project_owner "$DJANGO_PROJECT_PATH" "$DJANGO_USER"
    
django_configure_settings
django_configure_apache_virtualhost "$DJANGO_DOMAIN" "$DJANGO_PROJECT_PATH" "$DJANGO_USER"
touch /tmp/restart-apache2    
system_record_etc_dir_changes "Configured django project '$DJANGO_PROJECT_NAME'" # SS5770

if [ -n "$SYS_PRIVATE_IP" ]; then
    system_configure_private_network "$SYS_PRIVATE_IP"
    system_record_etc_dir_changes "Configured private network" # SS5770
fi

restart_services
restart_initd_services

# Send info message
cat > ~/setup_message <<EOD
Hi,

Your Linode VPS configuration is completed.

EOD

cat >> ~/setup_message <<EOD
You can now navigate to http://${DJANGO_DOMAIN}/ to see your web server running.
The Django project files are in $DJANGO_PROJECT_PATH/app.

EOD

cat >> ~/setup_message <<EOD
To access your server ssh to $USER_NAME@$RDNS

Thanks for using this StackScript. Follow https://github.com/slushy111/StackScripts for updates.

Need help with developing web apps? Email me at mike.lujan@me.com

Best,
Mike
--

EOD

mail -s "Your Linode VPS is ready" "$NOTIFY_EMAIL" < ~/setup_message
