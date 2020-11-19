FROM openjdk:8-jdk-slim
ENV version=12345 LANG=en_US.UTF-8

ARG version=12345

# metadata
LABEL com.axibase.maintainer="ATSD Developers" \
  com.axibase.vendor="Axibase Corporation" \
  com.axibase.product="Axibase Time Series Database" \
  com.axibase.code="ATSD" \
  com.axibase.revision="$version"

# add entrypoint and image cleanup script
COPY entry*.sh /

COPY atsd.standalone.tar.gz /

# install and configure pseudo-cluster
RUN apt-get update \
  && apt install -y curl procps iproute2;
  
#RUN curl -o atsd.standalone.tar.gz https://axibase.com/public/atsd.standalone.$version.tar.gz \
#  && tar -xzvf atsd.standalone.tar.gz -C /opt/ \
#  && rm -rf atsd.standalone.tar.gz; 

RUN which ss
   
RUN tar -xzvf atsd.standalone.tar.gz -C /opt/ \
  && rm -rf atsd.standalone.tar.gz;  


  
RUN adduser --disabled-password --quiet --gecos "" axibase;   
  
RUN /entrycleanup.sh;

USER axibase

# jmx, network commands(tcp), network commands(udp), graphite, http, https
EXPOSE 1099 8081 8082/udp 8085 8086 8084 8088 8443

VOLUME ["/opt/atsd"]

ENTRYPOINT ["/bin/bash", "/entrypoint.sh"]
