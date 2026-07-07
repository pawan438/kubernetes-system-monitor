#!/bin/bash

#creating a variable to store log path
LOG_FILE="/app/health.log"

#creating function to store date and time in log file
log_message(){
        echo "[$(date +'%d-%m-%Y %H:%M')] $1" >> "$LOG_FILE" # $1=passes only one argument
        echo "[$(date +'%d-%m-%Y %H:%M')] $1"
}

#cheking ngnix is active or not
#commented out for Docker version - systemctl/systemd not available inside plain containers
# systemctl is-active --quiet nginx
# STATUS=$?
#
# echo "Exit code = $STATUS"
#
# if [ $STATUS -ne 0 ]; then #respons if ngnix server isnt running or facing any error
#
#     log_message "CRITICAL: NGINX IS DEAD,RESTART"
#     exit 1
# fi

#cpu usage check("%.0f) for floating number
CPU_USAGE=$(top -bn 1 | grep "Cpu(s)" |awk '{printf "%.0f",$2}') #-bn 1 checks the process only one time than exits.
echo "CPU=$CPU_USAGE"
if [ "$CPU_USAGE" -gt 85 ]; then #checks if usage is greater than 85 it prints
       log_message "CRITICAL:CPU USAGE IS TOO HIGH ${CPU_USAGE}%"
       exit 1
fi


#ram usage check(NR==2)use for row number
RAM_USAGE=$(free -h|awk 'NR==2 {printf "%.0f",($3/$2)*100}') #NR==2 checks the roe no.2
echo "RAM=$RAM_USAGE"
if [ "$RAM_USAGE" -gt 85 ]; then #checks if usage is greater than 85 it prints
       log_message "CRITICAL:RAM USAGE IS TOO HIGH ${RAM_USAGE}%"
       exit 1
fi

#Disk usage check(sed s/%// -this cmd removes the % sign)
DISK_USAGE=$( df -h / | awk 'NR==2 {printf "%.0f",$5}'|sed 's/%//') # checks the disk usage
echo "DISK=$DISK_USAGE"
if [ "$DISK_USAGE" -gt 85 ]; then #checks if usage is greater than 85 it prints
       log_message "CRITICAL:DISK USAGE IS TOO HIGH ${DISK_USAGE}%"
       exit 1
fi

#log error detecting
if grep -i -q "error" "$LOG_FILE"; then #-i=case insensetive
         log_message "CRITICAL:ISSUE FOUND IN LOG MESSAGE"
         exit 1
fi

#final message print 
log_message "STATUS OKAY"
     exit 0
