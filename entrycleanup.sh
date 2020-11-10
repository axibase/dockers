#!/bin/bash

DISTR_HOME="/opt/atsd"
HOST="127.0.0.1"
HTTP_PORT=8088

function wait_for_start() {
  echo -n "waiting for ATSD server start"
  while [[ $(curl --write-out %{http_code} --silent --output /dev/null http://${HOST}:${HTTP_PORT}/) != 302 ]]; do
    echo -n "."
    sleep 3
  done
  echo ""
}

function create_hbase_tables() {
  echo "Creating Hbase tables"

  ${DISTR_HOME}/bin/start-atsd.sh
  wait_for_start
  ${DISTR_HOME}/bin/stop-atsd.sh -f
  #Cleanup logs
  rm -rf ${DISTR_HOME}/logs/*
  touch ${DISTR_HOME}/logs/err.log
  chown -R axibase:axibase ${DISTR_HOME}/logs
}

echo "Initiate build cleanup in ${DISTR_HOME}. Current user: $(whoami)"

cd "${DISTR_HOME}" || return
chown -R axibase:axibase ${DISTR_HOME}

create_hbase_tables
