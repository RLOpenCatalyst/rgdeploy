#!/bin/bash -xe
sudo docker login -u AWS -p $(aws ecr get-login-password --region us-east-2) 045938549113.dkr.ecr.us-east-2.amazonaws.com
sudo docker pull 045938549113.dkr.ecr.us-east-2.amazonaws.com/researchportal:_fd_1.21.2_b2433
sudo docker pull 045938549113.dkr.ecr.us-east-2.amazonaws.com/nginx:latest
sudo docker pull 045938549113.dkr.ecr.us-east-2.amazonaws.com/notificationsink:1.19.0_b2
