FROM debian:jessie

MAINTAINER Greg Werner <werner.greg@gmail.com>

# Install wget and install/updates certificates
RUN apt-get update \
 && apt-get install -y -q --no-install-recommends \
    ca-certificates \
    curl \
    build-essential \
    git \
    libncurses5-dev \
    libpcre3-dev \
    libreadline-dev \
    libssl-dev \
    locate \
    luajit-5.1-dev \
    make \
    nano \
    openssl \
    perl \
    procps \
    ruby-full \
    wget \
 && apt-get clean \
 && rm -r /var/lib/apt/lists/*

ENV OPENRESTY_VERSION 1.9.7.3
ENV OPENRESTY_PREFIX /opt/openresty
ENV NGINX_PREFIX /opt/openresty/nginx
ENV VAR_PREFIX /var/nginx
ENV NGINX_DEFAULT_CONF $NGINX_PREFIX/conf.d/default.conf

RUN cd /root \
 && echo "==> Downloading OpenResty..." \
 && curl -sSL http://openresty.org/download/openresty-${OPENRESTY_VERSION}.tar.gz | tar -xvz \
 && echo "==> Configuring OpenResty..." \
 && cd openresty-* \
 && readonly NPROC=$(grep -c ^processor /proc/cpuinfo 2>/dev/null || 1) \
 && echo "using upto $NPROC threads" \
 && ./configure \
    --prefix=$OPENRESTY_PREFIX \
    --conf-path=$NGINX_DEFAULT_CONF \
    --http-client-body-temp-path=$VAR_PREFIX/client_body_temp \
    --http-proxy-temp-path=$VAR_PREFIX/proxy_temp \
    --http-log-path=$VAR_PREFIX/access.log \
    --error-log-path=$VAR_PREFIX/error.log \
    --pid-path=$VAR_PREFIX/nginx.pid \
    --lock-path=$VAR_PREFIX/nginx.lock \
    --with-luajit \
    --with-pcre-jit \
    --with-ipv6 \
    --with-http_ssl_module \
    --without-http_ssi_module \
    --without-http_userid_module \
    --without-http_uwsgi_module \
    --without-http_scgi_module \
    -j${NPROC} \
 && echo "==> Building OpenResty..." \
 && make -j${NPROC} \
 && echo "==> Installing OpenResty..." \
 && make install \
 && echo "==> Finishing..." \
 && ln -sf $NGINX_PREFIX/sbin/nginx /usr/local/bin/nginx \
 && ln -sf $NGINX_PREFIX/sbin/nginx /usr/local/bin/openresty \
 && ln -sf $OPENRESTY_PREFIX/bin/resty /usr/local/bin/resty \
 && ln -sf $OPENRESTY_PREFIX/luajit/bin/luajit-* $OPENRESTY_PREFIX/luajit/bin/lua \
 && ln -sf $OPENRESTY_PREFIX/luajit/bin/luajit-* /usr/local/bin/lua \
 && rm -rf /root/ngx_openresty*

# Install Forego
RUN wget -P /usr/local/bin https://godist.herokuapp.com/projects/ddollar/forego/releases/current/linux-amd64/forego \
 && chmod u+x /usr/local/bin/forego

# Install App dependancies
RUN gem install faye-websocket --no-ri --no-rdoc && gem install tutum --no-ri --no-rdoc

COPY . /app/
WORKDIR /app/

# After OpenResty install, make sure nginx is available in PATH
ENV PATH $NGINX_PREFIX/sbin:$PATH

# Generate Default Self-signed certificate

ENV C US
ENV ST GA
ENV L Atlanta
ENV OU RandD
ENV O MyCompany
ENV CN www.mydomain.com

RUN openssl genrsa -des3 -passout pass:x -out default.pass.key 2048 \
 && openssl rsa -passin pass:x -in default.pass.key -out default.key \
 && rm default.pass.key \
 && openssl req -new -key default.key -out default.csr -subj "/C=$C/ST=$ST/L=$L/O=$O/OU=$OU/CN=$CN" \
 && openssl x509 -req -days 365 -in default.csr -signkey default.key -out default.crt \
 && mkdir -p $NGINX_PREFIX/certs/ \
 && mv default.crt $NGINX_PREFIX/certs/default.crt && mv default.key $NGINX_PREFIX/certs/default.key
 # Then, just use the generated default.key and default.crt files.

# nginx user without /home
RUN useradd --no-create-home nginx

RUN chown -R nginx $NGINX_PREFIX

CMD ["forego", "start", "-r"]
