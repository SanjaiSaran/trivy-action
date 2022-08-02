FROM docker.io/debian:buster-20201209
RUN mkdir /data
COPY log4j-core-2.14.1.jar /data
