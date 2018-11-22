# The sqm-scripts traffic shaper

[![DOI](https://zenodo.org/badge/36661217.svg)](https://zenodo.org/badge/latestdoi/36661217)

This repository contains the sqm-scripts traffic shaper from the CeroWrt
project. See:
http://www.bufferbloat.net/projects/cerowrt/wiki/Smart_Queue_Management

## Installing
`sudo make install` should install things on a regular Linux box. For
OpenWrt, there are packages available in the ceropackages repository:
https://github.com/dtaht/ceropackages-3.10 and in openwrt nightly
builds as well as in the main packages repository (https://github.com/openwrt/packages/tree/master/net/sqm-scripts).

## "Installing" the current development version from git

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
SQM_DEBUG controls whether sqm will log all binary invocations, their output and its shell output into a log file in `/var/run/sqm`.
The log files are named `/var/run/sqm/${interface_name}.debug.log` e.g. `/var/run/sqm/pppoe-ge00.debug.log`.

#### Examples

- Log only the binary invocations and their output:

    `/etc/init.d/sqm stop ; SQM_DEBUG=1 SQM_VERBOSITY_MAX=0 /etc/init.d/sqm start`

- Log verbose debug output and all the binary invocations and their output:

    `/etc/init.d/sqm stop ; SQM_DEBUG=1 SQM_VERBOSITY_MAX=8 /etc/init.d/sqm start`

- Log both start and stop:

    `SQM_DEBUG=1 SQM_VERBOSITY_MAX=8 /etc/init.d/sqm stop ; SQM_DEBUG=1 SQM_VERBOSITY_MAX=8 /etc/init.d/sqm start`

Note: This always appends to the log file(s). If you just run a one-off
command with debugging enabled from the command line this is fine, but
if you enable debugging in the web interface, the files can grow too
large and cause problems. So if you do enable debugging in the web
interface, remember to turn it back off again.
