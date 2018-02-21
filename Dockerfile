FROM nginx:1.13
MAINTAINER Richard Adams richard@madwire.co.uk

ENV NGINX_DEFAULT_CONF=/etc/nginx/conf.d/default.conf
ENV NGINX_DEFAULT_SSL_CRT=/etc/nginx/certs/default.crt
ENV NGINX_DEFAULT_SSL_KEY=/etc/nginx/certs/default.key

# Install wget and install/updates certificates
RUN apt-get update \
  && apt-get install -y -q --no-install-recommends \
    ca-certificates \
    wget \
    build-essential \
    openssl \
    libssl-dev \
    ruby-full \
  && apt-get clean \
  && rm -r /var/lib/apt/lists/*

# Configure Nginx and apply fix for very long server names
RUN echo "daemon off;" >> /etc/nginx/nginx.conf \
  && sed -i 's/^http {/&\n    server_names_hash_bucket_size 128;/g' /etc/nginx/nginx.conf

# Install Forego
RUN wget -P /usr/local/bin https://github.com/jwilder/forego/releases/download/v0.16.1/forego \
 && chmod u+x /usr/local/bin/forego

# Install App dependancies
RUN gem install faye-websocket --no-ri --no-rdoc && gem install tutum --no-ri --no-rdoc

COPY . /app/
WORKDIR /app/

# Generate Default Self-signed certificate
RUN openssl genrsa -des3 -passout pass:x -out default.pass.key 2048 \
  && openssl rsa -passin pass:x -in default.pass.key -out default.key \
  && rm default.pass.key \
  && openssl req -new -key default.key -out default.csr -subj "/C=UK/ST=State/L=local/O=OrgName/OU=Web/CN=example.com" \
  && openssl x509 -req -days 365 -in default.csr -signkey default.key -out default.crt \
  && mkdir -p /etc/nginx/certs/ \
  && mv default.crt /etc/nginx/certs/default.crt && mv default.key /etc/nginx/certs/default.key
  # Then, just use the generated default.key and default.crt files.

CMD ["forego", "start", "-r"]
