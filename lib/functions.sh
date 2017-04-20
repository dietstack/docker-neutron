wait_for_port() {
    local port="$1"
    local timeout=$2
    local counter=0
    echo "Wait till app is bound to port $port "
    while [[ $counter -lt $timeout ]]; do
        local counter=$[counter + 1]
        if [[ ! `ss -ntl | grep ":${port}"` ]]; then
            echo -n ". "
        else
            break
        fi
        sleep 1
    done

    if [[ $timeout -eq $counter ]]; then
        exit 1
    fi
}

get_docker_image_from_release() {
    # download image and load it to local docker repo
    # does not download if version already exists in local image repository
    local image_name=$1
    local http_image_repo_url=$2
    local reqversion=$3

    local version=${reqversion}
    if [[ "${reqversion}" -eq "latest" ]]; then
        local version=$(wget -q -O - ${http_image_repo_url}/latest_tag.txt)
        echo "Remote latest version is ${version}."
    fi

    if [[ ! `docker images | grep -w ${image_name} | grep -w ${version}` ]]; then
        # docker image of requests version doesn't exists in local repository
        local http_image_url=${http_image_repo_url}/${image_name}:${version}.tgz
        echo "Getting ${image_name} from ${http_image_url} ..."
        mkdir -p /tmp/${image_name}
        rm -f /tmp/${image_name}/*
        pushd /tmp/${image_name}
            wget ${http_image_url}
            image_file=$(ls -1t | head -n 1)
            gunzip ${image_file}
            unziped_image_file=$(ls -1t | head -n 1)
            docker load < ${unziped_image_file}
        popd
        rm -rf /tmp/${image_name}
    else
        echo "Docker image ${image_name}:${version} found in local repository."
    fi
    dimage=$(docker images | grep ${image_name} | grep ${version} | awk '{print $1}')
    docker tag ${dimage}:${version} ${image_name}:latest
}



create_db_osadmin() {
    # Usage: create_db_osadmin keystone keystone veryS3cr3t veryS3cr3t
    local DB_NAME=$1
    local USER_NAME=$2
    local ROOT_DB_PASSWD=$3
    local SVC_DB_PASSWD=$4
    MYSQL_CMD="docker run --net=host osadmin mysql -h 127.0.0.1 -P 3306 -u root -p$ROOT_DB_PASSWD"
    $MYSQL_CMD -e "CREATE DATABASE $DB_NAME;"
    $MYSQL_CMD -e "CREATE USER '$USER_NAME'@'%' IDENTIFIED BY '$SVC_DB_PASSWD';"
    $MYSQL_CMD -e "GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$USER_NAME'@'%' WITH GRANT OPTION;"
}


#!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
# Following functions are deprecated in favor of osadmin version defined above #
#!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

create_keystone_db() {
    MYSQL_CMD="mysql -h 127.0.0.1 -P 3306 -u root -pveryS3cr3t"
    $MYSQL_CMD -e "CREATE DATABASE keystone;"
    $MYSQL_CMD -e "CREATE USER 'keystone'@'%' IDENTIFIED BY 'veryS3cr3t';"
    $MYSQL_CMD -e "GRANT ALL PRIVILEGES ON keystone.* TO 'keystone'@'%' WITH GRANT OPTION;"
}

create_glance_db() {
    MYSQL_CMD="mysql -h 127.0.0.1 -P 3306 -u root -pveryS3cr3t"
    $MYSQL_CMD -e "CREATE DATABASE glance;"
    $MYSQL_CMD -e "CREATE USER 'glance'@'%' IDENTIFIED BY 'veryS3cr3t';"
    $MYSQL_CMD -e "GRANT ALL PRIVILEGES ON glance.* TO 'glance'@'%' WITH GRANT OPTION;"
}

create_nova_db() {
    MYSQL_CMD="mysql -h 127.0.0.1 -P 3306 -u root -pveryS3cr3t"
    $MYSQL_CMD -e "CREATE DATABASE nova_api;"
    $MYSQL_CMD -e "CREATE DATABASE nova;"
    $MYSQL_CMD -e "CREATE USER 'nova'@'%' IDENTIFIED BY 'veryS3cr3t';"
    $MYSQL_CMD -e "GRANT ALL PRIVILEGES ON nova_api.* TO 'nova'@'%' WITH GRANT OPTION;"
    $MYSQL_CMD -e "GRANT ALL PRIVILEGES ON nova.* TO 'nova'@'%' WITH GRANT OPTION;"
}

create_neutron_db() {
    MYSQL_CMD="mysql -h 127.0.0.1 -P 3306 -u root -pveryS3cr3t"
    $MYSQL_CMD -e "CREATE DATABASE neutron;"
    $MYSQL_CMD -e "CREATE USER 'neutron'@'%' IDENTIFIED BY 'veryS3cr3t';"
    $MYSQL_CMD -e "GRANT ALL PRIVILEGES ON neutron.* TO 'neutron'@'%' WITH GRANT OPTION;"
}

