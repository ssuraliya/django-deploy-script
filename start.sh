sudo systemctl daemon-reload
sudo systemctl restart gunicorn.socket
sudo systemctl enable gunicorn.socket

sudo systemctl enable celeryd
sudo systemctl enable celerybeat

sudo systemctl restart celeryd
sudo systemctl restart celerybeat

sudo systemctl restart nginx
sudo ufw allow 'Nginx Full'