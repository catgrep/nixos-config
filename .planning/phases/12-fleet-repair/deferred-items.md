
## 12-03 Task 2 (2026-08-23)

- **Item:** `shellcheck scripts/smoketests/ser8/all.sh scripts/smoketests/media/all.sh` exits 1 (SC2034 `SUITE_NAME`/`TESTS` "appears unused", SC1091 info on sourced libs).
- **Status:** Pre-existing, repo-wide pattern across every `scripts/smoketests/*/all.sh` fan-out entry point (verified against `gateway/all.sh` and `household/all.sh`, both untouched by this plan, showing the identical warnings). Not caused by this task's edits (removal of the qBittorrent MEDIA_SERVICES/MEDIA_ACCOUNTS entries and the nordvpn suite line). Not enforced by `make check` (no shellcheck target exists there).
- **Reason deferred:** Out of scope per Scope Boundary — fixing would require repo-wide changes to `scripts/smoketests/lib/fanout.sh`'s consumption pattern or adding disable directives to every `all.sh` file, well beyond this task's files_modified list.
