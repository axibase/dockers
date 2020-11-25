#!/bin/bash

DISTR_HOME="/opt/atsd"
HOST="127.0.0.1"
HTTP_PORT=8088

function cleanup_apt_files() {
  echo "Cleanup installed apt packages"
  rm -rf /var/lib/apt/lists/*
}

function create_hbase_tables() {
  echo "Creating Hbase tables"
  /bin/bash ${DISTR_HOME}/bin/atsd-tsd.sh start
  /bin/bash ${DISTR_HOME}/bin/stop-atsd.sh -f
  #Cleanup logs
  rm -rf ${DISTR_HOME}/logs/*
  touch ${DISTR_HOME}/logs/err.log
  chown -R axibase:axibase ${DISTR_HOME}/logs
}

echo "Initiate build cleanup in ${DISTR_HOME}. Current user: $(whoami)"

cd "${DISTR_HOME}" || return
chown -R axibase:axibase ${DISTR_HOME}

create_hbase_tables
cleanup_apt_files
