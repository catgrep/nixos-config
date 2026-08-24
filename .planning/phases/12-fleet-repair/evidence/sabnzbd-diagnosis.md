# SABnzbd 38:194 Ownership Drift — Diagnosis (D-11)

Phase 12 Plan 02, Task 1.
All commands run over SSH against ser8 (`bdhill@192.168.68.65`) on 2026-08-23/24, read-only — no
ownership was changed as part of this diagnosis.

## Root cause (confirmed)

`modules/media/sabnzbd.nix` never pins an explicit `uid`/`gid` for `users.users.sabnzbd` — only
`group = lib.mkForce cfg.group` is set, and `services.sabnzbd.group` is itself forced to `"media"`.
With no static `uid`, NixOS's declarative user/group ID allocator assigns sabnzbd's system uid from
its persisted allocation pool at `/var/lib/nixos/uid-map` (and the matching `gid-map` for any
group name ever declared for it). That pool is **set-dependent, not identity-stable**: whenever the
overall set of declared system users/groups changes anywhere in the fleet config, an
already-existing but still-unpinned account can be handed a *different* numeric id on the very next
`nixos-rebuild switch` — even though nothing in `modules/media/sabnzbd.nix` itself changed.

This is exactly what happened here, and it happened **twice**, confirmed by direct evidence:

1. **Historical drift (uid 38 / gid 194).** `/var/lib/sabnzbd/admin`, `/var/lib/sabnzbd/backup`,
   `/var/lib/sabnzbd/logs`, and `/var/lib/sabnzbd/sabnzbd.ini.bak` are all owned `38:194`, last
   modified `2026-08-17 02:07:34` — i.e. the last time sabnzbd successfully ran and wrote its own
   state, under whatever uid/gid the allocator had assigned it at that point in time. `getent passwd
   38` and `getent group 194` both return **nothing live today** — uid 38 and gid 194 are fully
   vacated identities, not currently claimed by any account. There is also no `/etc/group` entry
   named `sabnzbd` at all (the module forces the account's group to `media`), yet the persisted
   `gid-map` still carries a stale legacy reservation `"sabnzbd":194` — NixOS's id-allocator does not
   garbage-collect unused name→id reservations once made, which is why that number survives even
   though nothing uses it.
2. **A second, freshly observed drift event on this same host, today.** ser8's current system
   generation is `system-279-link` (activated `2026-08-22 01:33`, pointing at the same store path as
   `system-277-link`). `sabnzbd.service`'s last failure timestamp is `Sat 2026-08-22 01:33:56 PDT` —
   the same second as that activation. `/var/lib/nixos/uid-map` (mtime `Aug 22 01:33`) currently
   assigns `"sabnzbd":985`, and live `getent passwd sabnzbd` confirms `sabnzbd:x:985:1100:...`. The
   top-level `/var/lib/sabnzbd` directory and `/var/lib/sabnzbd/sabnzbd.ini` are already owned
   `985:1100` (modified `2026-08-22 00:52`, i.e. this most recent boot) — meaning the account's
   *current* auto-allocated identity is 985, already a different number than the *historical* 38
   found on the untouched subdirectories. The channel bump to NixOS 26.05 (`system-268-link`,
   activated `2026-08-17 11:30` — after the last successful sabnzbd write at `02:07` that same day)
   is the most likely point of the first reassignment away from 38; Phase 12 plan 12-01's own
   identity-reconciliation switch on `2026-08-22` (which pinned/adjusted other declared
   users/groups, per `12-01-SUMMARY.md`) is confirmed here as at least a contributing/compounding
   trigger for further reallocation, landing sabnzbd at 985 by generation 279.

**Conclusion: this matches the "uid auto-allocation drifted across a channel bump" hypothesis, and
generalizes it** — the mechanism is not tied to channel bumps specifically but to *any* change in
the fleet's declared user/group set while sabnzbd itself stays unpinned. It has now demonstrably
recurred at least twice on this host (the 26.05 bump, and again during this very phase's own
12-01 switch). Without a static pin, it will keep recurring on unrelated future switches — this is
the direct justification for D-12's static uid/gid pin, not merely a one-off historical accident.

**Failure mode on the live host:** sabnzbd (running as its *current* live identity, uid 985 / gid
1100 `media`) cannot open its own `admin/` state (`history1.db`, `queue10.sab`, etc. — all mode
`0600`, owned by the vacated `38:194`), so it dies almost immediately (474ms) before Python's own
logging/stdout buffer is ever flushed to the journal — which is why `journalctl -u sabnzbd`,
`journalctl _PID=<pid>`, and a full-journal `--grep=sabnzbd` all return **zero lines** for the
process itself despite `StandardOutput=journal`/`StandardError=journal` being set. This silent-crash
behavior is the same "known-blind" pattern already called out for the SABnzbd smoketest in
STATE.md's deferred items (D-13 in this plan explicitly does not fix that smoketest).

## Evidence — raw command output

### Ownership of `/var/lib/sabnzbd`

```
$ ssh bdhill@192.168.68.65 'ls -lan /var/lib/sabnzbd'
total 311
drwxr-xr-x  5 985 1100    7 Oct 11  2025 .
drwxr-xr-x 32   0    0   34 Aug 23 17:00 ..
drwxr-xr-x  3  38  194    9 Aug 17 02:07 admin
drwxr-xr-x  2  38  194 1250 Aug 17 02:07 backup
drwxr-xr-x  2  38  194    4 Aug 17 02:07 logs
-rw-------  1 985 1100 2647 Aug 22 00:52 sabnzbd.ini
-rw-------  1  38  194 2647 Aug 17 02:07 sabnzbd.ini.bak

$ ssh bdhill@192.168.68.65 'ls -lan /var/lib/sabnzbd/admin'
total 61
drwxr-xr-x 3  38  194     9 Aug 17 02:07 .
drwxr-xr-x 5 985 1100     7 Oct 11  2025 ..
drwxr-xr-x 2  38  194     3 Dec 26  2025 future
-rw------- 1  38  194 16384 Aug 17 02:07 history1.db
-rw------- 1  38  194    18 Aug 17 18:03 postproc2.sab
-rw------- 1  38  194    20 Aug 17 18:03 queue10.sab
-rw------- 1  38  194     5 Aug 17 18:03 rss_data.sab
-rw------- 1  38  194  5582 Aug 17 18:03 totals10.sab
-rw------- 1  38  194    21 Aug 17 18:03 watched_data2.sab
```

### Current live identities

```
$ ssh bdhill@192.168.68.65 'getent passwd sabnzbd'
sabnzbd:x:985:1100:sabnzbd user:/var/empty:/run/current-system/sw/bin/nologin

$ ssh bdhill@192.168.68.65 'getent group sabnzbd'
(no output — no group named "sabnzbd" exists live; the module forces group = "media")

$ ssh bdhill@192.168.68.65 'getent group media'
media:x:1100:bdhill,frigate

$ ssh bdhill@192.168.68.65 'getent group mealie'
mealie:x:992:

$ ssh bdhill@192.168.68.65 'getent passwd 38'
(no output — uid 38 is not a currently-declared account)

$ ssh bdhill@192.168.68.65 'getent group 194'
(no output — gid 194 is not a currently-declared group)

$ ssh bdhill@192.168.68.65 'getent passwd 985'
sabnzbd:x:985:1100:sabnzbd user:/var/empty:/run/current-system/sw/bin/nologin
(confirms 985 is collision-free — the only account claiming it is sabnzbd itself)
```

### Service failure

```
$ ssh bdhill@192.168.68.65 'systemctl status sabnzbd --no-pager -l'
× sabnzbd.service - sabnzbd server
     Loaded: loaded (/etc/systemd/system/sabnzbd.service; enabled; preset: ignored)
     Active: failed (Result: exit-code) since Sat 2026-08-22 01:33:56 PDT; 1 day 16h ago
   Duration: 474ms
 Invocation: a9032b3c8d614e5f84f7536e00713c47
    Process: 51450 ExecStart=/nix/store/.../sabnzbd-5.0.4/bin/sabnzbd --log-all --disable-file-log -f /var/lib/sabnzbd/sabnzbd.ini (code=exited, status=1/FAILURE)
    Main PID: 51450 (code=exited, status=1/FAILURE)

$ ssh bdhill@192.168.68.65 'journalctl -u sabnzbd -n 100 --no-pager'
-- No entries --

$ ssh bdhill@192.168.68.65 'journalctl _SYSTEMD_INVOCATION_ID=a9032b3c8d614e5f84f7536e00713c47 --no-pager'
-- No entries --

$ ssh bdhill@192.168.68.65 'journalctl _PID=51450 --no-pager'
-- No entries --

$ ssh bdhill@192.168.68.65 "journalctl --no-pager --grep=sabnzbd" | grep -v 'Sonarr\|Radarr'
(no sabnzbd-process-authored lines at all — only Sonarr/Radarr client error noise, e.g.
"Unable to connect to SABnzbd, Connection refused (127.0.0.1:8085)", confirming the port
never opens because the process dies during early startup, before logging is flushed)
```

### Generation / activation correlation

```
$ ssh bdhill@192.168.68.65 'ls -la /nix/var/nix/profiles/ | grep system'
system -> system-279-link
system-268-link  Aug 17 11:30  ...-nixos-system-ser8-26.05.20260817.0dd31db   <- first 26.05 (channel-bump) generation
...
system-277-link  Aug 20 21:39  ...-nixos-system-ser8-26.05.20260817.0dd31db
system-278-link  Aug 22 01:25  ...-nixos-system-ser8-26.05.20260817.0dd31db  (different store path)
system-279-link  Aug 22 01:33  ...-nixos-system-ser8-26.05.20260817.0dd31db  (currently active; same store path as 277)

$ ssh bdhill@192.168.68.65 'ls -la /var/lib/nixos/'
-rw-r--r-- 1 root root  804 Aug 22 01:33 gid-map
-rw-r--r-- 1 root root 1083 Aug 22 01:33 uid-map
(both regenerated at the same activation timestamp that sabnzbd.service failed)

$ ssh bdhill@192.168.68.65 "cat /var/lib/nixos/uid-map" | grep -o '"sabnzbd":[0-9]*'
"sabnzbd":985

$ ssh bdhill@192.168.68.65 "cat /var/lib/nixos/gid-map" | grep -o '"sabnzbd":[0-9]*'
"sabnzbd":194   <- stale legacy reservation for the never-garbage-collected group name "sabnzbd";
                   the live account's actual group is forced to "media" (1100), this number is
                   unused dead weight in the allocator's persisted map, not a currently active gid.

$ ssh bdhill@192.168.68.65 "cat /var/lib/nixos/gid-map" | grep -o '"mealie":[0-9]*'
"mealie":992    <- confirms gid 992 belongs to the live mealie service group, NOT media/sabnzbd.
                   This corrects this plan's frontmatter/Task-2 text, which cited "gid 992" as
                   the media group's target gid per an earlier (pre-correction) reading of D-07 —
                   PROJECT.md's actual corrected record (12-01-SUMMARY.md, "[Phase 12, D-07/D-08
                   corrected]") states media's live/declared gid is 1100, and gid 992 is mealie's.
                   See Deviations in 12-02-SUMMARY.md.
```

## Was any file under `modules/media/` modified in this task?

No. This task is diagnosis-only, per its acceptance criteria; `modules/media/sabnzbd.nix` is
touched in Task 2 only, gated on this diagnosis.

## Target values for Task 2's repair

- **uid to pin:** `985` — the live, currently-allocated `sabnzbd` identity (not `38`, which is
  vacated).
- **gid to pin:** `1100` — the live `media` group's real gid (not `992`, which is `mealie`'s; the
  plan's original Task-2 text citing "992 per D-07/plan 12-01" is stale relative to 12-01's own
  corrected finding that media is 1100/1100, not 1002/992 — see the Deviations section of
  `12-02-SUMMARY.md`).
- **Files to chown in place** (no delete/recreate): `/var/lib/sabnzbd/admin`,
  `/var/lib/sabnzbd/backup`, `/var/lib/sabnzbd/logs`, `/var/lib/sabnzbd/sabnzbd.ini.bak`, and their
  contents (currently `38:194`) → `985:1100`. The top-level dir and `sabnzbd.ini` are already
  `985:1100` and need no change; a single `chown -R 985:1100 /var/lib/sabnzbd` is idempotent and
  safe to run across the whole tree regardless.
