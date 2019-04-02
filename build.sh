#!/bin/bash -e
# 
# build.sh
# Creates a container to run the SAS Container Recipes tool.
# Run `./build.sh --help` or see `docs/usage.txt` for details.
#
#
# Copyright 2018 SAS Institute Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

# Allow running only `./build.sh` to show --help output
function usage() {
	cat docs/usage.txt
}
if [ $# -eq 0 ] ; then
	usage
	exit 0
fi

# Display logs only in Linux. 
# Logging on MacOS is currently not supported. 
set -e
if [[ -n ${SAS_DEBUG} ]]; then
    set -x
fi
unameSystem="$(uname -s)"
case "${unameSystem}" in
    Linux*)     OPERATING_SYSTEM=linux;;
    Darwin*)    OPERATING_SYSTEM=darwin;;
    *)          echo "[WARN] : Unknown system: ${unameSystem}. Will assume Linux."
esac


function sas_container_recipes_shutdown() {
    echo
    echo "================================"
    echo "Shutting down SAS recipe process"
    echo "================================"
    echo

    set +e
    echo "[INFO]  : Stop ${SAS_BUILD_CONTAINER_NAME} if it is running"
    docker stop ${SAS_BUILD_CONTAINER_NAME}
    echo "[INFO]  : Remove ${SAS_BUILD_CONTAINER_NAME}"
    docker rm -f ${SAS_BUILD_CONTAINER_NAME}
    set -e

    exit 1
}
trap sas_container_recipes_shutdown SIGTERM
trap sas_container_recipes_shutdown SIGINT


# Parse command arguments and flags
while [[ $# -gt 0 ]]; do
    key="$1"
    case ${key} in
        -h|--help)
            shift
            usage
            exit 0
            ;;
        -i|--baseimage)
            shift # past argument
            BASEIMAGE="$1"
            shift # past value
            ;;
        -t|--basetag)
            shift # past argument
            BASETAG="$1"
            shift # past value
            ;;
        -m|--mirror-url)
            shift # past argument
            export SAS_RPM_REPO_URL=$1
            shift # past value
            ;;
        -p|--platform)
            shift # past argument
            PLATFORM="$1"
            shift # past value
            ;;
        -z|--zip)
            shift # past argument
            SAS_VIYA_DEPLOYMENT_DATA_ZIP="$1"
            shift # past value
            ;;
        -k|--skip-mirror-url-validation)
            shift # past argument
            CHECK_MIRROR_URL=false
            ;;
        -d|--skip-docker-url-validation)
            shift # past argument
            CHECK_DOCKER_URL=false
            ;;
        -a|--addons)
            shift # past argument
            ADDONS="$1"
            shift # past value
            ;;
        -y|--type)
            shift # past argument
            SAS_RECIPE_TYPE="$1"
            shift # past value
            ;;
        -u|--docker-url|--docker-registry-url)
            shift # past argument
            export DOCKER_REGISTRY_URL=$(echo $1 | cut -d'/' -f3)
            shift # past value
            ;;
        -n|--docker-namespace|--docker-registry-namespace)
            shift # past argument
            export DOCKER_REGISTRY_NAMESPACE="$1"
            shift # past value
            ;;
        -v|--virtual-host)
            shift # past argument
            export CAS_VIRTUAL_HOST="$1"
            shift # past value
            ;;
        -j|--project-name)
            shift # past argument
            export PROJECT_NAME="$1"
            shift # past value
            ;;
        -s|--sas-docker-tag)
            shift # past argument
            export SAS_DOCKER_TAG="$1"
            shift # past value
            ;;
        --builder-port)
            shift # past argument
            export BUILDER_PORT="$1"
            shift # past value
            ;;
        *) # Ignore everything that isn't a valid arg
            shift
    ;;
    esac
done

# Set some defaults
git_sha=$(git rev-parse --short HEAD 2>/dev/null || echo "no-git-sha")
datetime=$(date "+%Y%m%d%H%M%S")
sas_recipe_version=$(cat docs/VERSION)
SAS_BUILD_CONTAINER_NAME="sas-container-recipes-builder"
SAS_BUILD_CONTAINER_TAG=${sas_recipe_version}-${datetime}-${git_sha}
CHECK_DOCKER_URL=true
CHECK_MIRROR_URL=false

# Pass each argument if it exists. Allow the sas-container-recipes binary to catch any missing
# arguments that are required and fill in the default values of those that are not provided.
run_args=""
if [[ -n ${SAS_RPM_REPO_URL} ]]; then
	run_args="${run_args} --mirror-url ${SAS_RPM_REPO_URL}"
fi

if [[ -n ${SAS_VIYA_DEPLOYMENT_DATA_ZIP} ]]; then
	run_args="${run_args} --zip /$(basename ${SAS_VIYA_DEPLOYMENT_DATA_ZIP})"
fi

if [[ -n ${SAS_RECIPE_TYPE} ]]; then
	run_args="${run_args} --type ${SAS_RECIPE_TYPE}"
fi

if [[ -n ${DOCKER_REGISTRY_URL} ]]; then
	run_args="${run_args} --docker-registry-url ${DOCKER_REGISTRY_URL}"
fi

if [[ -n ${DOCKER_REGISTRY_NAMESPACE} ]]; then
	run_args="${run_args} --docker-namespace ${DOCKER_REGISTRY_NAMESPACE}"
fi 

if [[ -n ${SAS_DOCKER_TAG} ]]; then
	SAS_BUILD_CONTAINER_NAME="sas-container-recipes-builder-${SAS_DOCKER_TAG}"
	run_args="${run_args} --tag ${SAS_DOCKER_TAG}"
fi 

if [[ -n ${BASEIMAGE} ]]; then
	run_args="${run_args} --base-image ${BASEIMAGE}:${BASETAG}"
fi

if [[ -n ${ADDONS} ]]; then
	ADDONS=${ADDONS## } # remove trailing space
	ADDONS=${ADDONS//  /} # replace multiple spaces with a single space
	ADDONS=${ADDONS// /,} # replace spaces with a comma
	run_args="${run_args} --addons ${ADDONS}"
fi

if [[ -n ${CAS_VIRTUAL_HOST} ]]; then
    run_args="${run_args} --virtual-host '${CAS_VIRTUAL_HOST## }'"
fi

if [[ ${CHECK_DOCKER_URL} == false ]]; then
    run_args="${run_args} --skip-docker-url-validation"
fi

if [[ ${CHECK_MIRROR_URL} == false ]]; then
    run_args="${run_args} --skip-mirror-url-validation"
fi

if [[ -n ${BUILDER_PORT} ]]; then
    run_args="${run_args} --builder-port ${BUILDER_PORT}"
fi

if [[ -n ${PROJECT_NAME} ]]; then
	run_args="${run_args} --project-name ${PROJECT_NAME}"
fi


echo
echo "=============="
echo "Variable check"
echo "=============="
echo ""
echo "  Build System OS                 = ${OPERATING_SYSTEM}"
echo "  Deployment Type                 = ${SAS_RECIPE_TYPE}"
echo "  BASEIMAGE                       = ${BASEIMAGE}"
echo "  BASETAG                         = ${BASETAG}"
echo "  Mirror URL                      = ${SAS_RPM_REPO_URL}"
echo "  Validate Mirror URL             = ${CHECK_MIRROR_URL}"
echo "  Platform                        = ${PLATFORM}"
echo "  Project Name                    = ${PROJECT_NAME}"
echo "  Deployment Data Zip             = ${SAS_VIYA_DEPLOYMENT_DATA_ZIP}"
echo "  Addons                          = ${ADDONS## }"
echo "  Docker registry URL             = ${DOCKER_REGISTRY_URL}"
echo "  Docker registry namespace       = ${DOCKER_REGISTRY_NAMESPACE}"
echo "  Validate Docker registry URL    = ${CHECK_DOCKER_URL}"
echo "  HTTP Ingress endpoint           = ${CAS_VIRTUAL_HOST}"
echo "  Tag SAS will apply              = ${SAS_DOCKER_TAG}"
echo "  Build run args                  = ${run_args## }"
echo


echo
echo "==============================="
echo "Building Docker Build Container"
echo "==============================="
echo
DOCKER_GID=$(getent group docker|awk -F: '{print $3}')
USER_GID=$(id -g)
mkdir -p ${PWD}/builds
docker build . \
    --label sas.recipe=true \
    --label sas.recipe.builder.version=${SAS_DOCKER_TAG} \
    --build-arg USER_UID=${UID} \
    --build-arg DOCKER_GID=${DOCKER_GID} \
    --tag sas-container-recipes-builder:${SAS_DOCKER_TAG} \
    --file Dockerfile \


echo
echo "=============================="
echo "Running Docker Build Container"
echo "=============================="
echo
docker run -d \
    --name ${SAS_BUILD_CONTAINER_NAME} \
    -u ${UID}:${DOCKER_GID} \
    -v $(realpath ${SAS_VIYA_DEPLOYMENT_DATA_ZIP}):/$(basename ${SAS_VIYA_DEPLOYMENT_DATA_ZIP}) \
    -v ${PWD}/builds:/sas-container-recipes/builds \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -v ${HOME}/.docker/config.json:/home/sas/.docker/config.json \
    sas-container-recipes-builder:${SAS_DOCKER_TAG} ${run_args}

docker logs -f ${SAS_BUILD_CONTAINER_NAME}


# Clean up and exit
build_container_exit_status=$(docker inspect ${SAS_BUILD_CONTAINER_NAME} --format='{{.State.ExitCode}}')
docker rm ${SAS_BUILD_CONTAINER_NAME}
exit ${build_container_exit_status}
