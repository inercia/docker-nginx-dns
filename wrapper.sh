#!/bin/bash


CURR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

NAME="docker-nginx-dns"
NGINX=/usr/local/openresty/nginx/sbin/nginx

# the service template and wehere it will be written to
NGINX_SERVICE_TEMPLATE=${NGINX_SERVICE_TEMPLATE:-$CURR_DIR/service.template}
NGINX_SERVICES_DIR=${NGINX_SERVICES_DIR:-/usr/local/openresty/nginx/conf/sites-enabled}

# where our Lua scripts are
LUA_LIBRARY=${LUA_LIBRARY:-$CURR_DIR/lua}

#########################################

usage() {
    cat <<-EOF
    
Usage:

    $NAME <service> [<service> ...]

where <service> = <EXT_PORT>:<NAME>:<INT_PORT>

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

NAMESERVER=$(curr_nameserver)
log "Using nameserver: $NAMESERVER"

[ -d $NGINX_SERVICES_DIR ] || mkdir -p $NGINX_SERVICES_DIR

while [ $# -gt 0 ]; do
    MAPPING=$1
    [ -n "$MAPPING" ] || usage_fatal "no mapping provided"

    EXT_PORT=$(echo $MAPPING | cut -d':' -f1)
    NAME=$(echo $MAPPING | cut -d':' -f2)
    INT_PORT=$(echo $MAPPING | cut -d':' -f3)

    [ -n "$EXT_PORT" ]   || usage_fatal "no external port provided in mapping"
    [ -n "$NAME"     ]   || usage_fatal "no name provided in mapping"
    [ -n "$INT_PORT" ]   || usage_fatal "no internal port provided in mapping"
    [ -n "$NAMESERVER" ] || usage_fatal "no nameserver could be obtained in mapping"

    SERVICE_FILE=$NGINX_SERVICES_DIR/$NAME-$EXT_PORT-$INT_PORT

    log "Adding service $EXT_PORT -> $NAME:$INT_PORT"
    cat $NGINX_SERVICE_TEMPLATE | \
        replace "NAME"        "$NAME"        | \
        replace "EXT_PORT"    "$EXT_PORT"    | \
        replace "INT_PORT"    "$INT_PORT"    | \
        replace "NAMESERVER"  "$NAMESERVER"  | \
        replace "LUA_LIBRARY" "$LUA_LIBRARY" > $SERVICE_FILE \
            || fatal "could not write file"

    shift
done

log "Starting nginx (nameserver: $NAMESERVER)"
$NGINX -g 'daemon off;'
