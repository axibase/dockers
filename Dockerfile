FROM openjdk:8-jdk-slim
ENV version=26577 LANG=en_US.UTF-8

ARG version=26577

# metadata
LABEL com.axibase.maintainer="ATSD Developers" \
  com.axibase.vendor="Axibase Corporation" \
  com.axibase.product="Axibase Time Series Database" \
  com.axibase.code="ATSD" \
  com.axibase.revision="$version"

# add entrypoint and image cleanup script
COPY entry*.sh /

# install and configure pseudo-cluster
RUN apt-get update \
  && apt install -y locales curl procps iproute2 \
  && locale-gen en_US.UTF-8;
  
  
#  
RUN curl -s atsd.standalone.tar.gz https://axibase.com/public/atsd.standalone.$version.tar.gz | tar -xzv -C /opt/

   
#RUN tar -xzvf atsd.standalone.tar.gz -C /opt/ \
#  && rm -rf atsd.standalone.tar.gz;  
  
RUN adduser --disabled-password --quiet --gecos "" axibase;   

COPY hbase-shell /opt/atsd/hbase

ADD https://repo1.maven.org/maven2/org/jruby/jruby-complete/1.6.8/jruby-complete-1.6.8.jar /opt/atsd/hbase/lib

RUN /entrycleanup.sh;

USER axibase

# jmx, network commands(tcp), network commands(udp), trades, statistics, graphite, http, https
EXPOSE 1099 8081 8082/udp 8084 8085 8086/udp 8091 8092/udp 8088 8443

VOLUME ["/opt/atsd"]

ENTRYPOINT ["/bin/bash", "/entrypoint.sh"]
