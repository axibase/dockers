#!/bin/bash
DISTR_HOME="/opt/atsd"

echo "Initiate build cleanup in ${DISTR_HOME}. Current user: `whoami`"

cd "${DISTR_HOME}" || return

chown -R axibase:axibase ${DISTR_HOME}

echo "Creating Hbase tables"

${DISTR_HOME}/bin/start-atsd.sh

echo -n "waiting ATSD server"

while [[ $(curl --write-out %{http_code} --silent --output /dev/null http://127.0.0.1:8088/) != 302 ]]; do  
 echo -n "."; sleep 3; 
done
echo ""
${DISTR_HOME}/bin/stop-atsd.sh -f
rm -rf ${DISTR_HOME}/logs/*
touch ${DISTR_HOME}/logs/err.log
chown -R axibase:axibase ${DISTR_HOME}/logs

