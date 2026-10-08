#!/usr/bin/env bash
# Asserts --dry-run prints one planned action per dummy study and does not invoke goofys.
set -euo pipefail

root="$(cd "$(dirname "$0")" && pwd)"
script="${root}/mount_s3 (6).sh"
config="${root}/s3mounts.dryrun.json"
out="$(mktemp)"
err="$(mktemp)"
trap 'rm -f "$out" "$err"' EXIT

bash "$script" --dry-run --config "$config" >"$out" 2>"$err"

if [ -s "$err" ]; then
    printf 'unexpected stderr:\n%s\n' "$(cat "$err")" >&2
    exit 1
fi

if grep -v '^DRY-RUN: ' "$out" | grep -q .; then
    printf 'stdout has lines that are not dry-run actions:\n%s\n' "$(cat "$out")" >&2
    exit 1
fi

if grep -v '^DRY-RUN: ' "$out" | grep -q 'goofys'; then
    printf 'goofys was invoked outside a dry-run line\n' >&2
    exit 1
fi

studies="${HOME}/studies"
s3files="${studies}/.s3files"
expected=(
    "DRY-RUN: mount s3files rw fs-dummy-shared -> ${s3files}/fs-dummy-shared"
    "DRY-RUN: mount s3files rw fs-dummy-ingress -> ${s3files}/fs-dummy-ingress"
    "DRY-RUN: goofys rw dummy-internal:InternalRW/ -> ${studies}/DummyInternalRW"
    "DRY-RUN: goofys ro dummy-internal:InternalRO/ -> ${studies}/DummyInternalRO"
    "DRY-RUN: goofys ro dummy-external:ExternalRO/ -> ${studies}/DummyExternalRO profile=DummyExternalRO kms=arn:aws:kms:us-east-2:000000000000:key/dry-run"
    "DRY-RUN: goofys rw dummy-defaults:Defaults/ -> ${studies}/DummyDefaults"
    "DRY-RUN: skip DummyUnreadable (readable=false)"
    "DRY-RUN: bind ro ${s3files}/fs-dummy-shared/SharedRO -> ${studies}/DummySharedRO"
    "DRY-RUN: symlink DummySharedRW -> ${s3files}/fs-dummy-shared/SharedRW"
    "DRY-RUN: bind ro ${s3files}/fs-dummy-ingress/IngressRO -> ${studies}/DummyIngressRO"
)

for line in "${expected[@]}"; do
    count="$(grep -c -F -x "$line" "$out" || true)"
    if [ "$count" -ne 1 ]; then
        printf 'expected exactly one line:\n%s\nfound %s\nfull output:\n%s\n' \
            "$line" "$count" "$(cat "$out")" >&2
        exit 1
    fi
done

if [ "$(wc -l < "$out")" -ne "${#expected[@]}" ]; then
    printf 'unexpected extra dry-run lines:\n%s\n' "$(cat "$out")" >&2
    exit 1
fi

printf 'dry-run check passed (%s actions)\n' "${#expected[@]}"
