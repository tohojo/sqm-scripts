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
# Try modprobe first, fall back to insmod
[ -z "$INSMOD" ] && INSMOD=$(which modprobe) || INSMOD=$(which insmod)
[ -z "$TARGET" ] && TARGET="5ms"
[ -z "$IPT_MASK" ] && IPT_MASK="0xff"
[ -z "$IPT_MASK_STRING" ] && IPT_MASK_STRING="/${IPT_MASK}"	# for set-mark
#sm: we need the functions above before trying to set the ingress IFB device
#sm: *_CAKE_OPTS should contain the diffserv keyword for cake
[ -z "$INGRESS_CAKE_OPTS" ] && INGRESS_CAKE_OPTS="diffserv4"
[ -z "$EGRESS_CAKE_OPTS" ] && EGRESS_CAKE_OPTS="diffserv4"

# This is used for writing the state file
ALL_SQM_VARS="IFACE UPLINK DOWNLINK SCRIPT ENABLED QDISC LLAM LINKLAYER OVERHEAD STAB_MTU STAB_MPU STAB_TSIZE AUTOFLOW ILIMIT ELIMIT TARGET ITARGET ETARGET IECN EECN SQUASH_DSCP SQUASH_INGRESS IQDISC_OPTS EQDISC_OPTS INGRESS_CAKE_OPTS EGRESS_CAKE_OPTS"

# These are the modules that do_modules() will attempt to load
ALL_MODULES="act_ipt sch_$QDISC sch_ingress act_mirred cls_fw cls_flow cls_u32 sch_htb sch_hfsc"
