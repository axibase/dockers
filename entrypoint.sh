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
ZOOKEEPER_DATA_DIR="${DISTR_HOME}/hbase/zookeeper"

collectorUser="${COLLECTOR_USER_NAME}"
collectorPassword="${COLLECTOR_USER_PASSWORD}"
collectorType="${COLLECTOR_USER_TYPE}"

if [ -n "$collectorPassword" ] && [ ${#collectorPassword} -lt 6 ]; then
    echo "[ATSD] Minimum password length for the collector account is 6 characters. Start cancelled." | tee -a $LOGFILESTART
    exit 1
fi

if [ -n "$ADMIN_USER_PASSWORD" ] && [ ${#ADMIN_USER_PASSWORD} -lt 6 ]; then
    echo "[ATSD] Minimum password length for the administrator account is 6 characters. Start cancelled." | tee -a $LOGFILESTART
    exit 1
fi

# set custom timezone
if [ -n "$DB_TIMEZONE" ]; then
    echo "[ATSD] Database timezone set to '$DB_TIMEZONE'." | tee -a  $LOGFILESTART
    echo "export JAVA_PROPERTIES=\"-Duser.timezone=$DB_TIMEZONE \$JAVA_PROPERTIES\"" >> /opt/atsd/atsd/conf/atsd-env.sh
fi

format_log="${DISTR_HOME}/format.log"
test_directory="${DISTR_HOME}/hdfs-data"
firstStart="true"
executing="true"

if [ -d "$test_directory" ] && [ -n "$(ls -A ${test_directory})" ] && [ -s "${format_log}" ]; then
    firstStart="false"
fi

if [ "$firstStart" = "true" ]; then
    # format HDFS data directory
    if [ "$HDFS_FORMAT" = "true" ]; then
        echo "[ATSD] Format HDFS data directory." | tee -a  $LOGFILESTART
        for d in $(ls -A ${DISTR_HOME} | grep hdfs); do
            if [ -n "$(ls -A ${DISTR_HOME}/${d})" ]; then
                echo "[ATSD] Cannot proceed. Remove all files from ${DISTR_HOME}/${d}." | tee -a  $LOGFILESTART
                exit 1
            fi
        done
        ${DISTR_HOME}/hadoop/bin/hdfs namenode -format > ${format_log} | tee -a  $LOGFILESTART
        echo "[ATSD] HDFS data directory format is completed." | tee -a  $LOGFILESTART
    fi
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

while [ "$executing" = "true" ]; do
    sleep 1
    trap 'echo "kill signal handled, stopping processes ..."; executing="false"' SIGINT SIGTERM
done

echo "[ATSD] SIGTERM received ( docker stop ). Stopping services ..." | tee -a $LOGFILESTOP

jps_output=$(jps)

if echo "${jps_output}" | grep -q "Server"; then
    echo "[ATSD] Stopping ATSD server ..." | tee -a $LOGFILESTOP
    kill -SIGKILL $(echo "${jps_output}" | grep 'Server' | awk '{print $1}') 2>/dev/null
fi
echo "[ATSD] Stopping HBase processes ..." | tee -a $LOGFILESTOP
if echo "${jps_output}" | grep -q "HRegionServer"; then
    ${HBASE_DAEMON} stop regionserver
fi
if echo "${jps_output}" | grep -q "HMaster"; then
    ${HBASE_DAEMON} stop master
fi
if echo "${jps_output}" | grep -q "HQuorumPeer"; then
    ${HBASE_DAEMON} stop zookeeper
fi
echo "[ATSD] ZooKeeper data cleanup ..." | tee -a $LOGFILESTOP
rm -rf "${ZOOKEEPER_DATA_DIR}" 2>/dev/null
echo "[ATSD] Stopping HDFS processes ..." | tee -a $LOGFILESTOP
${DFS_STOP}

exit 0
