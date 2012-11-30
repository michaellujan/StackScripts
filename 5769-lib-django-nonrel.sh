#!/bin/bash
#
# Set up django-nonrel project and add apace vhost configuration
#
# Copyright (c) 2012 Michael Lujan <mike.lujan@me.com>
#

PROJECT_CODE_DIR=app
DJANGO_PROJECT=myproject

function django_change_project_owner {
    # django_change_project_owner(project_path, user)
    PROJECT_PATH="$1"
    USER="$2"
    chown -R "$USER:$USER" "$PROJECT_PATH"
}

function django_create_project {
    # django_create_project(project_path)

    PROJECT_PATH="$1"
    if [ -z "$PROJECT_PATH" ]; then
        echo "django_create_project() requires the project root path as the first argument"
        return 1;
    fi

    mkdir -p "$PROJECT_PATH/$PROJECT_CODE_DIR/conf/apache"
    mkdir -p "$PROJECT_PATH/logs" "$PROJECT_PATH/run/eggs"

    virtualenv "$PROJECT_PATH/venv"
    $PROJECT_PATH/venv/bin/pip install https://github.com/django-nonrel/djangotoolbox/archive/master.zip
    $PROJECT_PATH/venv/bin/pip install https://github.com/django-nonrel/mongodb-engine/archive/master.zip
    $PROJECT_PATH/venv/bin/pip install https://github.com/django-nonrel/django-nonrel/archive/django-1.3.2.zip

	cd "$PROJECT_PATH/$PROJECT_CODE_DIR/"
	"$PROJECT_PATH/venv/bin/django-admin.py" startproject "$DJANGO_PROJECT"
	
    mkdir -p "$PROJECT_PATH/$PROJECT_CODE_DIR/$DJANGO_PROJECT/static"

    echo "Django" >> "$PROJECT_PATH/$PROJECT_CODE_DIR/requirements.txt"
}

function django_configure_settings {
	#django_configure_settings(project_path)
	PROJECT_PATH="$1"
	SETTINGS="$PROJECT_PATH/$PROJECT_CODE_DIR/$DJANGO_PROJECT/settings.py"
	sed -i "s/\.db\.backends\./_mongodb_engine/" "$SETTINGS"
	sed -i -e "s/'NAME': ''/'NAME': '$DJANGO_PROJECT'/" "$SETTINGS"
	sed -i "s/.*'django.contrib.staticfiles',.*/&\n    'djangotoolbox',/" "$SETTINGS"
}

function django_configure_wsgi {
	#django_configure_wsgi(project_path)
	PROJECT_PATH="$1"
	FILE_PATH="$PROJECT_PATH/$PROJECT_CODE_DIR/$DJANGO_PROJECT"
	
	cat > "$FILE_PATH/wsgi.py" << EOF
import os
import sys

path = '$FILE_PATH'
if path not in sys.path:
    sys.path.insert(0, '$FILE_PATH')

os.environ['DJANGO_SETTINGS_MODULE'] = '$DJANGO_PROJECT.settings'

import django.core.handlers.wsgi
application = django.core.handlers.wsgi.WSGIHandler()
EOF
}

function django_configure_apache_virtualhost {
	#django_configure_apache_virtualhost(hostname, project_path, wsgi_user)
	VHOST_HOSTNAME="$1"
	PROJECT_PATH="$2"
	USER="$3"
	
	if [ -z "$VHOST_HOSTNAME" ]; then
		echo "django_configure_apache_virtualhost() requires the hostname as the first argument"
		return 1;
	fi
	
	if [ -z "$PROJECT_PATH" ]; then
        echo "django_configure_apache_virtualhost() requires path to the django project as the second argument"
        return 1;
    fi
    
    APACHE_CONF="200-$VHOST_HOSTNAME.conf"
    APACHE_CONF_PATH="$PROJECT_PATH/$PROJECT_CODE_DIR/conf/apache/$APACHE_CONF"
    
    cat > "$APACHE_CONF_PATH" << EOF
<VirtualHost *:80>
    ServerAdmin root@$VHOST_HOSTNAME
    ServerName $VHOST_HOSTNAME
    ServerSignature Off

    Alias /static/ $PROJECT_PATH/$PROJECT_CODE_DIR/$DJANGO_PROJECT/static/
    Alias /robots.txt $PROJECT_PATH/$PROJECT_CODE_DIR/$DJANGO_PROJECT/static/robots.txt
    Alias /favicon.ico $PROJECT_PATH/$PROJECT_CODE_DIR/$DJANGO_PROJECT/static/favicon.ico

    SetEnvIf User_Agent "monit/*" dontlog
    CustomLog "|/usr/sbin/rotatelogs $PROJECT_PATH/logs/access.log.%Y%m%d-%H%M 5M" combined env=!dontlog
    ErrorLog "|/usr/sbin/rotatelogs $PROJECT_PATH/logs/error.log.%Y%m%d-%H%M 5M"
    LogLevel warn

    WSGIScriptAlias / $PROJECT_PATH/$PROJECT_CODE_DIR/$DJANGO_PROJECT/wsgi.py

    WSGIDaemonProcess $VHOST_HOSTNAME user=$USER group=$USER processes=2 threads=10 maximum-requests=10000 display-name=%{USER} python-path=$PROJECT_PATH/$PROJECT_CODE_DIR:$PROJECT_PATH/venv/lib/python2.7/site-packages python-eggs=$PROJECT_PATH/run/eggs
    WSGIProcessGroup $VHOST_HOSTNAME
    WSGIScriptAlias / $PROJECT_PATH/$PROJECT_CODE_DIR/$DJANGO_PROJECT/wsgi.py

    <Directory $PROJECT_PATH/$PROJECT_CODE_DIR/$DJANGO_PROJECT/static>
        Order deny,allow
        Allow from all
        Options -Indexes FollowSymLinks
    </Directory>

    <Directory $PROJECT_PATH/$PROJECT_CODE_DIR/conf/apache>
        Order deny,allow
        Allow from all
    </Directory>

 </VirtualHost>
EOF

    ln -s -t /etc/apache2/sites-available/ "$APACHE_CONF_PATH"
    a2ensite "$APACHE_CONF"
}
