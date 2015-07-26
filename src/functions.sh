# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 2 as
# published by the Free Software Foundation.
#
#       Copyright (C) 2012-4 Michael D. Taht, Toke Høiland-Jørgensen, Sebastian Moeller

#improve the logread output
sqm_logger() {
    if [ "$SQM_SYSLOG" -eq "1" ]; then
        logger -t SQM -s "$*"
    else
        echo "$@" >&2
    fi
}

insmod() {
  lsmod | grep -q ^$1 || $INSMOD $1
}

ipt() {
  d=$(echo $* | sed s/-A/-D/g)
  [ "$d" != "$*" ] && {
	iptables $d > /dev/null 2>&1
	ip6tables $d > /dev/null 2>&1
  }
  d=$(echo $* | sed s/-I/-D/g)
  [ "$d" != "$*" ] && {
	iptables $d > /dev/null 2>&1
	ip6tables $d > /dev/null 2>&1
  }
  iptables $* > /dev/null 2>&1
  ip6tables $* > /dev/null 2>&1
}

do_modules() {
#sm TODO: check first whether the modules exist and only load then
	insmod act_ipt
	insmod sch_$QDISC
	insmod sch_ingress
	insmod act_mirred
	insmod cls_fw
  insmod cls_flow
  insmod cls_u32
	insmod sch_htb
  insmod sch_hfsc
}



#sqm_logger "${0} IPT_MASK: ${IPT_MASK_STRING}"



# find the ifb device associated with a specific interface, return nothing of no ifb is associated with IF
get_ifb_associated_with_if() {
    CUR_IF=$1
    # CUR_IFB=$( tc -p filter show parent ffff: dev ${CUR_IF} | grep -o -e ifb'[[:digit:]]\+' )
    CUR_IFB=$( tc -p filter show parent ffff: dev ${CUR_IF} | grep -o -e ifb'[^)]\+' )	# my editor's syntax coloration is limitied so I need a single quote in this line (between eiditor and s)
    sqm_logger "ifb associated with interface ${CUR_IF}: ${CUR_IFB}"
    echo ${CUR_IFB}
}

ifb_name() {
    CUR_IF=$1
    MAX_IF_NAME_LENGTH=15
    IFB_PREFIX="ifb4"
    NEW_IFB="${IFB_PREFIX}${CUR_IF}"
    IFB_NAME_LENGTH=${#NEW_IFB}
    # IFB names can only be 15 chararcters, so we chop of excessive characters
    # at the start of the interface name
    if [ ${IFB_NAME_LENGTH} -gt ${MAX_IF_NAME_LENGTH} ];
    then
	OVERLIMIT=$(( ${#NEW_IFB} - ${MAX_IF_NAME_LENGTH} ))
	NEW_IFB=${IFB_PREFIX}${CUR_IF:${OVERLIMIT}:$(( ${MAX_IF_NAME_LENGTH} - ${#IFB_PREFIX} ))}
    fi
    echo ${NEW_IFB}
}

# if required
create_new_ifb_for_if() {
    NEW_IFB=$(ifb_name $1)
    sqm_logger "trying to create new IFB: ${NEW_IFB}"
    $IP link add name ${NEW_IFB} type ifb #>/dev/null 2>&1	# better be verbose
    echo ${NEW_IFB}
}

# the best match is either the IFB already associated with the current interface or a new named IFB
get_ifb_for_if() {
    CUR_IF=$1
    # if an ifb is already associated return that
    CUR_IFB=$( get_ifb_associated_with_if ${CUR_IF} )
    [ -z "$CUR_IFB" ] && CUR_IFB=$( create_new_ifb_for_if ${CUR_IF} )
    [ -z "$CUR_IFB" ] && sqm_logger "Could not find existing IFB for ${CUR_IF}, nor create a new IFB instead..."
    echo ${CUR_IFB}
}



get_htb_adsll_string() {
	ADSLL=""
	if [ "$LLAM" = "htb_private" -a "$LINKLAYER" != "none" ];
	then
		# HTB defaults to MTU 1600 and an implicit fixed TSIZE of 256, but HTB as of around 3.10.0
		# does not actually use a table in the kernel
		ADSLL="mpu ${STAB_MPU} linklayer ${LINKLAYER} overhead ${OVERHEAD} mtu ${STAB_MTU}"
		sqm_logger "ADSLL: ${ADSLL}"
	fi
	echo ${ADSLL}
}

get_stab_string() {
	STABSTRING=""
	if [ "${LLAM}" = "tc_stab" -a "$LINKLAYER" != "none" ];
	then
		STABSTRING="stab mtu ${STAB_MTU} tsize ${STAB_TSIZE} mpu ${STAB_MPU} overhead ${OVERHEAD} linklayer ${LINKLAYER}"
		sqm_logger "STAB: ${STABSTRING}"
	fi
	echo ${STABSTRING}
}

#sm: cake knows how to handle ATM and per packet overhead, so expose and use this...
get_cake_lla_string() {
	STABSTRING=""
	if [ "${LLAM}" = "cake" -a "${LINKLAYER}" != "none" ];
	then
		if [ "${LINKLAYER}" = "atm" ];
		then
		    STABSTRING="atm"
		fi

		STABSTRING="${STABSTRING} overhead ${OVERHEAD}"
		sqm_logger "cake link layer adjustments: ${STABSTRING}"
	fi
	echo ${STABSTRING}
}


sqm_stop() {
	$TC qdisc del dev $IFACE ingress
	$TC qdisc del dev $IFACE root
	$TC qdisc del dev $DEV root
}

# Note this has side effects on the prio variable
# and depends on the interface global too

fc() {
	$TC filter add dev $interface protocol ip parent $1 prio $prio u32 match ip tos $2 0xfc classid $3
	prio=$(($prio + 1))
	$TC filter add dev $interface protocol ipv6 parent $1 prio $prio u32 match ip6 priority $2 0xfc classid $3
	prio=$(($prio + 1))
}

fc_pppoe() {
	PPPOE_SESSION_ETHERTYPE="0x8864"
	PPPOE_DISCOVERY_ETHERTYPE="0x8863"
	PPP_PROTO_IP4="0x0021"
	PPP_PROTO_IP6="0x0057"
	ARP_PROTO_IP4="0x0806"
	$TC filter add dev $interface protocol ip parent $1 prio $prio u32 match ip tos $2 0xfc classid $3
	$TC filter add dev $interface parent $1 protocol ${PPPOE_SESSION_ETHERTYPE} prio $(( 400 + ${prio}  )) u32 \
	    match u16 ${PPP_PROTO_IP4} 0xffff at 6 \
	    match u8 $2 0xfc at 9 \
	    flowid $3

	prio=$(($prio + 1))
	$TC filter add dev $interface protocol ipv6 parent $1 prio $prio u32 match ip6 priority $2 0xfc classid $3
	$TC filter add dev $interface parent $1 protocol ${PPPOE_SESSION_ETHERTYPE} prio $(( 600 + ${prio} )) u32 \
	    match u16 ${PPP_PROTO_IP6} 0xffff at 6 \
	    match u16 0x0${2:2:2}0 0x0fc0 at 8 \
	    flowid $3

	prio=$(($prio + 1))
}

#sm: TODO: increase the quantum to lower computation cost.
# a) this should be calculated slightly more inteligently
# b) this should not arbitrarily end
# c) most likely it should be set so that the transfer time of a quantum stays constant
get_htb_quantum() {
	CUR_QUANTUM=$( get_mtu $1 )
	BANDWIDTH=$2

	if [ -z "${CUR_QUANTUM}" ]
	then
	CUR_QUANTUM=1500
	fi
	if [ ${BANDWIDTH} -gt 20000 ]
	then
		CUR_QUANTUM=$((${CUR_QUANTUM} * 2))
	fi
	if [ ${BANDWIDTH} -gt 30000 ]
	then
		CUR_QUANTUM=$((${CUR_QUANTUM} * 2))
	fi
	if [ ${BANDWIDTH} -gt 40000 ]
	then
		CUR_QUANTUM=$((${CUR_QUANTUM} * 2))
	fi
	if [ ${BANDWIDTH} -gt 50000 ]
	then
		CUR_QUANTUM=$((${CUR_QUANTUM} * 2))
	fi
	if [ ${BANDWIDTH} -gt 60000 ]
	then
		CUR_QUANTUM=$((${CUR_QUANTUM} * 2))
	fi
	if [ ${BANDWIDTH} -gt 80000 ]
	then
		CUR_QUANTUM=$((${CUR_QUANTUM} * 2))
	fi

	#sqm_logger "CUR_HTB_QUANTUM: ${CUR_QUANTUM}, BANDWIDTH: ${BANDWIDTH}"

	echo $CUR_QUANTUM
}


#sm: For a default PPPoE link this returns 1492 just as expected
# but I fear we actually need the wire size of the whole thing not so much the MTU
get_mtu() {
	CUR_MTU=$(cat /sys/class/net/$1/mtu)
	#sqm_logger "IFACE: ${1} MTU: ${CUR_MTU}"
	echo ${CUR_MTU}
}

get_flows() {

    if [ "${AUTOFLOW}" -eq "1" ]
    then
      case $QDISC in
			     codel|ns2_codel|pie|*fifo|pfifo_fast) ;;
           fq_codel|*fq_codel|sfq) echo flows $( get_flows_count ${1} ) ;;
      esac
    fi

}

get_flows_count() {

    FLOWS=8
	  [ $1 -gt 999 ] && FLOWS=16
    [ $1 -gt 2999 ] && FLOWS=32
	  [ $1 -gt 7999 ] && FLOWS=48
    [ $1 -gt 9999 ] && FLOWS=64
    [ $1 -gt 19999 ] && FLOWS=128
    [ $1 -gt 39999 ] && FLOWS=256
    [ $1 -gt 69999 ] && FLOWS=512
    [ $1 -gt 99999 ] && FLOWS=1024
    case $QDISC in
      codel|ns2_codel|pie|*fifo|pfifo_fast) ;;
      fq_codel|*fq_codel|sfq) echo $FLOWS ;;
    esac

}

# set the target parameter, also try to only take well formed inputs
# Note, the link bandwidth in the current direction (ingress or egress)
# is required to adjust the target for slow links
get_target() {
	local CUR_TARGET=${1}
	local CUR_LINK_KBPS=${2}
	[ ! -z "$CUR_TARGET" ] && sqm_logger "cur_target: ${CUR_TARGET} cur_bandwidth: ${CUR_LINK_KBPS}"
	CUR_TARGET_STRING=
	# either e.g. 100ms or auto
	CUR_TARGET_VALUE=$( echo ${CUR_TARGET} | grep -o -e \^'[[:digit:]]\+' )
	CUR_TARGET_UNIT=$( echo ${CUR_TARGET} | grep -o -e '[[:alpha:]]\+'\$ )
	#[ ! -z "$CUR_TARGET" ] && sqm_logger "CUR_TARGET_VALUE: $CUR_TARGET_VALUE"
	#[ ! -z "$CUR_TARGET" ] && sqm_logger "CUR_TARGET_UNIT: $CUR_TARGET_UNIT"

	AUTO_TARGET=
	UNIT_VALID=

	case $QDISC in
		*codel|*pie)
			if [ ! -z "${CUR_TARGET_VALUE}" -a ! -z "${CUR_TARGET_UNIT}" ];
    			then
    			    case ${CUR_TARGET_UNIT} in
    				    # permissible units taken from: tc_util.c get_time()
				    s|sec|secs|ms|msec|msecs|us|usec|usecs)
					CUR_TARGET_STRING="target ${CUR_TARGET_VALUE}${CUR_TARGET_UNIT}"
					UNIT_VALID="1"
					;;
			    esac
			fi
			# empty field in GUI or undefined GUI variable now defaults to auto
			if [ -z "${CUR_TARGET_VALUE}" -a -z "${CUR_TARGET_UNIT}" ];
    			then
				if [ ! -z "${CUR_LINK_KBPS}" ];
				then
				    TMP_TARGET_US=$( adapt_target_to_slow_link $CUR_LINK_KBPS )
				    TMP_INTERVAL_STRING=$( adapt_interval_to_slow_link $TMP_TARGET_US )
				    CUR_TARGET_STRING="target ${TMP_TARGET_US}us ${TMP_INTERVAL_STRING}"
				    AUTO_TARGET="1"
				    sqm_logger "get_target defaulting to auto."
			    	else
				    sqm_logger "required link bandwidth in kbps not passed to get_target()."
				fi
			fi
			# but still allow explicit use of the keyword auto for backward compatibility
                        case ${CUR_TARGET_UNIT} in
                            auto|Auto|AUTO)
                                if [ ! -z "${CUR_LINK_KBPS}" ];
                                then
                                    TMP_TARGET_US=$( adapt_target_to_slow_link $CUR_LINK_KBPS )
                                    TMP_INTERVAL_STRING=$( adapt_interval_to_slow_link $TMP_TARGET_US )
                                    CUR_TARGET_STRING="target ${TMP_TARGET_US}us ${TMP_INTERVAL_STRING}"
                                    AUTO_TARGET="1"
                                else
                                    sqm_logger "required link bandwidth in kbps not passed to get_target()."
                                fi
                            ;;
                        esac

			case ${CUR_TARGET_UNIT} in
			    default|Default|DEFAULT)
				if [ ! -z "${CUR_LINK_KBPS}" ];
				then
				    CUR_TARGET_STRING=""	# return nothing so the default target is not over-ridden...
				    AUTO_TARGET="1"
				    #sqm_logger "get_target using qdisc default, no explicit target string passed."
			    	else
			    	    sqm_logger "required link bandwidth in kbps not passed to get_target()."
			        fi
			    ;;
			esac
			if [ ! -z "${CUR_TARGET}" ];
			    then
			    if [ -z "${CUR_TARGET_VALUE}" -o -z "${UNIT_VALID}" ];
			    then
				[ -z "$AUTO_TARGET" ] && sqm_logger "${CUR_TARGET} is not a well formed tc target specifier; e.g.: 5ms (or s, us), or one of the strings auto or default."
			    fi
			fi
		    ;;
	esac
#	sqm_logger "target: ${CUR_TARGET_STRING}"
	echo $CUR_TARGET_STRING
}

# for low bandwidth links fq_codels default target of 5ms does not work too well
# so increase target for slow links (note below roughly 2500kbps a single packet will \
# take more than 5 ms to be tansfered over the wire)
adapt_target_to_slow_link() {
    CUR_LINK_KBPS=$1
    CUR_EXTENDED_TARGET_US=
    MAX_PAKET_DELAY_IN_US_AT_1KBPS=$(( 1000 * 1000 * 1540 * 8 / 1000 ))
    CUR_EXTENDED_TARGET_US=$(( ${MAX_PAKET_DELAY_IN_US_AT_1KBPS} / ${CUR_LINK_KBPS} ))	# note this truncates the decimals
    # do not change anything for fast links
    [ "$CUR_EXTENDED_TARGET_US" -lt 5000 ] && CUR_EXTENDED_TARGET_US=5000
    case ${QDISC} in
        *codel|pie)
	    echo "${CUR_EXTENDED_TARGET_US}"
	    ;;
    esac
}

# codel looks at a whole interval to figure out wether observed latency stayed below target
# if target >= interval that will not work well, so increase interval by the same amonut that target got increased
adapt_interval_to_slow_link() {
    CUR_TARGET_US=$1
    case ${QDISC} in
        *codel)
            CUR_EXTENDED_INTERVAL_US=$(( (100 - 5) * 1000 + ${CUR_TARGET_US} ))
	    echo "interval ${CUR_EXTENDED_INTERVAL_US}us"
	    ;;
	pie)
	    ## not sure if pie needs this, probably not
	    #CUR_EXTENDED_TUPDATE_US=$(( (30 - 20) * 1000 + ${CUR_TARGET_US} ))
	    #echo "tupdate ${CUR_EXTENDED_TUPDATE_US}us"
	    ;;
    esac
}


# set quantum parameter if available for this qdisc
get_quantum() {
    case $QDISC in
	*fq_codel|fq_pie|drr) echo quantum $1 ;;
	*) ;;
    esac
}

# only show limits to qdiscs that can handle them...
# Note that $LIMIT contains the default limit
get_limit() {
    CURLIMIT=$1
    case $QDISC in
    *codel|*pie|pfifo_fast|sfq|pfifo) [ -z ${CURLIMIT} ] && CURLIMIT=${LIMIT}	# use the global default limit
        ;;
    bfifo) [ -z "$CURLIMIT" ] && [ ! -z "$LIMIT" ] && CURLIMIT=$(( ${LIMIT} * $( cat /sys/class/net/${IFACE}/mtu ) ))	# bfifo defaults to txquelength * MTU,
        ;;
    *) sqm_logger "${QDISC} does not support a limit"
        ;;
    esac
    sqm_logger "get_limit: $1 CURLIMIT: ${CURLIMIT}"

    if [ ! -z "$CURLIMIT" ]
    then
    echo "limit ${CURLIMIT}"
    fi
}

get_ecn() {
    CURECN=$1
    #sqm_logger CURECN: $CURECN
	case ${CURECN} in
		ECN)
			case $QDISC in
				*codel|*pie|*red)
				    CURECN=ecn
				    ;;
				*)
				    CURECN=""
				    ;;
			esac
			;;
		NOECN)
			case $QDISC in
				*codel|*pie|*red)
				    CURECN=noecn
				    ;;
				*)
				    CURECN=""
				    ;;
			esac
			;;
		*)
		    sqm_logger "ecn value $1 not handled"
		    ;;
	esac
	#sqm_logger "get_ECN: $1 CURECN: ${CURECN} IECN: ${IECN} EECN: ${EECN}"
	echo ${CURECN}

}

# This could be a complete diffserv implementation

diffserv() {

interface=$1
prio=1

# Catchall

$TC filter add dev $interface parent 1:0 protocol all prio 999 u32 \
        match ip protocol 0 0x00 flowid 1:12

# Find the most common matches fast
#fc_pppoe() instead of fc() with effectice ingress classification for pppoe is very expensive and destroys LUL

fc 1:0 0x00 1:12 # BE
fc 1:0 0x20 1:13 # CS1
fc 1:0 0x10 1:11 # IMM
fc 1:0 0xb8 1:11 # EF
fc 1:0 0xc0 1:11 # CS3
fc 1:0 0xe0 1:11 # CS6
fc 1:0 0x90 1:11 # AF42 (mosh)

# Arp traffic
$TC filter add dev $interface protocol arp parent 1:0 prio $prio handle 500 fw flowid 1:11


prio=$(($prio + 1))


}

diffserv_pppoe() {

interface=$1
prio=1

# Catchall

$TC filter add dev $interface parent 1:0 protocol all prio 999 u32 \
        match ip protocol 0 0x00 flowid 1:12

# Find the most common matches fast
#fc_pppoe() instead of fc() with effectice ingress classification for pppoe is very expensive and destroys LUL

fc_pppoe 1:0 0x00 1:12 # BE
fc_pppoe 1:0 0x20 1:13 # CS1
fc_pppoe 1:0 0x10 1:11 # IMM
fc_pppoe 1:0 0xb8 1:11 # EF
fc_pppoe 1:0 0xc0 1:11 # CS3
fc_pppoe 1:0 0xe0 1:11 # CS6
fc_pppoe 1:0 0x90 1:11 # AF42 (mosh)

# Arp traffic
$TC filter add dev $interface protocol arp parent 1:0 prio $prio handle 500 fw flowid 1:11


prio=$(($prio + 1))


}

eth_setup() {

    ethtool -K $IFACE gso off
    ethtool -K $IFACE tso off
    ethtool -K $IFACE ufo off
    ethtool -K $IFACE gro off

    if [ -e /sys/class/net/$IFACE/queues/tx-0/byte_queue_limits ]
    then
       for i in /sys/class/net/$IFACE/queues/tx-*/byte_queue_limits
       do
          echo $(( 4 * $( get_mtu ${IFACE} ) )) > $i/limit_max
       done
    fi

}
