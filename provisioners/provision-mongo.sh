#!/bin/bash
#sudo apt-get install gnupg curl
#curl -fsSL https://pgp.mongodb.com/server-4.4.asc | \
   #sudo gpg -o /usr/share/keyrings/mongodb-server-4.4.gpg \
   #--dearmor
#sudo echo "deb [ arch=amd64,arm64 signed-by=/usr/share/keyrings/mongodb-server-4.4.gpg ] https://repo.mongodb.org/apt/ubuntu focal/mongodb-org/4.4 multiverse" | sudo tee /etc/apt/sources.list.d/mongodb-org-4.4.list
#sudo apt-get update
#sudo apt-get install -y mongodb-org=4.4.26 mongodb-org-server=4.4.26 mongodb-org-shell=4.4.26 mongodb-org-mongos=4.4.26 mongodb-org-tools=4.4.26
#sudo systemctl daemon-reload
#sudo systemctl start mongod
#sudo systemctl stop mongod


sudo apt update
sudo apt-get install gnupg curl
curl -fsSL https://www.mongodb.org/static/pgp/server-7.0.asc | sudo gpg -o /usr/share/keyrings/mongodb-server-7.0.gpg --dearmor
echo "deb [ arch=amd64,arm64 signed-by=/usr/share/keyrings/mongodb-server-7.0.gpg ] https://repo.mongodb.org/apt/ubuntu jammy/mongodb-org/7.0 multiverse" | sudo tee /etc/apt/sources.list.d/mongodb-org-7.0.list
sudo apt-get update
sudo apt-get install -y mongodb-org
sudo systemctl daemon-reload
sudo systemctl start mongod
sudo systemctl stop mongod
