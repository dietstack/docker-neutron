wait_for_port() {
    local port="$1"
    local timeout=$2
    local counter=0
    echo "Wait till app is bound to port $port "
    while [[ $counter -lt $timeout ]]; do
        local counter=$[counter + 1]
        if [[ ! `ss -ntl4 | grep ":${port}"` ]]; then
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
    # if latest is not assigned to requested version, tag it
    latest_id=$(docker images | grep ${image_name} | grep latest | awk '{print $3}')
    tag_id=$(docker images | grep ${image_name} | grep ${version} | awk '{print $3}')
    if [[ "$latest_id" != "$tag_id" ]]; then
        docker tag -f ${image_name}:${version} ${image_name}:latest
    fi
}

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
    $MYSQL_CMD -e "CREATE DATABASE nova;"
    $MYSQL_CMD -e "CREATE USER 'nova'@'%' IDENTIFIED BY 'veryS3cr3t';"
    $MYSQL_CMD -e "GRANT ALL PRIVILEGES ON nova.* TO 'nova'@'%' WITH GRANT OPTION;"
}

create_neutron_db() {
    MYSQL_CMD="mysql -h 127.0.0.1 -P 3306 -u root -pveryS3cr3t"
    $MYSQL_CMD -e "CREATE DATABASE neutron;"
    $MYSQL_CMD -e "CREATE USER 'neutron'@'%' IDENTIFIED BY 'veryS3cr3t';"
    $MYSQL_CMD -e "GRANT ALL PRIVILEGES ON neutron.* TO 'neutron'@'%' WITH GRANT OPTION;"
}


