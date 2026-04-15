#!/bin/bash
version="0.1.5"
echo "Fixing secrets...(fixsecrets.sh v$version)"
STACK_NAME="${STACK_NAME:-sp2}"

[ -z "$RG_HOME" ] && RG_HOME="/opt/deploy/${STACK_NAME}"
echo "RG_HOME=$RG_HOME"

old_secrets=$(docker secret ls | awk '{print $2}' | rg "^(${STACK_NAME}prod|${STACK_NAME})-(config|alert-config)\\.json$" || true)
if [ -n "$old_secrets" ]; then
	echo "Found old secrets. Removing..."
	echo "$old_secrets" |
		while IFS=$'\n' read -r mysecret; do
			docker secret rm "$mysecret"
		done
fi
docker secret create "${STACK_NAME}-config.json" "${RG_HOME}/config/config.json"
docker secret create "${STACK_NAME}-alert-config.json" "${RG_HOME}/config/alert-config.json"
