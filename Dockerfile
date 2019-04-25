FROM ubuntu:16.04
MAINTAINER ATSD Developers <dev-atsd@axibase.com>
ENV version latest
ENV DEPLOYMENT_TYPE api-test
#metadata
LABEL com.axibase.vendor="Axibase Corporation" \
  com.axibase.product="Axibase Time Series Database: API Test Non-distributed" \
  com.axibase.code="ATSD" \
  com.axibase.revision="${version}"
  
#install and configure
RUN apt-key adv --keyserver hkp://keyserver.ubuntu.com --recv-keys 26AEE425A57967CFB323846008796A6514F3CB79 \
  && apt-get update \
  && apt-get install --no-install-recommends -y locales apt-transport-https \
  && echo "deb [arch=amd64] http://axibase.com/public/repository/deb/ ./" >> /etc/apt/sources.list \
  && apt-get update \
  && locale-gen en_US.UTF-8 \
  && adduser --disabled-password --quiet --gecos "" axibase \
  && apt-get install --no-install-recommends -y atsd nano less wget curl && rm -rf /var/lib/apt/lists/* \
  && su -c '/opt/atsd/bin/atsd-all.sh stop' axibase

#put script to docker
ADD hbase-site.xml /opt/atsd/hbase/conf/
ADD rules.xml /opt/atsd/
ADD logback.xml /opt/atsd/atsd/conf/
ADD server.properties /opt/atsd/atsd/conf/

#custom entrypoint to api-test reason
ADD entrypoint-api-test.sh /

RUN chown -R axibase:axibase /opt/atsd /entrypoint*

USER axibase
#jmx, atsd(tcp), atsd(udp), pickle, http, https
EXPOSE 1099 8081 8082/udp 8084 8088 8443
VOLUME ["/opt/atsd"]
ENTRYPOINT ["/bin/bash","/entrypoint-api-test.sh"]
