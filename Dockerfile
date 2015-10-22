FROM ubuntu

RUN apt-get update
RUN apt-get install -y ca-certificates \
                       Libreadline-dev \
                       libncurses5-dev \
                       libpcre3-dev \
                       libssl-dev \
                       wget \
                       dnsutils \
                       perl \
                       make \
                       build-essential && \
    rm -rf /var/lib/apt/lists/*

# install nginx+openresty
RUN cd /tmp && \
    wget https://openresty.org/download/ngx_openresty-1.9.3.1.tar.gz && \
    tar xzvf ngx_openresty-*.tar.gz && \
    cd ngx_openresty-* && \
    ./configure && \
    make && \
    make install && \
    rm -rf ngx_openresty-*

RUN apt-get clean
RUN apt-get purge

# forward request and error logs to docker log collector
RUN ln -sf /dev/stdout /usr/local/openresty/nginx/logs/access.log && \
    ln -sf /dev/stderr /usr/local/openresty/nginx/logs/error.log

ADD nginx.conf                /usr/local/openresty/nginx/conf/
ADD wrapper.sh site.template  /home/weave/

VOLUME ["/var/cache/nginx"]

ENTRYPOINT ["/home/weave/wrapper.sh"]

