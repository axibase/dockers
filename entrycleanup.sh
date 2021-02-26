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
  #Do not import any artifacts on this step, as settings and profile defined only in entrypoint stage
  JAVA_PROPERTIES="-Dsettings= $JAVA_PROPERTIES"
  /bin/bash ${DISTR_HOME}/bin/atsd-tsd.sh start
  /bin/bash ${DISTR_HOME}/bin/stop-atsd.sh -f
}

function hbase_shell() {
  echo -e "$1" | ./hbase/bin/hbase-shell
}

function wait_hbase_start() {
  while hbase_shell "status" | grep -q "ERROR:"; do
    sleep 5
  done
}

function cleanup_hbase_tables() {
  #Start ATSD in hbase mode
  /bin/bash ${DISTR_HOME}/bin/start-atsd.sh -h
  wait_hbase_start

  echo "Truncate tables"

  for table in d entity li metric properties tag message message_source message_type; do
    hbase_shell "truncate 'atsd_${table}'"
  done

  #hbase-shell "scan 'atsd_config'"

  hbase_shell "delete 'atsd_config','options','mc:hostname'"
  hbase_shell "delete 'atsd_config','options','mc:server.url'"
  hbase_shell "deleteall 'atsd_config','activeFamily'"
  hbase_shell "deleteall 'atsd_config','inactiveFamily'"
  hbase_shell "get 'atsd_counter', '__inst'"
  hbase_shell "deleteall 'atsd_counter', '__inst'"

  echo "Stop all services"
  ./bin/stop-atsd.sh -f
}

function cleanup_log_files() {
  echo "Remove log files and temporary directories."
  rm -rf ${DISTR_HOME}/conf/license/*
  rm -rf ${DISTR_HOME}/hbase/logs/*
  rm -rf ${DISTR_HOME}/hbase/zookeeper
  rm -rf /tmp/atsd
  rm -rf ${DISTR_HOME}/logs/*
  touch ${DISTR_HOME}/logs/err.log
  chown -R axibase:axibase ${DISTR_HOME}/logs
}

echo "Initiate build cleanup in ${DISTR_HOME}. Current user: $(whoami)"

cd "${DISTR_HOME}" || return
chown -R axibase:axibase ${DISTR_HOME}

create_hbase_tables
cleanup_apt_files
cleanup_hbase_tables
cleanup_log_files
