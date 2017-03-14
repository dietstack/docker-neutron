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

#################################################################################################
# NETWORKING DOC (kmadac)
#################################################################################################
# DEFAULT_INTERFACE is interface where default gateway packets goes and is automatically detected.
# EXTERNAL_INTERFACE needs to be defined. If it is not, it'll be DEFAULT_INTERFACE
# EXTERNAL_INTERFACE is interface where floating ips are accessible over
# EXTERNAL_INTERFACE_IP is IP address which will be assigned to EXTERNAL_INTERFACE
# EXTERNAL_INTERFACE_IP must be in iproute2 interface format - 192.168.99.1/24
# It has to use cases:
#    1. You would like to access VMs running on your host from your the same host,
#       and you don't want to access it from outside. Then do not set EXTERNAL_INTERFACE_IP, and
#       floating IP range will be 192.168.99.10-192.168.99.245
#    2. You would like to access VMs running on your host from outside of the host.
#       You need to set EXTERNAL_INTERFACE_IP to address which is externally routable.
#       It can be IP address which is set on interface already. If it doesn't exists, entrypoint.sh
#       will add it to interface. If no EXTERNAL_INTERFACE_IP is set, no IP will be added or checked.
# PROVIDER_MAPPINGS is used if you would like to use provider networks. Format: prod:vlan666
###################################################################################################

DEFAULT_INTERFACE=$(cat /proc/net/route | awk '{print $1 " " $2}' | grep 00000000 | awk '{print $1}')
echo "DEFAULT_INTERFACE = $DEFAULT_INTERFACE"
EXTERNAL_INTERFACE=${EXTERNAL_INTERFACE:-$DEFAULT_INTERFACE}
echo "EXTERNAL_INTERFACE = $EXTERNAL_INTERFACE"

EXTERNAL_INTERFACE_IP=${EXTERNAL_INTERFACE_IP:-'192.168.99.1/24'}
echo "EXTERNAL_INTERFACE_IP = $EXTERNAL_INTERFACE_IP"

if [[ ! -z $EXTERNAL_INTERFACE ]]; then
    if [[ ! -z $EXTERNAL_INTERFACE_IP ]]; then
        if [[ ! `ip addr | awk '/inet/ && /'"$EXTERNAL_INTERFACE"'/{print $2}' | grep "$EXTERNAL_INTERFACE_IP"` ]]; then
            ip addr add $EXTERNAL_INTERFACE_IP dev $EXTERNAL_INTERFACE
#            EXTERN_NET=$(python -c "import os; import ipaddress; print(str(ipaddress.IPv4Interface(os.environ['EXTERNAL_INTERFACE_IP']).network))")
#            ip route add $EXTERN_NET dev $EXTERNAL_INTERFACE
        fi
    fi
    if [[ -z $PROVIDER_MAPPINGS ]]; then
        PROVIDER_MAPPINGS="external:$EXTERNAL_INTERFACE"
    else
        PROVIDER_MAPPINGS+=",external:$EXTERNAL_INTERFACE"
    fi
else
    echo "WARNING: EXTERNAL_INTERFACE not defined and could not be detected."
fi


# Overlay interface is interface which will be used for vxlan tunnels between nodes
# lo interface is used when all containers are running on one node
# if you want multinode installation change it to real interface
OVERLAY_INTERFACE=${OVERLAY_INTERFACE:-"$DEFAULT_INTERFACE"}
ip a s | grep -q $OVERLAY_INTERFACE || { echo "Overlay interface $OVERLAY_INTERFACE not found!" && exit 101; }
OVERLAY_INTERFACE_IP_ADDRESS=$(ip addr show dev $OVERLAY_INTERFACE | awk 'BEGIN {FS="[/ ]+"} /inet/ {print $3; exit}')
test -z $OVERLAY_INTERFACE_IP_ADDRESS && { echo "Overlay IP address not found!" && exit 102; }

if [[ ! -z $EXTERNAL_BRIDGE ]]; then
    # if controller which is also network node, add external bridge to mappings
    EXTERNAL_BRIDGE_MAPPING="external:$EXTERNAL_BRIDGE"
fi

LOG_MESSAGE="Docker start script:"
OVERRIDE=0
CONF_DIR="/etc/neutron"
SUPERVISOR_CONF_DIR="/etc/supervisor.d"
OVERRIDE_DIR="/neutron-override"
CONF_FILES=(`cd $CONF_DIR; find . -maxdepth 3 -type f`)
CONTROL_SRVCS="neutron-server neutron-dhcp-agent neutron-l3-agent neutron-metadata-agent"
COMPUTE_SRVCS="neutron-linuxbridge-agent"

INSECURE=${INSECURE:-true}

# check if external configs are provided
echo "$LOG_MESSAGE Checking if external config is provided.."
if [[ -f "$OVERRIDE_DIR/${CONF_FILES[0]}" ]]; then
        echo "$LOG_MESSAGE  ==> external config found!. Using it."
        OVERRIDE=1
        for CONF in ${CONF_FILES[*]}; do
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
            mv ${SUPERVISOR_CONF_DIR}/${SRVC}.ini.disabled ${SUPERVISOR_CONF_DIR}/${SRVC}.ini
        done
else
        for SRVC in $COMPUTE_SRVCS; do
            mv ${SUPERVISOR_CONF_DIR}/${SRVC}.ini.disabled ${SUPERVISOR_CONF_DIR}/${SRVC}.ini
        done
fi

[[ $DB_SYNC ]] && echo "Running db_sync ..." && neutron-db-manage --config-file /etc/neutron/neutron.conf --config-file /etc/neutron/plugins/ml2/ml2_conf.ini upgrade head

# echo "$LOG_MESSAGE starting neutron"
exec "$@"
