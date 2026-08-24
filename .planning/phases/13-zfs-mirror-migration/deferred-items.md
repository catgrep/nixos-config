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
