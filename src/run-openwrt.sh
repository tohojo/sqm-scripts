#!/bin/sh

# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 2 as
# published by the Free Software Foundation.
#
#       Copyright (C) 2012-4 Michael D. Taht, Toke Høiland-Jørgensen, Sebastian Moeller


. /usr/share/sqm/functions.sh

. /etc/sqm/sqm.conf

ACTION="${1:-start}"
RUN_IFACE="$2"

[ -d "${SQM_QDISC_STATE_DIR}" ] || ${SQM_LIB_DIR}/update-available-qdiscs

# Stopping all active interfaces
if [ "$ACTION" = "stop" -a -z "$RUN_IFACE" ]; then
    for f in ${SQM_STATE_DIR}/*.state; do
        # Source the state file prior to stopping; we need the $IFACE and
        # $SCRIPT variables saved in there.
        [ -f "$f" ] && ( . $f; IFACE=$IFACE SCRIPT=$SCRIPT SQM_DEBUG=$SQM_DEBUG SQM_DEBUG_LOG=$SQM_DEBUG_LOG OUTPUT_TARGET=$OUTPUT_TARGET ${SQM_LIB_DIR}/stop-sqm )
    done
    exit 0
fi

config_load sqm

run_sqm_scripts() {
    local section="$1"
    local SECTION_ACTION=start
    export IFACE=$(config_get "$section" interface)

    [ -z "$RUN_IFACE" -o "$RUN_IFACE" = "$IFACE" ] || return

    [ $(config_get "$section" enabled) -ne 1 ] && SECTION_ACTION=stop

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
    export SHAPER_BURST=$(config_get "$section" shaper_burst)
    export HTB_QUANTUM_FUNCTION=$(config_get "$section" htb_quantum_function)
    export QDISC=$(config_get "$section" qdisc)
    export SCRIPT=$(config_get "$section" script)

    # The UCI names for these two variables are confusing and should have been
    # changed ages ago. For now, keep the bad UCI names but use meaningful
    # variable names in the scripts to not break user configs.
    export ZERO_DSCP_INGRESS=$(config_get "$section" squash_dscp)
    export IGNORE_DSCP_INGRESS=$(config_get "$section" squash_ingress)

    #sm: if SQM_DEBUG or SQM_VERBOSITY_* were passed in via the command line make them available to the other scripts
    #	this allows to override sqm's log level as set in the GUI for quick debugging without GUI accesss.
    [ -n "$SQM_DEBUG" ] && export SQM_DEBUG || export SQM_DEBUG=$(config_get "$section" debug_logging)
    [ -n "$SQM_VERBOSITY_MAX" ] && export SQM_VERBOSITY_MAX || export SQM_VERBOSITY_MAX=$(config_get "$section" verbosity)
    [ -n "$SQM_VERBOSITY_MIN" ] && export SQM_VERBOSITY_MIN

    #sm: only stop-sqm if there is something running
    CUR_STATE_FILE="${SQM_STATE_DIR}/${IFACE}.state"
    if [ -f "${CUR_STATE_FILE}" ]; then
	"${SQM_LIB_DIR}/stop-sqm"
    fi

    [ "$SECTION_ACTION" = "start" ] && "${SQM_LIB_DIR}/start-sqm"
}

config_foreach run_sqm_scripts
