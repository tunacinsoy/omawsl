# Docker daemon proxy auto-configuration — design

**Date:** 2026-07-29
**Status:** approved
**Scope:** detect a corporate HTTP(S) proxy from the environment and configure `dockerd` (Engine-in-WSL mode only) to use it, so image pulls don't silently time out on a corp machine.

## Why

A real corp-machine report: `omawsl install` (with Redis storage selected) failed at
`sudo docker run -d --name omawsl-redis ... redis:7` with:

```
docker: Error response from daemon: failed to resolve reference "docker.io/library/redis:7":
failed to do request: Head "https://registry-1.docker.io/v2/library/redis/manifests/7":
dial tcp 52.71.176.121:443: i/o timeout
```

Root-caused by comparing behavior across the shell and the daemon on that machine:

- `env | grep -i proxy` showed a full corp proxy configuration (`HTTP_PROXY`, `HTTPS_PROXY`,
  `NO_PROXY`, both upper- and lowercase, e.g. `HTTPS_PROXY=http://webproxy.nykreditnet.net:8080`).
  `curl -v https://registry-1.docker.io/v2/` succeeded (got a normal "unauthorized" response from
  the registry API) using that proxy.
- `docker context ls` confirmed the active context is `default` (native `docker-ce`, engine mode -
  not Docker Desktop).
- `~/.docker/config.json` had no `proxies` block, and `/etc/systemd/system/docker.service.d/`
  had no proxy drop-in at all.

`dockerd` runs as a systemd service and never inherits the interactive shell's environment.
With no proxy configured for the daemon itself, it attempted a direct connection to
`registry-1.docker.io`, which the corp firewall silently dropped (`i/o timeout`) since only
proxied egress is allowed. `omawsl_docker_reachable` (`install/lib.sh`) only checks that
`docker info` succeeds — it has no visibility into whether pulls will actually work, so this
failure isn't caught until `select-dev-storage.sh`'s `docker run` step, well after Docker itself
looked "installed and reachable."

## Interaction with the corp-safe config editing policy

`docs/superpowers/specs/2026-07-28-corp-safe-config-editing-design.md` (one day prior to this
design) put `/etc/systemd/system/docker.service.d/*` on a never-touch list, enforced by
`tests/config_safety_test.bats` — and even named `docker.service.d/http-proxy.conf` explicitly as
a file a corp IT manual might already own. That policy's own preference ordering, though, lists
"the format's own drop-in mechanism... a systemd `*.conf.d/` override directory" as the *safest*
way to touch a shared config area — precisely what a new file inside `docker.service.d/` is,
structurally. The blanket ban was written defensively (a corp manual *might* already use this
directory), not because a drop-in is inherently unsafe.

This design resolves the tension by never touching the conventional `http-proxy.conf` filename at
all (the one a corp manual is likely to use) and instead having omawsl own a distinctly-named file
it alone ever creates, reads, or removes: `docker.service.d/omawsl-proxy.conf`. Before writing it,
omawsl scans every *other* `.conf` file already in that directory for an existing proxy setting;
if one is found, omawsl writes nothing (and removes its own file if a prior run left one), so
whatever the corp side already manages is left as the sole, unambiguous source of truth rather than
two drop-ins silently fighting over which one systemd applies last.

`docs/config-safety.md` and `tests/config_safety_test.bats` are updated with a narrow, explicit,
documented exception scoped to exactly this one filename — not the whole directory glob.

## Components

### 1. `install/terminal/docker.sh` — `omawsl_detect_proxy_env <VAR>`

Small helper: given an uppercase var name (`HTTP_PROXY`, `HTTPS_PROXY`, `NO_PROXY`), returns its
value, falling back to the lowercase form (`http_proxy`, etc.) if the uppercase one is unset -
matches the real corp environment, which had both set identically. Empty string if neither is set.

### 2. `install/terminal/docker.sh` — `omawsl_docker_proxy_conflict <docker_service_d_dir> <own_file>`

True if any `*.conf` file in `docker_service_d_dir`, other than `own_file`, already contains a
`PROXY` environment assignment (a simple grep for `Environment=.*PROXY` - this only needs to
detect "something else already configured a proxy here," not parse the setting). Used to decide
whether omawsl should back off entirely.

### 3. `install/terminal/docker.sh` — `omawsl_configure_docker_proxy [docker_service_d_dir]`

- `docker_service_d_dir` defaults to `${OMAWSL_DOCKER_SERVICE_D_DIR:-/etc/systemd/system/docker.service.d}`;
  the managed file is always `$docker_service_d_dir/omawsl-proxy.conf`.
- Resolves `HTTP_PROXY`/`HTTPS_PROXY`/`NO_PROXY` via `omawsl_detect_proxy_env`. If neither
  `HTTP_PROXY` nor `HTTPS_PROXY` resolves to a non-empty value, returns immediately - silent no-op,
  the common case on a non-corp machine.
- If `omawsl_docker_proxy_conflict` is true: removes `omawsl-proxy.conf` if it exists (`sudo rm -f`,
  `|| true`), prints a one-line note that an existing proxy drop-in was found and omawsl is
  deferring to it, and returns - no write, no restart.
- Otherwise builds the drop-in body, one `Environment=` line per resolved var:
  ```
  [Service]
  Environment="HTTP_PROXY=..."
  Environment="HTTPS_PROXY=..."
  Environment="NO_PROXY=..."
  ```
  (`NO_PROXY` line included only if it resolved to a non-empty value.)
- **Idempotent:** compares the built content against the existing file's content (`sudo cat`, empty
  string if missing). Identical → skip write and skip restart entirely, so re-running `install.sh`
  never bounces the Docker daemon needlessly. Different → `sudo mkdir -p "$docker_service_d_dir"`,
  write via `sudo tee`, `sudo systemctl daemon-reload && sudo systemctl restart docker`, print one
  confirmation line.

Called from `omawsl_docker_engine`, right after `omawsl_install_docker_ce` - Engine mode only.
Docker Desktop mode is untouched: its proxy setting lives in Windows-side GUI settings
(Settings → Resources → Proxies), outside anything a WSL script can reach, consistent with the
project's existing "never touch Windows-side config automatically" boundary.

### 4. `uninstall/docker.sh` — symmetry

`omawsl_uninstall_docker` additionally does `sudo rm -f "$docker_service_d_dir/omawsl-proxy.conf"`
alongside its existing apt-source/keyring cleanup - removes only the exact file omawsl itself
might have created, never anything else in that directory. No-ops cleanly if the file was never
written (no proxy was ever detected) or was already removed by the conflict-backoff path above.

### 5. `bin/omawsl-sub/doctor.sh` — passive check

Extends the existing special-cased "Docker:" section (currently only fires for a not-yet-reachable
Docker Desktop). Adds: if Engine mode is active (`OMAWSL_DOCKER_MODE` isn't
`"Docker Desktop for Windows"`), a proxy var is present in the environment, and
`docker.service.d/omawsl-proxy.conf` doesn't exist *and* there's no conflicting file already
providing one → `[PENDING] Docker daemon proxy config - re-run install.sh to pick up your
HTTP_PROXY/HTTPS_PROXY`. There's no working granular `omawsl install docker` command (`docker`
isn't wired into `omawsl_install_direct`'s category switch), so "re-run install.sh" is the correct,
already-idiomatic recovery path - cheap, since `docker-ce` install itself no-ops when already
present. Silent when nothing's pending (no proxy detected, already configured, or deferring to an
existing conflicting file), matching the section's existing minimalism.

### 6. `docs/config-safety.md` + `tests/config_safety_test.bats` — narrow exception

`docs/config-safety.md`'s never-touch list entry for `/etc/systemd/system/docker.service.d/*`
gains an explicit carve-out sentence: *"except `omawsl-proxy.conf`, a file omawsl exclusively
creates/rewrites/removes itself under docs/superpowers/specs/2026-07-29-docker-daemon-proxy-autoconfig-design.md
- never the conventional `http-proxy.conf` name a corp manual would use, and never written at all
if another file in that directory already configures a proxy."`

`tests/config_safety_test.bats`'s forbidden-pattern grep for `docker\.service\.d` is narrowed so it
still fails on a write to `docker.service.d/http-proxy.conf` or any other filename, but explicitly
excludes matches against `docker.service.d/omawsl-proxy.conf` (e.g. by checking the matched line
doesn't also contain `omawsl-proxy.conf` before failing).

## Data flow / install sequence

No change to install ordering: `docker.sh` already runs before `select-dev-storage.sh`
(`install/terminal.sh`), so a fresh Engine-mode install configures the proxy before any
`docker run` for storage containers happens. Re-running `install.sh` later (e.g. after `doctor`
flags it pending) re-invokes the same idempotent function.

## Error handling

- No proxy detected → silent no-op, same as today.
- Conflicting existing drop-in detected → silent (one informational line), never overwrites.
- `sudo systemctl restart docker` only runs when content actually changed - avoids disrupting a
  working daemon on every re-run.
- Doctor's check is read-only; it never writes anything itself, only reports.

## Testing

- `tests/docker_test.bats`: proxy detection (upper/lowercase fallback, absent case), drop-in
  content generation, idempotent skip (no restart when content unchanged), conflict-detection
  backoff (existing other-file with a proxy setting → no write, own file removed if present).
- `tests/uninstall_docker_test.bats`: `omawsl-proxy.conf` removed on uninstall.
- `tests/doctor_test.bats` (or wherever doctor cases live): new pending/silent cases for the
  Engine-mode proxy check.
- `tests/config_safety_test.bats`: updated to assert the narrowed pattern still catches a write to
  `http-proxy.conf` while allowing `omawsl-proxy.conf`.

## Non-scope / explicitly deferred

- Docker Desktop mode: proxy configuration there is a Windows-side GUI setting, not reachable from
  a WSL script - out of scope, same boundary the rest of this project already respects.
- Any attempt to parse or validate the *content* of a conflicting existing drop-in beyond
  "does it mention a proxy at all" - omawsl only needs to decide whether to defer, not understand
  what's already configured.
- A granular `omawsl install docker` / `omawsl uninstall docker` single-item command - doesn't
  exist today and isn't added by this design; "re-run install.sh" remains the recovery path.
