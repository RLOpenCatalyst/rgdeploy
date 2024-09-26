################################################################################
# Copyright (C) 2019-2024 NI SP GmbH
# All Rights Reserved
#
# info@ni-sp.com / www.ni-sp.com
#
# We provide the information on an as is basis. 
# We provide no warranties, express or implied, related to the
# accuracy, completeness, timeliness, useability, and/or merchantability
# of the data and are not liable for any loss, damage, claim, liability,
# expense, or penalty, or for any direct, indirect, special, secondary,
# incidental, consequential, or exemplary damages or lost profit
# deriving from the use or misuse of this information.
################################################################################
# Version v1.1
#

###################################################
# Install DCV on RH/CentOS 9.x
#
# We recommend to execute the script step by step to see what is happening.
# https://www.ni-sp.com/wp-content/uploads/2019/10/dcv_rh9_noGPU_installation.sh

###################################################
# Update the OS with latest patches  

sudo yum upgrade -y
# sudo reboot 

###################################################
# configuration
# check if on AWS 
aws_cfg="NO"

###################################################
# create dcvtest user? 
# echo -n "Do you want to setup the dcvtest user for testing the session creation Y/N ? " 
# read -s resp
# if [ $resp == "Y" ] ; then
#   echo 
#   echo -n "Password for user dcvtest : " 
#   read -s password
#   echo 
#   user="dcvtest"
#   # encr=`echo thePassword | sudo passwd $user --stdin`
#   sudo adduser $user 
#   echo "$user:$password" | sudo chpasswd
#   echo User $user has been setup 
# fi 

echo

##############################################################
# Installation of DCV 2022.x 

sudo yum groupinstall 'Server with GUI' -y

sudo sed -ie 's/#WaylandEnable=false/WaylandEnable=false/' /etc/gdm/custom.conf
sudo systemctl restart gdm

sudo systemctl get-default
sudo systemctl set-default graphical.target
sudo systemctl isolate graphical.target
# Verify that the X Server is running - if not reboot the server 
ps aux | grep X | grep -v grep

sudo yum install glx-utils -y  # for checking the installation

# Verify
sudo DISPLAY=:0 XAUTHORITY=$(ps aux | grep "X.*\-auth" | grep -v grep \
      | sed -n 's/.*-auth \([^ ]\+\).*/\1/p') glxinfo | grep -i "opengl.*version"
# OpenGL core profile version string: 3.3 (Core Profile) Mesa 19.3.4
# OpenGL core profile shading language version string: 3.30
# OpenGL version string: 3.1 Mesa 19.3.4
# OpenGL shading language version string: 1.40
# OpenGL ES profile version string: OpenGL ES 3.1 Mesa 19.3.4
# OpenGL ES profile shading language version string: OpenGL ES GLSL ES 3.10

# for console sessions on servers without GPU 
# install the xdummy server for virtual framebuffer support 
sudo yum install xorg-x11-drv-dummy -y

# sudo vim /etc/X11/xorg.conf
sudo cp /etc/X11/xorg.conf /etc/X11/xorg.conf-BACKUP
echo '
Section "Device"
    Identifier "DummyDevice"
    Driver "dummy"
    Option "ConstantDPI" "true"
    Option "IgnoreEDID" "true"
    Option "NoDDC" "true"
    VideoRam 2048000
EndSection

Section "Monitor"
    Identifier "DummyMonitor"
    HorizSync   5.0 - 1000.0
    VertRefresh 5.0 - 200.0
    Modeline "1920x1080" 23.53 1920 1952 2040 2072 1080 1106 1108 1135
    Modeline "1600x900" 33.92 1600 1632 1760 1792 900 921 924 946
    Modeline "1440x900" 30.66 1440 1472 1584 1616 900 921 924 946
    ModeLine "1366x768" 72.00 1366 1414 1446 1494  768 771 777 803
    Modeline "1280x800" 24.15 1280 1312 1400 1432 800 819 822 841
    Modeline "1024x768" 18.71 1024 1056 1120 1152 768 786 789 807
EndSection

Section "Screen"
    Identifier "DummyScreen"
    Device "DummyDevice"
    Monitor "DummyMonitor"
    DefaultDepth 24
    SubSection "Display"
        Viewport 0 0
        Depth 24
        Modes "1920x1080" "1600x900" "1440x900" "1366x768" "1280x800" "1024x768"
        virtual 1920 1080
    EndSubSection
EndSection
' | sudo tee  /etc/X11/xorg.conf

sudo systemctl isolate multi-user.target
sleep 1
sudo systemctl isolate graphical.target
sleep 2

###################################################
# identify the right DCV server to download
#dcv_version="2023"
#echo Checking for latest DCV $dcv_version version 
#dcv_server=`curl --silent --output - https://download.nice-dcv.com/ | \
   # grep href | egrep "$dcv_version" | grep "el9" | grep Server | sed -e 's/.*http/http/' -e 's/tgz.*/tgz/' | head -1`
#echo "We will be downloading DCV server from $dcv_server"
#echo 

sudo yum install wget -y

# install DCV 
# use $dcv_server
# wget https://d1uj6qtbmh3dt5.cloudfront.net/2019.0/Servers/nice-dcv-2019.0-7318-el8.tgz
sudo rpm --import https://d1uj6qtbmh3dt5.cloudfront.net/NICE-GPG-KEY # allow the package manager to verify the signature
#echo Downloading DCV Server from $dcv_server
#wget $dcv_server 

wget https://d1uj6qtbmh3dt5.cloudfront.net/2023.1/Servers/nice-dcv-2023.1-16388-el9-x86_64.tgz
tar -xvzf nice-dcv-2023.1-16388-el9-x86_64.tgz && cd nice-dcv-2023.1-16388-el9-x86_64


sudo yum install nice-dcv-server-2023.1.16388-1.el9.x86_64.rpm \
     nice-xdcv-2023.1.565-1.el9.x86_64.rpm  \
     nice-dcv-web-viewer-2023.1.16388-1.el9.x86_64.rpm  \
     nice-dcv-gltest-2023.1.325-1.el9.x86_64.rpm nice-dcv-simple-external-authenticator-2023.1.228-1.el9.x86_64.rpm -y

# in case of USB remotization
# sudo yum install https://dl.fedoraproject.org/pub/epel/epel-release-latest-8.noarch.rpm
# sudo yum install dkms
# sudo dcvusbdriverinstaller

# for microphone redirection
# sudo yum install pulseaudio-utils -y 

# ensure that X server is running; you might get logged out by these commands
# use these commands to stop the X-server and start it again for testing the X-org configuration 
sudo systemctl isolate multi-user.target
sudo systemctl isolate graphical.target
sleep 3  # it takes a little time for the X server to come up 

# Add QUIC/UDP support: In the [connectivity] section of /etc/dcv/dcv.conf add
# enable-quic-frontend=true

# verify installation
ps -ef | grep X | grep -v grep
echo You should see the X server running - e.g.  /usr/bin/X :0 -background none -noreset -audit 4 -verbose -auth /run/gdm/auth-for-gdm-kgN6Mc/database -seat seat0 -nolisten tcp vt1

echo Verify DCV installation 
# sudo DISPLAY=:0 XAUTHORITY=$(ps aux | grep "X.*\-auth" | grep -v grep | gawk -F" -auth "'{print $2}' | awk '{print $1}') xhost | grep "SI:localuser:dcv$"
sudo DISPLAY=:0 XAUTHORITY=$(ps aux | grep "X.*\-auth" | \
    grep -v grep | sed -n 's/.*-auth \([^ ]\+\) .*/\1/p') xhost | grep "SI:localuser:dcv$"
echo If the command has returned SI:localuser:dcv, the dcv user can access the X server.
# If not you can try the following command
#  sudo DISPLAY=:0 dcvxgrantaccess +dcv

# verify that local users can access the X server - should show LOCAL:
sudo DISPLAY=:0 XAUTHORITY=$(ps aux | grep "X.*\-auth" | grep -v grep | sed -n 's/.*-auth \([^ ]\+\).*/\1/p') xhost | grep "LOCAL:$"

# uncomment auth-token-verifier="http://127.0.0.1:8444" in case you want to use DCV with EnginFrame Views session management - please note this will disable standard authentication
# sudo vim /etc/dcv/dcv.conf
# configure dcvsimpleextauth
# sudo systemctl start dcvsimpleextauth    # in EF Views deployments

# enable autostart of the DCV server 
sudo systemctl enable dcvserver
# sudo systemctl enable dcvsimpleextauth    # in EF Views deployments

# start server
sudo systemctl start dcvserver
# stop command
# sudo systemctl stop dcvserver

# in case you want to check the DCV logfile to see output from the DCV server have a look at
tail /var/log/dcv/server.log

# DCV Conf file
# cat /etc/dcv/dcv.conf

# create a session
# sudo dcv create-session --owner $user session1    # issue: --type=console 
echo You should be non-root to test DCV session creation and be able to login as that user 
dcv create-session --type=virtual test1
# list sessions
dcv list-sessions
# for details
# dcv list-sessions -j
# get details of session
dcv describe-session test1 
# close session
# dcv close-session {session_id}
# in case the session is not created you might want to unset the variable XDG_RUNTIME_DIR
# or create the directory $XDG_RUNTIME_DIR (e.g. /run/user/1000)

# show DCV Server log in case to see the newly created session 
# tail /var/log/dcv/server.log

# open port in security group in case on AWS
[ "$aws_cfg" != "NO" ] && echo "Don\'t forget to open the port on the security group in case running in the cloud"

# open port on firewall
## >>>>> add inbound port rule in security group to allow 8443 inbound in case on AWS 
# show firewall settings
sudo iptables-save
sudo firewall-cmd --zone=public --add-port=8443/tcp --permanent
# sudo firewall-cmd --zone=public --add-port=8443/udp --permanent # in case of QUIC
# sudo firewall-cmd --zone=public --add-port=443/tcp --permanent
sudo firewall-cmd --reload
sudo firewall-cmd --list-all
sudo iptables-save | grep 8443

# installed CA for the https connection
# generate certificate
# cd /etc/dcv/
# sudo openssl req -x509 -newkey rsa:4096 -keyout key.pem -out cert.pem -days 365

# Add CA in the [security] section in dcv.conf near # auth-token-verifier="http://127.0.0.1:8444" at the end of the file
# sudo echo 'ca-file="/etc/dcv/cert.pem"  ' >> /etc/dcv/dcv.conf

# get Public IP on AWS
# curl http://169.254.169.254/latest/meta-data/public-ipv4

# in case you get a package manager update popup: 
# sudo echo X-GNOME-Autostart-enabled=false >> /etc/xdg/autostart/gnome-software-service.desktop

# connect to your DCV session
echo Point your browser to https://YOUR_IP_ADDRESS:8443 and login with the user and password you have been using to create the test1 session earlier
echo 
echo With EnginFrame Views session management you just click on a link in the portal and get the DCV session automatically including single-sign on.
echo 
echo After login you can start a terminal via Applications, Terminal and run your applications

############################################################
# Install other dependancies required for RG

sudo yum install python3-pip -y
sudo pip3 install supervisor crudini

#install aws cli
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install

sudo - root -c "pip3 install awscli --upgrade --user"
sudo - ec2-user -c "pip3 install awscli --upgrade --user"
sudo pip3 install  https://s3.amazonaws.com/cloudformation-examples/aws-cfn-bootstrap-py3-latest.tar.gz

#install docker 
sudo yum install -y yum-utils
sudo yum-config-manager --add-repo https://download.docker.com/linux/rhel/docker-ce.repo
sudo yum install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin -y
sudo systemctl enable docker
sudo systemctl start docker

sudo docker pull relevancelab/nice-dcv-auth-svc:latest
