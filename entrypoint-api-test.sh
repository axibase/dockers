#!/bin/bash
if [ -z "$axiname" ] || [ -z "$axipass" ]; then
	echo "axiname or axipass is empty. Fail to start container."
	exit 1
fi


DISTR_HOME="/opt/atsd"
UPDATELOG="`readlink -f ${DISTR_HOME}/atsd/logs/update.log`"
STARTLOG="`readlink -f ${DISTR_HOME}/atsd/logs/start.log`"
JAVA_DISTR_HOME="/usr/lib/jvm/java-1.8.0-openjdk-amd64/"
JAR="${JAVA_DISTR_HOME}/bin/jar"
URL="https://axibase.com/public"
LATEST="$URL/atsd_update_latest.htm"
LATESTTAR="${DISTR_HOME}/bin/atsd_latest.tar.gz"
revisionFile="applicationContext-common.xml"

function logger {
    echo "$1" | tee -a $UPDATELOG
}


logger "Starting ATSD update process ..."

cd ${DISTR_HOME}/bin/
uri="`curl $LATEST | grep -o 'URL=.*\"' | sed 's/URL=//g' | sed 's/"//g'`"
logger "Downloading revision $lastRevision from $URL/$uri"
curl -o $LATESTTAR $URL/$uri 2>&1 | tee -a $UPDATELOG
tar -xzvf $LATESTTAR -C ${DISTR_HOME}/bin/ >>$UPDATELOG 2>&1
newRevision="`$JAR xf ${DISTR_HOME}/bin/target/atsd.*.jar $revisionFile; cat $revisionFile | grep "revisionNumber" | sed 's/[^0-9]//g'; rm -f $revisionFile`"
logger "Current version: $newRevision"

cd ${DISTR_HOME}/hbase/lib && rm atsd-hbase.*.jar && mv ${DISTR_HOME}/bin/target/atsd-hbase.*.jar ./

cd ${DISTR_HOME}/atsd/bin/ && rm atsd.*.jar && mv ${DISTR_HOME}/bin/target/atsd.*.jar ./

logger "Files replaced."

#check timezone
if [ -n "$timezone" ]; then
    echo "export JAVA_PROPERTIES=\"-Duser.timezone=$timezone \$JAVA_PROPERTIES\"" >> ${DISTR_HOME}/atsd/conf/atsd-env.sh
fi
echo "version.check=false" >> ${DISTR_HOME}/atsd/conf/server.properties

#/opt/atsd/bin/atsd-dfs.sh start
/opt/atsd/bin/atsd-hbase.sh start
echo "delete 'atsd_counter', '__inst', 'type:t'" | /opt/atsd/hbase/bin/hbase shell
/opt/atsd/bin/atsd-tsd.sh start

curl -i --data "userBean.username=$axiname&userBean.password=$axipass&repeatPassword=$axipass" http://127.0.0.1:8088/login
curl -F "file=@/opt/atsd/rules.xml" -F "auto-enable=true" -F "replace=true" http://$axiname:$axipass@127.0.0.1:8088/rules/import
curl -i -u ${axiname}:${axipass} --data "options%5B0%5D.key=last.insert.write.period.seconds&options%5B0%5D.value=0&apply=Save" http://127.0.0.1:8088/admin/serverproperties

while true; do
 sleep 5
done
