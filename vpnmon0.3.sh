#!/bin/sh

#VPNMON 0.3 (VPNMON.SH) is a simple script that accompanies my VPNON.SH script, which compliments @JackYaz's VPNMGR 
#program to maintain a NordVPN setup. This script checks your 5 VPN connections on a regular interval to see if one 
#is connected, and sends a ping to a host of your choice through the active connection.  If it finds that connection
#has been lost, it will execute the script of your choice (in this case, VPNON.SH), which will kill all VPN clients, 
#and use VPNMGR's functionality to poll NordVPN for updated server names based on the locations you have selected in
#VPNMGR, and randomly picks one of the 5 VPN Clients to connect to. 

# Variables (Feel free to change)
TRIES=3              # Number of times to retry a ping - default = 3 tries
INTERVAL=30         # How often it should check your VPN connections - default = 30 seconds
PINGHOST="8.8.8.8"   # Which host you want to use to ping to determine if VPN connection is up - default, Google DNS
CALLSCRIPT="/jffs/scripts/vpnon.sh" # This is my default script that resets VPN connections, and uses VPNMGR to 
				    # reassign new NordVPN connections

# System Variables (Do not change)
LOCKFILE="/jffs/scripts/VPNON-Lock.txt" # Predefined lockfile that VPNON.sh creates when it resets the VPN so that
					# VPNMON does not interfere and possibly causes another reset
connState="2"        # Status = 2 means VPN is successfully connected, 1 is connecting, and 0 is not connected
STATUS=0             # Tracks whether or not a ping was successful
VPNCLCNT=0	     # Tracks to make sure there are not multiple connections running
CNT=0                # Counter
state1=0	     # Initialize the VPN connection states for VPN Clients 1-5
state2=0
state3=0
state4=0
state5=0

#Display title/version
echo -e "\nVPNMON v0.3\n"

while true; do

  while test -f "$LOCKFILE"; do
    echo -e "VPNON is currently resetting the VPN. Trying again in 10 seconds...\n"
    sleep 10
  done

  # Show the date and time
  echo $(date)

  # Determine if a VPN Client is active, first by getting the VPN state from NVRAM
  state1=$(nvram get vpn_client1_state)
  state2=$(nvram get vpn_client2_state)
  state3=$(nvram get vpn_client3_state)
  state4=$(nvram get vpn_client4_state)
  state5=$(nvram get vpn_client5_state)

  # Check each connection to see if its active, and perform a PING... borrowed heavily + credit to @Martineau for this code
  #VPN1
  if [[ $state1 -eq $connState ]]
  then
      #echo "VPN1 $state1"
         while [ $CNT -lt $TRIES ]; do
	  	ping -I tun11 -q -c 1 -W 2 $PINGHOST > /dev/null
		RC=$?
		if [ $RC -eq 0 ];then
					STATUS=1
					VPNCLCNT=$((VPNCLCNT+1))
					echo "VPN1 Ping is alive" #Status: $STATUS"
					break
				else
					sleep 1
					CNT=$((CNT+1))
				fi
		done
  else
      echo "VPN1 Disconnected"
  fi

  #VPN2
  if [[ $state2 -eq $connState ]]
  then
      #echo "VPN2 $state2"
         while [ $CNT -lt $TRIES ]; do
	  	ping -I tun12 -q -c 1 -W 2 $PINGHOST > /dev/null
		RC=$?
		if [ $RC -eq 0 ];then
					STATUS=1
					VPNCLCNT=$((VPNCLCNT+1))
					echo "VPN2 Ping is alive" #Status: $STATUS"
					break
				else
					sleep 1
					CNT=$((CNT+1))
				fi
		done
  else
      echo "VPN2 Disconnected"
  fi

  #VPN3
  if [[ $state3 -eq $connState ]]
  then
      #echo "VPN3 $state3"
         while [ $CNT -lt $TRIES ]; do
	  	ping -I tun13 -q -c 1 -W 2 $PINGHOST > /dev/null
		RC=$?
		if [ $RC -eq 0 ];then
					STATUS=1
					VPNCLCNT=$((VPNCLCNT+1))
					echo "VPN3 Ping is alive" #Status: $STATUS"
					break
				else
					sleep 1
					CNT=$((CNT+1))
				fi
		done
  else
      echo "VPN3 Disconnected"
  fi

  #VPN4
  if [[ $state4 -eq $connState ]]
  then
      #echo "VPN4 $state4"
         while [ $CNT -lt $TRIES ]; do
	  	ping -I tun14 -q -c 1 -W 2 $PINGHOST > /dev/null
		RC=$?
		if [ $RC -eq 0 ];then
					STATUS=1
					VPNCLCNT=$((VPNCLCNT+1))
					echo "VPN4 Ping is alive" #Status: $STATUS"
					break
				else
					sleep 1
					CNT=$((CNT+1))
				fi
		done
  else
      echo "VPN4 Disconnected"
  fi

  #VPN5
  if [[ $state5 -eq $connState ]]
  then
      #echo "VPN5 $state5"
         while [ $CNT -lt $TRIES ]; do
	  	ping -I tun15 -q -c 1 -W 2 $PINGHOST > /dev/null
		RC=$?
		if [ $RC -eq 0 ];then
					STATUS=1
					VPNCLCNT=$((VPNCLCNT+1))
					echo "VPN5 Ping is alive" #Status: $STATUS"
					break
				else
					sleep 1
					CNT=$((CNT+1))
				fi
		done
  else
      echo "VPN5 Disconnected"
  fi

  #If STATUS remains 0 then reset the VPN
	if [ $STATUS -ne 1 ]; then
		echo "Connection has failed, VPNMON is executing script to reset VPN"
		sh $CALLSCRIPT
		echo -e "\nVPNMON is letting the VPN settle for 30 seconds\n"
                sleep 30
		echo -e "\nResuming VPNMON"
	fi

  #If VPNCLCNT is greater than 1 there are multiple connections running, reset the VPN
	if [ $VPNCLCNT -gt 1 ]; then
		echo "Multiple VPN Client Connections detected, VPNMON is executing script to reset VPN"
		sh $CALLSCRIPT
		echo -e "\nVPNMON is letting the VPN settle for 30 seconds\n"
                sleep 30
		echo -e "\nResuming VPNMON"
	fi


echo -e "\r"

sleep $INTERVAL

#Reset Variables
STATUS=0
VPNCLCNT=0
state1=0
state2=0
state3=0
state4=0
state5=0

done

exit 0
