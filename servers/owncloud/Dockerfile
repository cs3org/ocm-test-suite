FROM apache-php
RUN rm -rf /var/www/html
USER www-data
RUN git clone --depth=1 https://github.com/owncloud/core.git --recursive --shallow-submodules
WORKDIR /var/www/core
USER root
RUN apt update && apt install -y composer curl dirmngr apt-transport-https lsb-release ca-certificates iproute2
RUN curl -sL https://deb.nodesource.com/setup_18.x | bash -
RUN apt install nodejs
RUN npm install -g yarn
USER www-data
WORKDIR /var/www
RUN mv core html
WORKDIR /var/www/html
RUN composer install --no-dev
RUN make install-nodejs-deps
ENV PHP_MEMORY_LIMIT="512M"
ADD init.sh /init.sh
RUN mkdir -p data ; touch data/owncloud.log
USER root
CMD /usr/sbin/apache2ctl -DFOREGROUND & tail -f /var/log/apache2/error.log & tail -f data/owncloud.log