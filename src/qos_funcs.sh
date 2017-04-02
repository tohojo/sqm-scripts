################################################################################
# (sqm) qos_funcs.sh
#
# These are helper functions for ipt and tc-based marking or classification.
# If you want to play around with your own shaper-qdisc-filter configuration
# look here for functions to use, and examples to start off on your own.
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

# The following three are the top-level functions for diffserv/classification
# setup within the built-in start_sqm() script. Users can easily override these
# to customize behaviour while preserving the built-in shaper and leaf qdisc
# setup options.

# Common-path diffserv/classification setup

qos_setup_common() {
    ipt_vtun_dns_ntp_dscp
}


# Egress path diffserv/classification setup once the qdisc/class tree has
# been built. Provide DSCP-based prioritization for CAKE or other qdiscs.

qos_setup_egress() {
    local prio=1  # dynamically scoped priority var for local tc_ func calls

    # setup diffserv if prioritization enabled with a classful shaper qdisc
    if is_multitier_classful egress; then
        ipt_setup_map_dscp_fwmark $IFACE
        ipt_enable_map_dscp_fwmark $IFACE
        tc_classify_fwmark $IFACE
        tc_classify_arp $IFACE
        tc_classify_icmp $IFACE
    fi
}


# Ingress path diffserv/classification setup once the qdisc/class tree has
# been built. Provide DSCP-based prioritization for CAKE or other qdiscs.
# Note that ingress qdiscs do not hook into netfilter, meaning tc filters
# must be used for classification.

qos_setup_ingress() {
    local prio=1  # dynamically scoped priority var for local tc_ func calls

    # setup diffserv if prioritization enabled with a classful shaper qdisc
    if is_multitier_classful ingress; then
        tc_classify_dscp $DEV
        tc_classify_arp $DEV
    fi
}


# Set up an IP tables chain to map DSCP flags to FW marks, following the same
# scheme as CAKE's 'diffserv3' mode. Note that this is intended for use during
# egress path setup.

ipt_setup_map_dscp_fwmark() {
    local iface=$1

    sqm_debug "Prepare DSCP based marking on egress. (multi-tier classification)"
    ipt -t mangle -N QOS_MARK_${iface}

    ipt -t mangle -A QOS_MARK_${iface} -j MARK --set-mark 0x2/${IPT_MASK}
    # You can go further with classification but...
    ipt -t mangle -A QOS_MARK_${iface} -m dscp --dscp-class CS1 -j MARK --set-mark 0x3/${IPT_MASK}
    ipt -t mangle -A QOS_MARK_${iface} -m dscp --dscp-class CS6 -j MARK --set-mark 0x1/${IPT_MASK}
    ipt -t mangle -A QOS_MARK_${iface} -m dscp --dscp-class CS7 -j MARK --set-mark 0x1/${IPT_MASK}
    ipt -t mangle -A QOS_MARK_${iface} -m dscp --dscp-class EF -j MARK --set-mark 0x1/${IPT_MASK}
    # Explicit value needed for VA class (Voice-Admit)
    ipt -t mangle -A QOS_MARK_${iface} -m dscp --dscp 0x2C -j MARK --set-mark 0x1/${IPT_MASK}
    ipt -t mangle -A QOS_MARK_${iface} -m tos  --tos Minimize-Delay -j MARK --set-mark 0x1/${IPT_MASK}
}


# Activate the DSCP-mapping chain by appending it the system POSTROUTING chain.
# Note that this is intended for use during egress path setup.

ipt_enable_map_dscp_fwmark() {
    local iface=$1

    sqm_debug "Activate DSCP based marking on egress. (multi-tier classification)"
    ipt -t mangle -A POSTROUTING -o $iface -m mark --mark 0x00/${IPT_MASK} -j QOS_MARK_${iface}
}


# These two functions enable DSCP squashing on egress and ingress paths. They
# operate independently of ipt-based DSCP marking, so can be used even if
# shaping is disabled but squashing still desired.
# Note that these are not used with CAKE, which provides built-in squashing.

ipt_squash_ingress() {
    # zeroing DSCP is useful to protect internal machines

    if [ "$ZERO_DSCP_INGRESS" = "1" ]; then
        sqm_debug "Squashing differentiated services code points (DSCP) from ingress."
        ipt -t mangle -A PREROUTING -i $IFACE -m dscp ! --dscp 0 -j DSCP --set-dscp-class BE
    else
        sqm_debug "Keeping differentiated services code points (DSCP) from ingress."
    fi
}


ipt_squash_egress() {
    # zeroing DSCP can protect from malicious external network filtering

    # This must be called after ipt_enable_map_dscp_fwmark() to allow
    # independent squashing and diffserv marking.
    if [ "$ZERO_DSCP_EGRESS" = "1" ]; then
        sqm_debug "Squashing differentiated services code points (DSCP) on egress."
        ipt -t mangle -A POSTROUTING -o $IFACE -m dscp ! --dscp 0 -j DSCP --set-dscp-class BE
    else
        sqm_debug "Keeping differentiated services code points (DSCP) on egress."
    fi
}


ipt_vtun_dns_ntp_dscp() {
    # Not sure if this will work. Encapsulation is a problem period

    ipt -t mangle -I PREROUTING -i vtun+ -p tcp -j DSCP --set-dscp-class BE # tcp tunnels need ordering

    # Emanating from router, do a little more optimization
    # but don't bother with it too much.

    ipt -t mangle -A OUTPUT -p udp -m multiport --ports 123,53 -j DSCP --set-dscp-class EF
}


# Note that the following tc-based functions use a locally scoped $prio
# variable to set their relevant tc filter priority values. This allows
# simpler insertion, removal, or reordering of tc_*() function calls from
# the parent qos_setup_*() function.

fc() {
    # Note this is a helper only used by tc_classify_dscp()

    $TC filter add dev $4 protocol ip parent $1 prio $prio \
        u32 match ip tos $2 0xfc classid $3
    prio=$(($prio + 1))
    $TC filter add dev $4 protocol ipv6 parent $1 prio $prio \
        u32 match ip6 priority $2 0xfc classid $3
    prio=$(($prio + 1))
}


# Classify based on reading a packet's DSCP value with the 'u32' tc module.
# This approach must be used on ingress since netfilter is not available.

tc_classify_dscp() {
    local iface=$1

    # Catchall

    $TC filter add dev $iface parent 1:0 protocol all prio 999 u32 \
        match ip protocol 0 0x00 flowid 1:12

    # Find the most common matches fast

    fc 1:0 0x00 1:12 $iface # BE
    fc 1:0 0x20 1:13 $iface # CS1
    fc 1:0 0x10 1:11 $iface # IMM (TOS4)
    fc 1:0 0xb0 1:11 $iface # VA
    fc 1:0 0xb8 1:11 $iface # EF
    fc 1:0 0xc0 1:11 $iface # CS6
    fc 1:0 0xe0 1:11 $iface # CS7
}


# Classify based on a packet's FW mark value as previously set using IP tables.
# This approach cannot be used on ingress since netfilter is not available.

tc_classify_fwmark() {
    local iface=$1

    # Need a catchall rule

    $TC filter add dev $iface parent 1:0 protocol all prio 999 \
        u32 match ip protocol 0 0x00 flowid 1:12

    # IPv4 support. Note the handle indicates the fw mark that is looked for

    $TC filter add dev $iface parent 1:0 protocol ip prio $prio \
        handle 1/${IPT_MASK} fw classid 1:11
    prio=$(($prio + 1))

    $TC filter add dev $iface parent 1:0 protocol ip prio $prio \
        handle 2/${IPT_MASK} fw classid 1:12
    prio=$(($prio + 1))

    $TC filter add dev $iface parent 1:0 protocol ip prio $prio \
        handle 3/${IPT_MASK} fw classid 1:13
    prio=$(($prio + 1))

    # IPv6 support. Note the handle indicates the fw mark that is looked for

    $TC filter add dev $iface parent 1:0 protocol ipv6 prio $prio \
        handle 1/${IPT_MASK} fw classid 1:11
    prio=$(($prio + 1))

    $TC filter add dev $iface parent 1:0 protocol ipv6 prio $prio \
        handle 2/${IPT_MASK} fw classid 1:12
    prio=$(($prio + 1))

    $TC filter add dev $iface parent 1:0 protocol ipv6 prio $prio \
        handle 3/${IPT_MASK} fw classid 1:13
    prio=$(($prio + 1))
}


tc_classify_arp() {
    local iface=$1

    # Arp traffic prioritization

    $TC filter add dev $iface parent 1:0 protocol arp prio $prio \
        u32 match u32 0 0 classid 1:11
    prio=$(($prio + 1))
}

tc_classify_icmp() {
    local iface=$1

    # ICMP traffic - Don't impress your friends. Deoptimize to manage
    # ping floods better instead

    $TC filter add dev $iface parent 1:0 protocol ip prio $prio \
        u32 match ip protocol 1 0xff flowid 1:13
    prio=$(($prio + 1))

    $TC filter add dev $iface parent 1:0 protocol ipv6 prio $prio \
        u32 match ip protocol 1 0xff flowid 1:13
    prio=$(($prio + 1))
}
