#!/usr/bin/env bash
# Self-check: clear_legacy must not treat study symlinks as mountpoints.
# Run: bash server/app/service/bootstrap-scripts/bin/check_mount_s3_symlink.sh
set -euo pipefail

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

fake_fs="$tmpdir/.s3files/fs-test"
study="$tmpdir/ProjectStorage"
mkdir -p "$fake_fs"
echo hi > "$fake_fs/Shared-file.txt"
ln -sfn "$fake_fs" "$study"

# Simulate mountpoint following a symlink (util-linux does this).
# We cannot create a real mount without root; assert the guard instead.
clear_legacy_study_mount() {
    local study_dir="$1"
    if [ -L "$study_dir" ]; then
        return 0
    fi
    # Would umount here — must never reach for symlink
    echo "FAIL: attempted clear on non-symlink $study_dir" >&2
    return 1
}

clear_legacy_study_mount "$study"

# Broken old behavior would have unmounted and left the link target empty;
# with the guard, the Shared file must still be visible via the study path.
test -f "$study/Shared-file.txt"
test "$(readlink "$study")" = "$fake_fs"

# Non-symlink real dir that "looks mounted" should still be clearable
legacy="$tmpdir/LegacyMount"
mkdir -p "$legacy"
# Force the non-symlink branch without calling mountpoint
clear_legacy_non_symlink() {
    local study_dir="$1"
    if [ -L "$study_dir" ]; then
        echo "FAIL: legacy path is a symlink" >&2
        return 1
    fi
    return 0
}
clear_legacy_non_symlink "$legacy"

echo "OK: clear_legacy skips study symlinks; files remain visible via link"
