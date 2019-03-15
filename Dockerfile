FROM centos

MAINTAINER dcsec dcsec.dev@datacloudsec.com

ARG PACKAGE_URL=https://repo.mysql.com/yum/mysql-5.7-community/docker/x86_64/mysql-community-server-minimal-5.7.22-1.el7.x86_64.rpm
ARG PACKAGE_URL_SHELL=https://repo.mysql.com/yum/mysql-tools-community/el/7/x86_64/mysql-shell-1.0.11-1.el7.x86_64.rpm
ENV MYSQL_ALLOW_EMPTY_PASSWORD=yes
ENV MYSQL_ROOT_HOST=127.0.0.1
ENV MYSQL_ROOT_PASSWORD=

RUN rpmkeys --import https://repo.mysql.com/RPM-GPG-KEY-mysql \
    && yum install -y $PACKAGE_URL $PACKAGE_URL_SHELL libpwquality java-1.8.0-openjdk-headless \
    && yum clean all \
    && mkdir /docker-entrypoint-initdb.d

VOLUME /var/lib/mysql

EXPOSE 8080/tcp

COPY authorization.sql /docker-entrypoint-initdb.d/
COPY base-0.0.1-SNAPSHOT.jar /usr/local/
COPY docker-entrypoint.sh /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
