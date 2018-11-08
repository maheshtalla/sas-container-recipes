#! /bin/bash -e

[[ -z ${PROJECT_NAME+x} ]]                 && PROJECT_NAME=sas-viya
[[ -z ${BASEIMAGE+x} ]]                    && BASEIMAGE=centos
[[ -z ${BASETAG+x} ]]                      && BASETAG=latest
[[ -z ${SAS_VIYA_DEPLOYMENT_DATA_ZIP+x} ]] && SAS_VIYA_DEPLOYMENT_DATA_ZIP=${PWD}/SAS_Viya_deployment_data.zip
[[ -z ${SAS_VIYA_PLAYBOOK_DIR+x} ]]        && SAS_VIYA_PLAYBOOK_DIR=${PWD}/sas_viya_playbook
[[ -z ${PLATFORM+x} ]]                     && PLATFORM=redhat
[[ -z ${SAS_RPM_REPO_URL+x} ]]             && SAS_RPM_REPO_URL=https://ses.sas.download/ses/
[[ -z ${DOCKER_REGISTRY_URL+x} ]]          && DOCKER_REGISTRY_URL=http://docker.company.com
[[ -z ${DOCKER_REGISTRY_NAMESPACE+x} ]]    && DOCKER_REGISTRY_NAMESPACE=sas

if [ -f ${SAS_VIYA_DEPLOYMENT_DATA_ZIP} ]; then

    if [ ! -f ${PWD}/sas-orchestration ]; then
        echo "[INFO]  : Get orchestrationCLI";echo
        curl --silent --remote-name https://support.sas.com/installation/viya/34/sas-orchestration-cli/lax/sas-orchestration-linux.tgz
        tar xvf sas-orchestration-linux.tgz
        rm sas-orchestration-linux.tgz
    fi

    echo;echo "[INFO]  : Generate programming playbook";echo
    ./sas-orchestration build \
      --input ${SAS_VIYA_DEPLOYMENT_DATA_ZIP} \
      --repository-warehouse ${SAS_RPM_REPO_URL} \
      --deployment-type programming \
      --platform $PLATFORM

    tar xvf ${PWD}/SAS_Viya_playbook.tgz

else

    if [ ! -d ${SAS_VIYA_PLAYBOOK_DIR} ]; then
        echo;echo "[ERROR] : Could not find a playbook to use";echo
        exit 5
    else
        echo;echo "[INFO]  : Using playbook at '${SAS_VIYA_PLAYBOOK_DIR}'";echo
    fi

fi

if [ -f "${PWD}/container.yml" ]; then
    mv ${PWD}/container.yml ${PWD}/container_$(date +"%Y%m%d%H%M").yml
fi

cp -v templates/container.yml container.yml

for file in $(ls -1 ${SAS_VIYA_PLAYBOOK_DIR}/group_vars); do
    echo; echo "*** Create the roles directory for the host groups"
    if [ "${file}" != "all" ] && \
       [ "${file}" != "CommandLine" ] && \
       [ "${file}" != "sas-all" ] && \
       [ "${file}" != "sas-casserver-secondary" ] && \
       [ "${file}" != "sas-casserver-worker" ]; then

        # Lets check to see if the file actually has packages for us to install
        # An ESP order is an example of this
        set +e
        grep --quiet "SERVICE_YUM_PACKAGE" ${SAS_VIYA_PLAYBOOK_DIR}/group_vars/${file}
        pkg_grep_rc=$?
        grep --quiet "SERVICE_YUM_GROUP" ${SAS_VIYA_PLAYBOOK_DIR}/group_vars/${file}
        grp_grep_rc=$?
        set -e

        if (( ${pkg_grep_rc} == 0 )) || (( ${grp_grep_rc} == 0 )); then

            echo "***   Create the roles directory for service '${file}'"; echo
            mkdir --parents --verbose roles/${file}/tasks
            mkdir --parents --verbose roles/${file}/templates
            mkdir --parents --verbose roles/${file}/vars

            if [ ! -f "roles/${file}/tasks/main.yml" ]; then
                echo; echo "***     Copy the tasks file for service '${file}'"; echo
                cp -v templates/task.yml roles/${file}/tasks/main.yml
            else
                echo; echo "***     Tasks file for service '${file}' already exists"; echo
            fi

            if [ ! -f "roles/${file}/templates/entrypoint" ]; then
                echo; echo "***     Copy the entrypoint file for service '${file}'"; echo
                cp -v templates/entrypoint roles/${file}/templates/entrypoint
            else
                echo; echo "***     entrypoint file for service '${file}' already exists"; echo
            fi

        else
            echo
            echo "*** There are no packages or yum groups in '${file}'"
            echo "*** Skipping adding service '${file}' to Docker list"
            echo
        fi
    else
        echo; echo "*** Skipping creating the roles directory for service '${file}'"; echo
    fi
done

echo

for role in $(ls -1 roles); do
    if [ -f ${SAS_VIYA_PLAYBOOK_DIR}/group_vars/${role} ]; then
        if [ -f roles/${role}/vars/${role} ]; then
            sudo rm -v roles/${role}/vars/${role}
        fi
        if [ -d roles/${role}/vars ]; then
            cp -v ${SAS_VIYA_PLAYBOOK_DIR}/group_vars/${role} roles/${role}/vars/
        fi
    fi
done

#
# When first starting with Ansible-Container, it would not take multiple
# var files. This section here dumps everything into one file and then
# adjusts the everything.yml file to make sure variables are in the correct order
#

echo
echo "PROJECT_NAME: ${PROJECT_NAME}" > everything.yml
echo "BASEIMAGE: ${BASEIMAGE}" >> everything.yml
echo "BASETAG: ${BASETAG}" >> everything.yml
echo "PLATFORM: ${PLATFORM}" >> everything.yml
echo "DOCKER_REGISTRY_URL: ${DOCKER_REGISTRY_URL}" >> everything.yml
echo "DOCKER_REGISTRY_NAMESPACE: ${DOCKER_REGISTRY_NAMESPACE}" >> everything.yml
echo "" >> everything.yml
echo "DEPLOYMENT_ID: viya" >> everything.yml
echo "SPRE_DEPLOYMENT_ID: spre" >> everything.yml

if [[ ! -z ${INCLUDE_DEMOUSER+x} ]]; then
    echo "INCLUDE_DEMOUSER: yes" >> everything.yml
fi

cp ${SAS_VIYA_PLAYBOOK_DIR}/group_vars/all temp_all
sed -i 's|^DEPLOYMENT_ID:.*||' temp_all
sed -i 's|^SPRE_DEPLOYMENT_ID:.*||' temp_all

cat temp_all >> everything.yml

sudo rm -v temp_all

cat ${SAS_VIYA_PLAYBOOK_DIR}/vars.yml >> everything.yml
cat ${SAS_VIYA_PLAYBOOK_DIR}/internal/soe_defaults.yml >> everything.yml

sed -i 's|---||g' everything.yml
sed -i 's|^SERVICE_NAME_DEFAULT|#SERVICE_NAME_DEFAULT|' everything.yml
sed -i 's|^CONSUL_EXTERNAL_ADDRESS|#CONSUL_EXTERNAL_ADDRESS|' everything.yml
sed -i 's|^YUM_INSTALL_BATCH_SIZE|#YUM_INSTALL_BATCH_SIZE|' everything.yml
sed -i 's|^sasenv_license|#sasenv_license|' everything.yml
sed -i 's|^sasenv_composite_license|#sasenv_composite_license|' everything.yml
sed -i 's|^METAREPO_CERT_SOURCE|#METAREPO_CERT_SOURCE|' everything.yml
sed -i 's|^ENTITLEMENT_PATH|#ENTITLEMENT_PATH|' everything.yml
sed -i 's|^SAS_CERT_PATH|#SAS_CERT_PATH|' everything.yml
sed -i 's|^SECURE_CONSUL:.*|SECURE_CONSUL: false|' everything.yml

#
# Copy over the certificates that will be needed to do the install
#

if [ -f ${PWD}/entitlement_certificate.pem ]; then
    sudo rm ${PWD}/entitlement_certificate.pem
fi
cp -v ${SAS_VIYA_PLAYBOOK_DIR}/entitlement_certificate.pem .

if [ -f ${PWD}/SAS_CA_Certificate.pem ]; then
    sudo rm ${PWD}/SAS_CA_Certificate.pem
fi
cp -v ${SAS_VIYA_PLAYBOOK_DIR}/SAS_CA_Certificate.pem .

#
# Update Container yaml
#


if [ -f ${PWD}/consul.data ]; then
    consul_data_enc=$(cat ${PWD}/consul.data | base64 --wrap=0 )
    sed -i "s|CONSUL_KEY_VALUE_DATA_ENC=|CONSUL_KEY_VALUE_DATA_ENC=${consul_data_enc}|g" container.yml
fi


setinit_enc=$(cat ${SAS_VIYA_PLAYBOOK_DIR}/SASViyaV0300*.txt | base64 --wrap=0 )
sed -i "s|SETINIT_TEXT_ENC=|SETINIT_TEXT_ENC=${setinit_enc}|g" container.yml
sed -i "s|{{ DOCKER_REGISTRY_URL }}|${DOCKER_REGISTRY_URL}|" container.yml
sed -i "s|{{ DOCKER_REGISTRY_NAMESPACE }}|${DOCKER_REGISTRY_NAMESPACE}|" container.yml
sed -i "s|{{ PROJECT_NAME }}|${PROJECT_NAME}|" container.yml

#
# Remove the playbook directory
#

rm -rf ${SAS_VIYA_PLAYBOOK_DIR}

#
# Run ansible-container
#

echo; # Formatting
echo; # Formatting
echo; # Formatting

[[ -z ${SAS_CREATE_AC_VIRTUAL_ENV+x} ]] && SAS_CREATE_AC_VIRTUAL_ENV="true"
[[ -z ${ARG_DOCKER_REG_USERNAME+x} ]]   && ARG_DOCKER_REG_USERNAME="--username foo"
[[ -z ${ARG_DOCKER_REG_PASSWORD+x} ]]   && ARG_DOCKER_REG_PASSWORD="--password foobar"

# Python virtualenv configuration
if [[ "${SAS_CREATE_AC_VIRTUAL_ENV}" == "true" ]]; then
    # Detect virtualenv with $VIRTUAL_ENV
    if [[ -n $VIRTUAL_ENV ]]; then
        echo "Existing virtualenv detected..."
    # Create default env if none
    elif [[ -z $VIRTUAL_ENV ]] && [[ ! -d ac-env/ ]]; then
        echo "Creating virtualenv ac-env..."
        virtualenv --system-site-packages ac-env
        . ac-env/bin/activate
    # Activate existing ac-env if available
    elif [[ -d ac-env/ ]]; then
        echo "Activating virtualenv ac-env..."
        . ac-env/bin/activate
    fi
    # Ensure env active or die
    if [[ -z $VIRTUAL_ENV ]]; then
        echo "Failed to activate virtualenv....exiting."
        exit 1
    fi
    # Detect python 2+ or 3+
    PYTHON_MAJOR_VER="$(python -c 'import platform; print(platform.python_version()[0])')"
    if [[ $PYTHON_MAJOR_VER -eq "2" ]]; then
        # Install ansible-container
        pip install --upgrade pip==9.0.3
        pip install ansible-container[docker]
    elif [[ $PYTHON_MAJOR_VER -eq "3" ]]; then
        echo "WARN: Python3 support is experimental in ansible-container."
        echo "Updating requirements file for python3 compatibility..."
        sed -i.bak '/ruamel.ordereddict==0.4.13/d' ./requirements.txt
        pip install --upgrade pip==9.0.3
        pip install -e git+https://github.com/ansible/ansible-container.git@develop#egg=ansible-container[docker]
    fi
    # Restore latest pip version
    pip install --upgrade pip setuptools
    pip install -r requirements.txt
fi

# Prevent ansible-container build from importing virtualenv to conductor
if [[ ! -w "$(pwd)/.dockerignore" ]]; then
    echo "${VIRTUAL_ENV##*/}" > .dockerignore
elif [[ -w "$(pwd)/.dockerignore" ]]; then
    if [[ -z "$(grep $VIRTUAL_ENV .dockerignore)" ]]; then
        echo "Adding current virtualenv to dockerignore..."
        echo "${VIRTUAL_ENV##*/}" >> .dockerignore
    fi
fi

if [[ ! -z ${SKIP_BUILD+x} ]]; then
    echo " Skipping build "
    exit 0
fi

echo
echo "===================================="
echo "[INFO]  : Building SAS Docker images"
echo "===================================="
echo

set +e
ansible-container build
build_rc=$?
set -e

if (( ${build_rc} != 0 )); then
    echo "[ERROR] : Unable to build Docker images"; echo
    exit 20
fi

if [[ ! -z ${SKIP_PUSH+x} ]]; then
    echo " Skipping push and manifest building "
    exit 0
fi

[[ -z ${SAS_DOCKER_TAG+x} ]] && export SAS_DOCKER_TAG=$(cat ${PWD}/../../VERSION)-$(date +"%Y%m%d%H%M%S")-$(git rev-parse --short HEAD)

echo
echo "==================================="
echo "[INFO]  : Pushing SAS Docker images"
echo "==================================="
echo

set +e
ansible-container push --push-to docker-registry --tag ${SAS_DOCKER_TAG} ${ARG_DOCKER_REG_USERNAME} ${ARG_DOCKER_REG_PASSWORD}
push_rc=$?
set -e

if (( ${push_rc} != 0 )); then
    echo "[ERROR] : Unable to push Docker images"; echo
    exit 22
fi

echo
echo "========================================="
echo "[INFO]  : Generating Kubernetes Manifests"
echo "========================================="
echo

set +e
# Ansible requires access to the host's libselinux-python lib. Setting ansible_python_interpreter.
ansible-playbook generate_manifests.yml -e "docker_tag=${SAS_DOCKER_TAG}" -e 'ansible_python_interpreter=/usr/bin/python'
apgen_rc=$?
set -e

if (( ${apgen_rc} != 0 )); then
    echo "[ERROR] : Unable to generate manifests"; echo
    exit 30
fi

exit 0
