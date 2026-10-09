#!/usr/bin/env bash

# Prepares S3 / S3 Files study mounts on a workspace instance.
S3_MOUNTS="$1"
RSTUDIO_USER="$2"

[ -z "$S3_MOUNTS" -o "$S3_MOUNTS" = "[]" ] && exit 0

FILES_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
GOOFYS_URL="https://github.com/kahing/goofys/releases/download/v0.24.0/goofys"

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

install_jq() {
    if command -v jq >/dev/null 2>&1; then
        return 0
    fi
    if [ -x "${FILES_DIR}/offline-packages/jq-1.5-linux64" ]; then
        sudo mv "${FILES_DIR}/offline-packages/jq-1.5-linux64" "/usr/local/bin/jq"
        sudo chmod +x "/usr/local/bin/jq"
        return 0
    fi
    sudo yum install -y jq
}

install_fuse() {
    if lsmod 2>/dev/null | grep -q '^fuse '; then
        return 0
    fi
    if [ -f "${FILES_DIR}/offline-packages/ec2-linux/fuse-2.9.2-11.amzn2.x86_64.rpm" ]; then
        sudo yum localinstall -y "${FILES_DIR}/offline-packages/ec2-linux/fuse-2.9.2-11.amzn2.x86_64.rpm"
        return 0
    fi
    sudo yum install -y fuse fuse-common 2>/dev/null || sudo yum install -y fuse
}

install_goofys() {
    # Prefer the bundled binary (IMDSv2-capable build). S3 sync does not
    # preserve the execute bit, so check -f not -x.
    if [ -f "${FILES_DIR}/offline-packages/goofys" ]; then
        sudo cp "${FILES_DIR}/offline-packages/goofys" /usr/local/bin/goofys
        sudo chmod +x /usr/local/bin/goofys
        return 0
    fi
    if command -v goofys >/dev/null 2>&1; then
        return 0
    fi
    printf 'WARN: offline-packages/goofys missing; falling back to GitHub v0.24.0 (no IMDSv2)\n' >&2
    curl -fsSL -o /tmp/goofys "$GOOFYS_URL"
    sudo mv /tmp/goofys /usr/local/bin/goofys
    sudo chmod +x /usr/local/bin/goofys
}

install_s3files_client() {
    if command -v yum >/dev/null 2>&1; then
        sudo yum install -y amazon-efs-utils python3-botocore python3-boto3 2>/dev/null || true
        sudo yum update -y amazon-efs-utils 2>/dev/null || true
    fi
    configure_s3files_mount_helper
}

configure_s3files_mount_helper() {
    local conf
    # ponytail: 3.1.1 enables CloudWatch before mount; without logs API access efs-proxy can fail to bind
    for conf in /etc/amazon/efs/s3files-utils.conf /etc/amazon/efs/efs-utils.conf; do
        [ -f "$conf" ] || continue
        if grep -q '^\[cloudwatch-log\]' "$conf" 2>/dev/null; then
            sudo sed -i '/^\[cloudwatch-log\]/,/^\[/ s/^[# ]*enabled = .*/enabled = false/' "$conf"
        fi
    done
}

add_mount_hook() {
    local profile_file="$1"
    local owner="$2"
    sudo touch "$profile_file"
    # Quiet + once-per-shell: mount_s3.sh logs to ~/.mount_s3.log; stdout spam annoyed VS Code terminals.
    if ! grep -qF 'RG_STUDIES_MOUNTED' "$profile_file" 2>/dev/null; then
        # Drop the old noisy one-liner if present
        if grep -qF 'mount_s3.sh' "$profile_file" 2>/dev/null; then
            sudo sed -i '/mount_s3\.sh/d;/Research Gateway S3 study mounts/d;/Mount S3 study data/d' "$profile_file"
        fi
        printf '\n# Research Gateway S3 study mounts\nif [ -z "${RG_STUDIES_MOUNTED:-}" ] && [ -x /usr/local/bin/mount_s3.sh ]; then\n  export RG_STUDIES_MOUNTED=1\n  /usr/local/bin/mount_s3.sh >>"${HOME}/.mount_s3.log" 2>&1\nfi\n\n' \
            | sudo tee -a "$profile_file" >/dev/null
    fi
    sudo chown "${owner}:${owner}" "$profile_file"
}

install_mount_systemd_unit() {
    local user="$1"
    local home="/home/${user}"
    sudo tee /etc/systemd/system/rg-mount-s3.service >/dev/null <<EOF
[Unit]
Description=Research Gateway S3 study mounts
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
User=${user}
Environment=HOME=${home}
ExecStart=/usr/local/bin/mount_s3.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
    sudo systemctl daemon-reload
    sudo systemctl enable rg-mount-s3.service >/dev/null 2>&1 || true
}

run_initial_mount() {
    local user="$1"
    local home="/home/${user}"
    local attempt=0
    local max_attempts=24

    [ -d "$home" ] || return 0
    sudo touch "${home}/.mount_s3.log"
    sudo chown "${user}:${user}" "${home}/.mount_s3.log"

    while [ "$attempt" -lt "$max_attempts" ]; do
        if sudo -u "$user" -H aws sts get-caller-identity >/dev/null 2>&1; then
            sudo -u "$user" -H /usr/local/bin/mount_s3.sh >>"${home}/.mount_s3.log" 2>&1 || true
            sleep 15
            sudo -u "$user" -H /usr/local/bin/mount_s3.sh >>"${home}/.mount_s3.log" 2>&1 || true
            return 0
        fi
        sleep 10
        attempt=$((attempt + 1))
    done
    printf 'WARN: IAM not ready during bootstrap; mounts will run via systemd/login\n' >&2
}

setup_linux_user_mounts() {
    local user="$1"
    if ! id "$user" >/dev/null 2>&1; then
        return 0
    fi
    add_mount_hook "/home/${user}/.bash_profile" "$user"
    add_mount_hook "/home/${user}/.bashrc" "$user"
    add_mount_hook "/home/${user}/.profile" "$user"
    install_mount_systemd_unit "$user"
    run_initial_mount "$user"
}

case "$(env_type)" in
    "ec2-linux"|"rstudio")
        install_jq
        install_fuse
        install_goofys
        install_s3files_client
        ;;
esac

if [ ! -f "${FILES_DIR}/bin/mount_s3.sh" ]; then
    printf 'ERROR: %s/bin/mount_s3.sh is missing; sync bootstrap-scripts to S3\n' "$FILES_DIR" >&2
    exit 1
fi

sudo mkdir -p /usr/local/etc
sudo chmod +x "${FILES_DIR}/bin/mount_s3.sh"
sudo ln -sf "${FILES_DIR}/bin/mount_s3.sh" "/usr/local/bin/mount_s3.sh"
printf "%s" "$S3_MOUNTS" | sudo tee /usr/local/etc/s3-mounts.json >/dev/null
sudo chmod 644 /usr/local/etc/s3-mounts.json

case "$(env_type)" in
    "ec2-linux")
        setup_linux_user_mounts "ec2-user"
        if [ -f "${FILES_DIR}/bin/configure_studies_desktop.sh" ]; then
            sudo chmod +x "${FILES_DIR}/bin/configure_studies_desktop.sh"
            sudo "${FILES_DIR}/bin/configure_studies_desktop.sh" "ec2-user" || true
        fi
        ;;
    "rstudio")
        setup_linux_user_mounts "${RSTUDIO_USER:-rstudio-user}"
        if [ -f "${FILES_DIR}/bin/configure_studies_desktop.sh" ]; then
            sudo chmod +x "${FILES_DIR}/bin/configure_studies_desktop.sh"
            sudo "${FILES_DIR}/bin/configure_studies_desktop.sh" "${RSTUDIO_USER:-rstudio-user}" || true
        fi
        ;;
esac

exit 0
