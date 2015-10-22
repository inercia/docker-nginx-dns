#!/bin/bash


CURR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

NAME="weave-reverse-proxy"
NGINX=/usr/local/openresty/nginx/sbin/nginx

# the service template and wehere it will be written to
NGINX_SITE_TEMPLATE=${NGINX_SITE_TEMPLATE:-$CURR_DIR/site.template}
NGINX_SITES_DIR=${NGINX_SITES_DIR:-/usr/local/openresty/nginx/conf/sites-enabled}

# where our Lua scripts are
LUA_LIBRARY=${LUA_LIBRARY:-$CURR_DIR/lua}

#########################################

usage() {
    cat <<-EOF
    
Usage:

    $NAME EXT_PORT:NAME:INT_PORT    

EOF
}

log()             { echo "$1" >&2 ;            }
fatal()           { log "FATAL: $1" ; exit 1 ; }
usage_fatal()     { log "ERROR: $1" ; usage  ; exit 1 ; }
replace()         { sed -e "s|@@$1@@|$2|g" ; }
curr_nameserver() { cat "/etc/resolv.conf" | grep "nameserver" | head -1 | cut -d' ' -f2 ; }

#########################################
# main
#########################################

MAPPING=$1
[ -n "$MAPPING" ] || usage_fatal "no mapping provided"

EXT_PORT=$(echo $MAPPING | cut -d':' -f1)
NAME=$(echo $MAPPING | cut -d':' -f2)
INT_PORT=$(echo $MAPPING | cut -d':' -f3)
NAMESERVER=$(curr_nameserver)

[ -n "$EXT_PORT" ]   || usage_fatal "no external port provided"
[ -n "$NAME"     ]   || usage_fatal "no name provided"
[ -n "$INT_PORT" ]   || usage_fatal "no internal port provided"
[ -n "$NAMESERVER" ] || usage_fatal "no nameserver could be obtained"

[ -d $NGINX_SITES_DIR ] || mkdir -p $NGINX_SITES_DIR

log "Creating load balancer for '$NAME'"
cat $NGINX_SITE_TEMPLATE | \
    replace "NAME"        "$NAME"        | \
    replace "EXT_PORT"    "$EXT_PORT"    | \
    replace "INT_PORT"    "$INT_PORT"    | \
    replace "NAMESERVER"  "$NAMESERVER"  | \
    replace "LUA_LIBRARY" "$LUA_LIBRARY" > $NGINX_SITES_DIR/$NAME \
       || fatal "could not write file"

log "Starting nginx:$EXT_PORT -> $NAME:$INT_PORT"
$NGINX -g 'daemon off;'


