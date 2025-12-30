Exchange files between two machines (id "a" and id "b") using a shared server as a relay.

## How it works
- Each id has its own incoming queue on the server.
- Enqueue uploads files to the other id's queue.
- Dequeue downloads everything for the current id and removes the files from the server.

## Requirements
- bash
- rsync
- ssh

## Example
```bash
$ QSYNC_ID=a qsync enqueue /tmp/qsync-test1.txt /tmp/qsync-test2.txt 
Enqueue: a -> b via user@host
qsync-test1.txt
             44 100%    0.00kB/s    0:00:00 (xfr#1, to-chk=0/1)
qsync-test2.txt
             44 100%    0.00kB/s    0:00:00 (xfr#1, to-chk=0/1)
Done.

$ qsync status
Server queues on user@host:/srv/qsync

Incoming queue for 'a':
<empty>

Incoming queue for 'b':
total 8.0K
-rw------- 1 user user 44 Dec 30 06:46 2025-12-30T064635Z--qsync-test1.txt
-rw------- 1 user user 44 Dec 30 06:45 2025-12-30T064635Z--qsync-test2.txt

$ QSYNC_ID=b qsync dequeue /tmp/
Dequeue: b -> a via user@host
2025-12-30T064635Z--qsync-test1.txt
             44  50%   42.97kB/s    0:00:00 (xfr#1, to-chk=1/3)
2025-12-30T064635Z--qsync-test2.txt
             88 100%   14.32kB/s    0:00:00 (xfr#2, to-chk=0/3)
Done.
```
