# Phase 13 Deferred Items

Out-of-scope discoveries found during execution, logged rather than fixed
(per executor scope boundary — only fix issues directly caused by the
current task's changes).

## 13-01 Task 1: Stale qBittorrent/wgnord/nginx references outside the approved edit scope

Task 1's approved scope covered 10 specific sections of
`.planning/SER8-ZFS-MIRROR-MIGRATION.md` (Service Freeze Set, Goal,
Steps 0.2/0.3/0.4, Smoketests, Stage 5, Migration State Machine mermaid,
Step 3.3, Handoff Status, Desired ZFS Configuration). Two sections outside
that scope still describe the qBittorrent/wgnord/nginx stack as live and
were pre-existing before this task's changes, so they were left untouched:

- **Known Blockers → "qBittorrent and wgnord Restart Loop"** (originally
  lines 218-225): still frames the restart loop as an open blocker
  ("This behavior must be diagnosed and resolved before the migration
  freeze"). Phase 12 deleted the stack; this section is now purely
  historical but is not marked as such.
- **Step 3.1: "Stop the Full Media Stack"** (originally lines 586-596):
  still instructs "Include `wgnord.service` as needed to keep qBittorrent
  from restarting" and "Optionally stop nginx if its qBittorrent proxy
  would otherwise present a misleading interface." Both units are deleted
  from the fleet — a fresh session following this step literally would
  reference nonexistent units.

**Recommendation:** Plan 13-03 (which executes Step 3.1's freeze) should
either amend Step 3.1 in its own task scope or treat this note as the
authoritative correction before running the stop sequence. The Known
Blockers section should be marked resolved/historical in a future doc
pass — Task 1's Handoff Status edit already marks the underlying blocker
resolved, so Known Blockers is now redundant with that update.

**Status:** deferred, not blocking — Task 1's Service Freeze Set (the
actual stop list Plan 13-03 executes) is correctly amended; this is
narrative/instructional staleness in adjacent prose, not in the operative
service list.

## 13-06 Task 4: `scripts/smoketests/media/all.sh` checks a legacy downloads path that no longer exists

`./scripts/smoketests/media/all.sh ser8` fails at its "completed download
permissions" check: `find /mnt/media/downloads/complete
/mnt/media/downloads/usenet/complete ...` errors because
`/mnt/media/downloads/complete` does not exist (only
`/mnt/media/downloads/usenet/complete` does). Confirmed pre-existing and
NOT caused by the restore: the Plan 13-01 preflight inventory
(`/persist/zfs-migration/media-inventory-preflight.tsv`, taken 2026-08-24
before the freeze) already shows only `/mnt/media/downloads` and
`/mnt/media/downloads/usenet` — no top-level `complete` directory existed
at that time either. This is very likely a leftover from Phase 12's
qBittorrent/torrent-stack retirement (the top-level `downloads/complete`
was presumably the retired torrent client's completed-download directory,
which was never recreated once torrents were removed), which this
smoketest was never updated to reflect.

**Recommendation:** Either recreate the legacy `downloads/complete`
directory as a harmless empty placeholder, or (better) update the
smoketest to check only the paths the current usenet-only download flow
actually uses. D-21 (Phase 13's final plan) already relocates downloads
off the media pool entirely to `rpool/safe/downloads`, which will make
this specific check moot — the smoketest's path assumptions should be
revisited as part of that same change.

**Status:** deferred, not blocking — every other check in `all.sh`
(service connectivity, primary groups, media library permissions, Bazarr
access assessed separately below, and the full `test-zfs-media.sh` D-19
suite) was independently run and passed; only this one stale check fails.

## 13-06 Task 4: systemic ACL gap blocks Bazarr's base-group write access across most of the library

Manually replicating `all.sh`'s "Bazarr access to media libraries" check
(unreachable via the script itself because it exits at the failure above)
found Bazarr genuinely cannot write into ~280 directories under
`/mnt/media/tv` and `/mnt/media/movies` (essentially the whole library,
not an isolated case). Root cause: these directories carry an extended
POSIX ACL where the base `group::` entry is `r-x` (not `rwx`), with a
`mask::rwx` and a named `group:mealie:rwx` entry giving full access only
to that one named group — `ls -l`'s displayed mode bits (`drwxrwsr-x`)
reflect the ACL mask, not the true base group permission, which is why
this was not visually obvious. Bazarr (uid 986, gid `media`, no named ACL
entry of its own) only inherits the base group's `r-x`.

Confirmed pre-existing and NOT caused by the restore: `getfacl` on
`backup/media-staging/tv/Seinfeld` (created via `rsync -aHAX` in Plan
13-03, weeks before any ZFS mirror work) shows the byte-identical ACL
structure. The block-checksummed `zfs send`/`recv` (D-08) and the
preceding rsync both faithfully preserved this pre-existing ACL state —
that is the restore working correctly, not a regression.

**Recommendation:** A deliberate `setfacl -R` normalization pass across
the library is needed, plus a decision on whether the `group:mealie:rwx`
named entries (found on multiple show directories, not just Seinfeld) are
intentional or leftover cruft from an earlier permissions script. This is
a substantial, separate body of work — out of scope for a restore-cutover
plan to invent.

**Status:** deferred, not blocking Plan 13-07 — the scrub (Step 5.5) and
staging destroy (Step 6.2) only depend on data/checksum integrity, which
is independently confirmed intact; this is a data-hygiene issue for a
future, separately-scoped plan.

## 13-07 Step 6.2: `backup/media-staging` destroy deferred to, then executed by, the operator (D-18)

Operator decision, relayed mid-plan-13-07: the destroy of
`backup/media-staging` (`zfs destroy backup/media-staging`) would NOT be
run by this plan at all. The operator would run it themselves, by hand,
after independently confirming the first media pool scrub (Step 5.5)
completed clean. D-18's gate ("first clean scrub AND Step 5.4 app tests
passed") is satisfied by the operator taking direct ownership of the
one-way destroy step rather than delegating it to the executor.

This plan's original Task 4 (checkpoint:decision — approve the destroy)
and Task 5 (execute the destroy) were intentionally not executed by the
plan's own automated flow.

**Update:** the operator ran the destroy themselves shortly after the
scrub completed — `zpool history backup` shows
`2026-08-25.16:39:47 zfs destroy -r backup/media-staging`, using the
exact sanctioned command (dataset destroy only, never a recursive
filesystem delete through the mountpoint). Capacity returned to the
backup pool (10.1T available). Camera datasets confirmed unaffected. See
`evidence/scrub-and-staging-destroy.md` for the full independent
verification.

**Status:** resolved — both by operator decision (this plan does not
execute the destroy) and by the operator's own subsequent action (the
destroy has, in fact, happened). Nothing further to do here.
