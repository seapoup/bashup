#!/bin/bash

#
# Creates an encrypted ZFS snapshot, prunes existing local snapshots, increment all remaining existing snapshots,
# 'compress' snapshots (will be removed in future version) and optionally rsync them offsite
#

# Call variables from the settings file
source settings.cfg

# Create logs folder
if [ ! -e $bashup_directory ] ; then
    mkdir -pv "$bashup_directory/logs"
fi

# Create snapshot folder hierarchy
if [ ! -e $snapshot_location ] ; then
    for archive in ${time_interval[@]}
    do
        mkdir -pv $snapshot_location/$archive
    done
fi

# Create snapshot 
zfs snapshot $snapshot_filesystem@$backup_dataset\_$timestamp
tee $log_latest <<< "$timestamp"
tee -a $log_latest <<< "Creating snapshot $snapshot_filesystem@${backup_dataset}_$timestamp"
snapshot_latest=$(zfs list -t snapshot | grep $snapshot_filesystem@$backup_dataset | cut -d \  -f 1 | tail -n -1)
snapshot_latest_name=$(echo $snapshot_latest | awk -F '@' '{print $NF}')

# Prune snapshots archive
for archive in ${!time_interval[@]}
do
    if [[ "${time_index[$archive]}" == "${snapshot_time[$archive]}" ]] ; then # compare if interval_time matches desired backup_time, otherwise (also) daily backup as both are empty
        interval=${time_interval[$archive]}                              # assign snapshot interval variable
        tee -a $log_latest <<< "Archiving $interval snapshot $snapshot_latest"
        zfs send --raw $snapshot_latest > $snapshot_location/$interval/$snapshot_latest_name # archive newest snapshot
        tee -a $log_latest <<< "Pruning snapshots archive:"
        while (($(ls $snapshot_location/$interval |wc -l) > ${snapshot_qty[$archive]})) ;    # loop while surpassing archive capacity
            do tee -a $log_latest <<< "removing $interval snapshot of $(ls -rt $snapshot_location/$interval | head -n 1)" 
            rm -rf $snapshot_location/$interval/$(ls -rt $snapshot_location/$interval | head -n 1)  # remove oldest snapshot
            tee -a $log_latest <<< "$(ls $snapshot_location/$interval |wc -l) $interval snapshots remaining"
        done
    fi
done
        
# List all files in snapshot folder recursively, thus including all daily, weekly, monthly, yearly snapshots
local_snapshots_disk=$(find $snapshot_location -type f -exec echo "{}" \; | awk -F '/' '{print $NF}')
tee -a $log_latest <<< "listing local snapshot files:\r\n$local_snapshots_disk"

# Compare filenames in snapshot folder with zfs list -t snapshot
local_snapshots_zfs=$(zfs list -t snapshot | grep $snapshot_filesystem@$backup_dataset | cut -d \  -f 1 | awk -F '@' '{print $NF}')
tee -a $log_latest <<< "listing local zfs snapshots:\r\n$local_snapshots_zfs"
    
# Destroy all excess snapshots in zfs system locally: others are stored offsite
tee -a $log_latest <<< "Pruning snapshots in zfs system:"
for snapshot in $local_snapshots_zfs
do
    if [[ "$local_snapshots_disk" == *"$snapshot"* ]]; then   
        tee -a $log_latest <<< "$snapshot found in local snapshot storage, kept" # Confirm existence of relevant snapshots
    else
        tee -a $log_latest <<< "$snapshot not found in local snapshot storage, destroyed" 
        zfs destroy $snapshot_filesystem@$snapshot # Delete old snapshots
    fi
done

# Increment all existing snapshots locally by overwriting file directly
local_snapshots_zfs=$(zfs list -t snapshot | grep $snapshot_filesystem@$backup_dataset | cut -d \  -f 1 | awk -F '@' '{print $NF}') # Revaluate after deleting snapshots
tee -a $log_latest <<< "Latest snapshot is $snapshot_latest"
for snapshot in $local_snapshots_zfs
do  
    interval_update=$(find $snapshot_location -name $snapshot -exec echo "{}" \; | awk -F'\/' '{print $(NF-1)}') # returns daily/weekly etc.
    for interval in $interval_update
    do
        tee -a $log_latest <<< "Archiving updated $interval snapshot of $snapshot"
        zfs send --raw $snapshot_filesystem@$snapshot > $snapshot_location/$interval/$snapshot
    done
done

# 6. Send snapshots offsite # Uncomment to activate
# echo "Performing remote sync to $remote_username@$remote_ip:$remote_location"
# rsync -e "ssh -i /home/user/.ssh/public_key_rsa" -Cavz --delete $snapshot_location 
# $remote_username@$remote_ip:$remote_location
