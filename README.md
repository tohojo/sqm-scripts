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
