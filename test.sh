#!/bin/bash
# Integration test for glance service
# Test runs mysql,memcached,keystone and glance container and checks whether glance is running on public and admin ports

DOCKER_PROJ_NAME=${DOCKER_PROJ_NAME:-''}
CONT_PREFIX=test

. lib/functions.sh

http_proxy_args="-e http_proxy=${http_proxy:-} -e https_proxy=${https_proxy:-} -e no_proxy=${no_proxy:-}"

cleanup() {
    echo "Clean up ..."
    docker stop ${CONT_PREFIX}_mariadb
    docker stop ${CONT_PREFIX}_memcached
    docker stop ${CONT_PREFIX}_rabbitmq
    docker stop ${CONT_PREFIX}_keystone
    docker stop ${CONT_PREFIX}_neutron-controller
    docker stop ${CONT_PREFIX}_neutron-compute

    docker rm ${CONT_PREFIX}_mariadb
    docker rm ${CONT_PREFIX}_memcached
    docker rm ${CONT_PREFIX}_rabbitmq
    docker rm ${CONT_PREFIX}_keystone
    docker rm ${CONT_PREFIX}_neutron-controller
    docker rm ${CONT_PREFIX}_neutron-compute
}

wait_for_linuxbridge() {
    local timeout=$1
    local counter=0
    echo "Wait till linuxbridge agent is registred to neutron..."
    while [[ $counter -lt $timeout ]]; do
        local counter=$[counter + 5]
        local OUT=$(docker run --net=host --rm $http_proxy_args ${DOCKER_PROJ_NAME}osadmin /bin/bash -c ". /app/adminrc; openstack network agent list --format csv | grep neutron-linuxbridge-agent | cut -d"," -f 6" | tail -n 1)
        if [[ $OUT != '"UP"' ]]; then
            echo -n ". "
        else
            break
        fi
        sleep 5
    done

    if [[ $timeout -eq $counter ]]; then
        exit 1
    fi
}

cleanup

##### Start Containers

echo "Starting mariadb container ..."
docker run  --net=host -d -e MYSQL_ROOT_PASSWORD=veryS3cr3t --name ${CONT_PREFIX}_mariadb \
       mariadb:10.1

echo "Wait till mariadb is running ."
wait_for_port 3306 120

echo "Starting Memcached node (tokens caching) ..."
docker run -d --net=host -e DEBUG= --name ${CONT_PREFIX}_memcached memcached

echo "Wait till Memcached is running ."
wait_for_port 11211 30

echo "Starting RabbitMQ container ..."
docker run -d --net=host -e DEBUG= --name ${CONT_PREFIX}_rabbitmq rabbitmq

echo "Wait till Rabbitmq is running ."
wait_for_port 5672 120

# create openstack user in rabbitmq
docker exec ${CONT_PREFIX}_rabbitmq rabbitmqctl add_user openstack veryS3cr3t
docker exec ${CONT_PREFIX}_rabbitmq rabbitmqctl set_permissions openstack '.*' '.*' '.*'

# build nova container from local sources
./build.sh

sleep 10

# create databases
create_db_osadmin keystone keystone veryS3cr3t veryS3cr3t
create_db_osadmin neutron neutron veryS3cr3t veryS3cr3t

echo "Starting keystone container"
docker run -d --net=host \
           -e DEBUG="true" \
           -e DB_SYNC="true" \
           $http_proxy_args \
           --name ${CONT_PREFIX}_keystone ${DOCKER_PROJ_NAME}keystone:latest

echo "Wait till keystone is running ."

wait_for_port 5000 120
ret=$?
if [ $ret -ne 0 ]; then
    echo "Error: Port 5000 (Keystone) not bounded!"
    exit $ret
fi

wait_for_port 35357 120
ret=$?
if [ $ret -ne 0 ]; then
    echo "Error: Port 35357 (Keystone Admin) not bounded!"
    exit $ret
fi

# bootstrap keystone data (endpoints/users/services)
set +e
docker run --net=host --rm \
           $http_proxy_args ${DOCKER_PROJ_NAME}osadmin /bin/bash -c ". /app/tokenrc; bash /app/bootstrap.sh"
ret=$?
if [ $ret -ne 0 ] && [ $ret -ne 128 ]; then
    echo "Error: Keystone bootstrap error ${ret}!"
    exit $ret
fi
set -e

echo "Configure External Networking ..."
ip a s | grep -q br-ex || { sudo brctl addbr br-ex && sudo ip link set dev br-ex up; }

echo "Starting neutron-controller container"
docker run -d --net=host --privileged \
           -e DEBUG="true" \
           -e DB_SYNC="true" \
           -e NEUTRON_CONTROLLER="true" \
           -e EXTERNAL_BRIDGE="br-ex" \
           -e EXTERNAL_IP="192.168.99.1/24" \
           $http_proxy_args \
           -v /lib/modules:/lib/modules \
           -v /run/netns:/run/netns:shared \
           --name ${CONT_PREFIX}_neutron-controller \
           ${DOCKER_PROJ_NAME}neutron:latest

wait_for_port 9696 120
ret=$?
if [ $ret -ne 0 ]; then
    echo "Logs of container ${CONT_PREFIX}_neutron-controller"
    docker logs ${CONT_PREFIX}_neutron-controller | tail -n 10
    echo "Error: Port 9696 (neutron server) not bounded!"
    exit $ret
fi

echo "Starting neutron-compute container"
docker run -d --net=host --privileged \
           -e DEBUG="true" \
           -e NEUTRON_CONTROLLER="false" \
           -e EXTERNAL_BRIDGE="br-ex" \
           $http_proxy_args \
           -v /lib/modules:/lib/modules \
           --name ${CONT_PREFIX}_neutron-compute \
           ${DOCKER_PROJ_NAME}neutron:latest


wait_for_linuxbridge 120
ret=$?
if [ $ret -ne 0 ]; then
    echo "Logs of container ${CONT_PREFIX}_neutron-compute"
    docker logs ${CONT_PREFIX}_neutron-compute | tail -n 10
    echo "Error: Linux compute container not registered to controller!"
    exit $ret
fi


echo "======== Success :) ========="

if [[ "$1" != "noclean" ]]; then
    cleanup
fi

