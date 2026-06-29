#!/usr/bin/env bash

# This script mounts S3 buckets/prefixes onto the local filesystem using fuse and
#   goofys. It also attempts to create a sym link to the mounted data if the instance
#   is an EMR or SageMaker instance so that it can be easily accessed by Jupyter notebooks.
#
# /usr/local/etc/s3-mounts.json should contain S3 study data metadata of the form
#  [{
#   "id": "STUDY_ID",
#   "bucket": "BUCKET_NAME",
#   "prefix": "BUCKET_PREFIX"
# }, ...]
CONFIG="/usr/local/etc/s3-mounts.json"
MOUNT_DIR="${HOME}/studies"
S3FILES_ROOT="${MOUNT_DIR}/.s3files"
AWS_CONFIG_DIR="${HOME}/.aws"

# Exit if CONFIG doesn't exist or is 0 bytes
[ ! -s "$CONFIG" ] && exit 0

# Define a function to determine what type of environment this is (EMR, SageMaker, RStudio, or EC2 Linux)
env_type() {
    if [ -d "/usr/share/aws/emr" ]
    then
        printf "emr"
    elif [ -d "/home/ec2-user/SageMaker" ]
    then
        printf "sagemaker"
    elif [ -d "/var/log/rstudio-server" ]
    then
        printf "rstudio"
    else
        printf "ec2-linux"
    fi
}

ensure_fuse() {
    if [ "$(uname -s)" != "Linux" ]; then
        return 0
    fi
    if lsmod 2>/dev/null | grep -q '^fuse '; then
        return 0
    fi
    if command -v yum >/dev/null 2>&1; then
        sudo yum install -y fuse fuse-common >/dev/null 2>&1 || true
    elif command -v dnf >/dev/null 2>&1; then
        sudo dnf install -y fuse fuse-common >/dev/null 2>&1 || true
    fi
    sudo modprobe fuse 2>/dev/null || true
}

s3files_client_installed() {
    command -v mount.s3files >/dev/null 2>&1 \
        || [ -x /sbin/mount.s3files ] \
        || [ -x /usr/sbin/mount.s3files ]
}

ensure_s3files_client() {
    if s3files_client_installed; then
        return 0
    fi

    printf 'Installing amazon-efs-utils (S3 Files client)...\n'
    ensure_fuse

    if command -v yum >/dev/null 2>&1; then
        if yum list available amazon-efs-utils 2>/dev/null | grep -q '3\.'; then
            sudo yum install -y 'amazon-efs-utils-3.*' fuse fuse-common
        else
            sudo yum install -y amazon-efs-utils fuse fuse-common
        fi
    elif command -v dnf >/dev/null 2>&1; then
        sudo dnf install -y amazon-efs-utils fuse fuse-common
    else
        curl -fsSL https://amazon-efs-utils.aws.com/efs-utils-installer.sh | sudo sh -s -- --install
    fi

    if ! s3files_client_installed; then
        printf 'ERROR: mount.s3files is not available; install amazon-efs-utils 3.x for S3 Files mounts\n' >&2
        return 1
    fi
    return 0
}

# Add roleArn for a study to credentials file if not present already
append_role_to_credentials() {
    study_id=$1
    role_arn=$2
    credentials_file=$AWS_CONFIG_DIR/credentials
    if ! grep -q "\[$study_id\]" $AWS_CONFIG_DIR/credentials &>/dev/null
    then
      # append role for this study since it doesn't already exist in the file
      echo "[$study_id]" >> $credentials_file
      echo "role_arn = $role_arn" >> $credentials_file
      echo "credential_source = Ec2InstanceMetadata" >> $credentials_file
      echo "" >> $credentials_file
    fi
}

add_fstab_entry() {
    local filesystem_id="$1"
    local mount_point="$2"
    local fstab_entry

    fstab_entry="${filesystem_id}:/ ${mount_point} s3files _netdev 0 0"

    if ! grep -qF "$fstab_entry" /etc/fstab; then
        echo "$fstab_entry" | sudo tee -a /etc/fstab >/dev/null
    fi
}

mount_s3files_filesystem() {
    local filesystem_id="$1"
    local mount_point="$2"

    ensure_s3files_client || return 1

    mkdir -p "$mount_point"
    if ! mountpoint -q "$mount_point"; then
        if ! sudo mount \
            -t s3files \
            "${filesystem_id}:/" \
            "$mount_point"
        then
            printf 'ERROR: failed to mount S3Files filesystem "%s" at "%s"\n' \
                "$filesystem_id" "$mount_point" >&2
            return 1
        fi
    fi
    add_fstab_entry "${filesystem_id}" "$mount_point"
}

s3files_link_target() {
    local fs_mount_point="$1"
    local s3_prefix="$2"

    if [ -n "$s3_prefix" ] && [ "$s3_prefix" != "null" ] && [ "$s3_prefix" != "/" ]; then
        printf "%s/%s" "$fs_mount_point" "$s3_prefix"
    else
        printf "%s" "$fs_mount_point"
    fi
}

link_study_to_s3files_mount() {
    local study_id="$1"
    local s3_prefix="$2"
    local filesystem_id="$3"
    local study_dir="${MOUNT_DIR}/${study_id}"
    local fs_mount_point="${S3FILES_ROOT}/${filesystem_id}"
    local link_target

    link_target="$(s3files_link_target "$fs_mount_point" "$s3_prefix")"
    mkdir -p "$MOUNT_DIR"
    if [ -e "$study_dir" ] && [ ! -L "$study_dir" ]; then
        rm -rf "$study_dir"
    fi
    ln -sfn "$link_target" "$study_dir"
}

# Use STS regional endpoint instead of global one. This allows external studies to connect with local interface endpoint
# if it exists. Refer https://docs.aws.amazon.com/sdkref/latest/guide/setting-global-sts_regional_endpoints.html
token=`curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600"`
region=`curl http://169.254.169.254/latest/meta-data/placement/availability-zone/ -H "X-aws-ec2-metadata-token: $token" | sed 's/.$//'`
export AWS_STS_REGIONAL_ENDPOINTS=regional
export AWS_DEFAULT_REGION=$region
export AWS_SDK_LOAD_CONFIG=1
is_linux="false"
if [ "$(uname -s)" = "Linux" ]; then
    is_linux="true"
fi

mkdir -p "$S3FILES_ROOT"

# Mount S3 buckets
mounts="$(cat "$CONFIG")"
num_mounts=$(printf "%s" "$mounts" | jq ". | length" -)

# First pass: mount each unique S3 Files filesystem once
if [ "$is_linux" = "true" ]; then
    for ((study_idx=0; study_idx<$num_mounts; study_idx++))
    do
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
            printf 'Mounting S3Files filesystem "%s" at "%s"\n' \
                "$filesystem_id" "$fs_mount_point"
            mount_s3files_filesystem "${filesystem_id}" "$fs_mount_point"
        fi
    done
fi

# Second pass: per-study paths (symlink to shared S3 Files mount or goofys)
for ((study_idx=0; study_idx<$num_mounts; study_idx++))
do
    # Parse bucket/key info
    study_id="$(printf "%s" "$mounts" | jq -r ".[$study_idx].id" -)"
    s3_bucket="$(printf "%s" "$mounts" | jq -r ".[$study_idx].bucket" -)"
    s3_prefix="$(printf "%s" "$mounts" | jq -r ".[$study_idx].prefix" -)"
    s3_role_arn="$(printf "%s" "$mounts" | jq -r ".[$study_idx].roleArn" -)"
    kms_arn="$(printf "%s" "$mounts" | jq -r ".[$study_idx].kmsArn" -)"
    bucket_region="$(printf "%s" "$mounts" | jq -r ".[$study_idx].region" -)"
    mount_source="$(printf "%s" "$mounts" | jq -r ".[$study_idx].source // \"S3\"" -)"
    filesystem_id="$(printf "%s" "$mounts" | jq -r ".[$study_idx].\"filesystem-id\" // .[$study_idx].filesystemId // \"\"" -)"
    study_dir="${MOUNT_DIR}/${study_id}"

    if [ "${filesystem_id}" = "" ] || [ "${filesystem_id}" = "null" ]; then
        mount_source="S3"
    fi

    if [ "$mount_source" = "S3Files" ] && [ "$is_linux" = "true" ]; then
        fs_mount_point="${S3FILES_ROOT}/${filesystem_id}"
        printf 'Linking study "%s" to S3Files mount at "%s"\n' \
            "$study_id" "$study_dir"
        link_study_to_s3files_mount "$study_id" "$s3_prefix" "$filesystem_id"
    else
        # Mount S3 location if not already mounted
        study_dir="${MOUNT_DIR}/${study_id}"
        ps -U "$LOGNAME" -o "command" | egrep -q "goofys .* ${study_dir}$"
        if [ $? -ne 0 ]
        then
            mkdir -p "$study_dir"
            if [ "$s3_role_arn" == "null" ]
            then
                printf 'Mounting internal study "%s" at "%s"\n' "$study_id" "$study_dir"
                goofys --region $bucket_region   --acl "bucket-owner-full-control" "${s3_bucket}:${s3_prefix}" "$study_dir"
            else
                bucket_region="$(printf "%s" "$mounts" | jq -r ".[$study_idx].region" -)"
                # BYOB studies have a region specified, but in case it isn't use the default region
                if [[ $bucket_region == "null" ]]; then
                printf 'Bucket region is not specified. Defaulting to "%s" for mounting \n' "$region"
                bucket_region=$region
                fi;

                # make .aws dir if it doesn't already exist and add credentials
                mkdir -p $AWS_CONFIG_DIR
                append_role_to_credentials $study_id $s3_role_arn
                if [ "$kms_arn" == "null" ]
                then
                    printf 'Mounting external study "%s" at "%s" using role "%s" and region "%s" \n' "$study_id" "$study_dir" \
                    "$s3_role_arn" "$bucket_region"
                    goofys --region $bucket_region --profile $study_id --acl "bucket-owner-full-control" \
                    "${s3_bucket}:${s3_prefix}" "$study_dir"
                else
                    printf 'Mounting external study "%s" at "%s" using role "%s", kms arn "%s" and region "%s" \n' "$study_id" "$study_dir" \
                    "$s3_role_arn" "$kms_arn" "$bucket_region"
                    goofys --region $bucket_region --profile $study_id --sse-kms $kms_arn --acl "bucket-owner-full-control" \
                    "${s3_bucket}:${s3_prefix}" "$study_dir"
                fi
            fi
        fi
    fi
done

# Define where the Jupyter notebook (if any) should be running
notebook_dir=""
case "$(env_type)" in
    "emr")
        notebook_dir="/opt/hail-on-AWS-spot-instances/notebook"
        ;;
    "sagemaker")
        notebook_dir="/home/ec2-user/SageMaker"
        ;;
esac

# Add a link to the mount in the notebook directory.
# (The user gets easy access, but it won't check the bucket into a git repo.)
# Only create a link if Jupyter is running, there are studies mounted, and the link
# doesn't already exist.
if [ -n "$notebook_dir" -a $num_mounts -ne 0 ]
then
    symlink_name="$notebook_dir/studies"
    [ ! -L "$symlink_name" ] && sudo ln -s "$MOUNT_DIR" "$symlink_name"
fi
