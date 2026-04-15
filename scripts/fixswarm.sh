#!/bin/bash
version="0.1.4"
echo "Fixing swarm....(fixswarm.sh v$version)"
STACK_NAME="${STACK_NAME:-sp2}"

[ -z "$RG_HOME" ] && RG_HOME="/opt/deploy/${STACK_NAME}"
echo "RG_HOME=$RG_HOME"

# Remove the stack which is deployed if any
echo "Removing ${STACK_NAME} stack"
docker stack remove "${STACK_NAME}"
old_secrets=$(docker secret ls | grep -i "${STACK_NAME}prod" | awk '{print $1}')
if [ -n "$old_secrets" ]; then
	echo "Found old secrets. Removing..."
	echo "$old_secrets" |
		while IFS=$'\n' read -r mysecret; do
			docker secret rm "$mysecret"
		done
fi
echo "Waiting 15 seconds"
sleep 15

# Remove this node from the swarm
echo 'Removing this node from the swarm'
docker swarm leave --force

# Remove the ingress network that is stuck
echo "Removing the stuck ingress network"
docker network rm ingress
#docker network ls | grep -e 'ingress.*overlay' | awk '{print $1}'

# trunk-ignore(shellcheck/SC2181)
[ $? -gt 0 ] && echo "Could not remove ingress network. Exiting" && exit 0

echo "You can now re-deploy your stack using start_server.sh"
