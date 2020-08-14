#!/bin/sh

# configure docker storage driver based on env var
if [ -z "$STORAGE_DRIVER" ];
then
  # STORAGE_DRIVER is unset or blank
  jq '.-{"storage-driver":""}' /etc/docker/daemon.json | sudo tee /etc/docker/daemon.json
else
  jq ".+{\"storage-driver\":\"$STORAGE_DRIVER\"}" /etc/docker/daemon.json | sudo tee /etc/docker/daemon.json
fi

# we need dockerd running to bootstrap the stack.  However, if we fork our bootstrap
# and then exec our dockerd we zombie our bootstrap when this process is replaced,
# so instead lets just start dockerd temporarily.
touch nohup.out
nohup /usr/local/bin/dockerd-entrypoint.sh $@ & tail -f nohup.out &
( tail -f -n0 nohup.out & ) | grep -q "API listen on /var/run/docker.sock"

# now lets do our initializations
if [ "inactive" = "$(docker info 2>/dev/null | grep "Swarm:" | awk '{ print $2 }')" ];
then
  docker swarm init --advertise-addr $ADVERTISE_ADDR
fi

# if /management/portainer is empty or the stack is missing then bootstrap the management stack
if [ "$(docker stack ls | grep -c management)" == "0" ];
then
  docker run -d -p 9001:9000 --name=portainer-bootstrap -v /var/run/docker.sock:/var/run/docker.sock -v /management/portainer:/data portainer/portainer
  ( docker logs -f portainer-bootstrap 2>&1 & ) | grep -q "Starting Portainer .* on :9000"
  http POST :9001/api/users/admin/init Username="admin" Password="changeme"
  auth_token=$(http POST :9001/api/auth Username="admin" Password="changeme" | jq -r ".jwt")
  http --form POST :9001/api/endpoints "Authorization: Bearer $auth_token" Name="local" EndpointType=1
  swarm_id=$(http -b GET :9001/api/endpoints/1/docker/swarm "Authorization: Bearer $auth_token" | jq -r ".ID")
  http POST ":9001/api/stacks?method=string&type=1&endpointId=1" "Authorization: Bearer $auth_token" \
    Name="management" SwarmID="$swarm_id" \
    StackFileContent=@/management/confs/bootstrap.yml
  docker stop portainer-bootstrap
  while [ "$(docker inspect --format='{{ .State.Running }}' portainer-bootstrap)" != "false" ]; do sleep 1; done
  docker rm portainer-bootstrap
  docker service scale management_portainer=1
  ( docker sevice logs -f portainer-bootstrap 2>&1 & ) | grep -q "Starting Portainer .* on :9000"
  auth_token=$(http POST :9000/api/auth Username="admin" Password="changeme" | jq -r ".jwt")
  http PUT ":9000/api/stacks/1?endpointId=1" "Authorization: Bearer $auth_token" StackFileContent=@/management/confs/management.yml
fi

# shutdown our temp dockerd before we exec the original entrypoint so it assumes our pid
kill $(cat /var/run/docker.pid)
while [ "$(ps -ef | grep dockerd | grep -v grep | wc -l)" != "0" ]; do sleep 1; done
pkill -f "tail -f nohup.out"

exec /usr/local/bin/dockerd-entrypoint.sh $@
