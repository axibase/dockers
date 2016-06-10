FROM alpine:latest
MAINTAINER ATSD Developers <dev-atsd@axibase.com>
ENV ftpuser="ftp-user"

RUN apk add --no-cache openssh && \
    addgroup ftpaccess && \
    mkdir -p /home/${ftpuser}/ftp && \
    adduser -D -G ftpaccess -s /usr/sbin/nologin ${ftpuser} && \
    chown root:root /home/${ftpuser} && \
    chown ${ftpuser}:ftpaccess /home/${ftpuser}/ftp

ADD entrypoint.sh /opt/entrypoint.sh
ADD sshd_config /etc/ssh/sshd_config 

WORKDIR /home/${ftpuser}

#sftp
EXPOSE 22
VOLUME ["/home/${ftpuser}"]
ENTRYPOINT ["/bin/sh", "/opt/entrypoint.sh"]
