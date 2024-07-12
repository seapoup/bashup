# bashup
Collection of shell scripts to safeguard data 

Bashup is intended to serve as a backup solution for NASs, run as scheduled tasks:  
`zfs-snapshot.sh` creates ZFS snapshots of data, which can be sent offsite and used to restore data to an earlier point in time;  
`folder-backup.sh` simply creates an LZ4 compressed tarball of a given folder.

Why Bashup?
Bashup can provide complete immortality to your data, as long as at least one snapshot exists. On top of that it uses the *[`--raw`](https://openzfs.github.io/openzfs-docs/man/master/8/zfs-send.8.html#w~2)* sending implementation of OpenZFS so that data can be sent to untrusted machines. 

Therefore, it provides:
* Incremental snapshots;
* Encryption;
* Offsite storage.

Requirements:
* ZFS pool

Optional (but heavily recommended):
* Empty filesystems;
* Encrypted filesystems;
* SSH keys to remote system.

# Preparation
* Create an encrypted filesystem and REMEMBER the passphrase:
`zfs create -o encryption=on -o keylocation=prompt -o keyformat=passphrase pool/filesystem`

# Example
1. Make sure that your desired configuration is applied in settings.cfg
2. Run the script over an empty filesystem
`bash ./zfs-snapshot.sh`
3. Write random data to the filesystem (e.g. 480 MiB)
`dd if=/dev/zero of=/poolposition/test/data1.tmp bs=16M count=30`
4. Run the script again
`bash ./zfs-snapshot.sh`
5. Repeat this procedure a number of times. In the default configuration 7 daily snapshots are kept. The script is designed to be run once a day. Thus, the eighth snapshot should toss the oldest (i.e. first) snapshot. For example, the data folder structure after 7 snapshots may look like:
```
/pool/test:
total 4.3G
-rw-r--r-- 1 root root 480M Jul 11 23:48 data1.tmp
-rw-r--r-- 1 root root 800M Jul 11 23:49 data2.tmp
-rw-r--r-- 1 root root 160M Jul 11 23:50 data3.tmp
-rw-r--r-- 1 root root 960M Jul 11 23:50 data4.tmp
-rw-r--r-- 1 root root 320M Jul 11 23:51 data5.tmp
-rw-r--r-- 1 root root 640M Jul 11 23:52 data6.tmp
```
Similarly, the snapshot folder structure may look like:
``` 
/pool/backup/test/daily:
total 12G
-rw-r--r-- 1 root users  22K Jul 11 23:52 test_2024-07-11_23-47-00
-rw-r--r-- 1 root users 482M Jul 11 23:52 test_2024-07-11_23-49-13
-rw-r--r-- 1 root users 1.3G Jul 11 23:52 test_2024-07-11_23-49-52
-rw-r--r-- 1 root users 1.5G Jul 11 23:52 test_2024-07-11_23-50-04
-rw-r--r-- 1 root users 2.4G Jul 11 23:52 test_2024-07-11_23-50-29
-rw-r--r-- 1 root users 2.7G Jul 11 23:52 test_2024-07-11_23-51-14
-rw-r--r-- 1 root users 3.3G Jul 11 23:53 test_2024-07-11_23-52-16
```
Note the increasing size of the snapshots. ZFS snapshots are created *[atomically](https://openzfs.github.io/openzfs-docs/man/master/8/zfs-snapshot.8.html)*, including only  "modifications to the dataset made by system calls that have successfully completed before that point in time". Therefore the pre-existing snapshots are incremented every time. Besides that, all data present BEFORE the first snapshot is made cannot be recovered later (if lost).  
6. Adding more data (~1 GiB) and running the script again deletes the oldest snapshot of its respective category (e.g. `daily`), while, of course, maintaining all the data:
```
total 4.3G
-rw-r--r-- 1 root root 480M Jul 11 23:48 data1.tmp
-rw-r--r-- 1 root root 800M Jul 11 23:49 data2.tmp
-rw-r--r-- 1 root root 160M Jul 11 23:50 data3.tmp
-rw-r--r-- 1 root root 960M Jul 11 23:50 data4.tmp
-rw-r--r-- 1 root root 320M Jul 11 23:51 data5.tmp
-rw-r--r-- 1 root root 640M Jul 11 23:52 data6.tmp
-rw-r--r-- 1 root root 960M Jul 12 00:06 data7.tmp
```
And the snapshot folder:
```
/poolposition/backup/test/daily:
total 16G
-rw-r--r-- 1 root users 482M Jul 12 00:10 test_2024-07-11_23-49-13
-rw-r--r-- 1 root users 1.3G Jul 12 00:10 test_2024-07-11_23-49-52
-rw-r--r-- 1 root users 1.5G Jul 12 00:10 test_2024-07-11_23-50-04
-rw-r--r-- 1 root users 2.4G Jul 12 00:10 test_2024-07-11_23-50-29
-rw-r--r-- 1 root users 2.7G Jul 12 00:10 test_2024-07-11_23-51-14
-rw-r--r-- 1 root users 3.3G Jul 12 00:10 test_2024-07-11_23-52-16
-rw-r--r-- 1 root users 4.3G Jul 12 00:11 test_2024-07-12_00-09-59
```
7. Oh no! Your system burnt/flooded/ransomwared and you have to rebuild from scratch. Fortunately you had a copy of the snapshot file offsite. That means that, for the sake of illustration:
your filesystem and internal snapshots are gone: `zfs destroy -r poolposition/test`
Note that a filesystem cannot be recovered if the system still contains said filesystem, or snapshots thereof.
7a. If you simply would like to rollback to an existing snapshot, use the *[`zfs rollback`](https://openzfs.github.io/openzfs-docs/man/master/8/zfs-rollback.8.html)* command instead. 
8. Let's say you would like to return up to and until data4.tmp. After returning the offsite snapshot to your system, you can restore the filesystem.
`zfs receive -F pool/test < /pool/backup/test/daily/test_2024-07-11_23-50-29`
9. If the filesystem is encrypted, the encryption keys will not be automatically loaded and the filesystem will not be mounted. Remember, if your encryption key (passphrase) is gone, your data is gone.
`zfs load-key pool/test`
`zfs mount pool/test`
10. Et voila, the data is back up to data4.tmp
```
/pool/test:
total 2.4G
-rw-r--r-- 1 root root 480M Jul 11 23:48 data1.tmp
-rw-r--r-- 1 root root 800M Jul 11 23:49 data2.tmp
-rw-r--r-- 1 root root 160M Jul 11 23:50 data3.tmp
-rw-r--r-- 1 root root 960M Jul 11 23:50 data4.tmp
```

# Troubleshooting
The encryption keys of filesystems may not be loaded after a reboot. Therefore, check if all encrypted filesystem are mounted after rebooting by `zfs list -o name,mountpoint,mounted`. Otherwise, load the keys and mount.

# Justification
* Why bashup?  
There are plenty of neat backup solutions available, though none of them combine FOSS, incremental backups, encryption and offsite-backups.

* Why is the built-in incremental feature of openZFS not used (i.e. `zfs send -i`)?  
bashup checks the internal ZFS snapshots with those that exist on disk. The internal ZFS snapshots are copied ('sent') straight to the backup folder. Therefore, they are always equal. Besides that, the archived snapshots all function independently, providing multiple options as 'restore points'. The disadvantage of this is that the daily updated snapshots overwrite their old versions with the same name, where the entire datastream is copied. 
`zfs send -i` send only the incremental stream of two snapshots compared to each other. Thus, to be able to perform a restore this way, ALL individual incremental streams are required, where no intermediate incremental streams can go missing or corrupt. 

* Why does bashup not use compression?  
Encrypted datasets are only marginably (losslessly) compressible, thus not worth the cpu cycles.

## Under construction
Insert a sanity check in zfs-snapshot.sh if settings.cfg is in the same folder, otherwise abort  
Insert a sanity check if bashup=found in settings.cfg, otherwise abort  
Moving uncommented rsync of zfs-snapshot.sh to its own script  
Moving variables of folder-backup.sh to settings.cfg
