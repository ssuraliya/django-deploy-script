#!/bin/bash

LINUX_PREREQ=('git' 'build-essential' 'python3-dev' 'python3-pip' 'nginx' 'postgresql' 'libpq-dev' )
for pkg in "${LINUX_PREREQ[@]}"
    do
        echo "Installing '$pkg'..."
        apt-get -y install $pkg
        if [ $? -ne 0 ]; then
            echo "Error installing system package '$pkg'"
            exit 1
        fi
    done


# conventional values that we'll use throughout the script
APPNAME=$1
DOMAINNAME=$2
GITREPO=$3
ENVFILE=$4

# check appname was supplied as argument
if [ "$APPNAME" == "" ] || [ "$DOMAINNAME" == "" ]; then
	echo "Usage:"
	echo "  $ create_django_project_run_env <project> <domain>"
	echo
	echo "  Python version is 2 or 3 and defaults to 3 if not specified. Subversion"
	echo "  of Python will be determined during runtime. The required Python version"
	echo "  has to be installed and available globally."
	echo
	exit 1
fi

USERNAME=deployer
GROUPNAME=deployers
# app folder name under /webapps/<appname>_project
APPFOLDER=$1_project
APPFOLDERPATH=/app/$APPFOLDER


# ###################################################################
# Create the app folder
# ###################################################################
echo "Creating app folder '$APPFOLDERPATH'..."
mkdir -p $APPFOLDERPATH || exit "Could not create app folder"

# test the group 'webapps' exists, and if it doesn't create it
getent group $GROUPNAME
if [ $? -ne 0 ]; then
    echo "Creating group '$GROUPNAME' for automation accounts..."
    groupadd --system $GROUPNAME || exit "Could not create group 'webapps'"
fi

# create the app user account, same name as the appname
grep "$USERNAME:" /etc/passwd
if [ $? -ne 0 ]; then
    echo "Creating automation user account '$USERNAME'..."
    useradd --system --gid $GROUPNAME --shell /bin/bash --home $APPFOLDERPATH $USERNAME || exit "Could not create automation user account '$USERNAME'"
fi


echo "Setting ownership of $APPFOLDERPATH and its descendents to $USERNAME:$GROUPNAME..."
chown -R $USERNAME:$GROUPNAME $APPFOLDERPATH || exit "Error setting ownership"
# give group execution rights in the folder;
# TODO: is this necessary? why?
chmod g+x $APPFOLDERPATH || exit "Error setting group execute flag"

# install python virtualenv in the APPFOLDER
echo "Creating environment setup for django app..."
su -l $USERNAME << 'EOF'
pwd
echo "Setting up python virtualenv..."
python3 -m venv venv || exit "Error installing Python 3 virtual environment to app folder"

EOF

echo "Obtaining github code..."
su -l $USERNAME << EOF
pwd
git clone $GITREPO code && mv code/* ./ || exit "Error installing Python 3 virtual environment to app folder"
rm -rf code/
EOF

echo "Installing python packages...."
su -l $USERNAME << EOF
pip3 install -r requirements.txt
pip3 install gunicorn
EOF

echo "Copying env file..."
su -l $USERNAME << EOF
cp $ENVFILE $APPFOLDERPATH
chown $USERNAME:$GROUPNAME $APPFOLDERPATH/.env
EOF

GUNICORNWORKERFOLDER=/app/gunicorn-worker


sudo mkdir -p $GUNICORNWORKERFOLDER || exit "Could not create gunicorn worker folder"
sudo chown $USERNAME:$GROUPNAME $GUNICORNWORKERFOLDER


GUNICORNWORKER=$GUNICORNWORKERFOLDER/gunicorn.sock

echo "Creating gunicorn socket file..."
sudo cat > /etc/systemd/system/gunicorn.socket << EOF
[Unit]
Description=gunicorn socket

[Socket]
ListenStream=$GUNICORNWORKER

[Install]
WantedBy=sockets.target
EOF

echo "Creating gunicorn service file..."
sudo cat > /etc/systemd/system/gunicorn.service << EOF
[Unit]
Description=gunicorn daemon
Requires=gunicorn.socket
After=network.target

[Service]
User=$USERNAME
Group=$GROUPNAME
WorkingDirectory=$APPFOLDERPATH
ExecStart=$APPFOLDERPATH/env/bin/gunicorn \
          --access-logfile - \
          --workers 3 \
          --bind unix:$GUNICORNWORKER \
          $APPNAME.wsgi:application

[Install]
WantedBy=multi-user.target
EOF


echo "Creating nginx file..."
sudo cat > /etc/nginx/sites-available/$DOMAINNAME << EOF
server {
    listen 80;
    server_name $DOMAINNAME;

    location = /favicon.ico { access_log off; log_not_found off; }
    location /static/ {
        root $APPFOLDERPATH;
    }

    location / {
        include proxy_params;
        proxy_pass http://unix:$GUNICORNWORKER;
    }
}
EOF

echo "Creating nginx file link..."
sudo ln -s /etc/nginx/sites-available/$DOMAINNAME /etc/nginx/sites-enabled


echo "Creating celery config file"
sudo cat > /etc/default/celeryd << EOF
CELERYD_NODES="worker1"

CELERY_APP="$APPNAME"

# Log and PID directories
CELERYD_LOG_FILE="/var/log/celery/%n%I.log"
CELERYD_PID_FILE="/var/run/celery/%n.pid"

# Log level
CELERYD_LOG_LEVEL=INFO

# Path to celery binary, that is in your virtual environment
CELERY_BIN=$APPFOLDERPATH/venv/bin/celery

# Options for Celery Beat
CELERYBEAT_PID_FILE="/var/run/celery/beat.pid"
CELERYBEAT_LOG_FILE="/var/log/celery/beat.log"
EOF


echo "Creating celery service file..."
sudo cat > /etc/systemd/system/celeryd.service << EOF
[Unit]
Description=Celery Service
After=network.target

[Service]
Type=forking
User=$USERNAME
Group=$GROUPNAME
EnvironmentFile=/etc/default/celeryd
WorkingDirectory=$APPFOLDERPATH
ExecStart=/bin/sh -c '${CELERY_BIN} multi start ${CELERYD_NODES} \
  -A ${CELERY_APP} --pidfile=${CELERYD_PID_FILE} \
  --logfile=${CELERYD_LOG_FILE} --loglevel=${CELERYD_LOG_LEVEL} ${CELERYD_OPTS}'
ExecStop=/bin/sh -c '${CELERY_BIN} multi stopwait ${CELERYD_NODES} \
  --pidfile=${CELERYD_PID_FILE}'
ExecReload=/bin/sh -c '${CELERY_BIN} multi restart ${CELERYD_NODES} \
  -A ${CELERY_APP} --pidfile=${CELERYD_PID_FILE} \
  --logfile=${CELERYD_LOG_FILE} --loglevel=${CELERYD_LOG_LEVEL} ${CELERYD_OPTS}'

[Install]
WantedBy=multi-user.target
EOF

echo "Creating celery beat service file..."
sudo cat > /etc/systemd/system/celerybeat.service << EOF
[Unit]
Description=Celery Service
After=network.target

[Service]
Type=simple
User=sajid
Group=sajid
EnvironmentFile=/etc/default/celeryd
WorkingDirectory=$APPFOLDERPATH
ExecStart=/bin/sh -c '${CELERY_BIN} beat  \
  -A ${CELERY_APP} --pidfile=${CELERYBEAT_PID_FILE} \
  --logfile=${CELERYBEAT_LOG_FILE} --loglevel=${CELERYD_LOG_LEVEL}'

[Install]
WantedBy=multi-user.target
EOF

sudo mkdir /var/log/celery /var/run/celery
sudo chown $USERNAME:$GROUPNAME /var/log/celery /var/run/celery

sudo chown $USERNAME:$GROUPNAME /var/log/nginx/