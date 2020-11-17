# The sqm-scripts traffic shaper

[![DOI](https://zenodo.org/badge/36661217.svg)](https://zenodo.org/badge/latestdoi/36661217)

This repository contains the sqm-scripts traffic shaper from the CeroWrt
project. See:
http://www.bufferbloat.net/projects/cerowrt/wiki/Smart_Queue_Management

## Requirements

To run sqm-scripts you just need a Linux machine with a kernel from the last
decade or so (any of the longterm releases on kernel.org should work - please
don't run a kernel that is not a currently released version, longterm or
current). The only exception is that if you want to use the `cake` qdisc, you
either need kernel 4.19 or newer (with matching `iproute2` version), or you need
to build CAKE yourself from the out-of-tree repository at
https://github.com/dtaht/sch_cake.

## Installing
`sudo make install` should install things on a regular Linux box. For
OpenWrt, there are packages available in the distribution, so just install the
sqm-scripts package, and optionally luci-app-sqm for GUI support.

## Running on regular Linux distributions
After installing using `make install`, do the following to enable sqm-scripts:

1. Copy `/etc/sqm/default.conf` to `/etc/sqm/<dev>.iface.conf` where `<dev>` is
   the name of the interface you wish to run sqm-scripts on. Then adjust the
   values in the file to your environment, setting at least UPLINK, DOWNLINK,
   and possibly SCRIPT.

2. If you're on a Debian-derived distribution that uses old-style network config
   in `/etc/network/`, the Makefile should detect this and drop in appropriate
   hotplug scripts, so sqm-script should automatically run on the next 'ifup'.

3. If you're on a systemd-enabled distro, just enable the `sqm@<dev>` service
   corresponding to your interface name. E.g., for `eth0`, issue `systemctl
   enable sqm@eth0` (and run `systemctl start sqm@eth0` to start sqm-scripts
   immediately).

## "Installing" the current development version from git on OpenWrt

Run the steps below on your own computer (not on the router) to retrieve the newest script version from this repository, create the scripts, then copy those new scripts to your router.

1. Make a local clone of the git repository (if you have not already):

    `git clone https://github.com/tohojo/sqm-scripts`

2. Change into the new directory:

    `cd ./sqm-scripts`

3. Make sure the source is updated:

    `git pull`

4. Create the scripts for your platform (PLATFORM is either linux or openwrt) and output them to a local `current_sqm_base` directory:

    `make install PLATFORM=openwrt DESTDIR=./current_sqm_base`

5. Change to `./current_sqm_base`:

    `cd ./current_sqm_base`

6. Optional for OpenWrt: The final step will overwrite your router's current sqm configuration file (at `/etc/config/sqm`). If you want to preserve the current configuration, delete the newly created config file from the local `etc/config`:

    `rm -r etc/config`

7. Now, use scp to copy the new scripts to the router. Change `$YOUR.SQM.HOSTNAME` to the address/DNS name for your computer - probably `192.168.1.1` or on cerowrt `gw.hom.lan`. If your account on the router is not "root", change "root" to your account:


    `scp -r ./* root@$YOUR.SQM.HOSTNAME:/`

Note this method relies on the presence of the required qdiscs on the router/destination host. On openwrt, you should first install the "normal" sqm-scripts package to take care of all the dependencies, then use this procedure to update to the newest sqm-scripts.

## Run-time debugging

SQM_VERBOSITY_MAX controls the verbosity of sqm's output to the shell and syslog (0: no logging; 8: full debug output).
SQM_DEBUG controls whether sqm will log the output of the last invocation of start-sqm into  `var/run/sqm/${interface_name}.start-sqm.log` and the ouput of the last invocation of stop-sqm into `var/run/sqm/${interface_name}.stop-sqm.log` e.g. for pppoe-wan `/var/run/sqm/pppoe-wan.start-sqm.log` and `/var/run/sqm/pppoe-wan.stop-sqm.log`.

#### Examples

- Log only the binary invocations and their output:

    `/etc/init.d/sqm stop ; SQM_DEBUG=1 SQM_VERBOSITY_MAX=0 /etc/init.d/sqm start`

- Log verbose debug output and all the binary invocations and their output:

    `/etc/init.d/sqm stop ; SQM_DEBUG=1 SQM_VERBOSITY_MAX=8 /etc/init.d/sqm start`

- Log both start and stop:

    `SQM_DEBUG=1 SQM_VERBOSITY_MAX=8 /etc/init.d/sqm stop ; SQM_DEBUG=1 SQM_VERBOSITY_MAX=8 /etc/init.d/sqm start`

Note: Both the start and stop log are re-written on every sqm instance start and stop and are logging all output independent of the value of `SQM_VERBOSITY_MAX`. They will not grow indefintely, but they are written repeatedly. On reliably rewritable media like hard disk, ssd, flash with wear-leveling, or ram-disk, `SQM_DEBUG` can be safely set to 1 in `defaults.sh`, but on media like NOR flash that do only allow few write-cycles, keeping the default at 0 and using the above invocations to run a single instance with `SQM_DEBUG=1` is recommended.
