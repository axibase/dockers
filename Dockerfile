FROM ubuntu:16.04
ENV version=22350 LANG=en_US.UTF-8

# metadata
LABEL com.axibase.maintainer="ATSD Developers" \
  com.axibase.vendor="Axibase Corporation" \
  com.axibase.product="Axibase Time Series Database" \
  com.axibase.code="ATSD" \
  com.axibase.revision="${version}"

# add entrypoint and image cleanup script
COPY entry*.sh /  

# install and configure pseudo-cluster
RUN apt-key adv --keyserver hkp://keyserver.ubuntu.com --recv-keys 26AEE425A57967CFB323846008796A6514F3CB79 \
  && apt-get update \
  && LANG=C DEBIAN_FRONTEND=noninteractive apt-get install -y locales apt-utils apt-transport-https \
  && echo "deb [arch=amd64] https://axibase.com/public/repository/deb/ ./" >> /etc/apt/sources.list \
  && apt-get update \
  && locale-gen en_US.UTF-8 \
  && adduser --disabled-password --quiet --gecos "" axibase \
  && DEBIAN_FRONTEND=noninteractive apt-get install --no-install-recommends -y atsd=${version} nano \
  && rm -rf /var/lib/apt/lists/* \
  && sed -i '/.*hbase.cluster.distributed.*/{n;s/.*/   <value>false<\/value>/}' /opt/atsd/hbase/conf/hbase-site.xml \
  && /entrycleanup.sh;

USER axibase

# jmx, network commands(tcp), network commands(udp), graphite, http, https
EXPOSE 1099 8081 8082/udp 8084 8088 8443

VOLUME ["/opt/atsd"]

ENTRYPOINT ["/bin/bash", "/entrypoint.sh"]
