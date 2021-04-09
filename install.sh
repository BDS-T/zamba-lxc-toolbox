#!/bin/bash

# This script will create and fire up a standard debian buster lxc container on your Proxmox VE.
# On a Proxmox cluster, the script will create the container on the local node, where it's executed.
# The container ID will be automatically assigned by increasing (+1) the highest number of
# existing LXC containers in your environment. If the assigned ID is already taken by a VM
# or no containers exist yet, the script falls back to the ID 100.

# Authors:
# (C) 2021 Idea an concept by Christian Zengel <christian@sysops.de>
# (C) 2021 Script design and prototype by Markus Helmke <helmke@cloudistboese.de>
# (C) 2021 Script rework by Thorsten Spille <thorsten@spille-edv.de>

# IMPORTANT NOTE:
# Please adjust th settings in 'zamba.conf' to your needs before running the script

############### ZAMBA INSTALL SCRIPT ###############

# Load configuration file
source ./zamba.conf

# CHeck is the newest template available, else download it.
DEB_LOC=$(pveam list $LXC_TEMPLATE_STORAGE | grep debian-10-standard | cut -d'_' -f2)
DEB_REP=$(pveam available --section system | grep debian-10-standard | cut -d'_' -f2)

if [[ $DEB_LOC == $DEB_REP ]];
then
  echo "Newest Version of Debian 10 Standard $DEP_REP exists.";
else
  echo "Will now download newest Debian 10 Standard $DEP_REP.";
  pveam download $LXC_TEMPLATE_STORAGE debian-10-standard_$DEB_REP\_amd64.tar.gz
fi

# Get next free LXC-number
LXC_LST=$( lxc-ls | egrep -o '.{1,5}$' )
LXC_CHK=$((LXC_LST+1));

if  [ $LXC_CHK -lt 100 ] || [ -f /etc/pve/qemu-server/$LXC_CHK.conf ]; then
  LXC_NBR=$(pvesh get /cluster/nextid);
else
  LXC_NBR=$LXC_CHK;
fi
echo "Will now create LXC Container $LXC_NBR!";

# Create the container
pct create $LXC_NBR -unprivileged $LXC_UNPRIVILEGED $LXC_TEMPLATE_STORAGE:vztmpl/debian-10-standard_$DEB_REP\_amd64.tar.gz -rootfs $LXC_ROOTFS_STORAGE:$LXC_ROOTFS_SIZE;
sleep 2;

# Check vlan configuration
if [[ $LXC_VLAN != "" ]];then
  VLAN=",vlan=$LXC_VLAN"
else
 VLAN=""
fi
# Reconfigure conatiner
pct set $LXC_NBR -memory $LXC_MEM -swap $LXC_SWAP -hostname $LXC_HOSTNAME \-nameserver $LXC_DNS -searchdomain $LXC_DOMAIN -onboot 1 -timezone Europe/Berlin -net0 name=eth0,bridge=$LXC_BRIDGE,firewall=1,gw=$LXC_GW,ip=$LXC_IP,type=veth$VLAN;
sleep 2;

PS3="Select the Server-Function: "

select opt in just_lxc zmb-standalone zmb-member zmb-pdc mailpiler matrix quit; do
  case $opt in
    just_lxc)
      echo "Debian-only LXC container selected"
      break
      ;;
    zmb-standalone)
      echo "Selected Zamba standalone"
      echo "This function is not implemented yet! Exiting..."
      # TODO: write script for Zamba Standalone
      exit 1
      ;;
    zmb-member)
      echo "Configuring LXC container '$opt'!"
      pct set $LXC_NBR -mp0 $LXC_SHAREFS_STORAGE:$LXC_SHAREFS_SIZE,mp=/$LXC_SHAREFS_MOUNTPOINT
      sleep 2;
      break
      ;;
    zmb-pdc)
      echo "Selected Zamba AD DC"
      # TODO: write script for Zamba AD DC
      echo "This function is not implemented yet! Exiting..."
      exit 1
      ;;
    mailpiler)
      echo "Configuring LXC container for '$opt'!"
      pct set $LXC_NBR -features nesting=1
      sleep 2;
      break
      ;;
    matrix)
      echo "Install Matrix chat server and element web service"
      break
      ;;
    quit)
      echo "Script aborted by user interaction."
      exit 0
      ;;
    *)
      echo "Invalid option! Exiting..."
      exit 1
      ;;
    esac
done


lxc-start $LXC_NBR;
sleep 5;
# Set the root password and key
echo -e "$LXC_PWD\n$LXC_PWD" | lxc-attach -n$LXC_NBR passwd;
lxc-attach -n$LXC_NBR mkdir /root/.ssh;
echo -e "$LXC_AUTHORIZED_KEY" | lxc-attach -n$LXC_NBR tee /root/.ssh/authorized_keys;
# usually not needed after adding authorized_keys: 
# lxc-attach -n$LXC_NBR systemctl restart ssh.service
pct push $LXC_NBR ./zamba.conf /root/zamba.conf
pct push $LXC_NBR ./$opt.sh /root/$opt.sh
echo "Install '$opt'!"
lxc-attach -n$LXC_NBR bash /root/$opt.sh