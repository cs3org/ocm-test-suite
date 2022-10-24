FROM apache-php
RUN rm -rf /var/www/html
USER www-data
RUN git clone --depth=1 https://github.com/owncloud/core.git --recursive --shallow-submodules
WORKDIR /var/www/core
USER root
RUN apt update && apt install -y composer curl dirmngr apt-transport-https lsb-release ca-certificates
RUN curl -sL https://deb.nodesource.com/setup_18.x | bash -
RUN apt install nodejs
RUN npm install -g yarn
USER www-data
WORKDIR /var/www
RUN mv core html
WORKDIR /var/www/html
RUN composer install
RUN make install-nodejs-deps
ENV PHP_MEMORY_LIMIT="512M"
ADD init.sh /init.sh
USER root
