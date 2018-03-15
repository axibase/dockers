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

ATSD_ADMIN_USER_NAME=axibase
ATSD_ADMIN_USER_PASSWORD=axibase

ATSD_COLLECTOR_USER_NAME=collector
ATSD_COLLECTOR_USER_PASSWORD=collector

COLLECTOR_USER_NAME=axibase
COLLECTOR_USER_PASSWORD=axibase

if [ -n "$IMPORT_PATHS" ]; then
    ATSD_IMPORT_PATH=$(echo "$IMPORT_PATHS" | cut -d ";" -f 1)
    COLLECTOR_IMPORT_PATH=$(echo "$IMPORT_PATHS" | cut -d ";" -f 2)
fi

function start_atsd {
    function set_tz {
        # set custom timezone
        if [ -n "$DB_TIMEZONE" ]; then
            echo "[ATSD] Database timezone set to '$DB_TIMEZONE'." | tee -a  $LOGFILESTART
            echo "export JAVA_PROPERTIES=\"-Duser.timezone=$DB_TIMEZONE \$JAVA_PROPERTIES\"" >> /opt/atsd/atsd/conf/atsd-env.sh
        fi
    }

    function create_account {
        local user=$1
        local pass=$2
        local params=$3
        local description=$4
        if curl -i -s --data "userBean.username=$user&userBean.password=$pass&repeatPassword=$pass" \
            http://127.0.0.1:8088/login${params} | grep -q "302"; then
            echo "[ATSD] $4 account '$user' created." | tee -a  $LOGFILESTART
        else
            echo "[ATSD] Failed to create $4 account '$ATSD_COLLECTOR_USER_NAME'." | tee -a  $LOGFILESTART
        fi
    }

    function configure_phantom {
        curl -u "$ATSD_ADMIN_USER_NAME":"$ATSD_ADMIN_USER_PASSWORD" --data \
            "options%5B0%5D.key=webdriver.phantomjs.path&options%5B0%5D.value=%2Fopt%2Fatsd%2Fphantomjs-2.1.1-linux-x86_64%2Fbin%2Fphantomjs&apply=Save" \
            http://127.0.0.1:8088/admin/serverproperties
    }

    function import_backup {
        if [ -n "$ATSD_IMPORT_PATH" ]; then
            tmp_path="/tmp/import-backup"
            mkdir "$tmp_path"
            if [[ "$ATSD_IMPORT_PATH" =~ (ftp|https?)://.* ]]; then
                wget -P "$tmp_path" "$ATSD_IMPORT_PATH"
            elif [[ "$ATSD_IMPORT_PATH" =~ /.* ]]; then
                cp -v "$ATSD_IMPORT_PATH" "$tmp_path"
            fi
            tmp_file="$tmp_path"/$(ls -1 $tmp_path)
            echo "Saved to $tmp_path"
            curl -u "$ATSD_ADMIN_USER_NAME:$ATSD_ADMIN_USER_PASSWORD" \
                -F "files=@$tmp_file" http://127.0.0.1:8088/admin/import-backup
            rm -fr "$tmp_path"
        fi
    }

    su axibase ${ATSD_ALL} start

    if [ $? -eq 1 ]; then
        echo "[ATSD] Failed to start ATSD. Check $LOGFILESTART file." | tee -a $LOGFILESTART
    fi

    if [ -f /first-start ]; then
        set_tz
        create_account "$ATSD_COLLECTOR_USER_NAME" "$ATSD_COLLECTOR_USER_PASSWORD" "?type=writer" "Collector"
        create_account "$ATSD_ADMIN_USER_NAME" "$ATSD_ADMIN_USER_PASSWORD" "" "Admininstrator"
        configure_phantom
        import_backup
    fi
}

function start_collector {
    SCRIPTS_HOME="/opt/axibase-collector/bin"

    cd ${SCRIPTS_HOME}
    echo "Starting Axibase Collector ..."

    function print_error {
        echo "Error: $1"
    }

    function validate_docker_socket {
        echo -n "Checking docker socket..."
        if [ ! -e "/var/run/docker.sock" ]; then
            print_error "Docker socket /var/run/docker.sock is not mounted"
            exit 1
        fi
        check_res=`java -classpath "../exploded/webapp/WEB-INF/classes:../exploded/webapp/WEB-INF/lib/*" com.axibase.collector.util.UnixSocketUtil /var/run/docker.sock 2>&1`;
        if ! [[ -z "$check_res" ]]; then
            if [ "$check_res" == "OK" ]; then
                echo "OK"
            elif [[ "$check_res" == "FAILED"* ]]; then
                echo "$check_res"
            elif [[ "$check_res" == "Unable to read"* ]]; then
                echo
                print_error "$check_res"
                exit 1
            else
                echo
                echo "$check_res"
            fi
        fi
    }

    function start_cron {
        #Create empty cron job
        touch /etc/cron.d/root
        chmod +x /etc/cron.d/root
        printf "# Empty line\n" >> /etc/cron.d/root
        crontab /etc/cron.d/root

        #Start cron
        cron -f &
    }

    validate_docker_socket
    start_cron

    if [ -f /first-start ] && [ -n "$COLLECTOR_IMPORT_PATH" ]; then
        JOB_PATH=-job-path="$COLLECTOR_IMPORT_PATH"
    fi

    #Start collector
    ./start-collector.sh -atsd-url="https://${ATSD_COLLECTOR_USER_NAME}:${ATSD_COLLECTOR_USER_PASSWORD}@localhost:8443" -job-enable=docker-socket "$JOB_PATH"

    if [ -f /first-start ]; then
        if curl -i -s --insecure --data \
            "user.username=$COLLECTOR_USER_NAME&newPassword=$COLLECTOR_USER_PASSWORD&confirmedPassword=$COLLECTOR_USER_PASSWORD&commit=Save" \
            https://127.0.0.1:9443/register.xhtml | grep -q "302"; then
            echo "[Collector] Account '$COLLECTOR_USER_NAME' created." | tee -a  $LOGFILESTART
        else
            echo "[Collector] Failed to create account '$COLLECTOR_USER_NAME'." | tee -a  $LOGFILESTART
        fi
    fi
}

function start_collectd {
    echo "Starting collectd ..."
    /usr/sbin/collectd
    COLLECTD_PID=$!
}

function stop_services {
    jps_output=$(jps)

    echo "Stopping collectd ..."
    kill ${COLLECTD_PID}

    echo "Stopping Axibase Collector ..."
    ./stop-collector.sh "-1"

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
}

function wait_loop {
    executing="true"
    trap 'echo "kill signal handled, stopping processes ..."; executing="false"' SIGINT SIGTERM
    while [ "$executing" = "true" ]; do
        sleep 1
    done
}

start_atsd
start_collector
start_collectd
if [ -f /first-start ]; then
    rm /first-start
fi
wait_loop
echo "SIGTERM received ( docker stop ). Stopping services ..." | tee -a $LOGFILESTOP
stop_services
