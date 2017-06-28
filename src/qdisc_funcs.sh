################################################################################
# (sqm) qdisc_funcs.sh
#
# These are helper functions for managing qdisc trees, shaper and leaf setup,
# and qdisc properties. They support the building of qdisc/class trees
# decoupled from specific qdiscs, and allow shaper and leaf qdisc mixing and
# matching. The functions further include a capabilities model for qdiscs,
# covering such details as supported diffserv schemes. Capabilities are also
# used to implement support for qdisc "preset configurations", with initial
# support for CAKE fairness options. If you want to play around with your own
# shaper-qdisc-filter configuration look here for functions to use, and
# examples to start off on your own.
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

# Verify the consistency of qdisc related configuration variables. This
# is critical to guard against manual config errors under Linux or LEDE.

verify_configs() {
    # Ensure shaper/leaf are listed in /etc/sqm/sqm.conf. This also implies
    # update-available-qdiscs has been run and capability files exist.
    for q in $QDISC $SHAPER; do
        local found="0"
        for allow in $SQM_CHECK_QDISCS; do
            [ "$q" = "$allow" ] && found="1" && break
        done
        if [  "$found" = "0" ]; then
            sqm_error "SHAPER or QDISC $q not listed in /etc/sqm/sqm.conf."
            return 1
        fi
    done

    # Ensure shaper/leaf are working and supported by capabilities
    if ! verify_qdisc $QDISC || ! qdisc_has_cap $QDISC leaf; then
        sqm_error "Leaf qdisc $QDISC not found or supported."
        return 1
    fi

    if ! verify_qdisc $SHAPER || ! qdisc_has_cap $SHAPER shaper; then
        sqm_error "Shaper $SHAPER not found or supported."
        return 1
    fi

    # Ensure CAKE shaper only used with CAKE leaf qdisc
    if [ "$SHAPER" = "cake" ] && [ "$QDISC" != "cake" ]; then
        sqm_error "Using SHAPER=cake requires QDISC=cake (not QDISC=$QDISC)."
        return 1
    fi

    # Ensure QDISC_PRESET is consistent with selected QDISC
    if [ -n "$QDISC_PRESET" ] &&
    ! qdisc_has_cap $QDISC "preset:$QDISC_PRESET"; then
        sqm_error "QDISC $QDISC does not support QDISC_PRESET=${QDISC_PRESET}."
        return 1
    fi

    # Ensure egress DSCP prioritization uses a valid diffserv scheme
    # with cake or any classful shaper
    if ( [ "$SHAPER" = "cake" ] || qdisc_has_cap $SHAPER classful ) &&
    [ "$IGNORE_DSCP_EGRESS" = "0" ] &&
    ! qdisc_has_cap $SHAPER "diffserv:$DIFFSERV_EGRESS"; then
        sqm_error "Prioritization enabled on egress with invalid scheme (DIFFSERV_EGRESS=${DIFFSERV_EGRESS})."
        return 1
    fi

    # Ensure ingress DSCP prioritization uses a valid diffserv scheme
    # with cake or any classful shaper
    if ( [ "$SHAPER" = "cake" ] || qdisc_has_cap $SHAPER classful ) &&
    [ "$IGNORE_DSCP_INGRESS" = "0" ] &&
    ! qdisc_has_cap $SHAPER "diffserv:$DIFFSERV_INGRESS"; then
        sqm_error "Prioritization enabled on ingress with invalid scheme (DIFFSERV_INGRESS=${DIFFSERV_INGRESS})."
        return 1
    fi

    sqm_debug "Checked validity of qdisc-related configuration variables."
    return 0
}


# Check if the current variables and shaper are configured for multi-tier
# classification.

is_multitier_classful() {
    local dir=$1

    case $dir in
        ingress)
            [ "$IGNORE_DSCP_INGRESS" = "0" ] &&
            qdisc_has_cap $SHAPER classful && return 0;;
        egress)
            [ "$IGNORE_DSCP_EGRESS" = "0" ] &&
            qdisc_has_cap $SHAPER classful && return 0;;
        *)
            sqm_error "Unknown direction \"$dir\" in is_multitier_classful()."
            return 1;;
    esac

    return 1
}


# Capture various qdisc capabilities, to support querying in both the scripts
# and the Luci GUI. There are two capability types: individual keywords
# express a property possessed, while more general 3-tuples express a range
# of mutually exclusive values for a property.

# The 3-tuple property format consists of 3 whitespace-free fields delimited
# by a ':' (colon) as follows: <property-type>:<var-value>:<description>.
# The <var-value> is the value of the related configuration variable, and
# the <description> text may be used in the GUI as a selection aid. Note that
# a '_' (underscore) in <description> will be rendered as a space in the GUI.

# The following is a summary of currently used capabilities:
#
# Capability     Description
# ==========     ===========
# leaf           The qdisc can act as a leaf
# shaper         The qdisc can act as a shaper
# classful       The shaper is classful and capable of priority tiers
# ecn            The qdisc is affected by ECN configuration variables
# diffserv       A supported priority scheme and DIFFSERV_ variable value
# preset         A qdisc-specific, supplementary configuration option

# All capabilities should be applicable to multiple qdiscs, both simplifying
# code and supporting decision logic. (And not to be abused as a general
# key/value store!)


# Look up the capabilities for a specific qdisc.

get_qdisc_caps() {
    local qdisc=$1
    local caps="$(get_caps_$qdisc 2>/dev/null)"

    [ -z "$caps" ] && sqm_warn "QDISC $qdisc has unknown capabilities."
    echo "$caps"
}


# Verify that a qdisc has the specified capability.

qdisc_has_cap() {
    local qdisc=$1
    local cap=$2
    [ -z "$qdisc" -o -z "$cap" ] && return 1

    local caps="$(get_qdisc_caps $qdisc)"
    [ -z "$caps" ] && return 1

    for c in $caps; do
        expr match "$c" "$cap" >/dev/null && return 0
    done

    return 1
}


# The following functions define the capabilities of individual qdiscs,
# allowing them to be looked up dynamically, overridden or new ones defined
# by users.


get_caps_fq_codel() {
    echo "leaf ecn"
}

get_caps_codel() {
    echo "leaf ecn"
}

get_caps_pie() {
    echo "leaf ecn"
}

get_caps_sfq() {
    echo "leaf"
}

get_caps_cake() {
    # NOTE: a qdisc should be defined as either a leaf or shaper, and CAKE was
    # previsouly assigned as "leaf", with additional code throughout to
    # accomodate its shaping aspects. But although CAKE is not a true shaper,
    # defining it as such does simplify the additional code overall.
    echo "leaf shaper
    diffserv:diffserv3:3-Tier_[diffserv3]
    diffserv:diffserv4:4-Tier_[diffserv4]
    diffserv:diffserv8:8-Tier_[diffserv8]
    diffserv:diffserv-llt:Latency/Loss_Tradeoff_[diffserv-llt]
    preset:int-host-fair:Internal_Host_Fairness
    preset:ext-host-fair:External_Host_Fairness
    preset:int-ext-host-fair:Internal/External_Host_Fairness"
}

get_caps_htb() {
    echo "shaper classful diffserv:diffserv3:3-Tier_[diffserv3]"
}

get_caps_hfsc() {
    echo "shaper classful diffserv:diffserv3:3-Tier_[diffserv3]"
}

get_caps_tbf() {
    echo "shaper"
}
# Central function for building a qdisc/class tree, while abstracting away
# specific leaf or shaper qdisc details using generator functions. It uses
# configuration settings and qdisc capabilities to distinguish between three
# main setup types: an all-in-one shaper/leaf, a classless shaper, and a
# classful shaper supporting one or more priority tiers.

# At each tier of the tree, specific qdisc parameters are generated by passing
# the tier details to the dynamically selected shaper or leaf function
# tier_shaper_$SHAPER or tier_leaf_$QDISC.

# For reference, the naming convention for tiers throughout this framework is
# the following:
#
# Tier     Description
# ====     ===========
# root     The root qdisc of the tree
#    0     The root class of a classful hierarchy
#    1     The 1st priority tier, for either a class or leaf qdisc
#    :
#    n     The nth priority tier, for either a class or leaf qdisc

qdisc_tree_build() {
    local dir=$1
    local iface=$2

    local rate
    local ignore_dscp
    local diffserv

    case $dir in
        ingress)
            rate="$DOWNLINK"
            ignore_dscp="$IGNORE_DSCP_INGRESS"
            diffserv="$DIFFSERV_INGRESS";;
        egress)
            rate="$UPLINK"
            ignore_dscp="$IGNORE_DSCP_EGRESS"
            diffserv="$DIFFSERV_EGRESS";;
        *)
            sqm_error "Unknown direction \"$dir\" in qdisc_tree_build()."
            return 1;;
    esac

    $TC qdisc del dev $iface root 2> /dev/null

    if [ "$SHAPER" = "$QDISC" ]; then
        # All-in-one shaper/leaf qdisc, currently only for CAKE
        case $SHAPER in
            cake)
                $TC qdisc add dev $iface root \
                    $(tier_shaper_$SHAPER tier_args $dir any root);;
            *)
                sqm_error "No support for $SHAPER as all-in-one shaper and leaf qdisc."
                return 1;;
        esac

    elif ! qdisc_has_cap $SHAPER classful; then
        # Classless shaper, different leaf qdisc, without classification
        sqm_debug "Do not perform DSCP based filtering on ${dir}. (1-tier classless)"
        $TC qdisc add dev $iface root handle 1: \
            $(tier_shaper_$SHAPER tier_args $dir 1 root)
        $TC qdisc add dev $iface parent 1: handle 110: \
            $(tier_leaf_$QDISC tier_args $dir 1 1 \
                $(tier_shaper_$SHAPER flow_rate $dir 1 1))

    else
        # Classful shaper, different leaf qdisc, 1 or n-tier classification

        local num_tiers
        if [ "$ignore_dscp" = "1" ]; then
            num_tiers="1"
            sqm_debug "Do not perform DSCP based filtering on ${dir}. (1-tier classification)"
        else
            num_tiers="${diffserv#diffserv}"
            sqm_debug "Perform DSCP based filtering on ${dir}. (${num_tiers}-tier classification)"
        fi

        $TC qdisc add dev $iface root handle 1: \
            $(tier_shaper_$SHAPER tier_args $dir $num_tiers root) \
            default 1$(tier_shaper_$SHAPER default_tier $dir $num_tiers root)
        $TC class add dev $iface parent 1: classid 1:1 \
            $(tier_shaper_$SHAPER tier_args $dir $num_tiers 0)

        for tier in $(seq $num_tiers); do
            $TC class add dev $iface parent 1:1 classid 1:1${tier} \
                $(tier_shaper_$SHAPER tier_args $dir $num_tiers $tier)

            $TC qdisc add dev $iface parent 1:1${tier} handle 1${tier}0: \
                $(tier_leaf_$QDISC tier_args $dir $num_tiers $tier \
                    $(tier_shaper_$SHAPER flow_rate $dir $num_tiers $tier))
        done
    fi
}


# The following are generator functions returning the arguments for specific
# shaper qdiscs supported by the framework. Each function may be called from
# qdisc_tree_build() dynamically using the SHAPER variable.

# Each function tier_shaper_$SHAPER takes four parameters as follows:
#
# Parameter   Values         Description
# =========   ======         ===========
#      func   flow_rate      Rate passed to get_flows() in leaf qdisc setup
#             default_tier   Default tier of the class hierarchy
#             tier_args      Generate parameters used by shaper qdisc
#       dir   ingress        Current tree built for ingress
#             egress         Current tree built for egress
# num_tiers   1 .. n         Total number of priority tiers
#      tier   root, 0 .. n   Current priority tier, described previously


# This defines the simple, classless TBF shaper qdisc.

tier_shaper_tbf() {
    local func=$1
    local dir=$2
    local num_tiers=$3
    local tier=$4

    local rate

    case $dir in
        ingress)
            rate="$DOWNLINK";;
        egress)
            rate="$UPLINK";;
        *)
            sqm_error "Unknown direction \"$dir\" in tier_shaper_$SHAPER()."
            return 1;;
    esac

    case $func in
        flow_rate)
            echo "$rate"
            return;;
        default_tier)
            echo "1"
            return;;
        tier_args)
            ;;
        *)
            sqm_error "Unknown function \"$func\" in tier_shaper_$SHAPER()."
            return 1;;
    esac

    local mtu=$(get_mtu $IFACE)
    local burst="$(get_burst ${mtu:-1514} ${rate})"
    burst=${burst:-1514}
    local args="$(get_stab_string) $SHAPER rate ${rate}kbit burst $burst latency 300ms $(get_htb_adsll_string)"

    case "$dir $num_tiers $tier" in
        "ingress 1 root"|"egress 1 root")
            echo "$args";;
        *)
            echo "$args"
            sqm_warn "Unhandled args \"$dir $num_tiers $tier\" to $func in tier_shaper_$SHAPER(). Using defaults."
            return 1;;
    esac
}


# This defines the commonly used, classful HTB shaper qdisc.

tier_shaper_htb() {
    local func=$1
    local dir=$2
    local num_tiers=$3
    local tier=$4

    local rate

    case $dir in
        ingress)
            rate="$DOWNLINK";;
        egress)
            rate="$UPLINK";;
        *)
            sqm_error "Unknown direction \"$dir\" in tier_shaper_$SHAPER()."
            return 1;;
    esac

    local prio_rate=`expr $rate / 3` # Ceiling for prioirty
    local be_rate=`expr $rate / 6`   # Min for best effort
    local bk_rate=`expr $rate / 6`   # Min for background
    local be_ceil=`expr $rate - 16`  # A little slop at the top

    case $func in
        flow_rate)
            case "$num_tiers $tier" in
                "1 1") echo "$rate";;
                "3 1") echo "$prio_rate";;
                "3 2") echo "$be_rate";;
                "3 3") echo "$bk_rate";;
                *)
                    echo "$rate"
                    sqm_warn "Unhandled args to flow_rate \"$num_tiers $tier\" in tier_shaper_$SHAPER(). Using defaults.";;
            esac
            return;;
        default_tier)
            case "$num_tiers" in
                "1") echo "1";;
                "3") echo "2";;
                *)
                    echo "$(expr $num_tiers - 1)"
                    sqm_warn "Unhandled args to default_tier \"$num_tiers\" in tier_shaper_$SHAPER(). Using defaults.";;
            esac
            return;;
        tier_args)
            ;;
        *)
            sqm_error "Unknown function \"$func\" in tier_shaper_$SHAPER()."
            return 1;;
    esac

    local lq="quantum `get_htb_quantum $IFACE $rate`"
    local burst="`get_htb_burst $IFACE $rate`"
    local args="$SHAPER $lq $burst $(get_htb_adsll_string)"
    local args31="$SHAPER $lq $(get_htb_adsll_string)"
    local ret=""

    case "$num_tiers $tier" in
        "1 root") ret="$(get_stab_string) $SHAPER";;
        "1 0") ret="$args rate ${rate}kbit ceil ${rate}kbit";;
        "1 1") ret="$args rate ${rate}kbit ceil ${rate}kbit prio 0";;
    esac

    case "$num_tiers $tier" in
        "3 root") ret="$(get_stab_string) $SHAPER";;
        "3 0") ret="$args rate ${rate}kbit ceil ${rate}kbit";;
        "3 1")
            case "$dir" in
                "ingress") ret="$args31 rate 32kbit ceil ${prio_rate}kbit prio 1";;
                "egress") ret="$args31 rate 128kbit ceil ${prio_rate}kbit prio 1";;
            esac;;
        "3 2") ret="$args rate ${be_rate}kbit ceil ${be_ceil}kbit prio 2";;
        "3 3") ret="$args rate ${bk_rate}kbit ceil ${be_ceil}kbit prio 3";;
    esac

    [ -n "$ret" ] && echo "$ret" && return

    sqm_error "Unhandled args \"$dir $num_tiers $tier\" to $func in tier_shaper_$SHAPER()."
    return 1
}


# This defines the specialized, classful HFSC shaper qdisc.

# The HFSC parameters used here are based on the hfsc_litest.qos and
# hfsc_lite.qos scripts by Eric Luehrsen, with additional feedback from him.

tier_shaper_hfsc() {
    local func=$1
    local dir=$2
    local num_tiers=$3
    local tier=$4

    local rate

    case $dir in
        ingress)
            rate="$DOWNLINK";;
        egress)
            rate="$UPLINK";;
        *)
            sqm_error "Unknown direction \"$dir\" in tier_shaper_$SHAPER()."
            return 1;;
    esac

# Parameter comments below from Eric Luehrsen:

# Link share (virtual time) tuning is only rough as borrowing will occur.
# However in saturation, each class is guaranteed (real time) minimum of 10%.
# This allows HFSC to do its work but avoids some of its virtual time quirks.

    local rate_c=$(( ${rate} * 105 / 100 ))
    local rate_r=$(( ${rate} *  10 / 100 ))
    local rate_1=$(( ${rate} *  20 / 100 ))
    local rate_2=$(( ${rate} *  50 / 100 ))
    local rate_3=$(( ${rate} *  30 / 100 ))

    case $func in
        flow_rate)
            case "$num_tiers $tier" in
                "1 1") echo "$rate";;
                "3 1") echo "$rate_1";;
                "3 2") echo "$rate_2";;
                "3 3") echo "$rate_3";;
                *)
                    echo "$rate"
                    sqm_warn "Unhandled args to flow_rate \"$num_tiers $tier\" in tier_shaper_$SHAPER(). Using defaults.";;
            esac
            return;;
        default_tier)
            case "$num_tiers" in
                "1") echo "1";;
                "3") echo "2";;
                *)
                    echo "$(expr $num_tiers - 1)"
                    sqm_warn "Unhandled args to default_tier \"$num_tiers\" in tier_shaper_$SHAPER(). Using defaults.";;
            esac
            return;;
        tier_args)
            ;;
        *)
            sqm_error "Unknown function \"$func\" in tier_shaper_$SHAPER()."
            return 1;;
    esac

# Root Class
# The SC curve (LS+RT) includes feedback in virtual time, but the UL
# ceiling is pure real time. If UL=SC, then you cant actually get SC.

    local ret=""

    case "$num_tiers $tier" in
        "1 root") ret="$(get_stab_string) $SHAPER";;
        "1 0") ret="$SHAPER sc m1 ${rate_c}kbit d 1s m2 ${rate}kbit ul rate ${rate_c}kbit";;
        "1 1") ret="$SHAPER ls rate ${rate}kbit";;
    esac

    case "$num_tiers $tier" in
        "3 root") ret="$(get_stab_string) $SHAPER";;
        "3 0") ret="$SHAPER sc m1 ${rate_c}kbit d 1s m2 ${rate}kbit ul rate ${rate_c}kbit";;
        "3 1") ret="$SHAPER ls rate ${rate_1}kbit rt rate ${rate_r}kbit";;
        "3 2") ret="$SHAPER ls rate ${rate_2}kbit rt rate ${rate_r}kbit";;
        "3 3") ret="$SHAPER ls rate ${rate_3}kbit rt rate ${rate_r}kbit";;
    esac

    [ -n "$ret" ] && echo "$ret" && return

    sqm_error "Unhandled args \"$dir $num_tiers $tier\" to $func in tier_shaper_$SHAPER()."
    return 1
}


# This defines the advanced CAKE qdisc. Some day it will be in mainline!
# Note that using CAKE as shaper implies using it as an all-in-one qdisc.

tier_shaper_cake() {
    local func=$1
    local dir=$2
    local num_tiers=$3
    local tier=$4

    local rate
    local ignore_dscp
    local zero_dscp
    local diffserv
    local qdisc_opts

    case $dir in
        ingress)
            rate="$DOWNLINK"
            ignore_dscp="$IGNORE_DSCP_INGRESS"
            zero_dscp="$ZERO_DSCP_INGRESS"
            diffserv="$DIFFSERV_INGRESS"
            qdisc_opts="$IQDISC_OPTS";;
        egress)
            rate="$UPLINK"
            ignore_dscp="$IGNORE_DSCP_EGRESS"
            zero_dscp="$ZERO_DSCP_EGRESS"
            diffserv="$DIFFSERV_EGRESS"
            qdisc_opts="$EQDISC_OPTS";;
        *)
            sqm_error "Unknown direction \"$dir\" in tier_shaper_$SHAPER()."
            return 1;;
    esac

    case $func in
        flow_rate)
            echo "$rate"
            return;;
        default_tier)
            echo "1"
            sqm_warn "Unneeded call to $func in tier_shaper_$SHAPER(). Shaper $SHAPER does not support classful tiers."
            return;;
        tier_args)
            ;;
        *)
            sqm_error "Unknown function \"$func\" in tier_shaper_$SHAPER()."
            return 1;;
    esac

    local args="$(get_stab_string) $(get_cake_lla_string) bandwidth ${rate}kbit flows"
    local preset="$QDISC_PRESET"

    [ "$zero_dscp" -eq "1" ] && args="$args wash"
    if [ "$ignore_dscp" -eq "1" ]; then
        args="$args besteffort"
    else
        args="$args $diffserv"
    fi

    [ -n "$preset" ] && args="$args $(preset_args_$QDISC $dir $preset)"

    args="$args $qdisc_opts"

    case "$dir $num_tiers $tier" in
        "ingress any root")
            echo "$SHAPER $args";;
        "egress any root")
            echo "$SHAPER $args";;
        *)
            echo "$SHAPER $args"
            sqm_warn "Unhandled args \"$dir $num_tiers $tier\" to $func in tier_shaper_$SHAPER(). Using defaults."
            return 1;;
    esac
}


# The following are generator functions returning the arguments for specific
# leaf qdiscs supported by the framework. Each function may be called from
# qdisc_tree_build() dynamically using the QDISC variable.

# Each function tier_leaf_$QDISC takes five parameters as follows:
#
# Parameter   Values         Description
# =========   ======         ===========
#      func   tier_args      Generate parameters used by leaf qdisc
#       dir   ingress        Current tree built for ingress
#             egress         Current tree built for egress
# num_tiers   1 .. n         Total number of priority tiers
#      tier   1 .. n         Current priority tier, described previously
#      rate   i              Rate passed to get_flows() for qdisc setup


# This defines CAKE when used as a leaf qdisc. In this mode we disable shaping
# and prioritization, which are handled by the shaper qdisc, and stick to our
# knitting of flow isolation and fairness.

tier_leaf_cake() {
    local func=$1
    local dir=$2
    local num_tiers=$3
    local tier=$4
    local rate=$5

    local preset="$QDISC_PRESET"

    if [ "$func" != "tier_args" ]; then
        sqm_error "Unknown function \"$func\" in tier_leaf_$QDISC()."
        return 1
    fi

    local args="$QDISC $(get_stab_string) $(get_cake_lla_string) unlimited besteffort flows"

    [ -n "$preset" ] && args="$args $(preset_args_$QDISC $dir $preset)"

    case $dir in
        ingress)
            [ "$ZERO_DSCP_INGRESS" -eq "1" ] && args="$args wash"
            echo "$args ${IQDISC_OPTS}";;
        egress)
            [ "$ZERO_DSCP_EGRESS" -eq "1" ] && args="$args wash"
            echo "$args ${EQDISC_OPTS}";;
        *)
            sqm_error "Unknown direction \"$dir\" in tier_leaf_$QDISC()."
            return 1;;
    esac
}


# This general function handles all currently supported non-CAKE leaf qdiscs.

tier_leaf_generic() {
    local func=$1
    local dir=$2
    local num_tiers=$3
    local tier=$4
    local rate=$5

    local args
    local qdisc_opts

    if [ "$func" != "tier_args" ]; then
        sqm_error "Unknown function \"$func\" in tier_leaf_$QDISC()."
        return 1
    fi

    case $dir in
        ingress)
            args="$QDISC $(get_limit ${ILIMIT}) $(get_target "${ITARGET}" ${DOWNLINK}) $(get_ecn ${IECN}) $(get_flows ${rate})"
            qdisc_opts="$IQDISC_OPTS";;
        egress)
            args="$QDISC $(get_limit ${ELIMIT}) $(get_target "${ETARGET}" ${UPLINK}) $(get_ecn ${EECN}) $(get_flows ${rate})"
            qdisc_opts="$EQDISC_OPTS";;
        *)
            sqm_error "Unknown direction \"$dir\" in tier_leaf_$QDISC()."
            return 1;;
    esac

    case "$dir $num_tiers $tier" in
        "ingress 1 1") echo "$args $qdisc_opts";;
        "ingress 3 1") echo "$args $(get_quantum 500) $qdisc_opts";;
        "ingress 3 2") echo "$args $(get_quantum 1500) $qdisc_opts";;
        "ingress 3 3") echo "$args $(get_quantum 300) $qdisc_opts";;

        "egress 1 1") echo "$args $qdisc_opts";;
        "egress 3 1") echo "$args $(get_quantum 300) $qdisc_opts";;
        "egress 3 2") echo "$args $(get_quantum 300) $qdisc_opts";;
        "egress 3 3") echo "$args $(get_quantum 300) $qdisc_opts";;

        *)
            echo "$args $(get_quantum 300) $qdisc_opts"
            sqm_warn "Unhandled args \"$dir $num_tiers $tier\" to $func in tier_leaf_$QDISC()."
            return 1;;
    esac
}

tier_leaf_fq_codel() {
    tier_leaf_generic $*
}

tier_leaf_codel() {
    tier_leaf_generic $*
}

tier_leaf_sfq() {
    tier_leaf_generic $*
}

tier_leaf_pie() {
    tier_leaf_generic $*
}


# This is currently the only helper for "preset configurations" based on
# QDISC_PRESET, and supports the host fairness options of CAKE.

preset_args_cake() {
    local dir=$1
    local preset=$2

    case $dir in
        ingress)
            case "$preset" in
                int-host-fair) echo "dual-dsthost nat";;
                ext-host-fair) echo "dual-srchost nat";;
                int-ext-host-fair) echo "triple-isolate nat";;
            esac;;
        egress)
            case "$preset" in
                int-host-fair) echo "dual-srchost nat";;
                ext-host-fair) echo "dual-dsthost nat";;
                int-ext-host-fair) echo "triple-isolate nat";;
            esac;;
    esac
}
