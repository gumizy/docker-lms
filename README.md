# docker-lms

## require
In springboot jar:
- mysql: host is localhost, username is root, password is empty!

## git clone
- git clone https://xxxx

## change mod
- cd docker-lms
- chmod 777 *

## docker build
- docker build -t dcsec/lms:v1.0 .

## docker run
- docker run --name lms -p 8080:8080 dcsec/lms:v1.0
- or
- docker run --name lms -d -p 8080:8080 dcsec/lms:v1.0 (in damon)

## docker save(export)
- docker save -o dcsec/lms:v1.0 lms.tar 

## docker load
- docker load < lms.tar


## Others
- enter the container: docker exec -it [docker_container_name] /bin/bash