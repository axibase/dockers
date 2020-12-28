# Axibase Time Series Database

## Overview

Axibase Time Series Database (ATSD) is a specialized database for storing and analyzing time series data.

ATSD provides the following tools for application developers and data scientists:

- Network API, CSV parsers, Storage Drivers, and Axibase Collector to collect time-series data.
- Rest API and API clients for integration with Python, Java, Go, Ruby, NodeJS applications and R scripts.
- SQL support with time-series extensions for scheduled and ad-hoc reporting.
- Built-in declarative visualization library with 15 time-series widgets.
- Rule engine with support for analytical rules and anomaly detection based on ARIMA and Holt-Winters forecasts.

Refer to [ATSD Documentation](https://axibase.com/docs/atsd/) for additional details.

## Image Summary

* Image name: `axibase/atsd:standalone`
* Base Image: Ubuntu 16.04
* [Dockerfile](https://github.com/axibase/dockers/blob/master/Dockerfile)

## Start Container

```properties
docker run \
  --detach \
  --name=atsd \
  --restart=always \
  --publish 8088:8088 \
  --publish 8443:8443 \
  --publish 8081:8081 \
  --publish 8082:8082/udp \
  axibase/atsd:latest
```

## Check Installation

Watch for **ATSD start completed** message at the end of the `start.log` file.

```sh
docker logs -f atsd
```

```txt
[ATSD] Starting ATSD ...
...
[ATSD] Waiting for ATSD to start. Checking ATSD user interface port 8088 ...
[ATSD] Waiting for ATSD to bind to port 8088 ...( 1 of 20 )
...
[ATSD] ATSD web interface:
[ATSD] http://172.17.0.2:8088
[ATSD] https://172.17.0.2:8443
[ATSD] ATSD start completed.
```

The user interface is accessible on port `8443`/https.

## Launch Parameters

| **Name** | **Required** | **Description** |
|:---|:---|:---|
|`--detach` | Yes | Run container in background and print container id. |
|`--hostname` | No | Assign hostname to the container. |
|`--name` | No | Assign a unique name to the container. |
|`--restart` | No | Auto-restart policy. _Not supported in all Docker Engine versions._ |
|`--publish` | No | Publish a container's port to the host. |
|`--env` | No | Define a new environment variable inside the container in _key=value_ format. |

## Environment Variables

| **Name** | **Required** | **Description** |
|:---|:---|:---|
|`ADMIN_USER_NAME` | No | User name for the built-in administrator account. |
|`ADMIN_USER_PASSWORD` | No | [Password](https://axibase.com/docs/atsd/administration/user-authentication.html#password-requirements) for the built-in administrator.|
|`COLLECTOR_USER_NAME` | No | User name for a data [collector account](https://axibase.com/docs/atsd/administration/collector-account.html). |
|`COLLECTOR_USER_PASSWORD` | No | [Password](https://axibase.com/docs/atsd/administration/user-authentication.html#password-requirements) for a data collector account.|
|`COLLECTOR_USER_TYPE` | No | User group for a data collector account, default value is `writer`.|
|`DB_TIMEZONE` | No | Database [timezone identifier](https://axibase.com/docs/atsd/administration/timezone.html).|
|`JAVA_OPTS` | No | Additional arguments to be passed to ATSD JVM process. |

View additional launch examples [here](https://axibase.com/docs/atsd/installation/docker.html).

## Exposed Ports

| **Name** | **Protocol** | **Description** |
|:---|:---|:---|
| 8088 | http | API, user interface. |
| 8443 | https | API, user interface (secure). |
| 8081 | tcp | Incoming [network commands](https://axibase.com/docs/atsd/api/network/#connection). |
| 8082 | udp | Incoming [network commands](https://axibase.com/docs/atsd/api/network/#udp-datagrams). |
| 8084 | tcp | Incoming Graphite commands in Python pickle format. |
| 1099 | tcp | JMX |

## Troubleshooting

* Review [Troubleshooting Guide](https://axibase.com/docs/atsd/installation/troubleshooting.html).

## Validation

* [Verify installation](https://axibase.com/docs/atsd/installation/verifying-installation.html).

## Post-installation Steps

* [Basic configuration](https://axibase.com/docs/atsd/installation/post-installation.html).
* [Getting Started guide](hhttps://axibase.com/docs/atsd/tutorials/getting-started.html).
