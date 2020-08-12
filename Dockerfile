FROM docker:19-dind

RUN mkdir -p /management/portainer && \
    mkdir -p /management/mounts && \
    mkdir -p /management/confs && \
    apk --no-cache add httpie jq

COPY bootstrap.yml /management/confs/bootstrap.yml
COPY management.yml /management/confs/management.yml
COPY bootstrap-entrypoint.sh /management/bootstrap-entrypoint.sh

RUN chmod 755 /management/bootstrap-entrypoint.sh

ENTRYPOINT ["/management/bootstrap-entrypoint.sh"]

