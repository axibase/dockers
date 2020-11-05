#!/bin/bash
DISTR_HOME="/opt/atsd"

echo "Initiate build cleanup in ${DISTR_HOME}. Current user: `whoami`"

cd ${DISTR_HOME}
chown -R axibase:axibase ${DISTR_HOME}
