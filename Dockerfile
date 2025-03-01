FROM php:8.0-fpm as BASE_PHP
ENV V8_VERSION=9.9.115.7

RUN apt-get update -y --fix-missing && apt-get upgrade -y;

# Install v8js (see https://github.com/phpv8/v8js/blob/php7/README.Linux.md)
RUN apt-get install -y --no-install-recommends \
    libtinfo5 libtinfo-dev \
    build-essential \
    curl \
    git \
    libglib2.0-dev \
    libxml2 \
    python \
    patchelf \
    && cd /tmp \
    \
    && git clone https://chromium.googlesource.com/chromium/tools/depot_tools.git --progress --verbose \
    && export PATH="$PATH:/tmp/depot_tools" \
    \
    && fetch v8 \
    && cd v8 \
    && git checkout $V8_VERSION \
    && gclient sync \
    \
    && tools/dev/v8gen.py -vv x64.release -- is_component_build=true use_custom_libcxx=false

RUN export PATH="$PATH:/tmp/depot_tools" \
    && cd /tmp/v8 \
    && ninja -C out.gn/x64.release/ \
    && mkdir -p /opt/v8/lib && mkdir -p /opt/v8/include \
    && cp out.gn/x64.release/lib*.so out.gn/x64.release/*_blob.bin out.gn/x64.release/icudtl.dat /opt/v8/lib/ \
    && cp -R include/* /opt/v8/include/ \
    && apt-get install patchelf \
    && for A in /opt/v8/lib/*.so; do patchelf --set-rpath '$ORIGIN' $A;done

# Install php-v8js
RUN cd /tmp \
    && git clone https://github.com/phpv8/v8js.git \
    && cd v8js \
    && git checkout php8 && git pull \
    && phpize \
    && ./configure --with-v8js=/opt/v8 LDFLAGS="-lstdc++" CPPFLAGS="-DV8_COMPRESS_POINTERS" \
    && make \
    && make test \
    && make install

RUN docker-php-ext-enable v8js

RUN ls -la /usr/local/etc/php/conf.d/ \
    && ls -la /usr/local/lib/php/extensions/no-debug-non-zts-20200930

FROM php:8.0-fpm

ARG VCS_REF
ARG BUILD_DATE
LABEL  org.label-schema.build-date=$BUILD_DATE \
    org.label-schema.name="PHP 8.0-FPM with V8JS" \
    org.label-schema.vcs-ref=$VCS_REF \
    org.label-schema.vcs-url="https://github.com/aozisik/docker-v8js-php"

COPY --from=BASE_PHP /opt /opt
COPY --from=BASE_PHP /usr/local/etc/php/conf.d/docker-php-ext-v8js.ini /usr/local/etc/php/conf.d/
COPY --from=BASE_PHP /usr/local/lib/php/extensions/no-debug-non-zts-20200930 /usr/local/lib/php/extensions/no-debug-non-zts-20200930
RUN apt-get update && apt-get install -y \
    libfreetype6-dev \
    libjpeg62-turbo-dev \
    libpng-dev

RUN docker-php-ext-configure gd --with-freetype --with-jpeg \
    && docker-php-ext-install -j$(nproc) gd \
    && docker-php-ext-install pdo_mysql exif pcntl bcmath gd