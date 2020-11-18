#!/bin/bash
trap 'echo "kill signal handled, stopping processes ..."; executing="false"' SIGINT SIGTERM
DISTR_HOME="/opt/atsd"
LOGFILESTART="`readlink -f ${DISTR_HOME}/atsd/logs/start.log`"
LOGFILESTOP="`readlink -f ${DISTR_HOME}/atsd/logs/stop.log`"
MAIN_CLASS="ATSD"

collectorUser="${COLLECTOR_USER_NAME}"
collectorPassword="${COLLECTOR_USER_PASSWORD}"
if [ -n "$COLLECTOR_USER_TYPE" ]; then
    collectorType="$COLLECTOR_USER_TYPE"
else
    collectorType="writer"
fi

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
    echo "export JAVA_PROPERTIES=\"-Duser.timezone=$DB_TIMEZONE \$JAVA_PROPERTIES\"" >> /opt/atsd/conf/atsd-env.sh
fi

executing="true"

bash /opt/atsd/bin/atsd-tsd.sh start

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
        echo "[ATSD] Failed to create administrator account '$ADMIN_USER_NAME'."
    fi
fi

sleep 5;

tail -f /opt/atsd/logs/start.log

while [ "$executing" = "true" ]; do
    sleep 1
    trap 'echo "kill signal handled, stopping processes ..."; executing="false"' SIGINT SIGTERM
done

echo "[ATSD] SIGTERM received ( docker stop ). Stopping services ..." 

jps_output=$(jps)

if echo "${jps_output}" | grep -q "${MAIN_CLASS}"; then
    echo "[ATSD] Stopping ATSD server ..." | tee -a $LOGFILESTOP
    kill -SIGKILL $(echo "${jps_output}" | grep '${MAIN_CLASS}' | awk '{print $1}') 2>/dev/null
fi


exit 0
