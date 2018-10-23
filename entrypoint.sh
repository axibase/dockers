#!/bin/bash

# Make ENV snapshot
env > /tmp/.env

trap 'echo "kill signal handled, stopping processes ..."; executing="false"' SIGINT SIGTERM
DISTR_HOME="/opt/atsd"
ATSD_ALL="${DISTR_HOME}/bin/atsd-all.sh"
HBASE="`readlink -f ${DISTR_HOME}/hbase/bin/hbase`"
HBASE_DAEMON="`readlink -f ${DISTR_HOME}/hbase/bin/hbase-daemon.sh`"
DFS_STOP="`readlink -f ${DISTR_HOME}/hadoop/sbin/stop-dfs.sh`"
LOGFILESTART="`readlink -f ${DISTR_HOME}/atsd/logs/start.log`"
LOGFILESTOP="`readlink -f ${DISTR_HOME}/atsd/logs/stop.log`"
ZOOKEEPER_DATA_DIR="${DISTR_HOME}/hbase/zookeeper"

HTTP_OK_CODE="200 OK"
HTTP_FOUND_CODE="302 Found"
WGET_SUCCESS_CODE=0
WGET_NETWORK_FAILURE_CODE=4

FIRST_START_MARKER="/first-start"
IMPORT_DIR="/import"
TMP_IMPORT_DIR="/tmp/import"
TMP_DOWNLOAD_DIR="/tmp/import-download"
TMP_EXTRACT_DIR="/tmp/extract"
DOCKER_SOCKET="/var/run/docker.sock"

ATSD_ADMIN_USER_NAME=axibase
ATSD_ADMIN_USER_PASSWORD=axibase

ATSD_COLLECTOR_USER_NAME=collector
ATSD_COLLECTOR_USER_PASSWORD=collector

COLLECTOR_USER_NAME=axibase
COLLECTOR_USER_PASSWORD=axibase

GITHUB_WEBHOOK_PATH="?exclude=organization.*;repository.*;*.signature;*.payload;*.sha;*.ref;*_at;*.id&include=repository.name;repository.full_name&header.tag.event=X-GitHub-Event&excludeValues=http*&debug=true"
AWS_WEBHOOK_PATH="?command.date=Timestamp&json.parse=Message&exclude=Signature;SignatureVersion;SigningCertURL;SignatureVersion;UnsubscribeURL;MessageId;Message.detail.instance-id;Message.time;Message.id;Message.version"
JENKINS_WEBHOOK_PATH="?command.date=build.timestamp&datetimePattern=milliseconds&exclude=build.url;url;build.artifacts*"
SLACK_WEBHOOK_PATH="?command.message=event.text&command.date=event.ts&exclude=event.event_ts&exclude=event_time&exclude=event.icons.image*&exclude=*thumb*&exclude=token&exclude=event_id&exclude=event.message.edited.ts&exclude=*.ts"
TELEGRAM_WEBHOOK_PATH="?command.message=message.text"

WEBHOOK_USER_RANDOM_PASSWORD_LENGTH=8

declare atsd_import_list
declare collector_import_arg
declare collector_execute_arg
declare import_path

declare test_email
declare -A email_form
declare -A email_form_mapping
email_form_mapping=(
    ["server_name"]="serverName"
    ["server"]="serverHost"
    ["port"]="port"
    ["password"]="password"
    ["user"]="user"
    ["sender"]="senderAddress"
    ["footer"]="messageFooter"
    ["header"]="messageHeader"
    ["auth"]="authentication"
    ["ssl"]="ssl"
    ["upgrade_ssl"]="startTls"
)

declare -A created_webhooks
declare -A webhook_mapping
webhook_mapping=(
    ["github"]="$GITHUB_WEBHOOK_PATH"
    ["aws-cw"]="$AWS_WEBHOOK_PATH"
    ["jenkins"]="$JENKINS_WEBHOOK_PATH"
    ["slack"]="$SLACK_WEBHOOK_PATH"
    ["telegram"]="$TELEGRAM_WEBHOOK_PATH"
)

declare -A telegram_form
declare -A slack_form

function split_by {
    local split_character=$1
    local str_to_split=$2
    # Remove occurrences of the splitting character not preceded by '\',
    # next remove occurrences of '\' that precede the splitting character
    echo "$str_to_split" | sed "s/\\([^\\\\]\\)$split_character/\\1 /g;s/\\\\\\($split_character\\)/\\1/g"
}

function xml_escape {
    local str_to_escape=$1
    # Escape & < > ' " symbols
    echo "$str_to_escape" | sed "s/\&/\&amp;/g;s/</\&lt;/g;s/>/\&gt;/g;s/'/\&apos;/g;s/\"/\&quot;/g"
}

function xml_unescape {
    # Unescape & < > ' " symbols
    sed "s/\&amp;/\&/g;s/\&lt;/</g;s/\&gt;/>/g;s/\&apos;/'/g;s/\&quot;/\"/g"
}

function sed_escape {
    local str_to_escape=$1
    # Escape '\', '/' and '&' symbols
    echo "$str_to_escape" | sed 's:[\/&]:\\&:g'
}

function concat_with {
    local left=$1
    local separator=$2
    local right=$3
    if [ -n "$left" ]; then
        echo -n "$left$separator"
    fi
    echo "$right"
}

# Read input to the end
# curl reports error if we don't do it
function contains {
    local pattern=$1
    cat > /tmp/cmd_output
    grep -q "$pattern" /tmp/cmd_output
    local result=$?
    rm /tmp/cmd_output
    return ${result}
}

function is_enabled {
    local value=$1
    if [ -z "$value" ] || [[ "$value" =~ ^(on|true)$ ]]; then
        return 0
    fi
    return 1
}

function html_extract_text {
    local mark="$1"
    sed -n "/$mark/{s/[^>]\+>\([^<]\+\).*/\1/p;q}"
}

function resolve_file {
    function download_or_fail {
        local url=$1
        local fatal_error_retries=3
        local retry_delay=5
        while [[ ${fatal_error_retries} > 0 ]]; do
            echo "Downloading $url"
            wget --retry-connrefused --waitretry=${retry_delay} \
                -P "$TMP_DOWNLOAD_DIR" "$url"
            local wget_exit_code=$?
            if [ ${wget_exit_code} -eq ${WGET_SUCCESS_CODE} ]; then
                return
            elif [ ${wget_exit_code} -eq ${WGET_NETWORK_FAILURE_CODE} ]; then
                sleep ${retry_delay}
                fatal_error_retries=$((fatal_error_retries-1))
                if [[ ${fatal_error_retries} > 0 ]]; then
                    echo "WARNING: wget network error, retry" >&2
                fi
            else
                break
            fi
        done
        echo "ERROR: unable to download '$url'"
        exit 1
    }

    local current_path=$1
    # Resolve file by URL, absolute path or relative path in $IMPORT_DIR directory
    if [[ "$current_path" =~ (ftp|https?)://.* ]]; then
        download_or_fail "$current_path"
        local file_name=$(ls -1 "$TMP_DOWNLOAD_DIR")
        import_path="$TMP_IMPORT_DIR"/${file_name%\?*}
        mv "$TMP_DOWNLOAD_DIR"/"$file_name" "$import_path"
    elif [[ "$current_path" =~ /.* ]]; then
        if [[ ! -f "$current_path" ]]; then
            echo "ERROR: File '$current_path' doesn't exist" >&2
            exit 1
        fi
        cp "$current_path" "$TMP_IMPORT_DIR"
        import_path="$TMP_IMPORT_DIR"/$(basename "$current_path")
    else
        local source_path="$IMPORT_DIR"/"$current_path"
        import_path="$TMP_IMPORT_DIR"/"$current_path"
        if [[ ! -f "$source_path" ]]; then
            echo "ERROR: File '$source_path' doesn't exist" >&2
            exit 1
        fi
        cp "$source_path" "$import_path"
    fi
}

function prepare_import {
    function extract_job_name {
        local file_path=$1
        sed -n '/<com.axibase.collector.model.job./{n;s/.*<name>\(.*\)<\/name>.*/\1/p;q}' "$file_path"
    }

    function update_atsd_import_list {
        local import_path=$1
        atsd_import_list="$atsd_import_list $import_path"
    }

    function update_collector_argument {
        local import_path=$1
        local job_name=$(extract_job_name "$import_path")
        collector_import_arg=$(concat_with "$collector_import_arg" , "$import_path")
        collector_execute_arg=$(concat_with "$collector_execute_arg" , "$job_name")
    }

    function set_email_form_field {
        local key=$1
        local value=$2
        email_form["$key"]="$value"
    }

    function configure_email_field {
        local key=$3
        local value=$4
        local form_param=${email_form_mapping["$key"]}
        if [ "$key" = "test_email" ]; then
            test_email="$value"
        elif [ -n "$form_param" ]; then
            set_email_form_field "$form_param" "$value"
        else
            echo "WARNING: Unknown email configuration property '$key'" >&2
        fi
    }

    function configure_slack_form_field {
        local key=$3
        local value=$4
        slack_form["$key"]="$value"
    }

    function configure_telegram_form_field {
        local key=$3
        local value=$4
        telegram_form["$key"]="$value"
    }

    function mime_of {
        file --brief --mime-type "$1"
    }

    function configure_from_file {
        local config_func=$1
        local file_path=$2
        local file_to_edit=$3
        local file_with_updates=$4
        local mime_type=$(mime_of "$file_with_updates")
        if ! [[ "$mime_type" =~ text/* ]]; then
            echo "ERROR: Bad file format or encoding '$file_with_updates'" >&2
            exit 1
        fi
        while read edit_line; do
            edit_line=$(echo "$edit_line" | tr '\r' '\n')
            local edit_line_key=${edit_line%%=*}
            local edit_line_value=${edit_line#*=}
            "$config_func" "$file_path" "$file_to_edit" "$edit_line_key" "$edit_line_value"
        done < "$file_with_updates"
    }

    function prepare_import_by_spec {
        local import_spec=$1
        local import_func=$2
        local allow_archives=$3
        mkdir -p "$IMPORT_DIR"
        mkdir -p "$TMP_DOWNLOAD_DIR"
        for current_path in ${import_spec//,/ }; do
            resolve_file "$current_path"
            if [ "$allow_archives" = true ]; then
                prepare_container_file ${import_func} "$import_path"
            else
                prepare_single_file ${import_func} "$import_path"
            fi
        done
        rm -rf "$TMP_DOWNLOAD_DIR"
    }

    function prepare_single_file {
        local import_func=$1
        local import_path=$2
        configure_from_file update_env "$import_path" "" "/tmp/.env"
        ${import_func} "$import_path"
    }

    function prepare_extracted {
        local import_func=$1
        local file_list=$(find "$TMP_EXTRACT_DIR")
        for file in ${file_list}; do
            if [ -f "$file" ]; then
                local file_name=$(basename "$file")
                local relative_path=${file#$"$TMP_EXTRACT_DIR"/}
                local relative_dir=$(dirname "$relative_path")
                local new_import_dir="$TMP_IMPORT_DIR"/"$relative_dir"
                local new_import_path="$TMP_IMPORT_DIR"/"$relative_path"
                mkdir -p "$new_import_dir"
                mv "$file" "$new_import_path"
                prepare_single_file ${import_func} "$new_import_path"
            fi
        done
    }

    function prepare_container_file {
        local import_func=$1
        local file_path=$2
        local mime_type=$(mime_of "$file_path")
        case "$mime_type" in
            application/zip)
                mkdir "$TMP_EXTRACT_DIR"
                if ! unzip "$file_path" -d "$TMP_EXTRACT_DIR" > /dev/null; then
                    echo "ERROR: Failed to extract archive '$file_path'" >&2
                    exit 1
                fi
                prepare_extracted ${import_func}
                rm -rf "$TMP_EXTRACT_DIR"
            ;;
            application/gzip|application/x-gzip)
                mkdir "$TMP_EXTRACT_DIR"
                if ! tar xzvf "$file_path" -C "$TMP_EXTRACT_DIR" > /dev/null; then
                    echo "ERROR: Failed to extract archive '$file_path'" >&2
                    exit 1
                fi
                prepare_extracted ${import_func}
                rm -rf "$TMP_EXTRACT_DIR"
            ;;
            application/xml|text/*)
                prepare_single_file ${import_func} "$import_path"
            ;;
            *)
                echo "ERROR: Unknown format '$mime_type' of file '$file_path'" >&2
                exit 1
            ;;
        esac
    }

    function update_entry {
        local file_path=$1
        local file_to_edit=$2
        local key=$3
        local right_side=$4
        if ! grep -qE "<$key( [^>]*)?>" "$file_path"; then
            echo "WARNING: Tag '$key' not found in '$file_to_edit'" >&2
            continue
        fi
        local value=$(sed_escape $(xml_escape "$right_side"))
        sed -i "/<$key.*>.*<\/$key>/s/>.*</>$value</" "$file_path"
        if [ "$key" = password ]; then
            sed -i "s/<password/& encrypted=\"false\"/" "$file_path"
        fi
    }

    function update_env {
        local file_path=$1
        local key=$3
        local value=$(sed_escape $4)
        sed -i "s/\${ENV.${key}}/${value}/g" "$file_path"
    }

    function update_import_configs {
        if [ -n "$COLLECTOR_CONFIG" ]; then
            local file_edits=$(split_by \; "$COLLECTOR_CONFIG")
            for file_edit in ${file_edits}; do
                local file_to_edit=${file_edit%%:*}
                local file_path="$TMP_IMPORT_DIR"/"$file_to_edit"
                if [ -f "$file_path" ]; then
                    echo "Updating file '$file_to_edit' for import"
                else
                    echo "WARNING: Can't update '$file_to_edit', file doesn't exist" >&2
                    continue
                fi
                local parameter_edits=$(split_by , "${file_edit#*:}")
                for parameter_edit in ${parameter_edits}; do
                    local key=${parameter_edit%%=*}
                    local right_side=${parameter_edit#*=}
                    if [ "$key" == "$right_side" ]; then
                        resolve_file "$key"
                        configure_from_file update_entry "$file_path" "$file_to_edit" "$import_path"
                    else
                        update_entry "$file_path" "$file_to_edit" "$key" "$right_side"
                    fi
                done
            done
        fi
    }

    function check_server_url {
        if [ -n "$SERVER_URL" ]; then
            if ! [[ "$SERVER_URL" =~ ^https?://[^:]+(:[0-9]+)?$ ]]; then
                echo "WARNING: Wrong Server URL '$SERVER_URL' format, should be https://hostname[:port]" >&2
            fi
            if [[ "SERVER_URL" =~ ^http://.* ]]; then
                echo "WARNING: HTTP protocol specified in Server URL '$SERVER_URL', use HTTPS instead" >&2
            fi
        fi
    }

    function check_simplified_configuration {
        if [ -n "$SLACK_TOKEN" ]; then
            configure_slack_form_field "" "" "token" "$SLACK_TOKEN"
        fi
        if [ -n "$SLACK_CHANNELS" ]; then
            configure_slack_form_field "" "" "channels" "$SLACK_CHANNELS"
        else
            configure_slack_form_field "" "" "channels" "general"
        fi

        if [ -n "$TELEGRAM_BOT_TOKEN" ]; then
            configure_telegram_form_field "" "" "bot_token" "$TELEGRAM_BOT_TOKEN"
        fi
        if [ -n "$TELEGRAM_CHAT_ID" ]; then
            configure_telegram_form_field "" "" "chat_id" "$TELEGRAM_CHAT_ID"
        fi
    }

    function configure_email_fields {
        resolve_file "$EMAIL_CONFIG"
        local email_config_file="$import_path"
        set_email_form_field update Update
        set_email_form_field enabled on
        set_email_form_field ssl on
        set_email_form_field startTls on
        if [ -n "$SERVER_URL" ]; then
            set_email_form_field serverName "$SERVER_URL"
        else
            set_email_form_field serverName "Axibase TSD"
        fi
        set_email_form_field port 587
        configure_from_file configure_email_field "" "" "$email_config_file"
        if [ -z ${email_form["senderAddress"]} ]; then
            set_email_form_field "senderAddress" ${email_form["user"]}
        fi
        if [ -n ${email_form["password"]} ] && [ -z ${email_form["authentication"]} ]; then
            set_email_form_field "authentication" on
        fi
        if [ -z "$test_email" ]; then
            test_email=${email_form["senderAddress"]}
        fi

        complete_email_form=true

        if [ -z ${email_form["serverHost"]} ]; then
            echo "[ATSD] Error: empty server mail configuration field. Mail client won't be enabled."
            complete_email_form=false
        fi
        if [ -z ${email_form["user"]} ]; then
            echo "[ATSD] Error: empty user mail configuration field. Mail client won't be enabled."
            complete_email_form=false
        fi
        if [ -z ${email_form["password"]} ]; then
            echo "[ATSD] Warning: empty password mail configuration field. Mail configuration may be incomplete."
        fi
    }

    if [ -f "$FIRST_START_MARKER" ]; then
        check_server_url

        mkdir -p "$TMP_IMPORT_DIR"
        if [ -n "$ATSD_IMPORT_PATH" ]; then
            prepare_import_by_spec "$ATSD_IMPORT_PATH" update_atsd_import_list true
        fi
        if [ -n "$COLLECTOR_IMPORT_PATH" ] && is_enabled "$START_COLLECTOR"; then
            prepare_import_by_spec "$COLLECTOR_IMPORT_PATH" update_collector_argument false
            JOB_PATH=-job-path="$collector_import_arg"
            update_import_configs
        fi
        if [ -n "$EMAIL_CONFIG" ]; then
            configure_email_fields
        fi
        if [ -n "$TELEGRAM_CONFIG" ]; then
            resolve_file "$TELEGRAM_CONFIG"
            local telegram_config_file="$import_path"
            configure_from_file configure_telegram_form_field "" "" "$telegram_config_file"
        fi
        if [ -n "$SLACK_CONFIG" ]; then
            resolve_file "$SLACK_CONFIG"
            local slack_config_file="$import_path"
            configure_from_file configure_slack_form_field "" "" "$slack_config_file"
        fi
        check_simplified_configuration
    fi
}

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
        if curl -i -s \
            --data-urlencode "userBean.username=$user" \
            --data-urlencode "userBean.password=$pass" \
            --data-urlencode "repeatPassword=$pass" \
            http://127.0.0.1:8088/login${params} | contains "$HTTP_FOUND_CODE"; then
            echo "[ATSD] $description account '$user' created." | tee -a  $LOGFILESTART
        else
            echo "[ATSD] Failed to create $description account '$ATSD_COLLECTOR_USER_NAME'." | tee -a  $LOGFILESTART
        fi
    }

    function set_atsd_property {
        local key=$1
        local value=$2

        curl -s -u "$ATSD_ADMIN_USER_NAME":"$ATSD_ADMIN_USER_PASSWORD" \
            --data-urlencode "options[0].key=$key" \
            --data-urlencode "options[0].value=$value" \
            --data-urlencode "apply=Save" \
            http://127.0.0.1:8088/admin/serverproperties
    }

    function configure_phantom {
        local property_name="webdriver.phantomjs.path"
        local binary_location="/opt/atsd/phantomjs-2.1.1-linux-x86_64/bin/phantomjs"
        set_atsd_property "$property_name" "$binary_location"
    }

    function set_server_url {
        if [ -n "$SERVER_URL" ]; then
            set_atsd_property "server.url" "$SERVER_URL"
        fi
    }

    function import_files_into_atsd {
        for file_path in ${atsd_import_list}; do
            echo "[ATSD] Importing '$file_path' configuration"
            if curl -i -s -u "$ATSD_ADMIN_USER_NAME:$ATSD_ADMIN_USER_PASSWORD" \
                    -F "files=@$file_path" \
                    -F "autoEnable=on" \
                    http://127.0.0.1:8088/admin/import-backup | contains "$HTTP_FOUND_CODE" ; then
                echo "[ATSD] Successfully imported '$file_path'"
            else
                echo "[ATSD] Failed to import '$file_path'"
            fi
        done
    }

    function random_password {
        cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w ${WEBHOOK_USER_RANDOM_PASSWORD_LENGTH} | head -n 1
    }

    function save_webhook_url {
        local name=$1
        local password=$2
        local path=$3
        local base_url="$SERVER_URL"
        if [ -z "$base_url" ]; then
            base_url="https://${HOSTNAME}:8443"
        fi
        local url_port=$(echo "$base_url" | sed 's/https:\/\/\([^:]\+\)\(:[0-9]\+\)/\2/')
        if [ -z "$url_port" ]; then
            base_url="${base_url}:8443"
        fi
        if [[ "$base_url" =~ http://.* ]]; then
            base_url=$(echo "${base_url}" | sed "s/^http/https/")
        fi
        base_url="${base_url/:\/\//:\/\/${name}:${password}@}"
        created_webhooks["$name"]="${base_url}/api/v1/messages/webhook/${name}${path}"
    }

    function create_webhook_user {
        local name=$1
        local new_password=$(random_password)
        local url_path=${webhook_mapping["$name"]}

        if [ -z  "$url_path" ]; then
            echo "ERROR: Unknown webhook type '$name'" >&2
            exit 1
        fi

        if curl -i -s -u "axibase:axibase" \
                --data-urlencode "create=Create" \
                --data-urlencode "entity=${name}" \
                --data-urlencode "entityGroup=${name}-entities" \
                --data-urlencode "password=${new_password}" \
                --data-urlencode "repeatPassword=${new_password}" \
                --data-urlencode "userGroup=${name}-users" \
                --data-urlencode "username=${name}" \
                http://127.0.0.1:8088/admin/users/webhook_user | \
           contains "$HTTP_OK_CODE"; then
            echo "[ATSD] $name webhook created"
            save_webhook_url "$name" "$new_password" "$url_path"
        else
            echo "WARNING: Failed to create webhook user '${name}'" >&2
        fi
    }

    function create_webhook_users {
        if [ -n "$WEBHOOK" ]; then
            for webhook_name in ${WEBHOOK//,/ }; do
                create_webhook_user "$webhook_name"
            done
        fi
    }

    function show_webhooks {
        if [ ${#created_webhooks[@]} -gt 0 ]; then
            echo "Webhooks created:"
            for key in ${!created_webhooks[@]}; do
                local value=${created_webhooks["$key"]}
                echo "Webhook user: $key"
                echo "Webhook URL: $value"
                echo
            done
        fi
    }

    function configure_email {
        if [ -n "$EMAIL_CONFIG" ] && [[ "$complete_email_form" == true ]]; then
            declare -a curl_data_arg

            for key in ${!email_form[@]}; do
                local value=${email_form["$key"]}
                curl_data_arg+=("--data-urlencode" "${key}=${value}")
            done

            if curl -i -s -u "axibase:axibase" "${curl_data_arg[@]}" \
                http://127.0.0.1:8088/admin/mailclient | \
                contains "$HTTP_OK_CODE"; then
                echo "[ATSD] Mail Client configured."
            else
                echo "[ATSD] Failed to configure mail client."
            fi

            if [ -n "$test_email" ]; then
                local display_url="$SERVER_URL"
                if [ -z "$display_url" ]; then
                    display_url="https://${HOSTNAME}:8443"
                fi
                local test_subject="Email configuration test from ATSD at ${display_url}"
                local test_response=$(curl -i -s -u "axibase:axibase" \
                    --data-urlencode "send=Send" \
                    --data-urlencode "subject=${test_subject}" \
                    --data-urlencode "email=${test_email}" \
                    http://127.0.0.1:8088/admin/mailclient |& cat)
                local err_message=$(echo "$test_response" | html_extract_text 'span style="color:red"' | xml_unescape)
                if [ -n "$err_message" ]; then
                    echo "[ATSD] Mail Client test failed: $err_message"
                else
                    echo "[ATSD] Mail Client test successful."
                fi
            fi
        fi
    }

    function create_certificate {
        if [ -n "$SERVER_URL" ]; then
            local server_host=$(echo "$SERVER_URL" | sed -e "s/[^/]*\/\/\([^:/]*\).*/\1/")
            if curl -i -s -u "axibase:axibase" \
                    -F "domainName=${server_host}" \
                    http://127.0.0.1:8088/admin/certificates/self-signed | contains "$HTTP_FOUND_CODE"; then
                echo "[ATSD] Custom SSL certificate created."
            else
                echo "[ATSD] WARNING: Updating SSL certificate failed."
            fi
        fi
    }

    function configure_telegram_notifications {
        if [ -n "$TELEGRAM_CONFIG" ] || [ -n "$TELEGRAM_BOT_TOKEN" ]; then
            if [ -z ${telegram_form["bot_token"]} ]; then
                echo "[ATSD] WARNING: Can't configure Telegram Web Notification, empty bot API token"
                return
            fi
            if [ -z ${telegram_form["chat_id"]} ]; then
                echo "[ATSD] WARNING: Can't configure Telegram Web Notification, empty chat ID"
                return
            fi
            echo "[ATSD] Configure Telegram Web Notifications."
            local curl_request="-s -u "axibase:axibase" \
                --data-urlencode "contentType=application/x-www-form-urlencoded" \
                --data-urlencode "parameterModels[0].key=bot_id" \
                --data-urlencode "parameterModels[0].value=${telegram_form["bot_token"]}" \
                --data-urlencode "parameterModels[1].key=chat_id" \
                --data-urlencode "parameterModels[1].value=${telegram_form["chat_id"]}" \
                --data-urlencode "parameterModels[2].key=text" \
                --data-urlencode "parameterModels[2].exposed=on" \
                --data-urlencode "parameterModels[3].key=details_table_format" \
                --data-urlencode "parameterModels[3].exposed=on" \
                --data-urlencode "parameterModels[4].key=disable_notification" \
                --data-urlencode "parameterModels[4].exposed=on" \
                --data-urlencode "pollingEnabled=on" \
                --data-urlencode "updatesEnabled=on" \
                --data-urlencode "enabled=on" \
                --data-urlencode "name=Telegram" \
                --data-urlencode "chatType=TELEGRAM""
            curl ${curl_request} --data-urlencode "save=Save" \
                http://127.0.0.1:8088/admin/web-notifications/telegram/Telegram &> /dev/null
            local response=$(curl ${curl_request} \
                --data-urlencode "test=Test" \
                --data-urlencode "parameterModels[5].key=text" \
                --data-urlencode "parameterModels[5].value=Test message from ATSD \${serverLink}." \
                http://127.0.0.1:8088/admin/web-notifications/telegram/Telegram |& cat)
            local response_status=$(echo "$response" | html_extract_text "response-status")
            if [ -z "$response_status" ]; then
                local error=$(echo "$response" | html_extract_text 'span class="error"')
                echo "[ATSD]   Telegram Web Notification test failed."
                echo "[ATSD]   Error: $error"
            else
                echo "[ATSD]   Telegram Web Notification test "
                local msg_response=$(echo "$response" | html_extract_text 'textarea id="msg-response-body"' | xml_unescape )
                if echo "$msg_response" | grep -q '"ok":false'; then
                    echo "failed."
                    echo "[ATSD]   Error: $msg_response"
                else
                    echo "OK."
                fi
            fi
        fi
    }

    function configure_slack_notifications {
        if [ -n "$SLACK_CONFIG" ] || [ -n "$SLACK_TOKEN" ]; then
            if [ -z ${slack_form["token"]} ]; then
                echo "[ATSD] WARNING: Can't configure Slack Web Notification, empty token"
                return
            fi
            if [ -z ${slack_form["channels"]} ]; then
                echo "[ATSD] WARNING: Can't configure Slack Web Notification, empty channels list"
                return
            fi
            echo "[ATSD] Configure Slack Web Notifications."
            local curl_request="-s -u "axibase:axibase" \
                --data-urlencode "contentType=application/x-www-form-urlencoded" \
                --data-urlencode "parameterModels[0].key=token" \
                --data-urlencode "parameterModels[0].value=${slack_form["token"]}" \
                --data-urlencode "parameterModels[1].key=username" \
                --data-urlencode "parameterModels[1].value=" \
                --data-urlencode "parameterModels[2].key=channels" \
                --data-urlencode "parameterModels[2].value=${slack_form["channels"]}" \
                --data-urlencode "parameterModels[3].exposed=on" \
                --data-urlencode "parameterModels[3].key=text" \
                --data-urlencode "enabled=on" \
                --data-urlencode "name=Slack" \
                --data-urlencode "chatType=SLACK""
            curl ${curl_request} --data-urlencode "save=Save" \
                http://127.0.0.1:8088/admin/web-notifications/slack/Slack &> /dev/null
            local response=$(curl ${curl_request} \
                --data-urlencode "parameterModels[3].key=text" \
                --data-urlencode "parameterModels[3].value=Test message from ATSD \${serverLink}." \
                --data-urlencode "test=Test" \
                http://127.0.0.1:8088/admin/web-notifications/slack/Slack |& cat)
            local response_status=$(echo "$response" | html_extract_text "response-status")
            if [ -z "$response_status" ]; then
                local error=$(echo "$response" | html_extract_text 'span class="error"')
                echo "[ATSD]   Slack Web Notification test failed."
                echo "[ATSD]   Error: $error"
            else
                echo -n "[ATSD]   Slack Web Notification test "
                local msg_response=$(echo "$response" | html_extract_text 'textarea id="msg-response-body"' | xml_unescape)
                if echo "$msg_response" | grep -q '"ok":false'; then
                    echo "failed."
                    echo "[ATSD]   Error: $msg_response"
                else
                    echo "OK."
                fi
            fi
        fi
    }

    function update_input_settings {
        curl -s -u "axibase:axibase" \
            http://127.0.0.1:8088/admin/inputsettings \
            --data-urlencode "commandLogEnabled=on" \
            --data-urlencode "csvEnabled=on" \
            --data-urlencode "hbaseWriteEnabled=on" \
            --data-urlencode "lastInsertEnabled=on" \
            --data-urlencode "lastInsertHbaseWriteEnabled=on" \
            --data-urlencode "lastInsertStatisticsEnabled=on" \
            --data-urlencode "malformedLogEnabled=on" \
            --data-urlencode "messageEnabled=on" \
            --data-urlencode "metricEnabled=on" \
            --data-urlencode "propertyEnabled=on" \
            --data-urlencode "ruleEnabled=on" \
            --data-urlencode "update-gateway=Update" > /dev/null
    }

    function post_start {
        if [ -f "$FIRST_START_MARKER" ]; then
            set_tz
            create_account "$ATSD_COLLECTOR_USER_NAME" "$ATSD_COLLECTOR_USER_PASSWORD" "?type=writer" "Collector"
            create_account "$ATSD_ADMIN_USER_NAME" "$ATSD_ADMIN_USER_PASSWORD" "" "Administrator"
            create_certificate
            configure_phantom
            import_files_into_atsd
            create_webhook_users
            configure_email
            configure_telegram_notifications
            configure_slack_notifications
            update_input_settings
        fi
    }

    su axibase ${ATSD_ALL} start
    if [ $? -eq 1 ]; then
        echo "[ATSD] Failed to start ATSD. Check $LOGFILESTART file." | tee -a $LOGFILESTART
        exit 1
    fi

    post_start
}

function start_collector {
    SCRIPTS_HOME="/opt/axibase-collector/bin"

    cd ${SCRIPTS_HOME}
    echo "Starting Axibase Collector ..."

    function validate_docker_socket {
        echo -n "Checking docker socket: ... "
        check_res=$(java -classpath \
            "../exploded/webapp/WEB-INF/classes:../exploded/webapp/WEB-INF/lib/*" \
            com.axibase.collector.util.UnixSocketUtil "$DOCKER_SOCKET" 2>&1);
        if ! [[ -z "$check_res" ]]; then
            if [ "$check_res" == "OK" ]; then
                echo "OK"
            elif [[ "$check_res" == "FAILED"* ]]; then
                echo "$check_res"
            elif [[ "$check_res" == "Unable to read"* ]]; then
                echo "error; $check_res"
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

    function create_collector_account {
        if [ -f "$FIRST_START_MARKER" ]; then
            if curl -i -s --insecure \
                --data-urlencode "user.username=$COLLECTOR_USER_NAME" \
                --data-urlencode "newPassword=$COLLECTOR_USER_PASSWORD" \
                --data-urlencode "confirmedPassword=$COLLECTOR_USER_PASSWORD" \
                --data-urlencode "commit=Save" \
                https://127.0.0.1:9443/register.xhtml | grep -q "$HTTP_FOUND_CODE"; then
                echo "[Collector] Account '$COLLECTOR_USER_NAME' created."
            else
                echo "[Collector] Failed to create account '$COLLECTOR_USER_NAME'."
            fi
        fi
    }

    if [ -e "$DOCKER_SOCKET" ]; then
        validate_docker_socket
        collector_execute_arg=$(concat_with "$collector_execute_arg" , docker-socket)
    fi
    start_cron

    if [ -n "$collector_execute_arg" ]; then
        JOB_ENABLE=-job-enable="$collector_execute_arg"
        JOB_EXECUTE=-job-execute="$collector_execute_arg"
        WAIT_EXEC="wait-exec"
    fi

    #Start collector
    ./start-collector.sh "$WAIT_EXEC" \
        -atsd-url="https://${ATSD_COLLECTOR_USER_NAME}:${ATSD_COLLECTOR_USER_PASSWORD}@localhost:8443" \
        "$JOB_ENABLE" "$JOB_PATH" "$JOB_EXECUTE"

    if [ $? -eq 1 ]; then
        echo "[Collector] Failed to start Collector."
        exit 1
    fi

    create_collector_account
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

prepare_import
start_atsd
start_collectd

if is_enabled "$START_COLLECTOR"; then
    start_collector
fi

echo 'All applications started'
if [ -f "$FIRST_START_MARKER" ]; then
    rm "$FIRST_START_MARKER"
    show_webhooks
fi
wait_loop
echo "SIGTERM received ( docker stop ). Stopping services ..." | tee -a $LOGFILESTOP
stop_services
