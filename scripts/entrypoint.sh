#!/bin/bash
set -e

# set debug
DEBUG_OPT=false
if [[ $DEBUG ]]; then
        set -x
        DEBUG_OPT=true
fi

# same image can be used in controller and compute node as well
# if true, CONTROL_SRVCS will be activated, if false, COMUPTE_SRVCS will be activated
NEUTRON_CONTROLLER=${NEUTRON_CONTROLLER:-true}

# define variable defaults

CPU_NUM=$(grep -c ^processor /proc/cpuinfo)

DB_HOST=${DB_HOST:-127.0.0.1}
DB_PORT=${DB_PORT:-3306}
DB_PASSWORD=${DB_PASSWORD:-veryS3cr3t}

MY_IP=${MY_IP:-127.0.0.1}
LOCAL_TUNNEL_IP=${LOCAL_TUNNEL_IP:-127.0.0.1}
NOVA_API_IP=${NOVA_API_IP:-127.0.0.1}
NOVA_API_PORT=${NOVA_API_PORT:-8774}

ADMIN_TENANT_NAME=${ADMIN_TENANT_NAME:-service}
ADMIN_USER=${ADMIN_USER:-neutron}
ADMIN_PASSWORD=${ADMIN_PASSWORD:-veryS3cr3t}

NOVA_ADMIN_USER=${NOVA_ADMIN_PASSWORD:-nova}
NOVA_ADMIN_PASSWORD=${NOVA_ADMIN_PASSWORD:-veryS3cr3t}

LOG_MESSAGE="Docker start script:"
OVERRIDE=0
CONF_DIR="/etc/neutron"
SUPERVISOR_CONF_DIR="/etc/supervisor.d"
OVERRIDE_DIR="/neutron-override"
CONF_FILES=(`cd $CONF_DIR; find . -maxdepth 3 -type f`)
CONTROL_SRVCS="neutron-server neutron-openvswitch-agent neutron-dhcp-agent neutron-l3-agent neutron-metadata-agent"
COMPUTE_SRVCS="neutron-openvswitch-agent"

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
                sed -i "s/\b_ADMIN_TENANT_NAME_\b/$ADMIN_TENANT_NAME/" $CONF_DIR/$CONF
                sed -i "s/\b_ADMIN_USER_\b/$ADMIN_USER/" $CONF_DIR/$CONF
                sed -i "s/\b_ADMIN_PASSWORD_\b/$ADMIN_PASSWORD/" $CONF_DIR/$CONF
                sed -i "s/\b_DEBUG_OPT_\b/$DEBUG_OPT/" $CONF_DIR/$CONF
                sed -i "s/\b_NOVA_ADMIN_USER_\b/$NOVA_ADMIN_USER/" $CONF_DIR/$CONF
                sed -i "s/\b_NOVA_ADMIN_PASSWORD_\b/$NOVA_ADMIN_PASSWORD/" $CONF_DIR/$CONF
                sed -i "s/\b_LOCAL_TUNNEL_IP_\b/$LOCAL_TUNNEL_IP/" $CONF_DIR/$CONF

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
