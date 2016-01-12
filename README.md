# The sqm-scripts traffic shaper

This repository contains the sqm-scripts traffic shaper from the CeroWrt
project. See:
http://www.bufferbloat.net/projects/cerowrt/wiki/Smart_Queue_Management

## Installing
`sudo make install` should install things on a regular Linux box. For
OpenWrt, there are packages available in the ceropackages repository:
https://github.com/dtaht/ceropackages-3.10 and in openwrt nightly
builds.

## "Installing" the current development version from git

0.) Make a local clone of the git repository (if you have not already):

`git clone https://github.com/tohojo/sqm-scripts`

1.) Change into the new directory:

`cd ./sqm-scripts`

2.) Make sure the source is updated:

`git pull`

3.) Create a directory containing the distribution files (PLATFORM is either linux or openwrt.):

`make install PLATFORM=openwrt DESTDIR=./$your_distribution_directory_here`

4.) Then just copy the contents of ./$your_distribution_directory_here onto the to be sqm'd computer. 

`cd ./$your_distribution_directory_here`

5.) Note for openwrt this will overwrite your specific /etc/config/sqm, so make sure to conserve your configuration file before. For openwrt this can be achieved by locally deleting the default config file in $your_distribution_directory_here first:

`rm -r etc/config`

6.) Now, update to the current state:

`scp -r ./* $USER@YOUR.SQM.HOSTNAME:/`

Note: `$something` is used as a stand-in for the real information, e.g.: `$your_distribution_directory_here` could be be `current_sqm_base`; `$USER` on openwrt most likely should be `root`; and `$YOUR.SQM.HOSTNAME` probably is `192.168.1.1` or on cerowrt `gw.hom.lan`.

## Run-time debugging

SQM_VERBOSITY controls the verbosity of sqm's output to the shell and syslog (0: no logging; 8: full debug output).
SQM_DEBUG controlls whether sqm will log all binary invocations, their output and its shel output into a log file in `/var/run/sqm`.
The log files are named `/var/run/sqm/${interface_name}.debug.log` e.g. `/var/run/sqm/pppoe-ge00.debug.log`.

### Examples

1) Log only the binary invocations and their output:
`/etc/init.d/sqm stop ; SQM_DEBUG=1 SQM_VERBOSITY=0 /etc/init.d/sqm start`

2) Log verbose debug output and all the binary invocations and their output:
`/etc/init.d/sqm stop ; SQM_DEBUG=1 SQM_VERBOSITY=8 /etc/init.d/sqm start`

3) Log both start and stop:
`SQM_DEBUG=1 SQM_VERBOSITY=8 /etc/init.d/sqm stop ; SQM_DEBUG=1 SQM_VERBOSITY=8 /etc/init.d/sqm start`

Note: This always appens to the log file(s), so manual intervention is required to save/delete these log files before they get too large.
