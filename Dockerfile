FROM docker:19-dind

ENV ADVERTISE_ADDR=eth0

RUN mkdir -p /docker/portainer && \
    mkdir -p /docker/mounts && \
    mkdir -p /docker/confs && \
    apk --no-cache add httpie jq

COPY bootstrap.yml /docker/confs/bootstrap.yml
COPY management.yml /docker/confs/management.yml
COPY bootstrap-entrypoint.sh /docker/bootstrap-entrypoint.sh

RUN chmod 755 /docker/bootstrap-entrypoint.sh

ENTRYPOINT ["/docker/bootstrap-entrypoint.sh"]

