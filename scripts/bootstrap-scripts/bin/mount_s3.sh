#!/usr/bin/env bash
# Mounts S3 / S3 Files study data onto the local filesystem.
#
# Config: /usr/local/etc/s3-mounts.json  (override with --config PATH)
#  [{
#   "id": "STUDY_ID",
#   "bucket": "BUCKET_NAME",
#   "prefix": "BUCKET_PREFIX",
#   "source": "S3" | "S3Files",
#   "filesystem-id": "fs-..."   # required when source is S3Files
#   "mount-target-ip": "10.0.0.50" # required for S3Files when DNS is unavailable
#   "writeable": true,          # false mounts the study path read-only ("writable" is an alias)
#   "readable": true            # false skips the study
# }, ...]
#
# S3Files: mount each filesystem once under ~/studies/.s3files/<fs-id>,
# then symlink ~/studies/<id> -> <mount>/<prefix> when the study is writeable.
# Read-only studies use a read-only bind mount of that prefix so a shared
# filesystem can stay read-write for other studies.
# Do not mount NFS on the study path itself (that exposes lost+found and
# confuses GNOME Files).
#
# --dry-run prints the planned actions and does not mount, unmount, or write.

CONFIG="/usr/local/etc/s3-mounts.json"
TARGET_USER=""
DRY_RUN=false

usage() {
    printf 'Usage: %s [--dry-run] [--config PATH] [--user NAME]\n' "$(basename "$0")" >&2
}

while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --config)
            if [ $# -lt 2 ]; then
                usage
                exit 1
            fi
            CONFIG="$2"
            shift 2
            ;;
        --config=*)
            CONFIG="${1#--config=}"
            shift
            ;;
        --user)
            if [ $# -lt 2 ]; then
                usage
                exit 1
            fi
            TARGET_USER="$2"
            shift 2
            ;;
        --user=*)
            TARGET_USER="${1#--user=}"
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            printf 'Unknown argument: %s\n' "$1" >&2
            usage
            exit 1
            ;;
    esac
done

resolve_target_user() {
    local user home
    if [ -n "$TARGET_USER" ]; then
        printf '%s\n' "$TARGET_USER"
        return
    fi
    if [ "$(id -u)" -ne 0 ]; then
        printf '%s\n' "$(id -un)"
        return
    fi
    # sudo bash mount_s3.sh must mount the calling user's studies, not /root/studies.
    if [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ]; then
        printf '%s\n' "$SUDO_USER"
        return
    fi
    for user in ec2-user ubuntu sagemaker-user; do
        home="$(getent passwd "$user" 2>/dev/null | cut -d: -f6)"
        if [ -n "$home" ] && [ -d "$home" ]; then
            printf '%s\n' "$user"
            return
        fi
    done
    printf '%s\n' "$(id -un)"
}

TARGET_USER="$(resolve_target_user)"
TARGET_UID="$(id -u "$TARGET_USER")"
TARGET_GID="$(id -g "$TARGET_USER")"
if [ "$TARGET_USER" = "$(id -un)" ] && [ -n "${HOME:-}" ]; then
    TARGET_HOME="$HOME"
else
    TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
fi
if [ -z "$TARGET_HOME" ]; then
    TARGET_HOME="${HOME:-/root}"
fi
MOUNT_DIR="${TARGET_HOME}/studies"
S3FILES_ROOT="${MOUNT_DIR}/.s3files"
AWS_CONFIG_DIR="${TARGET_HOME}/.aws"
LOG_FILE="${TARGET_HOME}/.mount_s3.log"
export HOME="$TARGET_HOME"
export LOGNAME="$TARGET_USER"
export USER="$TARGET_USER"

[ ! -s "$CONFIG" ] && exit 0

log() {
    printf '%s %s\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "$*" | tee -a "$LOG_FILE"
}

dry_run_line() {
    printf 'DRY-RUN: %s\n' "$*"
}

is_true() {
    case "$1" in
        true|True|TRUE) return 0 ;;
        *) return 1 ;;
    esac
}

# false is a real value; jq's // operator would treat it as missing.
jq_writeable='if has("writeable") then .writeable elif has("writable") then .writable else true end'
jq_readable='if has("readable") then .readable else true end'

fix_path_ownership() {
    local path="$1"
    [ -e "$path" ] || return 0
    sudo chown "${TARGET_UID}:${TARGET_GID}" "$path" 2>/dev/null || true
}

env_type() {
    if [ -d "/usr/share/aws/emr" ]; then
        printf "emr"
    elif [ -d "/home/ec2-user/SageMaker" ]; then
        printf "sagemaker"
    elif [ -d "/var/log/rstudio-server" ]; then
        printf "rstudio"
    else
        printf "ec2-linux"
    fi
}

append_role_to_credentials() {
    study_id=$1
    role_arn=$2
    credentials_file=$AWS_CONFIG_DIR/credentials
    if ! grep -q "\[$study_id\]" "$AWS_CONFIG_DIR/credentials" &>/dev/null; then
        echo "[$study_id]" >> "$credentials_file"
        echo "role_arn = $role_arn" >> "$credentials_file"
        echo "credential_source = Ec2InstanceMetadata" >> "$credentials_file"
        echo "" >> "$credentials_file"
    fi
}

ensure_fuse() {
    if [ "$(uname -s)" != "Linux" ]; then
        return 0
    fi
    # goofys needs fusermount in PATH (fuse + fuse-libs; fuse3-libs on AL2023)
    if command -v fusermount >/dev/null 2>&1 || command -v fusermount3 >/dev/null 2>&1; then
        if lsmod 2>/dev/null | grep -q '^fuse '; then
            return 0
        fi
    fi
    if command -v dnf >/dev/null 2>&1; then
        sudo dnf install -y fuse fuse-libs fuse3 fuse3-libs >/dev/null 2>&1 \
            || sudo dnf install -y fuse fuse-libs fuse3-libs >/dev/null 2>&1 \
            || true
    elif command -v yum >/dev/null 2>&1; then
        sudo yum install -y fuse fuse-libs fuse3 fuse3-libs >/dev/null 2>&1 \
            || sudo yum install -y fuse fuse-libs fuse3-libs >/dev/null 2>&1 \
            || sudo yum install -y fuse fuse-common >/dev/null 2>&1 \
            || true
    fi
    if ! command -v fusermount >/dev/null 2>&1 && command -v fusermount3 >/dev/null 2>&1; then
        sudo ln -sf "$(command -v fusermount3)" /usr/local/bin/fusermount
    fi
    sudo modprobe fuse 2>/dev/null || true
}

s3files_client_installed() {
    command -v mount.s3files >/dev/null 2>&1 \
        || [ -x /sbin/mount.s3files ] \
        || [ -x /usr/sbin/mount.s3files ]
}

# sudo mount resets PATH, so mount.s3files imports boto3 from system Python.
# A conda `(base)` python3 earlier on PATH does not see the yum package.
s3files_python() {
    if [ -x /usr/bin/python3 ]; then
        printf '%s\n' /usr/bin/python3
    else
        command -v python3
    fi
}

configure_s3files_mount_helper() {
    local conf
    for conf in /etc/amazon/efs/s3files-utils.conf /etc/amazon/efs/efs-utils.conf; do
        [ -f "$conf" ] || continue
        if grep -q '^\[cloudwatch-log\]' "$conf" 2>/dev/null; then
            sudo sed -i '/^\[cloudwatch-log\]/,/^\[/ s/^[# ]*enabled = .*/enabled = false/' "$conf"
        fi
    done
}

ensure_s3files_client() {
    # amazon-efs-utils 3.x ships mount.s3files; efs-proxy IAM auth needs botocore+boto3 (not bundled).
    local py
    py="$(s3files_python)"
    if command -v yum >/dev/null 2>&1; then
        if ! s3files_client_installed; then
            sudo yum install -y amazon-efs-utils >/dev/null 2>&1 || true
        fi
        if ! "$py" -c 'import botocore' >/dev/null 2>&1; then
            sudo yum install -y python3-botocore >/dev/null 2>&1 || true
        fi
        if ! "$py" -c 'import boto3' >/dev/null 2>&1; then
            sudo yum install -y python3-boto3 >/dev/null 2>&1 || true
        fi
        sudo yum update -y amazon-efs-utils >/dev/null 2>&1 || true
    fi
    if ! "$py" -c 'import boto3' >/dev/null 2>&1; then
        sudo yum install -y python3-pip >/dev/null 2>&1 || true
        sudo "$py" -m pip install boto3 >/dev/null 2>&1 || true
    fi
    if ! s3files_client_installed; then
        printf 'ERROR: mount.s3files is not available; install amazon-efs-utils 3.x for S3 Files mounts\n' >&2
        return 1
    fi
    if ! "$py" -c 'import botocore' >/dev/null 2>&1; then
        printf 'ERROR: python3-botocore is not available for %s; required for S3 Files IAM mount auth\n' "$py" >&2
        return 1
    fi
    if ! "$py" -c 'import boto3' >/dev/null 2>&1; then
        printf 'ERROR: python3-boto3 is not available for %s; required for S3 Files IAM mount auth\n' "$py" >&2
        return 1
    fi
    configure_s3files_mount_helper
}

mount_options_have_ro() {
    local opts="$1"
    [[ ",${opts}," == *",ro,"* ]]
}

# Do not follow a study symlink up to the shared S3 Files mount.
study_is_mountpoint() {
    local path="$1"
    [ -e "$path" ] || return 1
    [ ! -L "$path" ] || return 1
    if mountpoint -q -P "$path" 2>/dev/null; then
        return 0
    fi
    mountpoint -q "$path" 2>/dev/null
}

study_mount_options() {
    local path="$1"
    findmnt -n -o OPTIONS --mountpoint "$path" 2>/dev/null \
        || findmnt -n -o OPTIONS -T "$path" 2>/dev/null \
        || true
}

path_is_writable() {
    local dir="$1"
    local probe="${dir}/.mount_s3_ro_probe.$$"
    if ( : >"$probe" ) 2>/dev/null; then
        rm -f "$probe"
        return 0
    fi
    return 1
}

remove_fstab_mountpoint() {
    local mount_point="$1"
    [ -f /etc/fstab ] || return 0
    if ! awk -v mp="$mount_point" '$2 == mp { found = 1 } END { exit !found }' /etc/fstab; then
        return 0
    fi
    sudo awk -v mp="$mount_point" '$2 != mp { print }' /etc/fstab \
        | sudo tee /etc/fstab.tmp >/dev/null &&
        sudo mv /etc/fstab.tmp /etc/fstab
}

add_fstab_entry() {
    local filesystem_id="$1"
    local mount_point="$2"
    local mount_target_ip="$3"
    local fstab_entry="${filesystem_id}:/ ${mount_point} s3files _netdev,mounttargetip=${mount_target_ip},nodirects3read 0 0"

    # Replace an older DNS-based S3Files entry for this mount point.
    sudo awk -v mp="$mount_point" '
        !($2 == mp && $3 == "s3files") { print }
    ' /etc/fstab | sudo tee /etc/fstab.tmp >/dev/null &&
        sudo mv /etc/fstab.tmp /etc/fstab

    if ! grep -qF "$fstab_entry" /etc/fstab 2>/dev/null; then
        echo "$fstab_entry" | sudo tee -a /etc/fstab >/dev/null
    fi
}

add_bind_ro_fstab() {
    local link_target="$1"
    local study_dir="$2"
    local kind="${3:-bind}"
    local fstab_entry

    if [ "$kind" = "bindfs" ]; then
        fstab_entry="${link_target} ${study_dir} fuse.bindfs ro,allow_other 0 0"
    else
        fstab_entry="${link_target} ${study_dir} none bind,ro 0 0"
    fi

    remove_fstab_mountpoint "$study_dir"
    if ! grep -qF "$fstab_entry" /etc/fstab 2>/dev/null; then
        echo "$fstab_entry" | sudo tee -a /etc/fstab >/dev/null
    fi
}

ensure_bindfs() {
    command -v bindfs >/dev/null 2>&1 && return 0
    if command -v dnf >/dev/null 2>&1; then
        sudo dnf install -y bindfs >/dev/null 2>&1 || true
    elif command -v yum >/dev/null 2>&1; then
        sudo yum install -y bindfs >/dev/null 2>&1 || true
    fi
    command -v bindfs >/dev/null 2>&1
}

# S3 Files is NFS. remount,bind,ro often reports success but the prefix
# stays writable. bindfs is the fallback that actually rejects writes.
mount_prefix_read_only() {
    local src="$1"
    local dest="$2"

    mkdir -p "$dest"

    if sudo mount -o bind,ro "$src" "$dest" 2>/dev/null \
        || sudo mount --bind -o ro "$src" "$dest" 2>/dev/null; then
        sudo mount --make-private "$dest" 2>/dev/null || true
        sudo mount -o remount,ro,bind "$dest" 2>/dev/null \
            || sudo mount -o remount,bind,ro "$dest" 2>/dev/null \
            || true
        if ! path_is_writable "$dest"; then
            return 0
        fi
        unmount_path "$dest"
    elif sudo mount --bind "$src" "$dest"; then
        sudo mount --make-private "$dest" 2>/dev/null || true
        sudo mount -o remount,ro,bind "$dest" 2>/dev/null \
            || sudo mount -o remount,bind,ro "$dest" 2>/dev/null \
            || sudo mount -o remount,ro "$dest" 2>/dev/null \
            || true
        if ! path_is_writable "$dest"; then
            return 0
        fi
        unmount_path "$dest"
    fi

    if ensure_bindfs; then
        mkdir -p "$dest"
        if bindfs -r -u "$TARGET_UID" -g "$TARGET_GID" "$src" "$dest" \
            || sudo bindfs -r -u "$TARGET_UID" -g "$TARGET_GID" -o allow_other "$src" "$dest"; then
            if ! path_is_writable "$dest"; then
                return 0
            fi
            unmount_path "$dest"
        fi
    fi

    printf 'ERROR: could not make "%s" read-only (NFS bind remount left it writable)\n' \
        "$dest" >&2
    return 1
}

mount_s3files_filesystem() {
    local filesystem_id="$1"
    local mount_point="$2"
    local mount_target_ip="$3"
    local mount_opts="_netdev,nodirects3read"

    ensure_s3files_client || return 1

    # Optional IP bypass; otherwise DNS (needs VPC DNS resolution + hostnames)
    if [ -n "$mount_target_ip" ] && [ "$mount_target_ip" != "null" ]; then
        mount_opts="_netdev,mounttargetip=${mount_target_ip},nodirects3read"
    fi

    mkdir -p "$mount_point"
    if ! mountpoint -q "$mount_point"; then
        local attempt
        for attempt in 1 2 3; do
            sudo pkill -f "efs-proxy.*${filesystem_id}" 2>/dev/null || true
            if sudo mount \
                -t s3files \
                -o "${mount_opts}" \
                "${filesystem_id}:/" \
                "$mount_point"
            then
                break
            fi
            [ "$attempt" -lt 3 ] && sleep 2
        done
        if ! mountpoint -q "$mount_point"; then
            printf 'ERROR: failed to mount S3Files filesystem "%s" at "%s"\n' \
                "$filesystem_id" "$mount_point" >&2
            return 1
        fi
    fi
    add_fstab_entry "${filesystem_id}" "$mount_point" "$mount_target_ip"
    hide_s3files_metadata_dirs "$mount_point"
}

hide_s3files_metadata_dirs() {
    local fs_mount_point="$1"
    local hidden_file="${fs_mount_point}/.hidden"
    local entry

    for entry in .s3files-lost+found-* lost+found; do
        if [ -e "${fs_mount_point}/${entry}" ] && ! grep -qxF "$entry" "$hidden_file" 2>/dev/null; then
            printf '%s\n' "$entry" | sudo tee -a "$hidden_file" >/dev/null
        fi
    done
    if [ -f "$hidden_file" ]; then
        fix_path_ownership "$hidden_file"
    fi
}

s3files_link_target() {
    local fs_mount_point="$1"
    local s3_prefix="$2"

    # Strip leading/trailing slashes from prefix
    s3_prefix="${s3_prefix#/}"
    s3_prefix="${s3_prefix%/}"

    if [ -n "$s3_prefix" ] && [ "$s3_prefix" != "null" ]; then
        printf "%s/%s" "$fs_mount_point" "$s3_prefix"
    else
        printf "%s" "$fs_mount_point"
    fi
}

unmount_path() {
    local path="$1"
    fusermount -u "$path" 2>/dev/null \
        || sudo umount "$path" 2>/dev/null \
        || sudo umount -l "$path" 2>/dev/null \
        || true
}

# If study path was wrongly used as an NFS mount point (legacy), clear it
# so we can replace it with a symlink to <fs-root>/<prefix>.
# A read-only bind of the intended prefix is not legacy; the caller skips
# this function when that bind is already in place.
clear_legacy_study_mount() {
    local study_dir="$1"
    if study_is_mountpoint "$study_dir"; then
        printf 'Unmounting mount at study path "%s"\n' "$study_dir"
        unmount_path "$study_dir"
    fi
    if [ -e "$study_dir" ] && [ ! -L "$study_dir" ]; then
        # Only remove empty leftover dir after umount; do not rm -rf NFS contents
        rmdir "$study_dir" 2>/dev/null || true
    fi
}

cleanup_study_path() {
    local study_dir="$1"
    if study_is_mountpoint "$study_dir"; then
        printf 'Removing mount at "%s"\n' "$study_dir"
        unmount_path "$study_dir"
    fi
    if [ -L "$study_dir" ]; then
        rm -f "$study_dir"
    elif [ -d "$study_dir" ]; then
        rmdir "$study_dir" 2>/dev/null || true
    fi
    remove_fstab_mountpoint "$study_dir"
}

bind_ro_already() {
    local study_dir="$1"
    local link_target="$2"
    local opts

    [ -d "$study_dir" ] || return 1
    [ ! -L "$study_dir" ] || return 1
    study_is_mountpoint "$study_dir" || return 1
    path_is_writable "$study_dir" && return 1
    opts="$(study_mount_options "$study_dir")"
    [ -n "$opts" ] || return 1
    [ -e "$link_target" ] || return 1
}

link_study_to_s3files_mount() {
    local study_id="$1"
    local s3_prefix="$2"
    local filesystem_id="$3"
    local mount_target_ip="$4"
    local writeable="$5"
    local study_dir="${MOUNT_DIR}/${study_id}"
    local fs_mount_point="${S3FILES_ROOT}/${filesystem_id}"
    local link_target
    local prefix_rel

    # Ensure the NFS filesystem is mounted before creating the study symlink
    if ! mountpoint -q "$fs_mount_point" 2>/dev/null; then
        printf 'S3Files filesystem "%s" not mounted; mounting at "%s"\n' \
            "$filesystem_id" "$fs_mount_point"
        if ! mount_s3files_filesystem "$filesystem_id" "$fs_mount_point" "$mount_target_ip"; then
            printf 'ERROR: cannot link study "%s"; S3Files mount failed\n' "$study_id" >&2
            return 1
        fi
    fi

    prefix_rel="${s3_prefix#/}"
    prefix_rel="${prefix_rel%/}"
    link_target="$(s3files_link_target "$fs_mount_point" "$s3_prefix")"

    if is_true "$writeable"; then
        if [ -n "$prefix_rel" ] && [ "$prefix_rel" != "null" ]; then
            # Create prefix on the mount if it does not exist yet (e.g. empty ProjectStorage)
            if [ ! -d "${fs_mount_point}/${prefix_rel}" ]; then
                printf 'Creating missing S3Files prefix "%s" under "%s"\n' \
                    "$prefix_rel" "$fs_mount_point"
                if ! sudo mkdir -p "${fs_mount_point}/${prefix_rel}"; then
                    log "ERROR: cannot create prefix ${prefix_rel} for study ${study_id}"
                    return 1
                fi
                fix_path_ownership "${fs_mount_point}/${prefix_rel}"
            fi
        fi
        if [ ! -e "$link_target" ]; then
            printf 'ERROR: study "%s" link target does not exist: "%s"\n' \
                "$study_id" "$link_target" >&2
            return 1
        fi
        clear_legacy_study_mount "$study_dir"
        remove_fstab_mountpoint "$study_dir"
        mkdir -p "$MOUNT_DIR"
        if [ -e "$study_dir" ] && [ ! -L "$study_dir" ]; then
            rmdir "$study_dir" 2>/dev/null || rm -rf "$study_dir"
        fi
        ln -sfn "$link_target" "$study_dir"
        printf 'Linked study "%s" -> "%s"\n' "$study_id" "$link_target"
        return 0
    fi

    if [ -n "$prefix_rel" ] && [ "$prefix_rel" != "null" ] && [ ! -d "${fs_mount_point}/${prefix_rel}" ]; then
        printf 'ERROR: read-only study "%s" prefix does not exist: "%s"\n' \
            "$study_id" "${fs_mount_point}/${prefix_rel}" >&2
        log "ERROR: read-only study ${study_id} prefix ${prefix_rel} does not exist"
        return 1
    fi
    if [ ! -e "$link_target" ]; then
        printf 'ERROR: study "%s" link target does not exist: "%s"\n' \
            "$study_id" "$link_target" >&2
        return 1
    fi
    if bind_ro_already "$study_dir" "$link_target"; then
        printf 'Study "%s" already read-only at "%s"\n' "$study_id" "$study_dir"
        add_bind_ro_fstab "$link_target" "$study_dir"
        return 0
    fi

    if [ -L "$study_dir" ]; then
        printf 'Replacing writable symlink "%s" -> "%s" with a read-only mount\n' \
            "$study_dir" "$(readlink -f "$study_dir" 2>/dev/null || readlink "$study_dir")"
        rm -f "$study_dir"
    fi
    clear_legacy_study_mount "$study_dir"
    mkdir -p "$study_dir"
    if ! mount_prefix_read_only "$link_target" "$study_dir"; then
        printf 'ERROR: failed to mount study "%s" read-only\n' "$study_id" >&2
        return 1
    fi
    if path_is_writable "$study_dir"; then
        printf 'ERROR: study "%s" is still writable at "%s"\n' "$study_id" "$study_dir" >&2
        return 1
    fi
    if findmnt -n -t fuse -T "$study_dir" >/dev/null 2>&1 \
        || findmnt -n -t fuse.bindfs -T "$study_dir" >/dev/null 2>&1; then
        add_bind_ro_fstab "$link_target" "$study_dir" "bindfs"
    else
        add_bind_ro_fstab "$link_target" "$study_dir" "bind"
    fi
    printf 'Mounted study "%s" read-only -> "%s"\n' "$study_id" "$link_target"
}

goofys_running_on() {
    local study_dir="$1"
    ps -U "$LOGNAME" -o "command" | egrep -q "goofys .* ${study_dir}$"
}

goofys_mount_is_ro() {
    local study_dir="$1"
    local opts
    opts="$(findmnt -n -o OPTIONS --target "$study_dir" 2>/dev/null || true)"
    [ -n "$opts" ] && mount_options_have_ro "$opts"
}

run_goofys() {
    local study_dir="$1"
    local bucket_region="$2"
    local s3_bucket="$3"
    local s3_prefix="$4"
    local study_id="$5"
    local role_arn="$6"
    local kms_arn="$7"
    local writeable="$8"
    local -a opts

    opts=(--region "$bucket_region" --acl "bucket-owner-full-control")
    if ! is_true "$writeable"; then
        opts+=(-o ro)
    fi
    if [ "$role_arn" != "null" ] && [ -n "$role_arn" ]; then
        opts+=(--profile "$study_id")
    fi
    if [ "$kms_arn" != "null" ] && [ -n "$kms_arn" ]; then
        opts+=(--sse-kms "$kms_arn")
    fi
    goofys "${opts[@]}" "${s3_bucket}:${s3_prefix}" "$study_dir"
}

# Prints planned actions from the config only. Does not inspect mounts.
plan_dry_run() {
    local seen_fs=" "
    local study_idx study_id s3_bucket s3_prefix s3_role_arn kms_arn
    local mount_source filesystem_id writeable readable
    local study_dir fs_mount_point link_target mode access_note

    for ((study_idx=0; study_idx<num_mounts; study_idx++)); do
        mount_source="$(printf "%s" "$mounts" | jq -r ".[$study_idx].source // \"S3\"" -)"
        filesystem_id="$(printf "%s" "$mounts" | jq -r ".[$study_idx].\"filesystem-id\" // .[$study_idx].filesystemId // \"\"" -)"
        readable="$(printf "%s" "$mounts" | jq -r ".[$study_idx] | ${jq_readable}" -)"
        if [ "${filesystem_id}" = "" ] || [ "${filesystem_id}" = "null" ]; then
            continue
        fi
        if [ "$mount_source" != "S3Files" ]; then
            continue
        fi
        if ! is_true "$readable"; then
            continue
        fi
        case "$seen_fs" in
            *" ${filesystem_id} "*) continue ;;
        esac
        seen_fs="${seen_fs}${filesystem_id} "
        dry_run_line "mount s3files rw ${filesystem_id} -> ${S3FILES_ROOT}/${filesystem_id}"
    done

    for ((study_idx=0; study_idx<num_mounts; study_idx++)); do
        study_id="$(printf "%s" "$mounts" | jq -r ".[$study_idx].id" -)"
        s3_bucket="$(printf "%s" "$mounts" | jq -r ".[$study_idx].bucket" -)"
        s3_prefix="$(printf "%s" "$mounts" | jq -r ".[$study_idx].prefix" -)"
        s3_role_arn="$(printf "%s" "$mounts" | jq -r ".[$study_idx].roleArn" -)"
        kms_arn="$(printf "%s" "$mounts" | jq -r ".[$study_idx].kmsArn" -)"
        mount_source="$(printf "%s" "$mounts" | jq -r ".[$study_idx].source // \"S3\"" -)"
        filesystem_id="$(printf "%s" "$mounts" | jq -r ".[$study_idx].\"filesystem-id\" // .[$study_idx].filesystemId // \"\"" -)"
        writeable="$(printf "%s" "$mounts" | jq -r ".[$study_idx] | ${jq_writeable}" -)"
        readable="$(printf "%s" "$mounts" | jq -r ".[$study_idx] | ${jq_readable}" -)"
        study_dir="${MOUNT_DIR}/${study_id}"

        if [ "${filesystem_id}" = "" ] || [ "${filesystem_id}" = "null" ]; then
            mount_source="S3"
        fi

        if ! is_true "$readable"; then
            dry_run_line "skip ${study_id} (readable=false)"
            continue
        fi

        if [ "$mount_source" = "S3Files" ]; then
            fs_mount_point="${S3FILES_ROOT}/${filesystem_id}"
            link_target="$(s3files_link_target "$fs_mount_point" "$s3_prefix")"
            if is_true "$writeable"; then
                dry_run_line "symlink ${study_id} -> ${link_target}"
            else
                dry_run_line "bind ro ${link_target} -> ${study_dir}"
            fi
            continue
        fi

        if is_true "$writeable"; then
            mode="rw"
        else
            mode="ro"
        fi
        access_note=""
        if [ "$s3_role_arn" != "null" ] && [ -n "$s3_role_arn" ]; then
            access_note="${access_note} profile=${study_id}"
        fi
        if [ "$kms_arn" != "null" ] && [ -n "$kms_arn" ]; then
            access_note="${access_note} kms=${kms_arn}"
        fi
        dry_run_line "goofys ${mode} ${s3_bucket}:${s3_prefix} -> ${study_dir}${access_note}"
    done
}

mounts="$(cat "$CONFIG")"
num_mounts=$(printf "%s" "$mounts" | jq ". | length" -)

if [ "$DRY_RUN" = true ]; then
    plan_dry_run
    exit 0
fi

# Use STS regional endpoint (external studies / VPC endpoints).
token=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
region=$(curl -s "http://169.254.169.254/latest/meta-data/placement/availability-zone/" -H "X-aws-ec2-metadata-token: $token" | sed 's/.$//')
export AWS_STS_REGIONAL_ENDPOINTS=regional
export AWS_DEFAULT_REGION=$region
export AWS_SDK_LOAD_CONFIG=1

is_linux="false"
if [ "$(uname -s)" = "Linux" ]; then
    is_linux="true"
fi

mkdir -p "$S3FILES_ROOT"
fix_path_ownership "$MOUNT_DIR"
fix_path_ownership "$S3FILES_ROOT"
log "mount_s3.sh start user=${TARGET_USER} uid=${TARGET_UID} home=${TARGET_HOME}"

# Ensure fusermount is available before goofys mounts
if [ "$is_linux" = "true" ]; then
    ensure_fuse
fi

# Pass 1: mount each unique S3 Files filesystem once (read-write).
# The filesystem stays read-write when any study on it is writeable.
# Studies that are not readable do not cause a filesystem mount.
if [ "$is_linux" = "true" ]; then
    seen_fs=" "
    for ((study_idx=0; study_idx<num_mounts; study_idx++)); do
        mount_source="$(printf "%s" "$mounts" | jq -r ".[$study_idx].source // \"S3\"" -)"
        filesystem_id="$(printf "%s" "$mounts" | jq -r ".[$study_idx].\"filesystem-id\" // .[$study_idx].filesystemId // \"\"" -)"
        mount_target_ip="$(printf "%s" "$mounts" | jq -r ".[$study_idx].\"mount-target-ip\" // .[$study_idx].mountTargetIp // \"\"" -)"
        readable="$(printf "%s" "$mounts" | jq -r ".[$study_idx] | ${jq_readable}" -)"
        if [ "${filesystem_id}" = "" ] || [ "${filesystem_id}" = "null" ]; then
            continue
        fi
        if [ "$mount_source" != "S3Files" ]; then
            continue
        fi
        if ! is_true "$readable"; then
            continue
        fi
        case "$seen_fs" in
            *" ${filesystem_id} "*) continue ;;
        esac
        seen_fs="${seen_fs}${filesystem_id} "
        fs_mount_point="${S3FILES_ROOT}/${filesystem_id}"
        if ! mountpoint -q "$fs_mount_point" 2>/dev/null; then
            printf 'Mounting S3Files filesystem "%s" at "%s"\n' \
                "$filesystem_id" "$fs_mount_point"
            if ! mount_s3files_filesystem "${filesystem_id}" "$fs_mount_point" "$mount_target_ip"; then
                printf 'ERROR: S3Files mount failed for "%s"\n' "$filesystem_id" >&2
            fi
        fi
    done
fi

# Pass 2: per-study path (symlink or read-only bind for S3 Files, or goofys)
for ((study_idx=0; study_idx<num_mounts; study_idx++)); do
    study_id="$(printf "%s" "$mounts" | jq -r ".[$study_idx].id" -)"
    s3_bucket="$(printf "%s" "$mounts" | jq -r ".[$study_idx].bucket" -)"
    s3_prefix="$(printf "%s" "$mounts" | jq -r ".[$study_idx].prefix" -)"
    s3_role_arn="$(printf "%s" "$mounts" | jq -r ".[$study_idx].roleArn" -)"
    kms_arn="$(printf "%s" "$mounts" | jq -r ".[$study_idx].kmsArn" -)"
    bucket_region="$(printf "%s" "$mounts" | jq -r ".[$study_idx].region" -)"
    mount_source="$(printf "%s" "$mounts" | jq -r ".[$study_idx].source // \"S3\"" -)"
    filesystem_id="$(printf "%s" "$mounts" | jq -r ".[$study_idx].\"filesystem-id\" // .[$study_idx].filesystemId // \"\"" -)"
    mount_target_ip="$(printf "%s" "$mounts" | jq -r ".[$study_idx].\"mount-target-ip\" // .[$study_idx].mountTargetIp // \"\"" -)"
    writeable="$(printf "%s" "$mounts" | jq -r ".[$study_idx] | ${jq_writeable}" -)"
    readable="$(printf "%s" "$mounts" | jq -r ".[$study_idx] | ${jq_readable}" -)"
    study_dir="${MOUNT_DIR}/${study_id}"

    if [ "${filesystem_id}" = "" ] || [ "${filesystem_id}" = "null" ]; then
        mount_source="S3"
    fi

    if ! is_true "$readable"; then
        printf 'Skipping study "%s" (readable=false)\n' "$study_id"
        cleanup_study_path "$study_dir"
        continue
    fi

    if [ "$mount_source" = "S3Files" ] && [ "$is_linux" = "true" ]; then
        printf 'Study "%s" flags writeable=%s readable=%s source=%s\n' \
            "$study_id" "$writeable" "$readable" "$mount_source"
        if is_true "$writeable"; then
            printf 'Linking study "%s" to S3Files mount (prefix="%s", mount-target-ip="%s") at "%s"\n' \
                "$study_id" "$s3_prefix" "$mount_target_ip" "$study_dir"
        else
            printf 'Mounting study "%s" read-only on S3Files prefix "%s" at "%s"\n' \
                "$study_id" "$s3_prefix" "$study_dir"
        fi
        if ! link_study_to_s3files_mount "$study_id" "$s3_prefix" "$filesystem_id" "$mount_target_ip" "$writeable"; then
            printf 'ERROR: failed to link study "%s"\n' "$study_id" >&2
        fi
    else
        if goofys_running_on "$study_dir"; then
            if is_true "$writeable"; then
                desired_ro=false
            else
                desired_ro=true
            fi
            if goofys_mount_is_ro "$study_dir"; then
                current_ro=true
            else
                current_ro=false
            fi
            if [ "$desired_ro" = "$current_ro" ]; then
                continue
            fi
            printf 'Remounting study "%s" (writeable=%s)\n' "$study_id" "$writeable"
            unmount_path "$study_dir"
        fi
        mkdir -p "$study_dir"
        if [ "$s3_role_arn" == "null" ]; then
            printf 'Mounting internal study "%s" at "%s"\n' "$study_id" "$study_dir"
            run_goofys "$study_dir" "$bucket_region" "$s3_bucket" "$s3_prefix" \
                "$study_id" "null" "null" "$writeable"
        else
            bucket_region="$(printf "%s" "$mounts" | jq -r ".[$study_idx].region" -)"
            if [[ $bucket_region == "null" ]]; then
                printf 'Bucket region is not specified. Defaulting to "%s" for mounting\n' "$region"
                bucket_region=$region
            fi
            mkdir -p "$AWS_CONFIG_DIR"
            append_role_to_credentials "$study_id" "$s3_role_arn"
            if [ "$kms_arn" == "null" ]; then
                printf 'Mounting external study "%s" at "%s" using role "%s" and region "%s"\n' \
                    "$study_id" "$study_dir" "$s3_role_arn" "$bucket_region"
            else
                printf 'Mounting external study "%s" at "%s" using role "%s", kms arn "%s" and region "%s"\n' \
                    "$study_id" "$study_dir" "$s3_role_arn" "$kms_arn" "$bucket_region"
            fi
            run_goofys "$study_dir" "$bucket_region" "$s3_bucket" "$s3_prefix" \
                "$study_id" "$s3_role_arn" "$kms_arn" "$writeable"
        fi
    fi
done

notebook_dir=""
case "$(env_type)" in
    "emr")
        notebook_dir="/opt/hail-on-AWS-spot-instances/notebook"
        ;;
    "sagemaker")
        notebook_dir="/home/ec2-user/SageMaker"
        ;;
esac

if [ -n "$notebook_dir" ] && [ "$num_mounts" -ne 0 ]; then
    symlink_name="$notebook_dir/studies"
    [ ! -L "$symlink_name" ] && sudo ln -s "$MOUNT_DIR" "$symlink_name"
fi

log "mount_s3.sh finished mounts=${num_mounts}"
exit 0
