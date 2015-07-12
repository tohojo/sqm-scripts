#!/bin/sh

# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 2 as
# published by the Free Software Foundation.
#
#       Copyright (C) 2012-4 Michael D. Taht, Toke Høiland-Jørgensen, Sebastian Moeller


. /lib/functions.sh

SQM_LIB_DIR=${SQM_LIB_DIR:-/usr/lib/sqm}
ACTION="${1:-start}"

# Stopping all active interfaces
if [ "$ACTION" = "stop" -a -z "$2" ]; then
    ${SQM_LIB_DIR}/run.sh stop
    exit 0
fi

config_load sqm

run_sqm_scripts() {
	local section="$1"
	export IFACE=$(config_get "$section" interface)

	[ $(config_get "$section" enabled) -ne 1 ] && ACTION=stop

	export UPLINK=$(config_get "$section" upload)
	export DOWNLINK=$(config_get "$section" download)
	export LLAM=$(config_get "$section" linklayer_adaptation_mechanism)
	export LINKLAYER=$(config_get "$section" linklayer)
	export OVERHEAD=$(config_get "$section" overhead)
	export STAB_MTU=$(config_get "$section" tcMTU)
	export STAB_TSIZE=$(config_get "$section" tcTSIZE)
	export STAB_MPU=$(config_get "$section" tcMPU)
	export ILIMIT=$(config_get "$section" ilimit)
	export ELIMIT=$(config_get "$section" elimit)
	export ITARGET=$(config_get "$section" itarget)
	export ETARGET=$(config_get "$section" etarget)
	export IECN=$(config_get "$section" ingress_ecn)
	export EECN=$(config_get "$section" egress_ecn)
	export IQDISC_OPTS=$(config_get "$section" iqdisc_opts)
	export EQDISC_OPTS=$(config_get "$section" eqdisc_opts)
	export TARGET=$(config_get "$section" target)
	export SQUASH_DSCP=$(config_get "$section" squash_dscp)
	export SQUASH_INGRESS=$(config_get "$section" squash_ingress)

	export QDISC=$(config_get "$section" qdisc)
	export SCRIPT=$(config_get "$section" script)

        ${SQM_LIB_DIR}/run.sh $ACTION $IFACE
}

config_foreach run_sqm_scripts
