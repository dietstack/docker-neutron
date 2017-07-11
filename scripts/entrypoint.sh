#!/bin/bash
set -e

# set debug
DEBUG_OPT=false
if [[ $DEBUG ]]; then
        set -x
        DEBUG_OPT=true
fi

# same image can be used in controller and compute node as well
# if true, CONTROL_SRVCS will be activated, if false, COMPUTE_SRVCS will be activated
NEUTRON_CONTROLLER=${NEUTRON_CONTROLLER:-true}

# define variable defaults

CPU_NUM=$(grep -c ^processor /proc/cpuinfo)

DB_HOST=${DB_HOST:-127.0.0.1}
DB_PORT=${DB_PORT:-3306}
DB_PASSWORD=${DB_PASSWORD:-veryS3cr3t}

RABBITMQ_HOST=${RABBITMQ_HOST:-127.0.0.1}
RABBITMQ_PORT=${RABBITMQ_PORT:-5672}
RABBITMQ_USER=${RABBITMQ_USER:-openstack}
RABBITMQ_PASSWORD=${RABBITMQ_PASSWORD:-veryS3cr3t}

MY_IP=${MY_IP:-127.0.0.1}
NOVA_API_IP=${NOVA_API_IP:-127.0.0.1}
NOVA_API_PORT=${NOVA_API_PORT:-8774}

SERVICE_TENANT_NAME=${SERVICE_TENANT_NAME:-service}
SERVICE_USER=${SERVICE_USER:-neutron}
SERVICE_PASSWORD=${SERVICE_PASSWORD:-veryS3cr3t}

NOVA_SERVICE_USER=${NOVA_SERVICE_PASSWORD:-nova}
NOVA_SERVICE_PASSWORD=${NOVA_SERVICE_PASSWORD:-veryS3cr3t}

NEUTRON_METADATA_SECRET=${NEUTRON_METADATA_SECRET:-veryS3cr3tmetadata}

KEYSTONE_HOST=${KEYSTONE_HOST:-127.0.0.1}
NOVA_HOST=${NOVA_HOST:-127.0.0.1}
MEMCACHED_SERVERS=${MEMCACHED_SERVERS:-127.0.0.1:11211}

PROVIDER_MAPPINGS=${PROVIDER_MAPPINGS:-''}

INSECURE=${INSECURE:-true}

#################################################################################################
# NETWORKING DOC (kmadac)
#################################################################################################
# EXTERNAL_BRIDGE and EXTERNAL_INTERFACE are mutualy exclusive options
# EXTERNAL_BRIDGE has precedence if both are defined.
# If EXTERNAL_BRIDGE is defined, script will create it
# You do not want to define EXTERNAL_BRIDGE if you are running container of compute node
# PROVIDER_MAPPINGS is used if you would like to use provider networks. Format: prod:vlan666
###################################################################################################

# enable necessary networking kernel module (needed for minimal debian jessie installation)
lsmod | grep -q ebtables || modprobe ebtables
lsmod | grep -q ip_tables || modprobe ip_tables
lsmod | grep -q ip6_tables || modprobe ip6_tables

EXTERNAL_BRIDGE=${EXTERNAL_BRIDGE:-''}
echo "EXTERNAL_BRIDGE = $EXTERNAL_BRIDGE"
EXTERNAL_INTERFACE=${EXTERNAL_INTERFACE:-''}
echo "EXTERNAL_INTERFACE = $EXTERNAL_INTERFACE"

if [[ ! -z $EXTERNAL_BRIDGE ]]; then
    ip a s | grep -q $EXTERNAL_BRIDGE || { echo "EXTERNAL_BRIDGE $EXTERNAL_BRIDGE not found!" && exit 1; }
    EXTERNAL_BRIDGE_MAPPING="external:$EXTERNAL_BRIDGE"
elif [[ ! -z $EXTERNAL_INTERFACE ]]; then
    ip a s | grep -q $EXTERNAL_INTERFACE || { echo "EXTERNAL_INTERFACE $EXTERNAL_INTERFACE not found"} && exit 1; }
    if [[ -z $PROVIDER_MAPPINGS ]]; then
        PROVIDER_MAPPINGS="external:$EXTERNAL_INTERFACE"
    else
        PROVIDER_MAPPINGS+=",external:$EXTERNAL_INTERFACE"
    fi
else
    echo "EXTERNAL_BRIDGE nor EXTERNAL_INTERFACE not defined."
fi


# Overlay interface is interface which will be used for vxlan tunnels between nodes
# lo interface is used when all containers are running on one node
# if you want multinode installation set it to real interface with L3 connectivity to other nodes
OVERLAY_INTERFACE=${OVERLAY_INTERFACE:-lo}
ip a s | grep -q $OVERLAY_INTERFACE || { echo "Overlay interface $OVERLAY_INTERFACE not found!" && exit 101; }
OVERLAY_INTERFACE_IP_ADDRESS=$(ip addr show dev $OVERLAY_INTERFACE | awk 'BEGIN {FS="[/ ]+"} /inet/ {print $3; exit}')
test -z $OVERLAY_INTERFACE_IP_ADDRESS && { echo "Overlay IP address not found!" && exit 102; }

LOG_MESSAGE="Docker start script:"
OVERRIDE=0
CONF_DIR="/etc/neutron"
SUPERVISOR_CONF_DIR="/etc/supervisor.d"
OVERRIDE_DIR="/neutron-override"
CONF_FILES=(`cd $CONF_DIR; find . -maxdepth 3 -type f`)
OVERRIDE_CONF_FILES=(`cd $OVERRIDE_DIR; find . -maxdepth 3 -type f`)
CONTROL_SRVCS="neutron-server neutron-dhcp-agent neutron-l3-agent neutron-metadata-agent"
COMPUTE_SRVCS="neutron-linuxbridge-agent"

# check if external configs are provided
echo "$LOG_MESSAGE Checking if external config is provided.."
if [[ "$(ls -A $OVERRIDE_DIR)" ]]; then
        echo "$LOG_MESSAGE  ==> external config found!. Using it."
        OVERRIDE=1
        for CONF in ${OVERRIDE_CONF_FILES[*]}; do
                rm -f "$CONF_DIR/$CONF"
                ln -s "$OVERRIDE_DIR/$CONF" "$CONF_DIR/$CONF"
        done
fi

if [[ $OVERRIDE -eq 0 ]]; then
        for CONF in ${CONF_FILES[*]}; do
                echo "$LOG_MESSAGE generating $CONF file ..."
                sed -i "s/_DB_HOST_/$DB_HOST/" $CONF_DIR/$CONF
                sed -i "s/_DB_PORT_/$DB_PORT/" $CONF_DIR/$CONF
                sed -i "s/_DB_PASSWORD_/$DB_PASSWORD/" $CONF_DIR/$CONF
                sed -i "s/\b_RABBITMQ_HOST_\b/$RABBITMQ_HOST/" $CONF_DIR/$CONF
                sed -i "s/\b_RABBITMQ_PORT_\b/$RABBITMQ_PORT/" $CONF_DIR/$CONF
                sed -i "s/\b_RABBITMQ_USER_\b/$RABBITMQ_USER/" $CONF_DIR/$CONF
                sed -i "s/\b_RABBITMQ_PASSWORD_\b/$RABBITMQ_PASSWORD/" $CONF_DIR/$CONF
                sed -i "s/\b_SERVICE_TENANT_NAME_\b/$SERVICE_TENANT_NAME/" $CONF_DIR/$CONF
                sed -i "s/\b_SERVICE_USER_\b/$SERVICE_USER/" $CONF_DIR/$CONF
                sed -i "s/\b_SERVICE_PASSWORD_\b/$SERVICE_PASSWORD/" $CONF_DIR/$CONF
                sed -i "s/\b_DEBUG_OPT_\b/$DEBUG_OPT/" $CONF_DIR/$CONF
                sed -i "s/\b_NOVA_SERVICE_USER_\b/$NOVA_SERVICE_USER/" $CONF_DIR/$CONF
                sed -i "s/\b_NOVA_SERVICE_PASSWORD_\b/$NOVA_SERVICE_PASSWORD/" $CONF_DIR/$CONF
                sed -i "s/\b_KEYSTONE_HOST_\b/$KEYSTONE_HOST/" $CONF_DIR/$CONF
                sed -i "s/\b_NOVA_HOST_\b/$NOVA_HOST/" $CONF_DIR/$CONF
                sed -i "s/\b_MEMCACHED_SERVERS_\b/$MEMCACHED_SERVERS/" $CONF_DIR/$CONF
                sed -i "s/\b_INSECURE_\b/$INSECURE/" $CONF_DIR/$CONF
                sed -i "s/\b_EXTERNAL_BRIDGE_MAPPING_\b/$EXTERNAL_BRIDGE_MAPPING/" $CONF_DIR/$CONF
                sed -i "s/\b_PROVIDER_MAPPINGS_\b/$PROVIDER_MAPPINGS/" $CONF_DIR/$CONF
                sed -i "s/\b_OVERLAY_INTERFACE_IP_ADDRESS_\b/$OVERLAY_INTERFACE_IP_ADDRESS/" $CONF_DIR/$CONF
                sed -i "s/\b_NEUTRON_METADATA_SECRET_\b/$NEUTRON_METADATA_SECRET/" $CONF_DIR/$CONF
        done
        echo "$LOG_MESSAGE  ==> done"
fi

if [[ $NEUTRON_CONTROLLER == "true" ]]; then
        for SRVC in $CONTROL_SRVCS; do
            if [[ -f ${SUPERVISOR_CONF_DIR}/${SRVC}.ini.disabled ]]; then
                mv ${SUPERVISOR_CONF_DIR}/${SRVC}.ini.disabled ${SUPERVISOR_CONF_DIR}/${SRVC}.ini
            fi
        done
else
        for SRVC in $COMPUTE_SRVCS; do
            if [[ -f ${SUPERVISOR_CONF_DIR}/${SRVC}.ini.disabled ]]; then
                mv ${SUPERVISOR_CONF_DIR}/${SRVC}.ini.disabled ${SUPERVISOR_CONF_DIR}/${SRVC}.ini
            fi
        done
fi

[[ $DB_SYNC ]] && echo "Running db_sync ..." && neutron-db-manage --config-file /etc/neutron/neutron.conf --config-file /etc/neutron/plugins/ml2/ml2_conf.ini upgrade head

# echo "$LOG_MESSAGE starting neutron"
exec "$@"
