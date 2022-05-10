FROM cloudron/base:3.2.0@sha256:ba1d566164a67c266782545ea9809dc611c4152e27686fd14060332dd88263ea

RUN mkdir -p /app/code /app/data /app/data/modules /app/data/config /app/data/assets /app/data/runtime /app/data/uploads /app/data/tmp/config /app/data/img
WORKDIR /app/code

ENV VERSION=1.11.1

# keep the prefork linking below a2enmod since it removes dangling mods-enabled (!)
# perl kills setlocale() in php - https://bugs.mageia.org/show_bug.cgi?id=25411
RUN a2disconf other-vhosts-access-log && \
    echo "Listen 80" > /etc/apache2/ports.conf && \
    a2enmod rewrite headers rewrite expires cache php7.4 && \
    a2dismod perl && \
    rm /etc/apache2/sites-enabled/* && \
    sed -e 's,^ErrorLog.*,ErrorLog "|/bin/cat",' -i /etc/apache2/apache2.conf && \
    ln -sf /app/data/apache/mpm_prefork.conf /etc/apache2/mods-enabled/mpm_prefork.conf && \
    ln -sf /app/data/apache/app.conf /etc/apache2/sites-enabled/app.conf

COPY apache/ /app/code/apache/

# configure mod_php
RUN crudini --set /etc/php/7.4/apache2/php.ini PHP upload_max_filesize 64M && \
    crudini --set /etc/php/7.4/apache2/php.ini PHP post_max_size 64M && \
    crudini --set /etc/php/7.4/apache2/php.ini PHP memory_limit 128M && \
    crudini --set /etc/php/7.4/apache2/php.ini Session session.save_path /run/app/sessions && \
    crudini --set /etc/php/7.4/apache2/php.ini Session session.gc_probability 1 && \
    crudini --set /etc/php/7.4/apache2/php.ini Session session.gc_divisor 100

RUN cp /etc/php/7.4/apache2/php.ini /etc/php/7.4/cli/php.ini


RUN ln -s /app/data/php.ini /etc/php/7.4/apache2/conf.d/99-cloudron.ini && \
    ln -s /app/data/php.ini /etc/php/7.4/cli/conf.d/99-cloudron.ini

# install RPAF module to override HTTPS, SERVER_PORT, HTTP_HOST based on reverse proxy headers
# https://www.digitalocean.com/community/tutorials/how-to-configure-nginx-as-a-web-server-and-reverse-proxy-for-apache-on-one-ubuntu-16-04-server
RUN mkdir /app/code/rpaf && \
    curl -L https://github.com/gnif/mod_rpaf/tarball/669c3d2ba72228134ae5832c8cf908d11ecdd770 | tar -C /app/code/rpaf -xz --strip-components 1 -f -  && \
    cd /app/code/rpaf && \
    make && \
    make install && \
    rm -rf /app/code/rpaf

# configure rpaf
RUN echo "LoadModule rpaf_module /usr/lib/apache2/modules/mod_rpaf.so" > /etc/apache2/mods-available/rpaf.load && a2enmod rpaf

# ioncube. the extension dir comes from php -i | grep extension_dir
# extension has to appear first, otherwise will error with "The Loader must appear as the first entry in the php.ini file"
RUN mkdir /tmp/ioncube && \
    curl http://downloads.ioncube.com/loader_downloads/ioncube_loaders_lin_x86-64.tar.gz | tar zxvf - -C /tmp/ioncube && \
    cp /tmp/ioncube/ioncube/ioncube_loader_lin_7.4.so /usr/lib/php/20190902/ && \
    rm -rf /tmp/ioncube && \
    echo "zend_extension=/usr/lib/php/20190902/ioncube_loader_lin_7.4.so" > /etc/php/7.4/apache2/conf.d/00-ioncube.ini && \
    echo "zend_extension=/usr/lib/php/20190902/ioncube_loader_lin_7.4.so" > /etc/php/7.4/cli/conf.d/00-ioncube.ini

# configure supervisor
ADD supervisor/ /etc/supervisor/conf.d/
RUN sed -e 's,^logfile=.*$,logfile=/run/supervisord.log,' -i /etc/supervisor/supervisord.conf

RUN npm install -g grunt-cli less

RUN curl -L https://github.com/transitionnetwork/humhub/archive/refs/heads/transition-network.tar.gz | tar zx --strip-components 1 -C /app/code
RUN rm /app/code/index-test.php
RUN mv /app/code/.htaccess.dist /app/code/.htaccess
ENV DEBUG_TEXT="YII_DEBUG"
ENV ENV_TEXT="YII_ENV"
RUN sed -i "/$DEBUG_TEXT/d" ./index.php
RUN sed -i "/$ENV_TEXT/d" ./index.php
RUN npm install
RUN composer install
RUN grunt build-assets
RUN grunt build-theme

RUN rm /app/code/protected/config/common.php
COPY config.example /app/code/protected/config/common.php

RUN rm -rf /app/code/protected/modules && ln -s /app/data/modules /app/code/protected/modules
RUN cp -r /app/code/protected/config/* /app/data/tmp/config && rm -rf /app/code/protected/config && ln -s /app/data/config /app/code/protected/config
RUN rm -rf /app/code/assets && ln -s /app/data/assets /app/code/assets
RUN rm -rf /app/code/uploads && ln -sf /app/data/uploads /app/code/uploads
RUN rm -rf /app/code/protected/runtime && ln -s /app/data/runtime /app/code/protected/runtime
RUN cp -r /app/code/static/img/* /app/data/img && rm -rf /app/code/static/img && ln -s /app/data/img /app/code/static/img

# add code
COPY start.sh /app/code/
COPY db_update.sh /app/code/

RUN chown -R www-data:www-data /app/code

# lock www-data but allow su - www-data to work
RUN passwd -l www-data && usermod --shell /bin/bash --home /app/data www-data
RUN chmod +x /app/code/start.sh
RUN chmod +x /app/code/db_update.sh

CMD [ "/app/code/start.sh" ]
