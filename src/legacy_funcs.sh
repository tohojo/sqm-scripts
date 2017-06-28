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


# Warn if deprecated variables are found in the environment. This is more
# relevant on Linux since no automatic upgrade is possible. The legacy
# variables are IGNORE_DSCP,SQUASH_INGRESS and ZERO_DSCP,SQUASH_DSCP.

legacy_vars_warn() {
    [ -n "$IGNORE_DSCP" -o -n "$SQUASH_INGRESS" ] &&
    sqm_warn "Variables IGNORE_DSCP and SQUASH_INGRESS are deprecated." &&
    sqm_warn "Replace their usage with IGNORE_DSCP_INGRESS."

    [ -n "$ZERO_DSCP" -o -n "$SQUASH_DSCP" ] &&
    sqm_warn "Variables ZERO_DSCP and SQUASH_DSCP are deprecated." &&
    sqm_warn "Replace their usage with ZERO_DSCP_INGRESS."
}


# When passed to config_foreach() within a UCI-enabled shell script, this
# function renames the legacy UCI options 'squash_dscp' and 'squash_ingress'
# to the new 'zero_dscp_ingress' and 'ignore_dscp_ingress'. This renaming is
# first done for the current UCI-loaded sqm config environment, to allow
# later invocations of config_foreach() to see the updated names. Then the
# renaming is done again within the UCI database and committed for future use.

legacy_vars_rename() {
    local sec="$1"

    local pkg="sqm"
    local to_convert="squash_dscp:zero_dscp_ingress \
                      squash_ingress:ignore_dscp_ingress"

    for var in $to_convert; do
        local old_var=${var%:*}
        local new_var=${var#*:}
        local old_val=$(config_get "$sec" $old_var)

        [ -z "$old_val" ] && continue
        config_set $sec $new_var $old_val &&
        uci_rename $pkg $sec $old_var $new_var && uci_commit $pkg

        if [ $? -eq 0 ]; then
            echo "Updated legacy variable: $old_var -> $new_var." >&2
        else
            echo "Problem updating legacy variable: $old_var." >&2
        fi
    done
}


# Override the system UCI shell wrapper which is broken and does not allow
# renaming of a section option. Remove this once fixed upstream and in LEDE.

uci_rename() {
    local PACKAGE="$1"
    local CONFIG="$2"
    local OPTION="$3"
    local VALUE="$4"

    /sbin/uci ${UCI_CONFIG_DIR:+-c $UCI_CONFIG_DIR} rename "$PACKAGE.$CONFIG${VALUE:+.$OPTION}=${VALUE:-$OPTION}"
}
