# Sync roadmap 1→5 to Mac

This executor could not reach `uteesmacbook`
(`machineId` `2ad2e283-75f7-4635-a890-661cae9579cf`) — Shell/Read ran on the box.
Implementation is in `/workspace/lipo` and tarball `/workspace/lipo-roadmap-1-5.tgz`.
Changes are also pushed to `origin` (`dolphlabs/slang-lipo`).

## Apply on the Mac

```sh
# Prefer git pull if origin is up to date:
cd /Users/utee/Documents/lipo && git pull

# Or from tarball (never overwrite .env):
# rsync -a --exclude .env --exclude '*.db' --exclude main --exclude smoke_*_bin lipo/ /Users/utee/Documents/lipo/
cd /Users/utee/Documents/lipo
slangc main.sl
```

**Never overwrite `.env`.** Merge new keys from `.env.example` by hand.

## Verify

- `slangc main.sl` succeeds
- migrate at **v7**
- WS events: `post.created`, `post.liked`, `user.followed`, `typing`, `chat.read`
