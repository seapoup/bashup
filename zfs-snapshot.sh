#!/bin/bash

#
# Creates an encrypted ZFS snapshot, prunes existing local snapshots, increment all remaining existing snapshots,
# 'compress' snapshots (will be removed in future version) and optionally rsync them offsite
#

backup_location="pool"
backup_dataset="filesystem"
snapshot_filesystem="$backup_location/$backup_dataset"
snapshot_location="/$backup_location/backup/snapshots/$backup_dataset"
archive_location="/$backup_location/backup/archives/$backup_dataset"
remote_ip="12.345.678.910"
remote_username="username"
remote_location="/remote-pool/filesystem/$backup_dataset"
time_interval=("weekly" "monthly" "yearly" "daily")
time_index=($(date +%w) $(date +%d) $(date +%j)) # example output: 5 02 153
timestamp=$(date +"%Y-%m-%d_%H-%M-%S")
snapshot_qty=(4 6 3 7)                        # enter desired snapshot quantities (weekly (4), monthly (6), yearly (3), daily (7))
snapshot_time=(0 01 001)                      # enter desired backup times [Sun (0) - Sat (6); Day (01-30); Yearday (001-366)]

# Create folder hierarchy
if [ ! -e $snapshot_location ] ; then
    for archive in ${time_interval[@]}
    do
        mkdir -pv $snapshot_location/$archive
        mkdir -pv $archive_location/$archive
    done
fi

# 0. Create snapshot 
zfs snapshot $snapshot_filesystem@$backup_dataset\_$timestamp
echo "Creating snapshot $snapshot_filesystem@${backup_dataset}_$timestamp"
snapshot_latest=$(zfs list -t snapshot | cut -d \  -f 1 | tail -n -1)
snapshot_latest_name=$(echo $snapshot_latest | awk -F '@' '{print $NF}')

# 1. Prune snapshots archive
for archive in ${!time_interval[@]}
do
    if [[ "${time_index[$archive]}" == "${snapshot_time[$archive]}" ]] ; then # compare if interval_time matches desired backup_time, otherwise (also) daily backup as both are empty
        interval=${time_interval[$archive]}                              # assign snapshot interval variable
        echo "Archiving $interval snapshot $snapshot_latest"
        zfs send --raw $snapshot_latest > $snapshot_location/$interval/$snapshot_latest_name # archive newest snapshot
        echo "Pruning snapshots archive:"
        while (($(ls $snapshot_location/$interval |wc -l) > ${snapshot_qty[$archive]})) ;    # loop while surpassing archive capacity
            do echo "removing $interval snapshot of $(ls -rt $snapshot_location/$interval | head -n 1)" 
            rm -rf $snapshot_location/$interval/$(ls -rt $snapshot_location/$interval | head -n 1)  # remove oldest snapshot
            echo "$(ls -rt $archive_location/$interval | head -n 1) destroyed"
            rm -rf $archive_location/$interval/$(ls -rt $archive_location/$interval | head -n 1)  # remove oldest archive
            echo "$(ls $snapshot_location/$interval |wc -l) $interval snapshots remaining"
        done
    fi
done
        
# 2. List all files in snapshot folder recursively, thus including all daily, weekly, monthly, yearly snapshots
local_snapshots_disk=$(find $snapshot_location -type f -exec echo "{}" \; | awk -F '/' '{print $NF}')
echo -e "listing local snapshot files:\r\n$local_snapshots_disk"

# 3. Compare filenames in snapshot folder with zfs list -t snapshot
local_snapshots_zfs=$(zfs list -t snapshot | cut -d \  -f 1 | awk -F '@' '{print $NF}' | awk 'NR>1')
echo -e "listing local zfs snapshots:\r\n$local_snapshots_zfs"
    
# 4. Destroy all excess snapshots in zfs system locally: others are stored offsite
echo "Pruning snapshots in zfs system:"
for snapshot in $local_snapshots_zfs
do
    if [[ "$local_snapshots_disk" == *"$snapshot"* ]]; then   
        echo $snapshot "found in local snapshot storage, kept" # Confirm existence of relevant snapshots
    else
        echo $snapshot "not found in local snapshot storage, destroyed" 
        zfs destroy $snapshot_filesystem@$snapshot # Delete old snapshots
    fi
done

# 5. Increment all existing snapshots locally by overwriting file directly
local_snapshots_zfs=$(zfs list -t snapshot | cut -d \  -f 1 | awk -F '@' '{print $NF}' | awk 'NR>1') # Revaluate after deleting snapshots
echo "Latest snapshot is $snapshot_latest"
for snapshot in $local_snapshots_zfs
do  
    interval_update=$(find $snapshot_location -name $snapshot -exec echo "{}" \; | awk -F'\/' '{print $(NF-1)}') # returns daily/weekly etc.
    for interval in $interval_update
    do
        echo "Archiving updated $interval snapshot of $snapshot "
        zfs send --raw $snapshot_filesystem@$snapshot > $snapshot_location/$interval/$snapshot
        tar cfp - $snapshot_location/$interval/$snapshot | lz4 -f - $archive_location/$interval/$snapshot.tar.lz4
    done
done

# 6. Send snapshots offsite # Uncomment to activate
# echo "Performing remote sync to $remote_username@$remote_ip:$remote_location"
# rsync -e "ssh -i /home/user/.ssh/public_key_rsa" -Cavz --delete $archive_location 
# $remote_username@$remote_ip:$remote_location
