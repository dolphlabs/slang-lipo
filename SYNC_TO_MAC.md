# Sync roadmap 1→5 to Mac + push

Executor could not reach machineId `2ad2e283-75f7-4635-a890-661cae9579cf`
(Shell/Read stayed on the box). Work landed in `/workspace/lipo` and was
committed on top of `origin/main` as:

- `11f28ff` feat: realtime events, chat typing/read, password reset, post media, hardening

Push from the box failed: no `ssh` client and no `gh`/HTTPS credentials.
Push from the Mac (has GitHub auth):

```sh
cd /Users/utee/Documents/lipo
git fetch origin
git checkout main
git pull --ff-only   # should be at 0f72e99 or later
# Option A — if this workspace is shared / you copy the repo:
#   git cherry-pick 11f28ff
# Option B — apply patch/bundle from the box artifacts:
#   git pull
#   git am /path/to/lipo-roadmap-1-5.patch
#   # or: git pull /path/to/lipo-roadmap-1-5.bundle
git push -u origin HEAD
slangc main.sl
```

Or rsync tree (never overwrite `.env`):

```sh
rsync -a --exclude .env --exclude '*.db' --exclude main --exclude '*_bin' \
  /path/to/workspace/lipo/ /Users/utee/Documents/lipo/
cd /Users/utee/Documents/lipo && slangc main.sl && git push -u origin HEAD
```

Artifacts on the box: `/workspace/lipo-roadmap-1-5.tgz`, `.patch`, `.bundle`.
