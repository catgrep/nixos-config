# Phase 10 deferred items

Out-of-scope discoveries found during execution. Not fixed by the plan that found them.

## RESOLVED: `make status` cannot reach any host from the development workstation

- **Found during:** plan 10-04, Task 1
- **What:** the `status` target pings `$(host).internal`. That name resolves for none of ser8, firebat, pi4, or pi5 from this workstation — `ping: unknown host` for all four — so `make status` reports the entire fleet offline even when every host answers SSH at its `deploy.yaml` address.
- **Diagnosis corrected:** 10-04 read this as a workstation resolver concern. It was not. `.internal` was never a name this repository configures anywhere; the target simply did not use `get-host-ip`, the resolver that every other host target in the Makefile already calls. No LAN or workstation DNS change was needed.
- **Fixed by:** plan 10-05, Task 1, commit `e6547ca`. The target now pings `$(call get-host-ip,$(host))` and prints the address it used, so the report is checkable rather than merely coloured. `make status` now reports ser8 and firebat Online.
- **Residual, genuinely out of scope:** pi4 and pi5 report Offline and really are. Neither answers on its tailnet name nor on its `deploy.yaml` LAN address (`192.168.68.56`, `192.168.0.110`); the tailnet record shows pi4 last seen 64 days ago. That is a fleet condition, not a Makefile defect, and no Phase 10 plan owns it.

## `sabnzbd.service` fails on ser8 with a uid-drifted state directory

- **Found during:** plan 10-04, Task 2
- **What:** `sabnzbd.service` exits 1 at every start with `sqlite3.OperationalError: unable to open database file` on `/var/lib/sabnzbd/admin/totals10.sab`. The files under `/var/lib/sabnzbd/admin` are owned by the bare numeric ids `38:194`, which no longer map to any name, while the parent `/var/lib/sabnzbd` is correctly `sabnzbd:media`. `download-clients-setup.service` then fails as a direct consequence, timing out after 120 seconds waiting for the SABnzbd API that never comes up.
- **Why out of scope:** pre-existing and provably unrelated to this plan. Both units failed identically at `2026-08-17T18:06` — the boot of generation 268, roughly 17 hours before this plan's first activation command — with the same error on the same file. Plan 10-04's activation restarted the units and reproduced the existing failure; it did not cause it. The cause looks like a uid/gid remap from the 25.11 to 26.05 upgrade, which is Phase 09 territory.
- **Impact:** `make test-ser8` and `make switch-ser8` both return exit 4 (`the following units failed`) on ser8 for reasons no Phase 10 plan owns. Any plan gating on a zero exit status from those targets will get a false negative. Judge per-unit, as this plan did.
- **Suggested fix (not applied):** chown the drifted tree back to `sabnzbd:media` and find the declarative reason the ids drifted, rather than chowning and moving on.

## The SABnzbd media smoketest passes while the unit is failed

- **Found during:** plan 10-04, Task 2
- **What:** `scripts/smoketests/media/` reports "SABnzbd HTTP responded with HTTP 200 (via Host header)" and passes, in both the pre-activation and post-activation transcripts, during a window when `sabnzbd.service` was continuously in the `failed` state and nothing was listening for it. The 200 is coming from something other than a healthy SABnzbd.
- **Why out of scope:** a defect in the media area's assertion, which Phase 10 does not own or modify.
- **Impact:** the media area cannot currently be trusted to catch a dead SABnzbd, which is precisely the regression the per-area baseline comparison exists to detect. The comparison in this plan is still valid — both sides of it are equally blind here — but the blindness should not be inherited silently.
- **Suggested fix (not applied):** assert `systemctl is-active sabnzbd` on the host alongside the HTTP probe, the way the household area asserts unit state before it asserts the port.

## The gateway suite's TLS certificate subtests assert nothing

- **Found during:** plan 10-05, Task 1, reading the pre-activation transcript
- **What:** all eight `tls_*` subtests in `scripts/smoketests/gateway/test-tailscale.sh` emit `openssl not available on firebat, skipping TLS certificate check for NODE` and are then counted as **passes**. No certificate is inspected for any node, on either side of this plan's activation. A node serving an expired, self-signed, or wrong-subject certificate would score identically to a correct one.
- **Why out of scope:** the fix is either adding `openssl` to firebat's system packages or rewriting the check to use a client that is present. The first changes what `make test-firebat` activates and was not going to be introduced in the middle of an activation ladder; the second is a smoketest redesign that Phase 10 does not own.
- **Impact:** this is the direct reason plan 10-05 carries a blocking human checkpoint. Threat T-10-18 (an untrusted certificate accepted out of habit) cannot be discharged by the suite, because the suite's certificate assertions are vacuous. Any future plan tempted to replace that checkpoint with "the gateway suite covers TLS" would be wrong.
- **Suggested fix (not applied):** make the subtest fail, or report explicitly as skipped rather than passed, when no TLS client is available. A skip counted as a pass is worse than no test, because it reports coverage that does not exist.

## `https_sabnzbd` fails at the gateway with a 502

- **Found during:** plan 10-05, Task 1, pre-activation baseline
- **What:** `test-tailscale.sh` subtest `https_sabnzbd` fails with `sabnzbd HTTPS returned unexpected code: 502`, before and after this plan's activation.
- **Why out of scope:** it is the gateway-visible symptom of the dead `sabnzbd.service` on ser8 recorded two items above, not a firebat or Caddy defect. Caddy returns 502 because the backend it proxies to is down. Fixing it means fixing the ser8 unit.
- **Impact:** `./scripts/smoketests/gateway/all.sh firebat` cannot exit 0 while this holds, so plan 10-05's acceptance criterion of a zero exit from that suite is unreachable for a reason plan 10-05 does not own. The gate actually applied was the per-test comparison against the pre-activation transcript, which the plan's own action text specifies.
- **Worth noting:** the gateway area catches the dead SABnzbd that the media area misses. The two areas disagree, and the gateway one is right.
