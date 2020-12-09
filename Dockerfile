FROM axibase/atsd
MAINTAINER ATSD Developers <dev-atsd@axibase.com>
ENV version latest
ENV DEPLOYMENT_TYPE api-test
#metadata
LABEL com.axibase.vendor="Axibase Corporation" \
  com.axibase.product="Axibase Time Series Database: API Test Non-distributed" \
  com.axibase.code="ATSD" \
  com.axibase.revision="${version}"

#put script to docker
ADD rules.xml /opt/atsd/
ADD logback.xml /opt/atsd/conf/
ADD server.properties /opt/atsd/conf/

#custom entrypoint to api-test reason
ADD entrypoint-api-test.sh /

USER root

RUN chown -R axibase:axibase /opt/atsd /entrypoint*

USER axibase


#jmx, atsd(tcp), atsd(udp), pickle, http, https trades-csv(tcp)
EXPOSE 1099 8081 8082/udp 8084 8088 8443 8085
VOLUME ["/opt/atsd"]
ENTRYPOINT ["/bin/bash","/entrypoint-api-test.sh"]
