# You need to jiggle these parameters. Note limits are tuned towards a <10Mbit uplink <60Mbup down

[ -z "$UPLINK" ] && UPLINK=2302
[ -z "$DOWNLINK" ] && DOWNLINK=14698
[ -z "$IFACE" ] && IFACE=eth0
[ -z "$QDISC" ] && QDISC=fq_codel
[ -z "$LLAM" ] && LLAM="tc_stab"
[ -z "$LINKLAYER" ] && LINKLAYER="none"
[ -z "$OVERHEAD" ] && OVERHEAD=0
[ -z "$STAB_MTU" ] && STAB_MTU=2047
[ -z "$STAB_MPU" ] && STAB_MPU=0
[ -z "$STAB_TSIZE" ] && STAB_TSIZE=512
[ -z "$AUTOFLOW" ] && AUTOFLOW=0
[ -z "$LIMIT" ] && LIMIT=1001	# sane global default for *LIMIT for fq_codel on a small memory device
[ -z "$ILIMIT" ] && ILIMIT=
[ -z "$ELIMIT" ] && ELIMIT=
[ -z "$ITARGET" ] && ITARGET=
[ -z "$ETARGET" ] && ETARGET=
[ -z "$IECN" ] && IECN="ECN"
[ -z "$EECN" ] && EECN="ECN"
[ -z "$SQUASH_DSCP" ] && SQUASH_DSCP="1"
[ -z "$SQUASH_INGRESS" ] && SQUASH_INGRESS="1"
[ -z "$IQDISC_OPTS" ] && IQDISC_OPTS=""
[ -z "$EQDISC_OPTS" ] && EQDISC_OPTS=""
[ -z "$TC" ] && TC=$(which tc)
#[ -z "$TC" ] && TC="sqm_logger tc"# this redirects all tc calls into the log
[ -z "$IP" ] && IP=$(which ip)
[ -z "$INSMOD" ] && INSMOD=$(which insmod)
[ -z "$TARGET" ] && TARGET="5ms"
[ -z "$IPT_MASK" ] && IPT_MASK="0xff"
[ -z "$IPT_MASK_STRING" ] && IPT_MASK_STRING="/${IPT_MASK}"	# for set-mark
#sm: we need the functions above before trying to set the ingress IFB device
[ -z "$DEV" ] && DEV=$( get_ifb_for_if ${IFACE} )      # automagically get the right IFB device for the IFACE"
