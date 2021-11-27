#!/bin/bash
#
# daemonNanny - make sure specified daemon is running.
#               Intended to be run from cron.
#
COMMAND=$1
if [ -z "$COMMAND" ]; then
    echo "`date`: Usage: $0 <full_daemon_path>"
    exit 1
fi
# Notification skip count: set this to the number of crontab intervals to skip
# before reporting the same notification again. E.g., setting notifSkipCount to 12
# would imply that identical notifications would be generated only once an hour
# assuming 5-minute crontab check intervals.
NotifSkipCount=144          # 12 hours

MAPPER_HOME=`dirname $0`/..
PROGRAM=`basename $COMMAND`
BASEPROGRAM=${PROGRAM%.*}
PIDFILE=${MAPPER_HOME}/log/${BASEPROGRAM}.pid
LOGFILE=${MAPPER_HOME}/log/${BASEPROGRAM}.oe.log
VARFILE=${MAPPER_HOME}/log/${BASEPROGRAM}.var

NOW=`/bin/date '+%m/%d/%Y %H:%M:%S'`

# Generate a GitHub issue when an unexpected event occurs.
createIssue() {
    ${MAPPER_HOME}/common/tools/create_alert_issue.py "$SUBJECT" "$alertBody"
}

if [ ! -x "$COMMAND" ]; then
    echo "`date`: $COMMAND does not exist or is not executable"
    SUBJECT="Daemon nanny cannot start non-existent or non-executable $PROGRAM daemon"
    alertBody=`/bin/cat <<EOF
$SUBJECT

Daemon $PROGRAM could not be started at $NOW.
Check to make sure it exists and is executable.
EOF`
    createIssue

    exit 2
fi

checkrestart() {
    restart=0
    if [ -e $PIDFILE ]; then
        PID=`cat $PIDFILE`
        ps $PID > /dev/null 2>&1
        restart=$?
    else
        restart=1
    fi
}

checkuptime() {
    uptime=(`cat /proc/uptime`)
    upseconds=${uptime[0]%.*}
}

# Retrieve the variable values:
# varArray[0]: 'failed to restart' count
# varArray[1]: 'restarted' count
# varArray[2]: 'already running' count
#
if [ -e $VARFILE ]; then
    varArray=(`cat $VARFILE`)
else
    varArray=(0 0 0)
fi

# Main path starts here
checkrestart
# Daemon not running: System startup, or we killed it, or it failed.
# We need to start the daemon.
if [[ $restart -eq 1 ]]; then
    nohup $COMMAND >>$LOGFILE 2>&1 &
    echo $! >$PIDFILE
    sleep 20
    checkrestart
    # Daemon still not running after 20 seconds. Report problem periodically.
    if [[ $restart -eq 1 ]]; then
        if [[ ${varArray[0]} -eq 0 ]]; then
            varArray[1]=0
            varArray[2]=0
            echo "`date`: Failed to restart $PROGRAM"
            SUBJECT="Daemon nanny has failed to restart $PROGRAM daemon"
            alertBody=`/bin/cat <<EOF
$SUBJECT

Daemon $PROGRAM failed to restart at $NOW.
Please check $LOGFILE for details.
EOF`
            createIssue
        fi
        let varArray[0]=${varArray[0]}+1
        if [[ ${varArray[0]} -ge $NotifSkipCount ]]; then
            varArray[0]=0
        fi
    # Daemon still running after 20 seconds. Report change of state periodically.
    # NOTE: Normal case when system starts up.
    else
        # Don't create alert if daemon start is within 10 minutes of system boot.
        checkuptime
        if [[ ${varArray[1]} -eq 0 && $upseconds -gt 600 ]]; then
            varArray[0]=0
            varArray[2]=0
            echo "`date`: $PROGRAM restarted"
            SUBJECT="Daemon nanny has restarted $PROGRAM daemon"
            alertBody=`/bin/cat <<EOF
$SUBJECT

Daemon $PROGRAM restarted at $NOW.
Please check $LOGFILE for details.
EOF`
            createIssue
        fi
        let varArray[1]=${varArray[1]}+1
        if [[ ${varArray[1]} -ge $NotifSkipCount ]]; then
            varArray[1]=0
        fi
    fi
# Daemon already running. Just increment the already-running count.
else
    if [[ ${varArray[2]} -eq 0 ]]; then
        varArray[0]=0
        varArray[1]=0
        echo "`date`: $PROGRAM already running"
    fi
    let varArray[2]=${varArray[2]}+1
    if [[ ${varArray[2]} -ge $NotifSkipCount ]]; then
        varArray[2]=0
    fi
fi
echo ${varArray[@]} >$VARFILE
