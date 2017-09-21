#!/bin/bash
trap 'echo "kill signal handled, stopping processes ..."; executing="false"' SIGINT SIGTERM
DISTR_HOME="/opt/atsd"
installUser="${DISTR_HOME}/install_user.sh"
ATSD_ALL="${DISTR_HOME}/bin/atsd-all.sh"
HBASE="`readlink -f ${DISTR_HOME}/hbase/bin/hbase`"
HBASE_DAEMON="`readlink -f ${DISTR_HOME}/hbase/bin/hbase-daemon.sh`"
DFS_STOP="`readlink -f ${DISTR_HOME}/hadoop/sbin/stop-dfs.sh`"
LOGFILESTART="`readlink -f ${DISTR_HOME}/atsd/logs/start.log`"
LOGFILESTOP="`readlink -f ${DISTR_HOME}/atsd/logs/stop.log`"
CONF_TOOL="${HBASE} org.apache.hadoop.hbase.util.HBaseConfTool"

collectorUser="${COLLECTOR_USER_NAME}"
collectorPassword="${COLLECTOR_USER_PASSWORD}"
collectorType="${COLLECTOR_USER_TYPE-writer}"

if [ -n "$collectorPassword" ] && [ ${#collectorPassword} -lt 6 ]; then
    echo "[ATSD] Minimum password length is 6 characters. Start cancelled." | tee -a $LOGFILESTART
    exit 1
fi

if [ -n "$ADMIN_USER_PASSWORD" ] && [ ${#ADMIN_USER_PASSWORD} -lt 6 ]; then
    echo "[ATSD] Minimum password length is 6 characters. Start cancelled." | tee -a $LOGFILESTART
    exit 1
fi

# set custom timezone
if [ -n "$DB_TIMEZONE" ]; then
    echo "[ATSD] Database timezone set to '$DB_TIMEZONE'." | tee -a  $LOGFILESTART
    echo "export JAVA_PROPERTIES=\"-Duser.timezone=$DB_TIMEZONE \$JAVA_PROPERTIES\"" >> /opt/atsd/atsd/conf/atsd-env.sh
fi

distributed=$(${CONF_TOOL} hbase.cluster.distributed)
zk_dir="${DISTR_HOME}/hbase/zookeeper"

directoriesToCheck="hdfs-cache hdfs-data hdfs-data-name"
firstStart="true"
executing="true"

for directory in $directoriesToCheck; do
    if [ -d "${DISTR_HOME}/${directory}" ]; then
        firstStart="false"
    fi
done

if [ "$firstStart" = "true" ]; then
    ${ATSD_ALL} start skipTest
else
    ${ATSD_ALL} start
fi

if [ $? -eq 1 ]; then
    echo "[ATSD] Failed to start ATSD. Check $LOGFILESTART file." | tee -a $LOGFILESTART
fi

if curl -o - http://127.0.0.1:8088/login?type=writer 2>/dev/null | grep -q "400"; then
    echo "[ATSD] Collector account already exists." > /dev/null
elif [ -n "$collectorPassword" ] && [ -n "$collectorUser" ]; then
    if curl -s -i --data "userBean.username=$collectorUser&userBean.password=$collectorPassword&repeatPassword=$collectorPassword" http://127.0.0.1:8088/login?type=${collectorType} | grep -q "302"; then
        echo "[ATSD] Collector account '$collectorUser' created. Type: '$collectorType'." | tee -a  $LOGFILESTART
    else
        echo "[ATSD] Failed to create collector account '$collectorUser'." | tee -a  $LOGFILESTART
    fi
fi

if [ -n "$ADMIN_USER_NAME" ] && [ -n "$ADMIN_USER_PASSWORD" ]; then
    if curl -s -i --data "userBean.username=$ADMIN_USER_NAME&userBean.password=$ADMIN_USER_PASSWORD&repeatPassword=$ADMIN_USER_PASSWORD" http://127.0.0.1:8088/login | grep -q "302"; then
        echo "[ATSD] Administrator account '$ADMIN_USER_NAME' created." | tee -a  $LOGFILESTART
    else
        echo "[ATSD] Failed to create administrator account '$ADMIN_USER_NAME'." | tee -a  $LOGFILESTART
    fi
fi

sleep infinity & sleep_pid=$!
trap 'echo "kill signal handled, stopping processes ..."; kill $sleep_pid' SIGINT SIGTERM
wait $sleep_pid

echo "[ATSD] SIGTERM received ( docker stop ). Stopping services ..." | tee -a $LOGFILESTOP

jps_output=$(jps)

if echo ${jps_output} | grep -q "Server"; then
    echo "[ATSD] Stopping ATSD server ..." | tee -a $LOGFILESTOP
    kill -SIGKILL $(echo $jps_output | grep 'Server' | awk '{print $1}')
fi
echo "[ATSD] Stopping HBase processes ..." | tee -a $LOGFILESTOP
if echo ${jps_output} | grep -q "HRegionServer"; then
    ${HBASE_DAEMON} stop regionserver
fi
if echo ${jps_output} | grep -q "HMaster"; then
    ${HBASE_DAEMON} stop master
fi
if [ "$distributed" = "false" ]; then
    echo "[ATSD] ZooKeeper data cleanup ..." | tee -a $LOGFILESTOP
    rm -rf "$zk_dir"
fi
if echo ${jps_output} | grep -q "HQuorumPeer"; then
    ${HBASE_DAEMON} stop zookeeper
fi
echo "[ATSD] Stopping HDFS processes ..." | tee -a $LOGFILESTOP
${DFS_STOP}

exit 0
