#!/usr/bin/env bash
# GNOME Files (Nautilus) tuning for S3 Files study mounts on DCV workspaces.
set -euo pipefail

FILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHIM_SRC="${FILES_DIR}/rg-s3files-xattr-shim.c"
SHIM_SO="/usr/local/lib/librg-s3files-xattr-shim.so"
DESKTOP_USER="${1:-ec2-user}"
STUDIES_DIR="/home/${DESKTOP_USER}/studies"

install_xattr_shim() {
    if [ -f "$SHIM_SO" ]; then
        return 0
    fi
    if [ ! -f "$SHIM_SRC" ]; then
        printf 'WARN: %s missing; Nautilus may hang on S3 Files paths\n' "$SHIM_SRC" >&2
        return 0
    fi
    if ! command -v gcc >/dev/null 2>&1; then
        sudo yum install -y gcc 2>/dev/null || true
    fi
    if ! command -v gcc >/dev/null 2>&1; then
        printf 'WARN: gcc unavailable; skipping xattr shim\n' >&2
        return 0
    fi
    sudo gcc -shared -fPIC -o "$SHIM_SO" "$SHIM_SRC" -ldl || {
        printf 'WARN: failed to build xattr shim\n' >&2
        return 0
    }
    sudo chmod 755 "$SHIM_SO"
}

configure_dconf_defaults() {
    sudo mkdir -p /etc/dconf/db/local.d/locks /etc/dconf/profile
    sudo tee /etc/dconf/profile/user >/dev/null <<'EOF'
user-db:user
system-db:local
EOF

    sudo tee /etc/dconf/db/local.d/00-rg-nautilus-s3files >/dev/null <<'EOF'
[org/gnome/nautilus/preferences]
show-image-thumbnails='never'
show-folder-item-counts='never'
fts-enabled=false
default-folder-viewer='list-view'
search-filter-time-type='last_modified'

[org/gnome/desktop/thumbnails]
enable-thumbnails=false
EOF

    sudo tee /etc/dconf/db/local.d/locks/00-rg-nautilus-s3files >/dev/null <<'EOF'
/org/gnome/nautilus/preferences/show-image-thumbnails
/org/gnome/nautilus/preferences/show-folder-item-counts
/org/gnome/nautilus/preferences/fts-enabled
/org/gnome/desktop/thumbnails/enable-thumbnails
EOF

    if command -v dconf >/dev/null 2>&1; then
        sudo dconf update 2>/dev/null || true
    fi
}

configure_tracker_ignore() {
    sudo mkdir -p /etc/tracker3
    sudo tee /etc/tracker3/tracker-miner-fs-3.conf >/dev/null <<EOF
[org.freedesktop.Tracker3.Miner.Files]
ignored-directories=['${STUDIES_DIR}', '${STUDIES_DIR}/.s3files']
index-recursive-directories=[]
EOF
}

configure_session_preload() {
    [ -f "$SHIM_SO" ] || return 0
    sudo mkdir -p /etc/environment.d
    sudo tee /etc/environment.d/99-rg-s3files-xattr.conf >/dev/null <<EOF
LD_PRELOAD=${SHIM_SO}
EOF

    sudo tee /etc/profile.d/rg-s3files-xattr.sh >/dev/null <<EOF
# Research Gateway: avoid GNOME Files hangs on S3 Files NFS xattr queries.
if [ -f ${SHIM_SO} ]; then
    case ":\${LD_PRELOAD:-}:" in
        *:${SHIM_SO}:*) ;;
        *) export LD_PRELOAD="${SHIM_SO}\${LD_PRELOAD:+:\$LD_PRELOAD}" ;;
    esac
fi
EOF
    sudo chmod 644 /etc/profile.d/rg-s3files-xattr.sh
}

install_nautilus_desktop_override() {
    local src="/usr/share/applications/org.gnome.Nautilus.desktop"
    local dest="/usr/local/share/applications/org.gnome.Nautilus.desktop"
    [ -f "$SHIM_SO" ] || return 0
    if [ ! -f "$src" ]; then
        return 0
    fi
    sudo mkdir -p /usr/local/share/applications
    sudo awk -v shim="$SHIM_SO" '
        /^Exec=/ && $0 !~ /LD_PRELOAD/ {
            sub(/^Exec=/, "Exec=env LD_PRELOAD=" shim " ");
        }
        { print }
    ' "$src" | sudo tee "$dest" >/dev/null
    sudo chmod 644 "$dest"
    if command -v update-desktop-database >/dev/null 2>&1; then
        sudo update-desktop-database /usr/local/share/applications 2>/dev/null || true
    fi
}

install_xattr_shim
configure_dconf_defaults
configure_tracker_ignore
configure_session_preload
install_nautilus_desktop_override
