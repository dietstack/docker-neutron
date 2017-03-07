#!/bin/bash
# Integration test for glance service
# Test runs mysql,memcached,keystone and glance container and checks whether glance is running on public and admin ports

GIT_REPO=172.27.10.10
RELEASE_REPO=172.27.9.130
CONT_PREFIX=test

. lib/functions.sh

cleanup() {
    echo "Clean up ..."
    docker stop ${CONT_PREFIX}_galera
    docker stop ${CONT_PREFIX}_memcached
    docker stop ${CONT_PREFIX}_rabbitmq
    docker stop ${CONT_PREFIX}_keystone
    docker stop ${CONT_PREFIX}_neutron-controller
    docker stop ${CONT_PREFIX}_neutron-compute

    docker rm ${CONT_PREFIX}_galera
    docker rm ${CONT_PREFIX}_memcached
    docker rm ${CONT_PREFIX}_rabbitmq
    docker rm ${CONT_PREFIX}_keystone
    docker rm ${CONT_PREFIX}_neutron-controller
    docker rm ${CONT_PREFIX}_neutron-compute
}

wait_for_linuxbridge() {
    local timeout=$1
    local counter=0
    echo "Wait till linuxbridge afent is registred to neutron..."
    while [[ $counter -lt $timeout ]]; do
        local counter=$[counter + 5]
        local OUT=$(docker run --net=host osadmin /bin/bash -c ". /app/adminrc; openstack network agent list --format csv | grep neutron-linuxbridge-agent | cut -d"," -f 6" | tail -n 1)
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

##### Download/Build containers

# pull galera docker image
get_docker_image_from_release galera http://${RELEASE_REPO}/docker-galera latest

# pull rabbitmq docker image
get_docker_image_from_release rabbitmq http://${RELEASE_REPO}/docker-rabbitmq latest

# pull osmaster docker image
get_docker_image_from_release osmaster http://${RELEASE_REPO}/docker-osmaster latest

# pull keystone image
get_docker_image_from_release keystone http://${RELEASE_REPO}/docker-keystone latest

# pull osadmin docker image
get_docker_image_from_release osadmin http://${RELEASE_REPO}/docker-osadmin latest

##### Start Containers

echo "Starting galera container ..."
docker run -d --net=host -e INITIALIZE_CLUSTER=1 -e MYSQL_ROOT_PASS=veryS3cr3t -e WSREP_USER=wsrepuser -e WSREP_PASS=wsreppass -e DEBUG= --name ${CONT_PREFIX}_galera galera:latest

echo "Wait till galera is running ."
wait_for_port 3306 30

echo "Starting Memcached node (tokens caching) ..."
docker run -d --net=host -e DEBUG= --name ${CONT_PREFIX}_memcached memcached

echo "Starting RabbitMQ container ..."
docker run -d --net=host -e DEBUG= --name ${CONT_PREFIX}_rabbitmq rabbitmq

# build nova container from local sources
./build.sh

sleep 10

# create databases
create_db_osadmin keystone keystone veryS3cr3t veryS3cr3t
create_db_osadmin neutron neutron veryS3cr3t veryS3cr3t

echo "Starting keystone container"
docker run -d --net=host -e DEBUG="true" -e DB_SYNC="true" --name ${CONT_PREFIX}_keystone keystone:latest

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
docker run --net=host osadmin /bin/bash -c ". /app/tokenrc; bash /app/bootstrap.sh"
ret=$?
if [ $ret -ne 0 ]; then
    echo "Error: Keystone bootstrap error ${ret}!"
    exit $ret
fi

echo "Starting neutron-controller container"
docker run -d --net=host --privileged \
           -e DEBUG="true" \
           -e DB_SYNC="true" \
           -e NEUTRON_CONTROLLER="true" \
           -v /run/netns:/run/netns:shared \
           --name ${CONT_PREFIX}_neutron-controller \
           neutron:latest

wait_for_port 9696 60
ret=$?
if [ $ret -ne 0 ]; then
    echo "Error: Port 9696 (neutron server) not bounded!"
    exit $ret
fi

echo "Starting neutron-compute container"
docker run -d --net=host --privileged \
           -e DEBUG="true" \
           -e NEUTRON_CONTROLLER="false" \
           -e PROVIDER_INTERFACE="br-ex" \
           --name ${CONT_PREFIX}_neutron-compute \
           neutron:latest

wait_for_linuxbridge 120

echo "======== Success :) ========="

if [[ "$1" != "noclean" ]]; then
    cleanup
fi

