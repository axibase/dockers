FROM ubuntu:16.04
MAINTAINER ATSD Developers <dev-atsd@axibase.com>
ENV version 17258
ENV LANG en_US.UTF-8
#metadata
LABEL com.axibase.vendor="Axibase Corporation" \
  com.axibase.product="Axibase Time Series Database" \
  com.axibase.code="ATSD" \
  com.axibase.revision="${version}"

#install and configure
RUN apt-key adv --keyserver hkp://keyserver.ubuntu.com --recv-keys 26AEE425A57967CFB323846008796A6514F3CB79 \
  && echo "deb [arch=amd64] http://axibase.com/public/repository/deb/ ./" >> /etc/apt/sources.list \
  && apt-get update \
  && apt-get install --no-install-recommends -y locales \
  && locale-gen en_US.UTF-8 \
  && adduser --disabled-password --quiet --gecos "" axibase \
  && apt-get install --no-install-recommends -y atsd=${version}  && rm -rf /var/lib/apt/lists/*;

#set hbase distributed mode false
RUN sed -i '/.*hbase.cluster.distributed.*/{n;s/.*/   <value>false<\/value>/}' /opt/atsd/hbase/conf/hbase-site.xml

#jmx, atsd(tcp), atsd(udp), pickle, http, https
EXPOSE 1099 8081 8082/udp 8084 8088 8443
VOLUME ["/opt/atsd"]

ENTRYPOINT ["/bin/bash","/opt/atsd/bin/entrypoint.sh"]
