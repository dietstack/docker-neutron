#!/bin/bash

RELEASE_REPO=172.27.9.130

. lib/functions.sh

IMAGE_NAME=neutron
VERSION=$(git describe --abbrev=7 --tags)

# get osmaster docker image
get_docker_image_from_release osmaster http://${RELEASE_REPO}/docker-osmaster latest

docker build $@ -t $IMAGE_NAME:$VERSION .
docker tag -f $IMAGE_NAME:$VERSION $IMAGE_NAME:latest

