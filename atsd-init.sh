#!/bin/bash
DISTR_HOME="/opt/atsd"

echo "Initiate build cleanup in ${DISTR_HOME}. Current user: `whoami`"

function start_services {
    echo "Start all services to ensure that schema is initialized. Skip tests."
    ./bin/atsd-all.sh start skipTest

    echo "=== ATSD log ==="
    tail -n 50 ./atsd/logs/atsd.log
    echo "================"

    echo "Stop ATSD"
    ./bin/atsd-tsd.sh stop

    # only HDFS and HBase must be running at this time
    ./bin/atsd-all.sh status
}

function stop_services {
    echo "Stop all services"

    ./bin/atsd-hbase.sh stop
    ./bin/atsd-dfs.sh stop

    echo "Remove log files, license files, and temporary directories."

    rm -rf ./atsd/conf/license/*
    rm -rf ./atsd/logs/*
    rm -rf ./hbase/logs/*
    rm -rf ./hadoop/logs/*
    rm -rf ./hbase/zookeeper
    rm -rf ./hdfs-cache
}

function truncate_tables {
    echo "status" | ./hbase/bin/hbase shell

    echo "Truncate tables"

    for table in d entity li metric properties tag message message_source message_type; do
      echo "truncate 'atsd_${table}'" | ./hbase/bin/hbase shell
    done

    #echo "scan 'atsd_config'" | ./hbase/bin/hbase shell

    echo "delete 'atsd_config','options','mc:hostname'" | ./hbase/bin/hbase shell
    echo "delete 'atsd_config','options','mc:server.url'" | ./hbase/bin/hbase shell
    echo "deleteall 'atsd_config','activeFamily'" | ./hbase/bin/hbase shell
    echo "deleteall 'atsd_config','inactiveFamily'" | ./hbase/bin/hbase shell
}

function move_install {
    echo "Move install files to ./install directory"

    mkdir -p ./install
    mv ./install*.log ./install
    mv ./install*.sh ./install
    mv ./java_find.sh ./install
    mv ./atsd*ervice ./install
}

cd ${DISTR_HOME}
echo "Set file ownership to 'axibase' user"
chown -R axibase:axibase ${DISTR_HOME}
start_services
truncate_tables
stop_services
move_install
chown -R axibase:axibase ${DISTR_HOME}
touch /first-start
