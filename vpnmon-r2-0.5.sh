#!/bin/sh

#VPNMON-R2 v0.5 (VPNMON-R2.SH) is an all-in-one simple script which compliments @JackYaz's VPNMGR program to maintain a
#NordVPN/PIA/WeVPN setup, though this is not a requirement, and can function without problems in a standalone environment.
#This script checks your (up to) 5 VPN connections on a regular interval to see if one is connected, and sends a ping to a
#host of your choice through the active connection.  If it finds that connection has been lost, it will execute a series of
#commands that will kill all VPN clients, and optionally use VPNMGR's functionality to poll NordVPN/PIA/WeVPN for updated
#server names based on the locations you have selected in VPNMGR, optionally whitelists all US-based NordVPN servers in the
#Skynet Firewall, and randomly picks one of the 5 VPN Clients to connect to. Logging added to capture relevant events for
#later review.  As mentioned, disabling VPNMGR and Skynet functionality is completely supported should you be using other
#VPN options, and as such, this script would help maintain an eye on your connection, and able to randomly reset it if
#needed.


# User-Selectable Variables (Feel free to change)
TRIES=3                                 # Number of times to retry a ping - default = 3 tries
INTERVAL=30                             # How often it should check your VPN connections - default = 30 seconds
PINGHOST="8.8.8.8"                      # Which host you want to use to ping to determine if VPN connection is up
LOGFILE="/jffs/scripts/vpnmon-r2.log"   # Logfile path/name that captures important date/time events - change to:
                                        # "/dev/null" to disable this functionality.
UpdateVPNMGR=1                          # This variable checks to see whether you want to integrate more deeply with
                                        # VPNMGR, and should only do so if you're running NordVPN, PIA or WeVPN. Enabling
                                        # this calls VPNMGR-specific scripts to update your VPN Client configs. Disabling
                                        # this function would make VPNMON-R2 compatible with any other VPN setup.
                                        # Default = 1, change to 0 to disable.
UpdateSkynet=1                          # This variable checks to see whether or not to update Skynet Firewall whitelist
                                        # with NordVPN IPs.  Default = 1, change to 0 to disable.
let N=5                                 # Number of configured VPN Clients to choose from, max = 5 on Asus 86U
let BASE=1                              # Random numbers start at BASE up to N, ie. 1..3
ResetOption=1                           # Do you want VPNMON-R2 to run a daily reset?  1=yes, 0=no
DailyResetTime="01:00"                  # Time at which you choose to randomly reset your VPN clients in 24H HH:MM format

# System Variables (Do not change)
Version="0.5"                           # Current version of VPNMON-R2
LOCKFILE="/jffs/scripts/VPNON-Lock.txt" # Predefined lockfile that VPNON.sh creates when it resets the VPN so that
                                        # VPNMON-R2 does not interfere and possibly causes another reset during a reset
RSTFILE="/jffs/scripts/vpnmon-rst.log"  # Logfile containing the last date/time a VPN reset was performed.  If none exists
                                        # then the latest date/time that VPNMON-R2 restarted will be indicated.
connState="2"                           # Status = 2 means VPN is connected, 1 is connecting, and 0 is not connected
STATUS=0                                # Tracks whether or not a ping was successful
VPNCLCNT=0                              # Tracks to make sure there are not multiple connections running
CNT=0                                   # Counter
AVGPING=0                               # Average ping value
state1=0                                # Initialize the VPN connection states for VPN Clients 1-5
state2=0
state3=0
state4=0
state5=0
START=$(date +%s)                       # Start a timer to determine intervals of VPN resets

# Color variables
CBlack="\e[1;30m"
CRed="\e[1;31m"
CGreen="\e[1;32m"
InvGreen="\e[1;42m"
CYellow="\e[1;33m"
CBlue="\e[1;34m"
InvBlue="\e[1;44m"
CMagenta="\e[1;35m"
CCyan="\e[1;36m"
CWhite="\e[1;37m"
CClear="\e[0m"

# -----------------------------------------------------------------------------------------------------------
# Functions
# -----------------------------------------------------------------------------------------------------------

# Spinner is a script that provides a small indicator on the screen to show script activity
spinner() {

  i=0
  j=$((INTERVAL / 4))
  while [ $i -le $j ]; do
    for s in / - \\ \|; do
      printf "\r$s"
      sleep 1
    done
    i=$((i+1))
  done

  printf "\r"
}

# VPNReset() is a script based on my VPNON.SH script to kill connections and reconnect to a clean VPN state
vpnreset() {

  # Start the VPN reset process
    echo -e "$(date) - VPNMON-R2 - Executing VPN Reset" >> $LOGFILE

  # Start the process
    echo -e "${CCyan}Step 1 - Kill all VPN Client Connections\n${CClear}"

  # Kill all current VPN client sessions
    echo -e "${CRed}Kill VPN Client 1${CClear}"
      service stop_vpnclient1
    echo -e "${CRed}Kill VPN Client 2${CClear}"
      service stop_vpnclient2
    echo -e "${CRed}Kill VPN Client 3${CClear}"
      service stop_vpnclient3
    echo -e "${CRed}Kill VPN Client 4${CClear}"
      service stop_vpnclient4
    echo -e "${CRed}Kill VPN Client 5${CClear}"
      service stop_vpnclient5
    echo -e "$(date) - VPNMON-R2 - Killed all VPN Client Connections" >> $LOGFILE

  # Export NordVPN IPs via API into a txt file, and import them into Skynet
    if [[ $UpdateSkynet -eq 1 ]]
    then
          echo -e "\n${CCyan}Step 2 - Updating Skynet whitelist with NordVPN Server IPs (US-based)\n${CClear}"
          curl --silent "https://api.nordvpn.com/v1/servers?limit=16384" | jq --raw-output '.[] | select(.locations[].country.name == "United States") | .station' > /jffs/scripts/NordVPN-US.txt
          firewall import whitelist /jffs/scripts/NordVPN-US.txt
          echo -e "\n${CCyan}VPNMON-R2 is letting Skynet import and settle for 10 seconds\n${CClear}"
                  sleep 10
          rm /jffs/scripts/NordVPN-US.txt  #Cleanup
          echo -e "$(date) - VPNMON-R2 - Updated Skynet Whitelist" >> $LOGFILE
    else
          echo -e "\n${CCyan}Step 2 - Skipping Skynet whitelist update with NordVPN Server IPs (US-based)\n${CClear}"
    fi

  # Call VPNMGR functions to refresh server lists and save their results to the VPN client configs
    if [[ $UpdateVPNMGR -eq 1 ]]
    then
          echo -e "${CCyan}Step 3 - Refresh VPNMGRs NordVPN/PIA/WeVPN Server Locations and Hostnames\n${CClear}"
          sh /jffs/scripts/service-event start vpnmgrrefreshcacheddata
                  sleep 10
          sh /jffs/scripts/service-event start vpnmgr
                  sleep 10
          echo -e "$(date) - VPNMON-R2 - Refreshed VPNMGR Server Locations and Hostnames" >> $LOGFILE
    else
          echo -e "\n${CCyan}Step 3 - Skipping VPNMGR update for NordVPN/PIA/WeVPN Server Locations and Hostname\n${CClear}"
    fi

  # Pick a random VPN Client to connect to
    echo -e "${CCyan}Step 4 - Randomly select a VPN Client between 1 and $N\n${CClear}"

  # Generate a number between BASE and N, ie.1 and 5 to choose which VPN Client is started
    RANDOM=$(awk 'BEGIN {srand(); print int(32768 * rand())}')
    option=$(( RANDOM % N + BASE ))

  # Set option to 1 in that rare case that it comes out to 0
    if [[ $option -eq 0 ]]
      then
      option=1
    fi

  # Start the selected VPN Client
    case ${option} in

      1)
          service start_vpnclient1
          logger -t VPN client1 "on"
          echo -e "${CGreen}VPN Client 1 ON\n${CClear}"
          echo -e "$(date) - VPNMON-R2 - Randomly selected VPN1 Client ON" >> $LOGFILE
      ;;

      2)
          service start_vpnclient2
          logger -t VPN client2 "on"
          echo -e "${CGreen}VPN Client 2 ON\n${CClear}"
          echo -e "$(date) - VPNMON-R2 - Randomly selected VPN2 Client ON" >> $LOGFILE
      ;;

      3)
          service start_vpnclient3
          logger -t VPN client3 "on"
          echo -e "${CGreen}VPN Client 3 ON\n${CClear}"
          echo -e "$(date) - VPNMON-R2 - Randomly selected VPN3 Client ON" >> $LOGFILE
      ;;

      4)
          service start_vpnclient4
          logger -t VPN client4 "on"
          echo -e "${CGreen}VPN Client 4 ON\n${CClear}"
          echo -e "$(date) - VPNMON-R2 - Randomly selected VPN4 Client ON" >> $LOGFILE
      ;;

      5)
          service start_vpnclient5
          logger -t VPN client5 "on"
          echo -e "${CGreen}VPN Client 5 ON\n${CClear}"
          echo -e "$(date) - VPNMON-R2 - Randomly selected VPN5 Client ON" >> $LOGFILE
      ;;

    esac

    echo -e "${CCyan}VPNMON-R2 VPN Reset finished\n${CClear}"
    echo -e "$(date) - VPNMON-R2 - VPN Reset Finished" >> $LOGFILE

}

# checkvpn() is a script that checks each connection to see if its active, and performs a PING... borrowed
# heavily and much credit to @Martineau for this code from his VPN-Failover script.
checkvpn() {

  CNT=0
  VPNSTATE=$(nvram get vpn_client$1_state)
  TUN="tun1"$1

  if [[ $VPNSTATE -eq $connState ]]
  then
        while [ $CNT -lt $TRIES ]; do
        ping -I $TUN -q -c 1 -W 2 $PINGHOST &> /dev/null
        RC=$?
        if [ $RC -eq 0 ];then
                    STATUS=1
                    VPNCLCNT=$((VPNCLCNT+1))
                    AVGPING=$(ping -I $TUN -c 1 $PINGHOST | awk -F'time=| ms' 'NF==3{print $(NF-1)}' | sort -rn)
                    echo -e "${CGreen}VPN$1 Tunnel is active | ||${CBlack}${InvGreen} $AVGPING ms ${CClear}${CGreen}|| | ${CClear}  ${CYellow}Int: ${InvBlue}$INTERVAL Sec${CClear}"
                    break
                else
                    sleep 1
                    CNT=$((CNT+1))

                    if [[ $CNT -eq $TRIES ]];then
                      STATUS=0
                      echo -e "${CRed}VPN$1 Ping failed${CClear}"
                      echo -e "$(date) - VPNMON-R2 - VPN$1 Ping failed" >> $LOGFILE
                    fi
                fi
        done
  else
      echo "VPN$1 Disconnected"
  fi
}

# Begin VPNMON-R2 Main Loop ------------------------------------------------------------------------------

while true; do

  # Testing to see if a VPN Reset Date/Time Logfile exists or not, and if not, creates one
    if [ -f $RSTFILE ]
      then
          #Read in its contents for the date/time of last reset
          START=$(cat $RSTFILE)
      else
          #Create a new file with a new date/time of when VPNMON-R2 restarted, not sure when VPN last reset
          echo -e "$(date +%s)" > $RSTFILE
          START=$(cat $RSTFILE)
    fi

  # Testing to see if VPNON is currently running, and if so, hold off until it finishes
    while test -f "$LOCKFILE"; do
      echo -e "${CRed}VPNON is currently performing a scheduled reset of the VPN. Trying again in 10 seconds...${CClear}\n"
      echo -e "$(date +%s)" > $RSTFILE
      START=$(cat $RSTFILE)
      sleep 10
    done

  # Testing to see if a reset needs to run at the scheduled time, first by pulling our hair out to find a timeslot to
  # run this thing, by looking at current time and the scheduled time, converting to epoch seconds, and seeing if it
  # falls between scheduled time + 2 * the number of interval seconds, to ensure there's enough of a gap to check for
  # this if it happens to be in a sleep loop.

    if [[ $ResetOption -eq 1 ]]
      then
        currentepoch=$(date +%s)
        ConvDailyResetTime=$(date -d $DailyResetTime +%H:%M)
        ConvDailyResetTimeEpoch=$(date -d $ConvDailyResetTime +%s)
        variance=$(( $ConvDailyResetTimeEpoch + (( $INTERVAL*2 ))))

        if [[ $currentepoch -gt $ConvDailyResetTimeEpoch && $currentepoch -lt $variance ]]
          then
            echo -e "\n${CRed}VPNMON-R2 is executing a scheduled VPN Reset${CClear}\n"
            echo -e "$(date) - VPNMON-R2 - Executing scheduled VPN Reset" >> $LOGFILE

            vpnreset

            echo -e "\n${CCyan}Resuming VPNMON-R2 in T minus $INTERVAL${CClear}\n"
            echo -e "$(date) - VPNMON-R2 - Resuming normal operations" >> $LOGFILE
            echo -e "$(date +%s)" > $RSTFILE
            START=$(cat $RSTFILE)

            spinner
       fi
    fi

  # Calculate days, hours, minutes and seconds between VPN resets
    END=$(date +%s)
    SDIFF=$((END-START))
    LASTVPNRESET=$(printf '%dd %02dh:%02dm:%02ds\n' $(($SDIFF/86400)) $(($SDIFF%86400/3600)) $(($SDIFF%3600/60)) $(($SDIFF%60)))

  # clear screen
    clear

  # Display title/version
    echo -e "\n${CGreen}VPNMON-R2 v$Version${CClear}\n"

  # Show the date and time
    echo -e "${CYellow}$(date) ------- Last Reset: ${InvBlue}$LASTVPNRESET${CClear}"

  # Determine if a VPN Client is active, first by getting the VPN state from NVRAM
    state1=$(nvram get vpn_client1_state)
    state2=$(nvram get vpn_client2_state)
    state3=$(nvram get vpn_client3_state)
    state4=$(nvram get vpn_client4_state)
    state5=$(nvram get vpn_client5_state)

    if [[ $ResetOption -eq 1 ]]
      then
        echo -e "${CCyan}VPN State 1:$state1 2:$state2 3:$state3 4:$state4 5:$state5${CClear}${CYellow} ----- Sched Reset: ${InvBlue}$ConvDailyResetTime${CClear}"
      else
        echo -e "${CCyan}VPN State 1:$state1 2:$state2 3:$state3 4:$state4 5:$state5${CClear}"
    fi

    echo -e "${CGreen}---------------------------------------------------------------${CClear}"

  # Cycle through the CheckVPN function for N number of VPN Clients
    i=0
    while [ $i -ne $N ]
      do
        i=$(($i+1))

        checkvpn $i

    done

    echo -e "${CGreen}---------------------------------------------------------------${CClear}"

  # If STATUS remains 0 then reset the VPN
    if [ $STATUS -eq 0 ]; then
        echo -e "\n${CRed}Connection has failed, VPNMON-R2 is executing VPN Reset${CClear}\n"
        echo -e "$(date) - VPNMON-R2 - Connection failed, executing VPN Reset" >> $LOGFILE

        vpnreset

        echo -e "\n${CCyan}Resuming VPNMON-R2 in T minus $INTERVAL${CClear}\n"
        echo -e "$(date) - VPNMON-R2 - Resuming normal operations" >> $LOGFILE
        echo -e "$(date +%s)" > $RSTFILE
        START=$(cat $RSTFILE)
    fi

  # If VPNCLCNT is greater than 1 there are multiple connections running, reset the VPN
    if [ $VPNCLCNT -gt 1 ]; then
        echo -e "\n${CRed}Multiple VPN Client Connections detected, VPNMON-R2 is executing VPN Reset${CClear}\n"
        echo -e "$(date) - VPNMON-R2 - Multiple VPN Client Connections detected, executing VPN Reset" >> $LOGFILE

        vpnreset

        echo -e "\n${CCyan}Resuming VPNMON-R2 in T minus $INTERVAL ${CClear}\n"
        echo -e "$(date) - VPNMON-R2 - Resuming normal operations" >> $LOGFILE
        echo -e "$(date +%s)" > $RSTFILE
        START=$(cat $RSTFILE)
    fi

    echo -e "\r"

  # Provide a spinner to show script activity

    spinner

  #Reset Variables
    STATUS=0
    VPNCLCNT=0
    CNT=0
    AVGPING=0
    state1=0
    state2=0
    state3=0
    state4=0
    state5=0

done

exit 0
