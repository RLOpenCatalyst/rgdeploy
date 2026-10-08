---
name: Honour mount flags
overview: "Make the mount script enforce each entry’s `writeable` and `readable` flags, and add a --dry-run mode plus a dummy config so those decisions can be checked from printed actions without mounting."
todos:
  - id: parse-flags
    content: Parse writeable/writable and readable per entry, defaulting missing flags to true; skip studies that are not readable and clean up an existing study path
    status: pending
  - id: goofys-ro
    content: Pass -o ro to goofys when writeable is false, and remount if an existing goofys mount has the wrong mode
    status: pending
  - id: s3files-bind-ro
    content: For read-only S3 Files studies, skip prefix creation and use a read-only bind mount plus fstab entry instead of a symlink
    status: pending
  - id: dry-run-flag
    content: Add --dry-run and --config so the script prints planned actions and performs no mounts, installs, fstab edits, or IMDS calls
    status: pending
  - id: dummy-config-test
    content: Add a dummy s3mounts JSON and a dry-run check that asserts the printed action for each flag combination
    status: pending
isProject: false
---

# Honour `writeable` and `readable` in the mount script

The JSON key is **`writeable`** (not `writable`). All seven entries in [s3mounts.json](s3mounts.json) are `readable: true`. Two are read-only: `TopChartsNew-RO` and `IngressStore` (`writeable: false`). `TopChartsNew-RO` and `TopChartsNew-RW` share filesystem `fs-09158291c6ffc650b`, so the NFS mount itself cannot be read-only.

Today [mount_s3 (6).sh](mount_s3%20(6).sh) never reads those flags. Every S3 entry is a read-write goofys mount, and every S3 Files study is a symlink onto a read-write NFS mount (a symlink cannot be read-only on its own).

## Flag rules

Read `writeable`, with `writable` as an alias. Missing flags default to `true` so older configs keep current behavior.

- `readable` is not true: do not mount or link that study. If a previous run left a goofys mount, symlink, or bind mount at `~/studies/<id>`, remove it.
- `readable` true and `writeable` true: current behavior (goofys read-write, or symlink onto the S3 Files prefix).
- `readable` true and `writeable` false: mount read-only at `~/studies/<id>`.

## S3 (goofys)

In pass 2, when `writeable` is false, add `-o ro` to all three `goofys` invocations (internal, external, and KMS). FUSE `ro` rejects writes; file-mode bits would not.

If goofys is already running on that path with the wrong mode (`findmnt` options), unmount and remount so a flag change takes effect on the next run.

## S3 Files

Keep the shared filesystem mount under `~/studies/.s3files/<fs-id>` read-write. That preserves prefix creation for RW siblings and the `.hidden` metadata write in `hide_s3files_metadata_dirs`.

For a study with `writeable: false` in `link_study_to_s3files_mount`:

- Do not `mkdir` the prefix. If the prefix is missing, log an error and skip.
- Replace the symlink with a read-only bind mount of `<fs-mount>/<prefix>` onto `~/studies/<id>` (`mount --bind`, then `mount -o remount,bind,ro`).
- If that path is already a read-only bind to the same target, leave it.
- Add a matching `fstab` line: `<target> <study_dir> none bind,ro 0 0`, and drop a stale symlink-era or read-write fstab line for that study path.

`clear_legacy_study_mount` must unmount a legacy NFS mount on the study path, and must not tear down a correct read-only bind.

Read-write S3 Files studies stay symlinks. If a study flips from read-only to read-write, unmount the bind and replace it with the symlink.

## Dry run

Add flags to [mount_s3 (6).sh](mount_s3%20(6).sh):

- `--dry-run` prints each planned action and exits 0. It does not mount, unmount, `mkdir`, symlink, edit `/etc/fstab`, install packages, call IMDS, or invoke `goofys`.
- `--config PATH` overrides `/usr/local/etc/s3-mounts.json`.

Dry run is declarative: it does not look at the live mount table. Output is determined only by the JSON, so a local run is stable and does not require the prefix or filesystem to exist. Skip the instance-metadata `curl` block when `--dry-run` is set, and use a placeholder region only if a later print needs one.

Print one line per action, prefixed `DRY-RUN:`, for example:

- `DRY-RUN: skip <id> (readable=false)`
- `DRY-RUN: goofys rw <bucket>:<prefix> -> ~/studies/<id>`
- `DRY-RUN: goofys ro <bucket>:<prefix> -> ~/studies/<id>`
- `DRY-RUN: mount s3files rw <fs-id> -> ~/studies/.s3files/<fs-id>` (once per filesystem)
- `DRY-RUN: symlink <id> -> <fs-mount>/<prefix>`
- `DRY-RUN: bind ro <fs-mount>/<prefix> -> ~/studies/<id>`

A shared filesystem is still printed as one read-write `mount s3files` even when one of its studies is read-only. The read-only study is a `bind ro` line, not a second filesystem mount.

## Dummy config and check

Add [s3mounts.dryrun.json](s3mounts.dryrun.json) with fake bucket and filesystem ids covering every branch:

- S3 internal, both flags true: goofys rw
- S3 internal, `writeable: false`, `readable: true`: goofys ro
- S3 with `roleArn` and `kmsArn`, `writeable: false`: goofys ro (profile and kms still printed)
- flags omitted: goofys rw (defaults)
- `readable: false`: skip, no goofys or link line
- two S3 Files studies on the same `filesystem-id`, one `writeable: false` and one `writeable: true`: one `mount s3files rw`, one `bind ro`, one `symlink`
- one S3 Files study, `writeable: false` (IngressStore shape): one `mount s3files rw` plus `bind ro`, and no prefix-create line

Add [test_mount_s3_dry_run.sh](test_mount_s3_dry_run.sh) that runs:

```bash
bash "mount_s3 (6).sh" --dry-run --config s3mounts.dryrun.json
```

and fails unless stdout contains exactly those actions for the dummy ids and contains no `goofys` invocation that is not on a `DRY-RUN:` line. The check is the verification; it does not need AWS, root, or a live mount.
