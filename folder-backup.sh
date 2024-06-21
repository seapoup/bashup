#!/bin/bash

###                     
### Tars a folder (lz4 compressed) and sends it to another location, keeping at most a predefined number of copies
###

ssd_loc="/home/user/folder" # folder to backup
zfs_loc="/pool/filesystem/backups" # folder to send backup to
time_interval=("weekly" "monthly" "yearly" "daily")
time_index=($(date +%w) $(date +%d) $(date +%j)) # example output: 5 02 153
backup_time=(0 01 001) # enter desired backup times [Sun (0) - Sat (6); Day (01-30); Yearday (001-366)]
backup_qty=(4 6 3 7) # enter desired backup quantities (weekly, monthly, yearly, daily)

if [ ! -e $zfs_loc ] ; then
    for archive in ${time_interval[@]}
    do
        mkdir -pv $zfs_loc/$archive       # create intervals if nonexistent
    done
fi

for archive in ${!time_interval[@]}
do
    if [[ "${time_index[$archive]}" == "${backup_time[$archive]}" ]] ; then # compare if time_interval matches desired backup_time, otherwise (also) daily backup as both are empty
        interval=${time_interval[$archive]}                              # assign backup interval variable
        # mkdir $zfs_loc/$interval/$(date +"%Y-%m-%d-%H-%M-%S")            #create timestamped folder
        echo "creating $interval folder backup of $ssd_loc"
        tar cfp - $ssd_loc | lz4 - "$zfs_loc/$interval/$(date +"%Y-%m-%d-%H-%M-%S").tar.lz4" # copy from ssd to zfs under timestamp
        while (($(ls $zfs_loc/$interval |wc -l) > ${backup_qty[$archive]})) ;                  # loop while surpassing archive capacity
            do echo "removing $interval backup of $(ls -rt $zfs_loc/$interval | head -n 1)" 
            rm -rf $zfs_loc/$interval/$(ls -rt $zfs_loc/$interval | head -n 1)  # remove oldest backup
            echo "$(ls $zfs_loc/$interval |wc -l) $interval backups remaining"
        done
    fi
done
