#!/bin/sh

PATH="/sbin:/usr/sbin:/usr/local/sbin:/bin:/usr/bin:/usr/local/bin"
LOCATION="$(cd -P -- "$(dirname -- "$0")" && pwd -P)/.."
HN=`/bin/hostname`
DATE=`date "+%Y-%m-%d-%H%M%S"`

LLOG=""
INCREM=""

RSYNCBIN=`which rsync`

# read configuration
if [ -f "$LOCATION/etc/rsync-backup.conf.dist" ]; then
    . "$LOCATION/etc/rsync-backup.conf.dist"
    if [ -f "$LOCATION/etc/rsyn-cbackup.conf" ]; then
        . "$LOCATION/etc/rsync-backup.conf"
    fi
    if [ -f "$LOCATION/etc/rsync-backup.local.conf" ]; then
        . "$LOCATION/etc/rsync-backup.local.conf"
    fi
else
    echo "rsync-backup.conf.dist not found"
    exit 0
fi

case "$1" in

    daily)
        WHICH=$1
        INCREM=$[$DAILY -1]
        ;;

    weekly)
        WHICH=$1
        INCREM=$[$[$WEEKLY -1]*7]
        ;;

    monthly)
        WHICH=$1
        INCREM=$[$[$MONTHLY -1]*30]
        ;;
    *)
    echo "Usage: $0 {daily|weekly|monthly}"
    exit 1
    
esac

mkdir -p /var/empty

echo $WHICH
echo $INCREM


if [ x$1 != "xforce" ]; then
  RAID=`cat /proc/mdstat | awk '/^md[0-9]+/ {md++} /\[U+\]$/ {up++} END {if (md == up){print 1} else {print 0}}'`
  if [ "$RAID" == "0" ]; then
    echo "RAID is not up! Backup aborted"
    LLOG=`cat /proc/mdstat`
    echo $LLOG
    ALERT=${HN}$'\n''Raid is not up. Backup aborted'$'\n'${LLOG}
    echo "$ALERT" | mail -s "$HN rsync-backup error alert" root
    exit
  fi
fi
 
if pidof -x $(basename $0) > /dev/null; then
  for p in $(pidof -x $(basename $0)); do
    if [ $p -ne $$ ]; then
      echo "Script $0 is already running: exiting"
      ALERT=${HN}$'\n'"Script $0 is already running: exiting"
      echo "$ALERT" | mail -s "$HN rsync-backup error alert" root
      exit
    fi
  done
fi

PBACKUP=`ps ax | grep postgresql-backup.sh | grep -v "grep"`
MBACKUP=`ps ax | grep mysql-backup.sh | grep -v "grep"`

while [ -n "$PBACKUP$MBACKUP" ]; do
  echo "Wait 300 sec for database backup..."
  sleep 300
  PBACKUP=`ps ax | grep postgresql-backup.sh | grep -v "grep"`
  MBACKUP=`ps ax | grep mysql-backup.sh | grep -v "grep"`
  DAT=`date +%H`
  if [ $DAT -ge 8 ]; then
      echo "Script database backup is running: exiting"
      ALERT=${HN}$'\n'"Script database backup is running: exiting"$'\n'
      ALERT=${ALERT}$'\n'${MBACKUP}$'\n'${PBACKUP}
      echo "$ALERT" | mail -s "$HN rsync-backup error alert" root
      exit
  fi
done

# Nice debugging messages
function e { 
    echo -e $(date "+%F %T"): $1
}
function die {
    e "Error: $1" >&2
    exit 1;
}

# Make sure all is sane
[ ! -d "$VZ_PRIVATE" ] && die "\$VZ_PRIVATE directory doesn't exist. ($VZ_PRIVATE)"
[ "$VEIDS" = "*" ] && die "VEID in \$VZ_PRIVATE directory not found."
[ "$LOCAL_DIR" != "" -a ! -d "$LOCAL_DIR" ] && mkdir -p $LOCAL_DIR

if [ "$PREBACKUP" ]
    then
        eval $PREBACKUP
fi

# Exclude unneeded VEIDS
for VEID in $VEIDS_EXCLUDE; do
    VEIDS=`echo $VEIDS | sed "s/\b$VEID\b//g"`
done

echo $VEIDS

RSYNCBACKUP_REMOTE_CMD="rsync -ax --exclude-from $EXCLUDE"
RSYNCBACKUP_LOCAL_CMD="rsync -ax --exclude-from $EXCLUDE"
LOCAL_ARGS=""
REMOTE_ARGS=""

if [ -f "$REMOTE_EXCLUDE" ]; then
REMOTE_ARGS="$REMOTE_ARGS --exclude-from $REMOTE_EXCLUDE"
fi

if [ -f "$LOCAL_EXCLUDE" ]; then
LOCAL_ARGS="$LOCAL_ARGS --exclude-from $LOCAL_EXCLUDE"
fi

RSYNCBACKUP_REMOTE_CMD="$RSYNCBACKUP_REMOTE_CMD$REMOTE_ARGS"
RSYNCBACKUP_LOCAL_CMD="$RSYNCBACKUP_LOCAL_CMD$LOCAL_ARGS"

# Loop through each VEID
for VEID in $VEIDS; do
    echo "Beginning backup of VEID $VEID";
   
    echo $RSYNCBACKUP_LOCAL_CMD
    if [ "$LOCAL_DIR" != "" ]; then
        e "Make the backup folder $LOCAL_DIR/$VEID/$WHICH $LOCAL_DIR/$VEID/Latest"
        
        LLOG=`/bin/mkdir -p $LOCAL_DIR/$VEID/$WHICH $LOCAL_DIR/$VEID/Latest`

        e $LLOG

        e "Doing local backup"
        e "$RSYNCBACKUP_LOCAL_CMD --link-dest=../../Latest $VZ_PRIVATE/$VEID $LOCAL_DIR/$VEID/$WHICH/Processing$DATE"
        LLOG=`$RSYNCBACKUP_LOCAL_CMD --link-dest=../../Latest $VZ_PRIVATE/$VEID $LOCAL_DIR/$VEID/$WHICH/Processing$DATE 2>&1`
        if [ $? -gt 0 ]; then
              ALERT1="Alert rsync-backup LOCAL stage error !"$'\n'
              ALERT1=${ALERT1}"$RSYNCBACKUP_LOCAL_CMD --link-dest=../../Latest $VZ_PRIVATE/$VEID $LOCAL_DIR/$VEID/$WHICH/Processing$DATE"$'\n'$'\n'
              ALERT1=${ALERT1}${LLOG}
        else 
	      e $LLOG
	      
	      if [ -f "$LOCAL_INCLUDE" ]; then
		  e "sync include"
		  e "rsync -ax --include=*/ --include-from=$LOCAL_INCLUDE --exclude=* --link-dest=../../Latest $VZ_PRIVATE/$VEID $LOCAL_DIR/$VEID/$WHICH/Processing$DATE"
		  LLOG=`rsync -ax --include=*/ --include-from=$LOCAL_INCLUDE --exclude=* --link-dest=../../Latest $VZ_PRIVATE/$VEID $LOCAL_DIR/$VEID/$WHICH/Processing$DATE 2>&1`
	      fi
	      e $LLOG

	      e "cd $LOCAL_DIR/$VEID/ && mv $WHICH/Processing$DATE $WHICH/$DATE && rm -rf Latest  && ln -s $WHICH/$DATE Latest"
              LLOG=`cd $LOCAL_DIR/$VEID/ && mv $WHICH/Processing$DATE $WHICH/$DATE && rm -rf Latest  && ln -s $WHICH/$DATE Latest`
              
              if [ $? -gt 0 ]; then
              ALERT1="Alert rsync-backup LOCAL stage error !"$'\n'
              ALERT1=${ALERT1}"cd $LOCAL_DIR/$VEID/ && mv $WHICH/Processing$DATE $WHICH/$DATE && rm -rf Latest  && ln -s $WHICH/$DATE Latest"$'\n'$'\n'
              ALERT1=${ALERT1}${LLOG}
              else 
                  e $LLOG
                  e "Removing old files"
                  e "find $LOCAL_DIR/$VEID/$WHICH/* -maxdepth 0 -mtime +$INCREM | xargs rm -rf 2>&1" 
                  LLOG=`find $LOCAL_DIR/$VEID/$WHICH/* -maxdepth 0 -mtime +$INCREM | xargs rm -rf 2>&1`
                  if [ $? -gt 0 ]; then
                      ALERT11="Alert rsync-backup LOCAL stage error !"$'\n'
                      ALERT11=${ALERT11}"find $LOCAL_DIR/$VEID/$WHICH/* -maxdepth 0 -mtime +$INCREM | xargs rm -rf 2>&1"
                      ALERT11=${ALERT11}${LLOG}
                  fi
                  e $LLOG
              fi
              
              
        fi
        

     
    else
        # if there is no local backup, add local exclude paths to the remote
        RSYNCBACKUP_REMOTE_CMD="$RSYNCBACKUP_LOCAL_CMD$LOCAL_ARGS"
    fi

    for REMOTE_HOST in $REMOTE_HOSTS; do
      e "Doing remote backup"
      e "Make the remote backup folder"
      #If there are no folder
      LLOG=`ssh $USERNAME@$REMOTE_HOST "mkdir -p /home/$USERNAME/rsyncbackups/$VEID/$WHICH /home/$USERNAME/rsyncbackups/$VEID/Latest "`
      e $LLOG
      e "$RSYNCBACKUP_REMOTE_CMD --link-dest=../../Latest $VZ_PRIVATE/$VEID rsync://$REMOTE_HOST/$USERNAME/$VEID/$WHICH/Processing$DATE"
      LLOG=`$RSYNCBACKUP_REMOTE_CMD --link-dest=../../Latest $VZ_PRIVATE/$VEID rsync://$REMOTE_HOST/$USERNAME/$VEID/$WHICH/Processing$DATE 2>&1`
       if [ $? -gt 0 ]; then
              ALERT21=${ALERT21}"Alert rsync-backup REMOTE stage error !"$'\n'
              ALERT21=${ALERT21}"$RSYNCBACKUP_REMOTE_CMD --link-dest=../Latest $VZ_PRIVATE/$VEID rsync://$REMOTE_HOST/$USERNAME/$VEID/$WHICH/Processing$DATE"$'\n'
              ALERT21=${ALERT21}${LLOG}
            else 
            e $LLOG
            
            if [ -f "$REMOTE_INCLUDE" ]; then
		e "sync include"
		e "rsync -ax --include=*/ --include-from=$REMOTE_INCLUDE --exclude=* --link-dest=../../Latest $VZ_PRIVATE/$VEID rsync://$REMOTE_HOST/$USERNAME/$VEID/$WHICH/Processing$DATE"
		LLOG=`rsync -ax --include=*/ --include-from=$REMOTE_INCLUDE --exclude=* --link-dest=../../Latest $VZ_PRIVATE/$VEID rsync://$REMOTE_HOST/$USERNAME/$VEID/$WHICH/Processing$DATE 2>&1`
	    fi
	    e $LLOG
            
            
            e "ssh $USERNAME@$REMOTE_HOST  \"cd /home/$USERNAME/rsyncbackups/$VEID/ && mv $WHICH/Processing$DATE $WHICH/$DATE && rm -rf Latest  && ln -s $WHICH/$DATE Latest && sudo touch -m $WHICH/$DATE\""
            LLOG=`ssh $USERNAME@$REMOTE_HOST "cd /home/$USERNAME/rsyncbackups/$VEID/ && mv $WHICH/Processing$DATE $WHICH/$DATE && rm -rf Latest  && ln -s $WHICH/$DATE Latest"`

              if [ $? -gt 0 ]; then
              ALERT1="Alert rsync-backup REMOTE stage error !"$'\n'
              ALERT1=${ALERT1}"ssh $USERNAME@$REMOTE_HOST  \"cd /home/$USERNAME/rsyncbackups/$VEID/ && mv $WHICH/Processing$DATE $WHICH/$DATE && rm -rf Latest  && ln -s $WHICH$DATE Latest &&\""$'\n'$'\n'
              ALERT1=${ALERT1}${LLOG}
               else 
                  e $LLOG
                  e "Removing old files"
                  
                  e "ssh $USERNAME@$REMOTE_HOST \"find /home/$USERNAME/rsyncbackups/$VEID/$WHICH/* -maxdepth 0 -mtime +$INCREM\""
                  LLOG=`ssh $USERNAME@$REMOTE_HOST "find /home/$USERNAME/rsyncbackups/$VEID/$WHICH/* -maxdepth 0 -mtime +$INCREM" | awk -F '/' '{print $7 }'`
                  if [ $? -gt 0 ]; then
                      ALERT21=${ALERT21}"Alert rsync-backup REMOTE stage error !"$'\n'
                      ALERT21=${ALERT21}"ssh $USERNAME@$REMOTE_HOST \"find /home/$USERNAME/rsyncbackups/$VEID/$WHICH/* -maxdepth 0 -mtime +$INCREM -delete\""$'\n'
                      ALERT11=${ALERT11}${LLOG}
                  else
                    for FOLDER in $LLOG; do
                        echo $FOLDER
                        e "rsync -av --delete /var/empty/  rsync://$REMOTE_HOST/$USERNAME/$VEID/$WHICH/$FOLDER"
                        LLOG1=`rsync -av --delete /var/empty/  rsync://$REMOTE_HOST/$USERNAME/$VEID/$WHICH/$FOLDER 2>&1`
                            if [ $? -gt 0 ]; then
                                ALERT21=${ALERT21}"Alert rsync-backup REMOTE stage error !"$'\n'
                                ALERT21=${ALERT21}"rsync -av --delete /var/empty/  rsync://$REMOTE_HOST/$USERNAME/$VEID/$WHICH/$FOLDER"$'\n'
                                ALERT11=${ALERT11}${LLOG1}
                            else
                                e $LLOG1
                                e "ssh $USERNAME@$REMOTE_HOST \"rm -rf /home/$USERNAME/rsyncbackups/$VEID/$WHICH/$FOLDER\""
                                LLOG1=`ssh $USERNAME@$REMOTE_HOST "rm -rf /home/$USERNAME/rsyncbackups/$VEID/$WHICH/$FOLDER" 2>&1`
                                if [ $? -gt 0 ]; then
                                    ALERT21=${ALERT21}"Alert rsync-backup REMOTE stage error !"$'\n'
                                    ALERT21=${ALERT21}"rsync -av --delete /var/empty/  rsync://$REMOTE_HOST/$USERNAME/$VEID/$WHICH/$FOLDER"$'\n'
                                    ALERT11=${ALERT11}${LLOG1}
                                else
                                    e $LLOG1
                                fi
                            fi 
                    done;
                  fi
                  
                  fi
              
              
              fi
        #fi
    done;

    e "All done."
    
done;

ALERT=${ALERT1}${ALERT11}${ALERT21}${ALERT22}

if [ "$ALERT" != "" ]; then
  ALERT=$HN$'\n'${ALERT1}$'\n'${ALERT11}$'\n'$'\n'${ALERT21}$'\n'${ALERT22}$'\n'
  echo "$ALERT"
  echo "$ALERT" | mail -s "$HN rsync-backup error alert" backup-alert@centos-admin.ru
fi

if [ "$POSTBACKUP" ]
    then
        eval $POSTBACKUP
fi
