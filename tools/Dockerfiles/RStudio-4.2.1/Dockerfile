FROM rocker/r-ver:4.2.1

LABEL org.opencontainers.image.licenses="GPL-2.0-or-later" \
      org.opencontainers.image.source="https://github.com/rocker-org/rocker-versioned2" \
      org.opencontainers.image.vendor="Rocker Project" \
      org.opencontainers.image.authors="Carl Boettiger <cboettig@ropensci.org>"

RUN apt-get update -qq && apt-get -y --no-install-recommends install \
    libxml2-dev 
RUN R -e "install.packages(c('tidyverse', 'ggrepel', 'devtools', 'kableExtra', 'survminer', 'quantreg', 'DescTools', 'optparse'), \
    version = c('1.3.1', '0.9.0', '2.4.3', '1.3.4', '0.4.9', '2.0.1', '0.11.1', '1.9.3'))" 

ENV S6_VERSION=v2.1.0.2
ENV RSTUDIO_VERSION=2022.07.2+576
ENV DEFAULT_USER=ec2-user 
ENV PANDOC_VERSION=default
ENV QUARTO_VERSION=default

RUN /rocker_scripts/install_rstudio.sh
RUN /rocker_scripts/install_pandoc.sh
RUN /rocker_scripts/install_quarto.sh

RUN rm -rf /var/cache/R/*

EXPOSE 8787

CMD ["/init"]