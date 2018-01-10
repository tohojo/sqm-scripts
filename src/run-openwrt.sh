#!/bin/sh

# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 2 as
# published by the Free Software Foundation.
#
#       Copyright (C) 2012-4 Michael D. Taht, Toke Høiland-Jørgensen, Sebastian Moeller


. /etc/sqm/sqm.conf
. /lib/functions.sh
. ${SQM_LIB_DIR}/legacy_funcs.sh

ACTION="${1:-start}"
RUN_IFACE="$2"

stop_statefile() {
    local f="$1"
    # Source the state file prior to stopping; we need the variables saved in
    # there.
    [ -f "$f" ] && ( . "$f"; ${SQM_LIB_DIR}/stop-sqm )
}

start_sqm_section() {
    local section="$1"
    export IFACE=$(config_get "$section" interface)

    [ -z "$RUN_IFACE" -o "$RUN_IFACE" = "$IFACE" ] || return
    [ "$(config_get "$section" enabled)" -eq 1 ] || return
    [ -f "${SQM_STATE_DIR}/${IFACE}.state" ] && return

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
    export QDISC_PRESET=$(config_get "$section" qdisc_preset)
    export SHAPER=$(config_get "$section" shaper)
    export SCRIPT=$(config_get "$section" script)

    # The old UCI names for these two variables were confusing but are now
    # updated at runtime, so use the new, more meaningful names.
    export ZERO_DSCP_INGRESS=$(config_get "$section" zero_dscp_ingress)
    export IGNORE_DSCP_INGRESS=$(config_get "$section" ignore_dscp_ingress)

    # These two variables are new so the UCI names can be kept consistent.
    export ZERO_DSCP_EGRESS=$(config_get "$section" zero_dscp_egress)
    export IGNORE_DSCP_EGRESS=$(config_get "$section" ignore_dscp_egress)

    # These two variables determine the prioritization scheme if enabled.
    export DIFFSERV_INGRESS=$(config_get "$section" diffserv_ingress)
    export DIFFSERV_EGRESS=$(config_get "$section" diffserv_egress)

    # If SQM_DEBUG or SQM_VERBOSITY_* were passed in via the command line make
    # them available to the other scripts this allows to override sqm's log
    # level as set in the GUI for quick debugging without GUI accesss.
    export SQM_DEBUG=${SQM_DEBUG:-$(config_get "$section" debug_logging)}
    export SQM_VERBOSITY_MAX=${SQM_VERBOSITY_MAX:-$(config_get "$section" verbosity)}
    export SQM_VERBOSITY_MIN

    "${SQM_LIB_DIR}/start-sqm"
}

if [ "$ACTION" = "stop" ]; then
    if [ -z "$RUN_IFACE" ]; then
        # Stopping all active interfaces
        for f in ${SQM_STATE_DIR}/*.state; do
            stop_statefile "$f"
        done
    else
        stop_statefile "${SQM_STATE_DIR}/${RUN_IFACE}.state"
    fi
else
    config_load sqm
    config_foreach legacy_vars_rename
    config_foreach start_sqm_section
fi
