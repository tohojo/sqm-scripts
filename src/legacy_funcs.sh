################################################################################
# (sqm) legacy_funcs.sh
#
# These are helper functions for dealing with legacy aspects of sqm-scripts,
# such as identifying and emulating the behaviour of QOS scripts that have
# been removed, or handling retired configuration variables.
#
# Please note the SQM logger function is broken down into levels of logging.
# Use only levels appropriate to touch points in your script and realize the
# potential to overflow SYSLOG.
#
################################################################################
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 2 as
# published by the Free Software Foundation.
#
#   Copyright (C) 2017
#       Tony Ambardar
#
################################################################################

# Check if the supplied script is deprecated and needs emulation for
# backwards compatibility.

is_legacy_script() {
    local script=$1

    # Legacy scripts removed from the distribution
    local regex="\(simpl\(e\|est\|est_tbf\)\|\(piece_of\|layer\)_cake\).qos"
    expr match "$script" "$regex" >/dev/null && return 0
    return 1
}


# Given a legacy script, generate the configuration variables required to
# emulate its function within the new framework.

legacy_script_settings() {
    local script=$1

    case $script in
        simple.qos) echo 'IGNORE_DSCP_EGRESS="0"';;
        simplest.qos) echo 'IGNORE_DSCP_INGRESS="1"; IGNORE_DSCP_EGRESS="1"';;
        simplest_tbf.qos) echo 'SHAPER="tbf"; IGNORE_DSCP_INGRESS="1"; IGNORE_DSCP_EGRESS="1"';;
        piece_of_cake.qos) echo 'QDISC=cake; SHAPER=cake; IGNORE_DSCP_INGRESS="1"; IGNORE_DSCP_EGRESS="1"';;
        layer_cake.qos) echo 'QDISC=cake; SHAPER=cake; IGNORE_DSCP_EGRESS="0"';;
    esac
}


# Given a legacy script, warn about its usage and emulate its function.

legacy_script_emulate() {
    local script=$1
    local vars=$(legacy_script_settings $script)

    sqm_warn "Legacy script $script is deprecated and should not be used."
    sqm_warn "You can achieve the same effect by setting the following"
    sqm_warn "equivalent configuration variables or their GUI counterparts:"
    sqm_warn "$vars"
    eval "$vars"
}
