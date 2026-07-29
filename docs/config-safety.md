# Config safety

omawsl runs on machines that are often also managed by a company-specific
WSL2 setup manual - proxy settings, corporate DNS, VPN/mirrored-networking
config, internal Maven/npm mirrors, and more, spread across a fixed list of
files. That list varies from company to company, so omawsl can't special-case
any one of them. Instead it follows one rule, everywhere:

> omawsl never writes its own content directly into a file it doesn't exclusively own. Content omawsl needs to provide lives in files under its own tree (the repo checkout at `$OMAWSL_HOME`, default `~/.local/share/omawsl`) and is freely rewritten there - omawsl is the sole owner. Touching a shared file happens only through the smallest possible, idempotent, content-checked addition: the format's own drop-in mechanism if one exists (`/etc/profile.d/*`, `/etc/apt/apt.conf.d/*`, `/etc/sudoers.d/*`, a systemd `*.conf.d/` override directory), a single guarded include/source line added only if not already present, or - only for formats with neither, like `/etc/wsl.conf` - a content-based check-then-append.

## What this looks like in practice

- `~/.bashrc` gets at most one guarded `source` line pointing at omawsl's own
  `configs/bashrc` in the repo checkout, added only if not already present.
  Everything else already in `~/.bashrc` - corp additions, hand edits - is
  left exactly as-is.
- `~/.inputrc` is never written by omawsl at all. `configs/bashrc` only
  points `$INPUTRC` at omawsl's own copy when the user has no `~/.inputrc`
  of their own.
- `/etc/wsl.conf`'s `[boot] systemd=true` line (needed for Docker Engine
  mode) is appended only if not already present, tolerant of whitespace
  variants - a no-op if a corp manual (or you, by hand) already set it.

## Files omawsl never creates or modifies

- `~/.zshrc`, `/etc/zsh/zshenv`, `~/.oh-my-zsh/**` - omawsl ships bash only.
- `~/.curlrc`
- `/etc/apt/apt.conf.d/*`
- `/etc/profile.d/*`
- `/etc/sudoers*`
- `~/.m2/settings.xml`
- `~/.git-templates/**`
- `~/.config/direnv/direnvrc`
- `/etc/systemd/system/wsl-vpnkit.service`
- `/etc/systemd/system/docker.service.d/*` - except `omawsl-proxy.conf`, which omawsl
  exclusively creates, rewrites, and removes itself. It's never the conventional
  `http-proxy.conf` name a corp manual would use, and it's never written at all if another
  file in that directory already configures a proxy - see
  `docs/superpowers/specs/2026-07-29-docker-daemon-proxy-autoconfig-design.md`.

Enforced by `tests/config_safety_test.bats`, a static regression guard that
fails the suite if a future change ever adds a write to one of these paths.

## Migrating from a pre-source-line install

Every existing install's `~/.bashrc` is a full old-style copy of a past
`configs/bashrc` revision (see "What this looks like in practice" above -
that's exactly the pattern this feature replaced). The one-time migration
(`migrations/1785266018.sh`) never deletes that old copy - it only appends
the new guarded `# >>> omawsl >>>` marker block below it, same as it would
for any other pre-existing `~/.bashrc` content.

That's safe, but it's worth cleaning up by hand: the old copy ends in
`exec zellij`, and on any fresh outer shell where zellij is installed, that
`exec` replaces the shell process before ever reaching the newly-appended
marker block - so the new sourced `configs/bashrc` never actually loads.
Everything above the `# >>> omawsl >>>` line in `~/.bashrc` is safe to
delete by hand once you've migrated; the migration script itself prints
this same advisory to stdout when it detects an old-style `~/.bashrc`.
