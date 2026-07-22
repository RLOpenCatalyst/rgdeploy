#!/bin/bash
version='0.3.0'
echo "deleteusers.sh v($version)"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CSV="${SCRIPT_DIR}/removeusers.csv"
REMOVE_USER="${SCRIPT_DIR}/remove-user.sh"

if [ ! -f "$CSV" ]; then
	echo "File removeusers.csv not found!"
	exit 1
fi

if [ ! -x "$REMOVE_USER" ]; then
	echo "Could not find executable remove-user.sh at $REMOVE_USER"
	exit 1
fi

# No header row in CSV; dedupe while preserving first-seen order
mapfile -t users < <(sed 's/\r$//' "$CSV" | sed '/^[[:space:]]*$/d' | awk '!seen[$0]++')

echo "Processing ${#users[@]} unique user(s) from $CSV"

for username in "${users[@]}"; do
	username=$(echo "$username" | xargs)
	[ -z "$username" ] && continue
	echo "=== Removing $username ==="
	if ! "$REMOVE_USER" "$username"; then
		echo "WARNING: remove-user.sh failed for $username"
	fi
	sleep 6
done

echo "Done."
