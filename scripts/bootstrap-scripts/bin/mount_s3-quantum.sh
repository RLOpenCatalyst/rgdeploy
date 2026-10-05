#!/usr/bin/env bash
# Mounts S3 / S3 Files study data onto the local filesystem.
#
# Config: /usr/local/etc/s3-mounts.json
#  [{
#   "id": "STUDY_ID",
#   "bucket": "BUCKET_NAME",
#   "prefix": "BUCKET_PREFIX",
#   "source": "S3" | "S3Files" | "EFS",
#   "type": "EFS",              # optional; also accepted for demo EFS mounts
#   "filesystem-id": "fs-..."   # required when source is S3Files or EFS
#   "region": "us-east-2"       # recommended for EFS NFS DNS mount
#   "prefix": "" | "subdir"     # EFS: normalized by backend before S3Mounts is written
#   "target": "/home"           # optional; only for the single EFS used as user homes
# }, ...]
#
# Default study mounts: /mnt/studies/<id>
# Optional EFS home:    target=/home mounts that filesystem at /home (at most one)
#
# S3Files: mount each filesystem once under /mnt/studies/.s3files/<fs-id>,
# then symlink /mnt/studies/<id> -> <mount>/<prefix> (e.g. Shared).
# Do not mount NFS on the study path itself (that exposes lost+found and
# confuses GNOME Files).

CONFIG="/usr/local/etc/s3-mounts.json"
MOUNT_DIR="/mnt/studies"
S3FILES_ROOT="${MOUNT_DIR}/.s3files"
AWS_CONFIG_DIR="${HOME}/.aws"
LOG_FILE="${HOME}/.mount_s3.log"
HOME_MOUNT_TARGET="/home"

[ ! -s "$CONFIG" ] && exit 0

# File-only by default so login/VS Code shells stay quiet. Set RG_MOUNT_S3_VERBOSE=1 to tee.
log() {
    local line
    line="$(printf '%s %s' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "$*")"
    printf '%s\n' "$line" >> "$LOG_FILE" 2>/dev/null || true
    if [ "${RG_MOUNT_S3_VERBOSE:-}" = "1" ]; then
        printf '%s\n' "$line"
    fi
}

info() {
    log "$*"
    if [ "${RG_MOUNT_S3_VERBOSE:-}" = "1" ]; then
        printf '%s\n' "$*"
    fi
}

fix_path_ownership() {
    local path="$1"
    [ -e "$path" ] || return 0
    sudo chown "$(id -u):$(id -g)" "$path" 2>/dev/null || true
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

s3files_client_installed() {
    command -v mount.s3files >/dev/null 2>&1 \
        || [ -x /sbin/mount.s3files ] \
        || [ -x /usr/sbin/mount.s3files ]
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
    if command -v yum >/dev/null 2>&1; then
        if ! s3files_client_installed; then
            sudo yum install -y amazon-efs-utils >/dev/null 2>&1 || true
        fi
        if ! python3 -c 'import botocore' 2>/dev/null; then
            sudo yum install -y python3-botocore >/dev/null 2>&1 || true
        fi
        if ! python3 -c 'import boto3' 2>/dev/null; then
            sudo yum install -y python3-boto3 >/dev/null 2>&1 || true
        fi
        # ponytail: no yum update on every shell — that spammed terminals and added latency
    fi
    if ! s3files_client_installed; then
        printf 'ERROR: mount.s3files is not available; install amazon-efs-utils 3.x for S3 Files mounts\n' >&2
        return 1
    fi
    if ! python3 -c 'import botocore' 2>/dev/null; then
        printf 'ERROR: python3-botocore is not available; required for S3 Files IAM mount auth\n' >&2
        return 1
    fi
    if ! python3 -c 'import boto3' 2>/dev/null; then
        printf 'ERROR: python3-boto3 is not available; required for S3 Files IAM mount auth\n' >&2
        return 1
    fi
    configure_s3files_mount_helper
}

add_fstab_entry() {
    local filesystem_id="$1"
    local mount_point="$2"
    local fstab_entry="${filesystem_id}:/ ${mount_point} s3files _netdev 0 0"
    if ! grep -qF "$fstab_entry" /etc/fstab 2>/dev/null; then
        echo "$fstab_entry" | sudo tee -a /etc/fstab >/dev/null
    fi
}

mount_s3files_filesystem() {
    local filesystem_id="$1"
    local mount_point="$2"

    ensure_s3files_client || return 1

    mkdir -p "$mount_point"
    if ! mountpoint -q "$mount_point"; then
        local attempt
        # ponytail: efs-proxy may need a moment to bind localhost; 3 tries, no backoff tuning
        for attempt in 1 2 3; do
            sudo pkill -f "efs-proxy.*${filesystem_id}" 2>/dev/null || true
            if sudo mount \
                -t s3files \
                -o _netdev,nodirects3read \
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
    add_fstab_entry "${filesystem_id}" "$mount_point"
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

# If study path was wrongly used as an NFS mount point (legacy), clear it
# so we can replace it with a symlink to <fs-root>/<prefix>.
#
# CRITICAL: study paths are normally symlinks into .s3files/<fs-id>.
# mountpoint(1) follows symlinks, so mountpoint -q on the study path returns
# true for a healthy link and umount would tear down the real NFS mount.
clear_legacy_study_mount() {
    local study_dir="$1"
    if [ -L "$study_dir" ]; then
        return 0
    fi
    if [ -d "$study_dir" ] && mountpoint -q "$study_dir" 2>/dev/null; then
        info "Unmounting legacy S3Files mount at study path \"${study_dir}\""
        sudo umount "$study_dir" 2>/dev/null || sudo umount -l "$study_dir" 2>/dev/null || true
    fi
    if [ -e "$study_dir" ] && [ ! -L "$study_dir" ]; then
        # Only remove empty leftover dir after umount; do not rm -rf NFS contents
        rmdir "$study_dir" 2>/dev/null || true
    fi
}

study_link_is_healthy() {
    local study_dir="$1"
    local link_target="$2"
    local fs_mount_point="$3"

    [ -L "$study_dir" ] || return 1
    [ "$(readlink "$study_dir")" = "$link_target" ] || return 1
    mountpoint -q "$fs_mount_point" 2>/dev/null || return 1
    return 0
}

link_study_to_s3files_mount() {
    local study_id="$1"
    local s3_prefix="$2"
    local filesystem_id="$3"
    local study_dir="${MOUNT_DIR}/${study_id}"
    local fs_mount_point="${S3FILES_ROOT}/${filesystem_id}"
    local link_target
    local prefix_rel

    # Backend often sends prefix=""; S3 Files layout keeps data under Shared/.
    # Link study path into Shared so ProjectStorage shows files, not the Shared folder.
    if [ -z "$s3_prefix" ] || [ "$s3_prefix" = "null" ]; then
        s3_prefix="Shared"
    fi

    # Ensure the NFS filesystem is mounted before creating the study symlink
    if ! mountpoint -q "$fs_mount_point" 2>/dev/null; then
        info "S3Files filesystem \"${filesystem_id}\" not mounted; mounting at \"${fs_mount_point}\""
        if ! mount_s3files_filesystem "$filesystem_id" "$fs_mount_point"; then
            printf 'ERROR: cannot link study "%s"; S3Files mount failed\n' "$study_id" >&2
            return 1
        fi
    fi

    prefix_rel="${s3_prefix#/}"
    prefix_rel="${prefix_rel%/}"
    if [ -n "$prefix_rel" ] && [ "$prefix_rel" != "null" ]; then
        # Create prefix on the mount if it does not exist yet (e.g. empty ProjectStorage)
        if [ ! -d "${fs_mount_point}/${prefix_rel}" ]; then
            info "Creating missing S3Files prefix \"${prefix_rel}\" under \"${fs_mount_point}\""
            if ! sudo mkdir -p "${fs_mount_point}/${prefix_rel}"; then
                log "ERROR: cannot create prefix ${prefix_rel} for study ${study_id}"
                return 1
            fi
        fi
    fi

    link_target="$(s3files_link_target "$fs_mount_point" "$s3_prefix")"
    # AD multi-user: mount often runs as root; 777 so every desktop user can write.
    if [ -e "$link_target" ]; then
        sudo chmod 777 "$link_target" 2>/dev/null || true
    fi
    if study_link_is_healthy "$study_dir" "$link_target" "$fs_mount_point"; then
        return 0
    fi

    if [ ! -e "$link_target" ]; then
        printf 'ERROR: study "%s" link target does not exist: "%s"\n' \
            "$study_id" "$link_target" >&2
        return 1
    fi

    clear_legacy_study_mount "$study_dir"
    mkdir -p "$MOUNT_DIR"
    if [ -e "$study_dir" ] && [ ! -L "$study_dir" ]; then
        rmdir "$study_dir" 2>/dev/null || rm -rf "$study_dir"
    fi
    ln -sfn "$link_target" "$study_dir"
    info "Linked study \"${study_id}\" -> \"${link_target}\""
}

# Mount classic Amazon EFS.
# Default: /mnt/studies/<id>. If target is /home, mount at /home (shared AD homes).
# prefix is already normalized by backend (empty = root, else e.g. "folderA").
mount_efs_at_study_path() {
    local study_id="$1"
    local filesystem_id="$2"
    local efs_region="$3"
    local efs_prefix="$4"
    local mount_target="${5:-}"
    local study_dir
    local remote_path="/"
    local is_home_mount="false"

    if [ -z "$filesystem_id" ] || [ "$filesystem_id" = "null" ]; then
        printf 'ERROR: EFS study "%s" is missing filesystem-id\n' "$study_id" >&2
        return 1
    fi
    if [ -z "$efs_region" ] || [ "$efs_region" = "null" ]; then
        efs_region="$region"
    fi

    if [ -n "$efs_prefix" ] && [ "$efs_prefix" != "null" ]; then
        remote_path="/${efs_prefix}"
    fi

    if [ "$mount_target" = "$HOME_MOUNT_TARGET" ]; then
        study_dir="$HOME_MOUNT_TARGET"
        is_home_mount="true"
    else
        study_dir="${MOUNT_DIR}/${study_id}"
        sudo mkdir -p "$MOUNT_DIR"
        # Study path may be a leftover symlink from S3Files; remove before NFS mount
        if [ -L "$study_dir" ]; then
            rm -f "$study_dir"
        fi
        sudo mkdir -p "$study_dir"
    fi

    if mountpoint -q "$study_dir" 2>/dev/null; then
        info "EFS already mounted at \"${study_dir}\""
        return 0
    fi

    info "Mounting EFS \"${filesystem_id}:${remote_path}\" at \"${study_dir}\" (study=${study_id})"
    if command -v mount.efs >/dev/null 2>&1 || [ -x /sbin/mount.efs ] || [ -x /usr/sbin/mount.efs ]; then
        if sudo mount -t efs -o tls,_netdev "${filesystem_id}:${remote_path}" "$study_dir"; then
            if [ "$is_home_mount" != "true" ]; then
                fix_path_ownership "$study_dir"
            fi
            return 0
        fi
        log "WARN: mount -t efs failed for ${filesystem_id}:${remote_path}; trying nfs4"
    fi

    if sudo mount -t nfs4 \
        -o nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2,noresvport \
        "${filesystem_id}.efs.${efs_region}.amazonaws.com:${remote_path}" \
        "$study_dir"
    then
        if [ "$is_home_mount" != "true" ]; then
            fix_path_ownership "$study_dir"
        fi
        return 0
    fi

    printf 'ERROR: failed to mount EFS "%s:%s" at "%s"\n' \
        "$filesystem_id" "$remote_path" "$study_dir" >&2
    return 1
}

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

mkdir -p "$AWS_CONFIG_DIR" 2>/dev/null || true
sudo mkdir -p "$MOUNT_DIR" "$S3FILES_ROOT"
sudo chmod 755 "$MOUNT_DIR" 2>/dev/null || true
# Convenience for interactive users who still look under ~/studies
if [ -n "${HOME}" ] && [ ! -e "${HOME}/studies" ]; then
    ln -sfn "$MOUNT_DIR" "${HOME}/studies" 2>/dev/null || true
fi
log "mount_s3.sh start user=$(id -un) home=${HOME} mount_dir=${MOUNT_DIR}"

mounts="$(cat "$CONFIG")"
num_mounts=$(printf "%s" "$mounts" | jq ". | length" -)

# Pass 0: EFS with target=/home first (only one expected)
if [ "$is_linux" = "true" ]; then
    for ((study_idx=0; study_idx<num_mounts; study_idx++)); do
        mount_source="$(printf "%s" "$mounts" | jq -r ".[$study_idx].source // \"S3\"" -)"
        mount_type="$(printf "%s" "$mounts" | jq -r ".[$study_idx].type // \"\"" -)"
        mount_target="$(printf "%s" "$mounts" | jq -r ".[$study_idx].target // \"\"" -)"
        if [ "$mount_target" != "$HOME_MOUNT_TARGET" ]; then
            continue
        fi
        if [ "$mount_source" != "EFS" ] && [ "$mount_type" != "EFS" ]; then
            printf 'ERROR: target=/home is only supported for EFS mounts (study_idx=%s)\n' "$study_idx" >&2
            continue
        fi
        study_id="$(printf "%s" "$mounts" | jq -r ".[$study_idx].id" -)"
        filesystem_id="$(printf "%s" "$mounts" | jq -r ".[$study_idx].\"filesystem-id\" // .[$study_idx].filesystemId // \"\"" -)"
        bucket_region="$(printf "%s" "$mounts" | jq -r ".[$study_idx].region" -)"
        s3_prefix="$(printf "%s" "$mounts" | jq -r ".[$study_idx].prefix" -)"
        if ! mount_efs_at_study_path "$study_id" "$filesystem_id" "$bucket_region" "$s3_prefix" "$HOME_MOUNT_TARGET"; then
            printf 'ERROR: failed to mount home EFS study "%s"\n' "$study_id" >&2
        fi
    done
fi

# Pass 1: mount each unique S3 Files filesystem once
if [ "$is_linux" = "true" ]; then
    for ((study_idx=0; study_idx<num_mounts; study_idx++)); do
        mount_source="$(printf "%s" "$mounts" | jq -r ".[$study_idx].source // \"S3\"" -)"
        filesystem_id="$(printf "%s" "$mounts" | jq -r ".[$study_idx].\"filesystem-id\" // .[$study_idx].filesystemId // \"\"" -)"
        if [ "${filesystem_id}" = "" ] || [ "${filesystem_id}" = "null" ]; then
            continue
        fi
        if [ "$mount_source" != "S3Files" ]; then
            continue
        fi
        fs_mount_point="${S3FILES_ROOT}/${filesystem_id}"
        if ! mountpoint -q "$fs_mount_point" 2>/dev/null; then
            info "Mounting S3Files filesystem \"${filesystem_id}\" at \"${fs_mount_point}\""
            if ! mount_s3files_filesystem "${filesystem_id}" "$fs_mount_point"; then
                printf 'ERROR: S3Files mount failed for "%s"\n' "$filesystem_id" >&2
            fi
        fi
    done
fi

# Pass 2: per-study path (EFS mount, S3 Files symlink + prefix, or goofys)
for ((study_idx=0; study_idx<num_mounts; study_idx++)); do
    study_id="$(printf "%s" "$mounts" | jq -r ".[$study_idx].id" -)"
    s3_bucket="$(printf "%s" "$mounts" | jq -r ".[$study_idx].bucket" -)"
    s3_prefix="$(printf "%s" "$mounts" | jq -r ".[$study_idx].prefix" -)"
    s3_role_arn="$(printf "%s" "$mounts" | jq -r ".[$study_idx].roleArn" -)"
    kms_arn="$(printf "%s" "$mounts" | jq -r ".[$study_idx].kmsArn" -)"
    bucket_region="$(printf "%s" "$mounts" | jq -r ".[$study_idx].region" -)"
    mount_source="$(printf "%s" "$mounts" | jq -r ".[$study_idx].source // \"S3\"" -)"
    mount_type="$(printf "%s" "$mounts" | jq -r ".[$study_idx].type // \"\"" -)"
    mount_target="$(printf "%s" "$mounts" | jq -r ".[$study_idx].target // \"\"" -)"
    filesystem_id="$(printf "%s" "$mounts" | jq -r ".[$study_idx].\"filesystem-id\" // .[$study_idx].filesystemId // \"\"" -)"
    study_dir="${MOUNT_DIR}/${study_id}"

    # Home EFS already handled in pass 0
    if [ "$mount_target" = "$HOME_MOUNT_TARGET" ]; then
        continue
    fi

    # Classic EFS -> /mnt/studies/<id> (prefix selects remote subdir; "" = root)
    if [ "$is_linux" = "true" ] && { [ "$mount_source" = "EFS" ] || [ "$mount_type" = "EFS" ]; }; then
        if ! mount_efs_at_study_path "$study_id" "$filesystem_id" "$bucket_region" "$s3_prefix" ""; then
            printf 'ERROR: failed to mount EFS study "%s"\n' "$study_id" >&2
        fi
        continue
    fi

    if [ "${filesystem_id}" = "" ] || [ "${filesystem_id}" = "null" ]; then
        mount_source="S3"
    fi

    if [ "$mount_source" = "S3Files" ] && [ "$is_linux" = "true" ]; then
        if ! link_study_to_s3files_mount "$study_id" "$s3_prefix" "$filesystem_id"; then
            printf 'ERROR: failed to link study "%s"\n' "$study_id" >&2
        fi
    else
        ps -U "$LOGNAME" -o "command" | egrep -q "goofys .* ${study_dir}$"
        if [ $? -ne 0 ]; then
            sudo mkdir -p "$study_dir"
            if [ "$s3_role_arn" == "null" ]; then
                info "Mounting internal study \"${study_id}\" at \"${study_dir}\""
                goofys --region "$bucket_region" --acl "bucket-owner-full-control" \
                    "${s3_bucket}:${s3_prefix}" "$study_dir"
            else
                bucket_region="$(printf "%s" "$mounts" | jq -r ".[$study_idx].region" -)"
                if [[ $bucket_region == "null" ]]; then
                    info "Bucket region is not specified. Defaulting to \"${region}\" for mounting"
                    bucket_region=$region
                fi
                mkdir -p "$AWS_CONFIG_DIR"
                append_role_to_credentials "$study_id" "$s3_role_arn"
                if [ "$kms_arn" == "null" ]; then
                    info "Mounting external study \"${study_id}\" at \"${study_dir}\" using role \"${s3_role_arn}\" and region \"${bucket_region}\""
                    goofys --region "$bucket_region" --profile "$study_id" \
                        --acl "bucket-owner-full-control" \
                        "${s3_bucket}:${s3_prefix}" "$study_dir"
                else
                    info "Mounting external study \"${study_id}\" at \"${study_dir}\" using role \"${s3_role_arn}\", kms arn \"${kms_arn}\" and region \"${bucket_region}\""
                    goofys --region "$bucket_region" --profile "$study_id" \
                        --sse-kms "$kms_arn" --acl "bucket-owner-full-control" \
                        "${s3_bucket}:${s3_prefix}" "$study_dir"
                fi
            fi
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
