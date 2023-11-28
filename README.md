# Django Deployment Helper Script

This is a deployment helper script which will help you setup all the necessary files and services to deploy a django project.

It configures Nginx, gunicorn, celery and django project.

The responsibilities of this script is to:
- Create a system user 'deployer' with group 'deployers'
- Clone the github projects and install all dependencies
- Configure Nginx
- Configure gunicorn socket and service
- Configure celery and celery beat worker services

## There are two scripts in the project.

### prepare.sh

This script does the major work of configuring all the components. To run this script:

`sudo ./deploy.sh <APP_NAME> <DOMAIN_NAME> <GITHUB_LINK> <PATH_TO_ENV>`

### start.sh

This script is responsible to start the services created by the prepare.sh script. To run this script:

`sudo ./start.sh`


<em>Note: Inspired by https://github.com/harikvpy/deploy-django</em>