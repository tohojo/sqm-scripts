#!/bin/sh

# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 2 as
# published by the Free Software Foundation.
#
#       Copyright (C) 2012-4 Michael D. Taht, Toke Høiland-Jørgensen, Sebastian Moeller


SQM_LIB_DIR=${SQM_LIB_DIR:-/usr/lib/sqm}
. ${SQM_LIB_DIR}/functions.sh

ACTION="${1:-start}"
SQM_STATE_DIR=${SQM_STATE_DIR:-/var/run/SQM}
ACTIVE_STATE_PREFIX="SQM_active_on_"
mkdir -p ${SQM_STATE_DIR}


START_ON_IF=$2	# only process this interface
# TODO if $2 is empty select all interfaces with running sqm instance
if [ -z ${START_ON_IF} ] ;
then
    # find all interfaces with active sqm instance
    sqm_logger "Trying to start/stop SQM on all interfaces."
    PROTO_STATE_FILE_LIST=$( echo ${SQM_STATE_DIR}/${ACTIVE_STATE_PREFIX}* 2> /dev/null )
else
    # only try to restart the just hotplugged interface, so reduce the list of interfaces to stop to the specified one
    sqm_logger "Trying to start/stop SQM on interface ${START_ON_IF}"
    PROTO_STATE_FILE_LIST=${SQM_STATE_DIR}/${ACTIVE_STATE_PREFIX}${START_ON_IF}
fi




# the current uci config file does not necessarily contain sections for all interfaces with active
# SQM instances, so use the ACTIVE_STATE_FILES to detect the interfaces on which to stop SQM.
# Currently the .qos scripts start with stopping any existing traffic shaping so this should not
# effectively change anything...
for STATE_FILE in ${PROTO_STATE_FILE_LIST} ; do
    if [ -f ${STATE_FILE} ] ;
    then
	STATE_FILE_BASE_NAME=$( basename ${STATE_FILE} )
	CURRENT_INTERFACE=${STATE_FILE_BASE_NAME:${#ACTIVE_STATE_PREFIX}:$(( ${#STATE_FILE_BASE_NAME} - ${#ACTIVE_STATE_PREFIX} ))}
	sqm_logger "${0} Stopping SQM on interface: ${CURRENT_INTERFACE}"
	${SQM_LIB_DIR}/stop.sh ${CURRENT_INTERFACE}
	rm ${STATE_FILE}	# well, we stop it so it is not running anymore and hence no active state file needed...
    fi
done

[ "$ACTION" = "stop" ] && exit 0

# in case of spurious hotplug events, try double check whether the interface is really up
if [ ! -d /sys/class/net/${IFACE} ] ;
then
    sqm_logger "${IFACE} does currently not exist, not even trying to start SQM on nothing."
    exit 0
fi

sqm_logger "${0} Queue Setup Script: ${SCRIPT}"
[ -x "${SQM_LIB_DIR}/$SCRIPT" ] && { "${SQM_lIB_DIR}/$SCRIPT" ; touch ${ACTIVE_STATE_FILE_FQN}; }
