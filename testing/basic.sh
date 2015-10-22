#!/usr/bin/env bash

# simple testing scenario with the help of docker-machine
# - creates 2 VMs with
#    - docker, Weave and Discovery
# - creates a token
# - both VMs join the same token
# - and we show the Weave logs (if "--check")

[ -n "$WEAVE_DEBUG" ] && set -x

CHECK=
STOP=
NGINX_MACHINES="gateway"
WEBSERVER_MACHINES="host1 host2"
ALL_MACHINES="$NGINX_MACHINES $WEBSERVER_MACHINES"
ALL_MACHINE_COUNT=$(echo $ALL_MACHINES | wc -w)

DISCO_SCRIPT_URL=https://raw.githubusercontent.com/weaveworks/discovery/master/discovery

NGINX_IMAGE="weaveworks/weave-nginx"
NGINX_IMAGE_FILES="../weave_nginx.tar"
REMOTE_ROOT=/home/docker
WEAVE=$REMOTE_ROOT/weave
WEAVER_PORT=6783
TOKEN=

log() { echo ">>> $1" >&2 ; }

############################
# main
############################

while [ $# -gt 0 ] ; do
    case "$1" in
        -check|--check)
            CHECK=1
            ;;
        --token)
            TOKEN="$2"
            shift
            ;;
        --token=*)
            TOKEN="${1#*=}"
            ;;
        --stop)
            STOP=1
            ;;
        *)
            break
            ;;
    esac
    shift
done

# Get a token
[ -z "$TOKEN" ] && TOKEN=$(curl --silent -X POST https://discovery-stage.hub.docker.com/v1/clusters)

# Create two machines
for machine in $ALL_MACHINES ; do
    docker-machine status $machine >/dev/null 2>&1
    if [ $? -ne 0 ] ; then
        log "Creating VirtualBox $machine..."
        docker-machine create --driver virtualbox $machine
    fi
done

log "Building..."
make -C ..

log "Uploading $NGINX_IMAGE image"
for machine in $NGINX_MACHINES ; do
    for file in $NGINX_IMAGE_FILES ; do
        log "... uploading to $machine"
        docker-machine scp $file $machine:$REMOTE_ROOT/ >/dev/null
    done
done

for machine in $ALL_MACHINES ; do
    advertise=$(docker-machine ip $machine):$WEAVER_PORT

    SCRIPT=$(tempfile)
    cat <<EOF > $SCRIPT
#!/bin/sh

echo ">>> Installing and launching Weave"
[ -x $WEAVE ] && $WEAVE stop  >/dev/null 2>&1 || /bin/true
cd $REMOTE_ROOT                         && \
    rm -f $WEAVE                        && \
    sudo curl -L git.io/weave -o $WEAVE && \
    sudo chmod a+x $WEAVE               && \
    $WEAVE launch --init-peer-count $ALL_MACHINE_COUNT

    sleep 2
    
echo ">>> Installing and launching Discovery (advertising $advertise)"
[ -f $REMOTE_ROOT/discovery ] && docker stop weavediscovery  >/dev/null 2>&1 || /bin/true
cd $REMOTE_ROOT                              && \
    curl --silent -L -O $DISCO_SCRIPT_URL    && \
    chmod a+x $REMOTE_ROOT/discovery         && \
    $REMOTE_ROOT/discovery join --advertise=$advertise token://$TOKEN

EOF

    echo "$WEBSERVER_MACHINES" | grep -q $machine 
    if [ $? -eq 0 ] ; then 
        cat <<EOF >> $SCRIPT
        docker inspect webserver >/dev/null 2>&1 && docker stop webserver && docker rm webserver
        $WEAVE run -p 8080:8080 -ti --name webserver adejonge/helloworld
EOF
    else
        cat <<EOF >> $SCRIPT
        docker inspect nginx >/dev/null 2>&1 && docker stop nginx && docker rm nginx
        docker load -i $REMOTE_ROOT/weave_nginx.tar
        $WEAVE run -p 80:80 --name nginx $NGINX_IMAGE 80:webserver:8080
EOF
    fi
    
    log "Preparing provisioning for $machine..."
    docker-machine scp $SCRIPT $machine:$REMOTE_ROOT/provision.sh >/dev/null
    rm -f $SCRIPT
done

for machine in $ALL_MACHINES ; do
    log "Provisioning $machine..."
    docker-machine ssh $machine sh $REMOTE_ROOT/provision.sh &
done
