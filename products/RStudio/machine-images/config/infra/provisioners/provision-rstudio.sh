#!/usr/bin/env bash
# exec > >(tee /var/log/provision-rstudio.log|logger -t provision-rst -s 2>/dev/console) 2>&1
# Various development packages needed to compile R
sudo yum update -y
sudo yum install -y gcc gcc-gfortran gcc-c++
sudo yum install -y java-1.8.0-openjdk-devel-1.8.0
#sudo yum install -y readline-devel-6.2 zlib-devel-1.2.* bzip2-devel-1.0.* xz-devel-5.2.* pcre-devel-8.32
sudo yum install -y libcurl-devel libpng-devel cairo-devel pango-devel
sudo yum install -y xorg-x11-server-devel libX11-devel libXt-devel

sudo yum groupinstall -y "Development Tools"
sudo yum install -y readline-devel
sudo yum install -y libX11-devel
sudo yum install -y libX11-devel libXt-devel
sudo yum install -y bzip2-devel
sudo yum install -y pcre2-devel
sudo yum install -y xz xz-devel
#yum install libjpeg-turbo-devel


#add sleep for 10 second to install R
sleep 10
# Install R from source (https://docs.rstudio.com/resources/install-r-source/)
R_VERSION="4.3.2"
mkdir -p "/tmp/R/"
curl -s "https://cran.r-project.org/src/base/R-4/R-${R_VERSION}.tar.gz" > "/tmp/R/R-${R_VERSION}.tar.gz"
cd "/tmp/R/"
tar xvf "R-${R_VERSION}.tar.gz"
cd "R-${R_VERSION}/"
./configure --enable-memory-profiling --enable-R-shlib --with-blas --with-lapack --with-pcre1
sudo make
sudo make install
cd "../../.."

# Install RStudio
mkdir -p "/tmp/rstudio"
rstudio_rpm="rstudio-server-rhel-2023.09.0-463-x86_64.rpm"
curl -s "https://download2.rstudio.org/server/centos7/x86_64/${rstudio_rpm}" > "/tmp/rstudio/${rstudio_rpm}"
sudo yum install -y "/tmp/rstudio/${rstudio_rpm}"
sudo systemctl enable rstudio-server
sudo systemctl start rstudio-server
sudo systemctl status rstudio-server


#Generate self signed certificate
commonname=$(uname -n)
password=dummypassword
mkdir -p "/tmp/rstudio/ssl"
chmod 700 /tmp/rstudio/ssl
cd /tmp/rstudio/ssl
openssl genrsa -des3 -passout pass:$password -out cert.key 2048
#Remove passphrase from the key. Comment the line out to keep the passphrase
openssl rsa -in cert.key -passin pass:$password -out cert.key
openssl req -new -key cert.key -out cert.csr -passin pass:$password \
    -subj "/C=NA/ST=NA/L=NA/O=NA/OU=RG/CN=$commonname/emailAddress=example.com"
openssl x509 -req -days 365 -in cert.csr -signkey cert.key -out cert.pem
cd "../../.."

# Install and configure nginx
sudo amazon-linux-extras install -y nginx1
sudo openssl dhparam -out "/etc/nginx/dhparam.pem" 2048
sudo mv "/tmp/rstudio/ssl/cert.pem" "/etc/nginx/"
sudo mv "/tmp/rstudio/ssl/cert.key" "/etc/nginx/"
sudo mv "/tmp/rstudio/nginx.conf" "/etc/nginx/"
sudo chown -R nginx:nginx "/etc/nginx"
sudo chmod -R 600 "/etc/nginx"
sudo systemctl enable nginx
sudo systemctl restart nginx


# Install system packages necessary for installing R packages through RStudio CRAN [devtools, tidyverse]
sudo yum install -y git-2.23.* openssl-devel-1.0.* libxml2-devel-2.9.*
libgit2_rpm="libgit2-0.26.6-1.el7.x86_64.rpm"
libgit2_devel_rpm="libgit2-devel-0.26.6-1.el7.x86_64.rpm"
mkdir -p "/tmp/libgit2/"
curl -s "http://mirror.centos.org/centos/7/extras/x86_64/Packages/${libgit2_rpm}" > "/tmp/libgit2/${libgit2_rpm}"
sudo yum install -y "/tmp/libgit2/${libgit2_rpm}"
curl -s "http://mirror.centos.org/centos/7/extras/x86_64/Packages/${libgit2_devel_rpm}" > "/tmp/libgit2/${libgit2_devel_rpm}"
sudo yum install -y "/tmp/libgit2/${libgit2_devel_rpm}"


# Other recommended system packages for installing R packages (https://docs.rstudio.com/rsc/post-setup-tool/)
sudo yum groupinstall -y 'Development Tools'            # Compiling tools 
sudo yum install -y libssh2-devel-1.4.*                       # Client SSH

sudo yum install -y libjpeg-turbo-devel-1.2.*    # Images
sudo yum install -y ImageMagick-6.9.* ImageMagick-c++-devel-6.9.*   # Images
sudo yum install -y mesa-libGLU-devel-9.0.*            # Graphs
sudo yum install freetype-devel-2.8 harfbuzz-devel-1.7.*          # Font

sudo yum install -y mariadb-devel-5.5.*                       # MariaDB/MySQL client & server packages
sudo yum install -y unixODBC-devel-2.3.*                      # ODBC API client
sudo yum install -y gmp-devel-6.0.*                           # GNU MP arbitrary precision library

#Additional R Packages
sudo su - -c "R -e \"install.packages('tidyverse', version='2.0.0', repos='http://cran.rstudio.com/')\""
sudo su - -c "R -e \"install.packages('devtools', version='2.4.5', repos='http://cran.rstudio.com/')\""
sudo su - -c "R -e \"install.packages('kableExtra', version='1.3.4', repos='http://cran.rstudio.com/')\""
sudo su - -c "R -e \"install.packages('survival', version='3.5-7', repos='http://cran.rstudio.com/')\""
# sudo su - -c "R -e \"install.packages('survminer', version='0.4.9', repos='http://cran.rstudio.com/')\""
sudo su - -c "R -e \"install.packages('MASS', version='7.3.53.1', repos='http://cran.rstudio.com/')\""
sudo su - -c "R -e \"install.packages('quantreg', version='5.85', repos='http://cran.rstudio.com/')\""
# sudo su - -c "R -e \"install.packages('DescTools', version='0.99.41', repos='http://cran.rstudio.com/')\""

# Install script that checks idle time and shuts down if max idle is reached
sudo mv "/tmp/rstudio/check-idle" "/usr/local/bin/"
sudo chown root: "/usr/local/bin/check-idle"
sudo chmod 775 "/usr/local/bin/check-idle"
sudo crontab -l 2>/dev/null > "/tmp/crontab"
echo '*/2 * * * * /usr/local/bin/check-idle 2>&1 >> /var/log/check-idle.log' >> "/tmp/crontab"
sudo crontab "/tmp/crontab"

# Wipe out all traces of provisioning files
sudo rm -rf "/tmp/rstudio"
#sudo rm -rf "/tmp/rstudiov2"
sudo rm -rf "/tmp/libgit2"
sudo rm -rf "/tmp/R"