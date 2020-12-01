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

function cleanup_hbase_tables() {
  #Start ATSD in hbase mode
  ./bin/start-atsd.sh -h
  echo "status" | ./bin/hbase-shell

  echo "Truncate tables"

  for table in d entity li metric properties tag message message_source message_type; do
    echo "truncate 'atsd_${table}'" | ./bin/hbase-shell
  done

  #echo "scan 'atsd_config'" | ./bin/hbase-shell

  echo "delete 'atsd_config','options','mc:hostname'" | ./bin/hbase-shell
  echo "delete 'atsd_config','options','mc:server.url'" | ./bin/hbase-shell
  echo "deleteall 'atsd_config','activeFamily'" | ./bin/hbase-shell
  echo "deleteall 'atsd_config','inactiveFamily'" | ./bin/hbase-shell
  echo "deleteall 'atsd_counter', '__inst'" | ./bin/hbase-shell

  echo "Stop all services"
  ./bin/stop-atsd.sh -f
}

echo "Initiate build cleanup in ${DISTR_HOME}. Current user: $(whoami)"

cd "${DISTR_HOME}" || return
chown -R axibase:axibase ${DISTR_HOME}

create_hbase_tables
cleanup_apt_files
cleanup_hbase_tables
