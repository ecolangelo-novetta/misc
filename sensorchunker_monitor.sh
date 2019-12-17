#!/bin/bash

# This script will look for sensors that have gone sour within a specified amount of time (usually 1 minute and ran as cron 1 min)
# It will kill the specific sensorchunker pid, effectively forcing executor to restart the sensorchunker process
#
# Install to cron:
# */1 * * * * /bin/bash /path/to/sensorchunker_monitor.sh
#
# Log file:
# /root/sensorchunker_monitor.log (or ~/sensorchunker_monitor.log)
#
#

### Script Variables
LOG_TIMESTAMP=$(date "+%b $(date "+%d" | sed 's/^0/ /g') %H:%M:%S")

# Minutes for which the script uses the previous $MINS from executor.log (default 1)
MINS=1 

## Function
kill_sensorchunker () {

  # Input the sensor UUID we want to find & kill the PID for associated sensorchunker process
  SENSORC_ID=$1

  # Set SENSORC_PID to the PID of the sensorchunker process we want to kill
  SENSORC_PID=$(ps aux | grep sensorchunker | grep $SENSORC_ID | awk '{print $2}')
  
  # Kill SENSORC_PID (comment out this line if you just want to report sensors that went sour)
  kill -9 $SENSORC_PID
  
  # Log this event
  echo "$LOG_TIMESTAMP - Sensorchunker process [$SENSORC_PID] with UUID [$SENSORC_ID] killed ..." >> /root/sensorchunker_monitor.log && exit

}

### Begin script primary code

# Ensure script is being ran as root
if [[ $EUID -ne 0 ]]; then
        echo "*** ERROR: This script must be ran as root."
        exit 1
fi

# Start with fresh temp files
[[ -f /tmp/sensorchunker_monitor.nopackets ]] && rm /tmp/sensorchunker_monitor.nopackets
[[ -f /tmp/sensorchunker_monitor.deadsensors ]] && rm /tmp/sensorchunker_monitor.deadsensors

# I. Filter 'chunks: received no packets in 10 seconds' from executor.log. This is what we want to use.
grep 'chunks: received no packets in 10 seconds' /var/log/executor/executor.log > /tmp/sensorchunker_monitor.nopackets

# II. Filter /tmp/sensorchunker_monitor.nopackets to only return log timestamp lines within $MINS of history
D1=$(date --date="-$MINS min" "+%b $(date "+%d" | sed 's/^0/ /g') %H:%M:%S")
D2=$(date "+%b $(date "+%d" | sed 's/^0/ /g') %H:%M:%S")
while read -r line; do
  [[ $line > $D1 && $line < $D2 || $line =~ $D2 ]] && echo $line >> /tmp/sensorchunker_monitor.deadsensors
done < /tmp/sensorchunker_monitor.nopackets

# III. Kill (or report) sensorchunkers individually from the above temp file which forces executor to restart the sensorchunkers

if [[ ! -f /tmp/sensorchunker_monitor.deadsensors ]]; then echo "$LOG_TIMESTAMP - No dead sensors to report ..." >> /root/sensorchunker_monitor.log; exit 0; fi
while read -r line; do
  [[ $line > $D1 && $line < $D2 || $line =~ $D2 ]] && kill_sensorchunker $(echo $line | awk '{print $7}' | sed 's/sensorchunker-//g' | sed 's/://g')
  done < /tmp/sensorchunker_monitor.deadsensors
  
