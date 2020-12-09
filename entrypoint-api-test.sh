#!/bin/bash
if [ -z "${axiname}" ] || [ -z "${axipass}" ]; then
	echo "axiname or axipass is empty. Fail to start container."
	exit 1
fi


DISTR_HOME="/opt/atsd"
UPDATELOG="$(readlink -f ${DISTR_HOME}/logs/update.log)"
STARTLOG="$(readlink -f ${DISTR_HOME}/logs/start.log)"
URL="https://axibase.com/public"
LATEST="atsd.standalone.latest.tar.gz"
LATESTTAR="${DISTR_HOME}/bin/atsd.standalone.latest.tar.gz"
revisionFile="applicationContext-common.xml"

function logger {
    echo "$1" | tee -a $UPDATELOG
}


yes | bash ${DISTR_HOME}/bin/update.sh

#check timezone
if [ -n "${timezone}" ]; then
    echo "export JAVA_PROPERTIES=\"-Duser.timezone=$timezone \$JAVA_PROPERTIES\"" >> /opt/atsd/conf/atsd-env.sh
fi
rm -rf atsd.standalone.tar.gz
rm -rf /opt/atsd/bin/atsd
rm /opt/atsd/conf/license/*
rm /opt/atsd/logs/atsd.log
rm /opt/atsd/logs/command*.log
rm /opt/atsd/logs/err.log

curl https://raw.githubusercontent.com/axibase/atsd/master/rule-engine/resources/calendars/usa.json > /opt/atsd/conf/calendars/usa.json
curl https://raw.githubusercontent.com/axibase/atsd/master/rule-engine/resources/calendars/rus.json > /opt/atsd/conf/calendars/rus.json
logger "USA and RUS workday calendars updated"

${DISTR_HOME}/bin/atsd-tsd.sh start

curl -i --data "userBean.username=$axiname&userBean.password=$axipass&repeatPassword=$axipass" http://127.0.0.1:8088/login
curl -F "file=@/opt/atsd/rules.xml" -F "auto-enable=true" -F "replace=true" http://"$axiname":"$axipass"@127.0.0.1:8088/rules/import

while true; do
 sleep 5
done
