---
phase: 10-household-foundation-and-mealie
plan: 05
subsystem: infra
tags: [caddy, caddy-tailscale, tsnet, tailscale, firebat, gateway, tls, acme, sops, mealie]
status: complete

requires:
  - "modules/gateway/Caddyfile mealie vhost (plan 10-01) — the configuration this plan activated"
  - "modules/gateway/caddy.nix (pre-existing) — the caddy-tailscale plugin pin and the TS_AUTHKEY export from the shared SOPS secret"
  - "scripts/smoketests/gateway/test-tailscale.sh EXPECTED_NODES (plan 10-01) — the node, DNS, and HTTPS assertions this plan turned green"
  - "ser8 running Mealie on 192.168.68.65:9000 as boot default generation 269 (plan 10-04) — the proxy target"
provides:
  - "firebat running the mealie tsnet vhost as boot-default generation 74"
  - "A registered Tailscale node named mealie at 100.85.94.86, serving a Let's Encrypt certificate for mealie.shad-bangus.ts.net"
  - "An end-to-end proven path: tailnet client -> firebat tsnet listener -> 192.168.68.65:9000 -> mealie.service, correlated by a unique probe path in ser8's journal"
  - "A rotated, reusable, non-ephemeral shared tailscale_authkey, which restored all thirteen tsnet nodes"
  - "RESEARCH.md assumption A5 replaced by evidence, split into a true half and a false half"
  - "A pre/post activation gateway transcript and Tailscale node list for per-test comparison by later plans"
affects:
  - "plan 10-06 — owns the unproven composed-link half of the BASE_URL criterion and the five red household subtests"
  - "phase 12 and phase 13 — each adds three more tsnet nodes and must treat a valid reusable non-ephemeral auth key as an explicit precondition"
  - "phase 11 backups — the gateway is the access path being backed behind, and its single-credential fragility is now documented"

actuals:
  tokens: 20000
  tasks: 3
  commits: 6

tech-stack:
  added: []
  patterns:
    - "Prove a proxy hop by requesting a unique nonexistent path and correlating the backend's own 404 in its journal, rather than trusting a 200 that anything in the chain could have produced"
    - "Verify a shared credential by restarting the consuming process on purpose, because a long-lived process holds its sessions in memory and masks a revoked key indefinitely"

key-files:
  created:
    - .planning/phases/10-household-foundation-and-mealie/baseline/preflight-firebat-2026-08-18.md
    - .planning/phases/10-household-foundation-and-mealie/baseline/incident-firebat-caddy-authkey-2026-08-18.md
    - .planning/phases/10-household-foundation-and-mealie/baseline/tsnet-endpoint-evidence-2026-08-18.md
    - .planning/phases/10-household-foundation-and-mealie/baseline/smoketests-gateway-pre-activation.txt
    - .planning/phases/10-household-foundation-and-mealie/baseline/smoketests-gateway-post-activation.txt
    - .planning/phases/10-household-foundation-and-mealie/baseline/tailscale-nodes-firebat-pre-activation.txt
    - .planning/phases/10-household-foundation-and-mealie/baseline/tailscale-nodes-firebat-post-activation.txt
    - .planning/phases/10-household-foundation-and-mealie/baseline/smoketests-household-post-activation.txt
    - .planning/phases/10-household-foundation-and-mealie/baseline/smoketests-mealie-endpoint-post-activation.txt
  modified:
    - Makefile
    - secrets/shared.yaml
    - .planning/phases/10-household-foundation-and-mealie/deferred-items.md

key-decisions:
  - "The dead auth key was NOT worked around by commenting out the tsnet vhosts. That would have restored the LAN .vofi routes while leaving every tailnet endpoint down, and landed a temporary mutilation in the repository for a fault whose real fix takes minutes in the admin console."
  - "The outage was surfaced as a blocker and handed to the operator rather than self-resolved, because minting a Tailscale auth key requires the admin console and is not an executor action."
  - "The composed-link half of the BASE_URL criterion was left UNMET rather than satisfied by authenticating with the shipped default administrator credentials, which still work. Doing that over the API would have contradicted the plan's own checkpoint instruction not to log in with those defaults, purely to earn a green mark."
  - "The gateway suite's exit status was not used as the gate. It cannot reach 0 while https_sabnzbd 502s on a dead ser8 unit this plan does not own, so the per-test comparison against the pre-activation transcript was the gate, as the plan's action text specifies."
  - "The five failing household subtests were left failing rather than relaxed; plan 10-06 turns them green by doing the bootstrap."

patterns-established:
  - "A shared credential consumed by N services is an N-service outage waiting for the first restart. Verify it by restarting deliberately, and record the expiry date."
  - "A skipped subtest counted as a pass reports coverage that does not exist; the blocking human checkpoint is the only real assertion when the automated one is vacuous."

requirements-completed: [MEAL-03]

coverage:
  - id: D1
    description: "firebat runs the Caddy configuration carrying the mealie tsnet vhost as its boot default, with a clean caddy unit and no regression in the gateway route set"
    requirement: MEAL-03
    verification:
      - kind: integration
        ref: "ssh firebat systemctl is-active caddy; journalctl -b -u caddy --priority=err (no output); baseline/smoketests-gateway-post-activation.txt vs smoketests-gateway-pre-activation.txt"
        status: pass
    human_judgment: true
    rationale: "The gate is a per-test comparison of two transcripts, not an exit status. Deciding that the one remaining failure (https_sabnzbd 502) is a pre-existing ser8 defect rather than a gateway regression is a judgment the suite cannot make for itself."
  - id: D2
    description: "A tsnet node named mealie registered and is online, demonstrated as a delta against the pre-activation node list"
    requirement: MEAL-03
    verification:
      - kind: integration
        ref: "scripts/smoketests/gateway/test-tailscale.sh#tailscale_nodes; baseline/tailscale-nodes-firebat-{pre,post}-activation.txt (29 -> 30 nodes, +mealie only)"
        status: pass
    human_judgment: false
  - id: D3
    description: "The endpoint resolves and answers over HTTPS from a tailnet member through the firebat vhost, and the proxy hop genuinely reaches Mealie on ser8"
    requirement: MEAL-03
    verification:
      - kind: integration
        ref: "scripts/smoketests/gateway/test-tailscale.sh#dns_mealie, #https_mealie; scripts/smoketests/household/test-mealie-endpoint.sh#mealie_tsnet_dns, #mealie_tsnet_https; unique-path probe correlated in ser8's mealie journal"
        status: pass
    human_judgment: false
  - id: D4
    description: "A household device's browser loads the endpoint over HTTPS with no certificate warning and a publicly issued certificate"
    requirement: MEAL-03
    verification:
      - kind: manual_procedural
        ref: "plan 10-05 blocking checkpoint, resolved `approved`; baseline/tsnet-endpoint-evidence-2026-08-18.md#human-checkpoint"
        status: pass
    human_judgment: true
    rationale: "curl over ssh validates a chain differently from a phone browser, and the suite's eight tls_* subtests assert nothing because openssl is absent from firebat. Only a human with a real browser can discharge threat T-10-18."
  - id: D5
    description: "The deployed base URL is the tsnet URL and a link generated by the application starts with it"
    requirement: MEAL-03
    verification:
      - kind: integration
        ref: "scripts/smoketests/household/test-mealie-endpoint.sh#mealie_base_url, #mealie_base_url_not_default"
        status: pass
      - kind: integration
        ref: "a link COMPOSED by the application asserted against https://mealie.shad-bangus.ts.net"
        status: fail
    human_judgment: false
  - id: D6
    description: "RESEARCH.md assumption A5 resolved into recorded fact for phases 12 and 13"
    verification:
      - kind: other
        ref: "baseline/tsnet-endpoint-evidence-2026-08-18.md#assumption-a5; baseline/incident-firebat-caddy-authkey-2026-08-18.md"
        status: pass
    human_judgment: false

duration: 55min
completed: 2026-08-18
---

# Phase 10 Plan 05: Activate the Mealie Tsnet Endpoint on firebat Summary

**firebat now serves `https://mealie.shad-bangus.ts.net` as boot-default generation 74 with a Let's Encrypt certificate a real browser accepts, and the activation detonated a latent revoked Tailscale auth key that had been silently holding the entire gateway hostage for 64 days.**

## Performance

- **Duration:** ~55 min wall clock, including a ~47 minute outage window blocked on a human admin-console action
- **Tasks:** 2 automated tasks plus one blocking human-verify checkpoint, all complete
- **Commits:** 6

## Accomplishments

- firebat switched to generation 74 with the mealie tsnet vhost live; `caddy.service` active with zero error-priority journal entries for the boot.
- The `mealie` tsnet node registered at `100.85.94.86` and claimed its name with no ACL edit and no per-node console approval.
- The full household path is proven from outside the hosts that run it: tailnet client to firebat's tsnet listener to `192.168.68.65:9000` to `mealie.service`, correlated by a unique probe path appearing in ser8's own journal.
- A real browser on a tailnet household device loaded the login screen with no warning and a Let's Encrypt issuer, discharging threat T-10-18, which the automated suite provably cannot.
- The shared `tailscale_authkey` was rotated to a reusable non-ephemeral key, restoring all thirteen tsnet nodes and, with them, every `*.shad-bangus.ts.net` and `.vofi` service endpoint.
- `make status` was fixed to resolve host addresses the way every other host target already does.

## Task Commits

1. **Rule 3 deviation: rotate the revoked `tailscale_authkey`** - `11e0fda` (secrets)
2. **Task 1: activate firebat with the mealie tsnet vhost** - `46662ae` (gateway)
3. **Task 2: prove the tsnet node registers and the endpoint answers end to end** - `63ddbd9` (gateway)
4. **Checkpoint: human browser certificate verification** - resolved `approved`, recorded in this SUMMARY and in the evidence artifact

Supporting commits made during this plan:

- `e6547ca` (make) - fix `status` to ping resolved host addresses
- `2c19393` (gateway) - record the firebat preflight and the caddy authkey incident
- `5779566` (docs) - record the firebat gateway outage as an active blocker
- `32033ee` (docs) - clear the resolved blocker and record its carry-forwards

## The auth-key incident

This is the substance of the plan and the reason it took 55 minutes rather than 10.

`make test-firebat` activated the configuration and `caddy.service` failed:

```
Error: loading initial config: loading new config: http app module: start:
starting HTTP/3 QUIC listener: tsnet.Up: backend: invalid key: API key does not exist
```

The configuration was rolled straight back to generation 73, the boot default without the mealie vhost. **Caddy failed identically there.** That is the decisive fact: the mealie vhost is incidental, and the failure reproduces without it.

firebat had 64 days of uptime and `caddy.service` had been running continuously across that window. A long-lived Caddy process holds its tsnet sessions in memory, so nothing re-authenticated during those 64 days. The shared key was revoked somewhere inside that window and nothing surfaced it, because nothing restarted Caddy. Any restart would have detonated it: a reboot, an unrelated gateway change, an OOM kill, a power cut. This plan performed the restart; it did not break the key.

The plumbing was verified intact without printing the value: the secret is present at `/run/secrets/tailscale_authkey`, mode `400`, owner `caddy:caddy`, 61 bytes, `tskey` prefix. SOPS decryption, the age identity, the mount, and the `TS_AUTHKEY` export all work. The control plane was rejecting the credential itself, and `API key does not exist` is the response for a deleted or revoked key rather than a merely expired one.

**Outage window:** 2026-08-18 ~12:05 to ~12:52 PDT, roughly 47 minutes, latent for the preceding 64 days.

**Scope while down:** every `*.shad-bangus.ts.net` endpoint (`jellyfin`, `grafana`, `prom`, `radarr`, `sonarr`, `bazarr`, `prowlarr`, `sabnzbd`, `nzbget`, `frigate`, `hass`, `torrent`) and every LAN `.vofi` vhost. Backing services stayed healthy and untouched; only the proxy in front of them was down. ser8 was unaffected.

**This is the third rotation of this credential** (`8c5c1ff` 2026-01-31, `8d8cb12` 2026-01-31, `9311c21` 2026-07-26). The key in place was 23 days old and already invalid, which suggests the keys being minted are single-use or short-expiry when the deployment needs a reusable long-lived one — thirteen tsnet nodes authenticate from this single value.

**Recommendation carried forward:** disable key expiry on the long-lived service nodes in the Tailscale admin console, so a dead auth key stops being able to take the whole gateway down. Phases 12 and 13 each add three more tsnet nodes and must treat a valid, reusable, non-ephemeral key as an explicit precondition, verified by restarting Caddy on purpose rather than by trusting a process that has been up for weeks.

Full record: `baseline/incident-firebat-caddy-authkey-2026-08-18.md`.

## Assumption A5, resolved

RESEARCH.md assumption A5 held that adding a tsnet vhost needs no Tailscale admin-console action because the shared authentication key covers new nodes. It splits cleanly:

| Claim | Verdict |
|---|---|
| A new tsnet node needs no ACL edit and no console approval | **TRUE**, now evidenced — `mealie` claimed its name unaided |
| The shared key can be assumed valid because eleven nodes already use it | **FALSE**, and it is the half that caused the outage |

The plan carried A5 as its single flagged risk and made it an explicit acceptance step precisely so a failure would surface as a named finding rather than a mystery 502. It did exactly that.

## The evidence chain

| Link | Evidence |
|---|---|
| Node registered | `tailscale status` 29 -> 30 nodes, `+mealie` only, no removals; `100.85.94.86` |
| DNS from a tailnet member | `dig +short mealie.shad-bangus.ts.net` -> `100.85.94.86`, from firebat and from the developer workstation |
| HTTPS answers | `http_code=200` from both origins; not `502`, not `000` |
| Chain validates for curl | `ssl_verify_result=0`, no `-k`, no custom CA bundle |
| Certificate issuer | `CN=mealie.shad-bangus.ts.net`, issuer `C=US; O=Let's Encrypt; CN=YE1`, valid Aug 18 to Nov 16 2026 |
| Proxy hop reaches ser8 | `GET /gsd-proxy-probe-1787082984` produced `404 Not Found` in ser8's `mealie` journal in the same second — Mealie itself handled it |
| Real client address forwarded | The journal recorded `100.119.109.112`, the workstation's tailnet address, not firebat's — Pitfall 2's forwarded-header concern satisfied for the client-IP half |
| Browser accepts the chain | Human checkpoint `approved`, Let's Encrypt issuer confirmed from certificate details, no warning |

**Cold-start artifact worth knowing:** the first gateway suite run after activation failed `https_mealie` while `tailscale_nodes` and `dns_mealie` had already flipped to passing. The certificate was being issued at that moment (`start date: Aug 18 18:55:26 2026 GMT`); a re-run minutes later passed. A suite run immediately after adding a new tsnet vhost should be expected to fail that one subtest once.

Full record: `baseline/tsnet-endpoint-evidence-2026-08-18.md`.

## The human checkpoint, recorded

The blocking checkpoint resolved **`approved`**.

| Criterion | Result |
|---|---|
| Login screen loads on a tailnet household device in a normal browser | yes |
| Certificate warning, interstitial, or insecure indicator | none |
| Issuer, from the certificate details | Let's Encrypt — a public authority, not the local CA the `.vofi` names use |
| Logged in with the shipped defaults | no, per the checkpoint instruction |
| **Device and browser recorded** | **NOT recorded** |

The last row is an acceptance criterion this plan did not meet. The human confirmed a tailnet household device and a normal browser but named neither. Recording that gap is the honest option; inventing a plausible device string would be a fabricated observation.

What the checkpoint does discharge is what it existed for. The suite's eight `tls_*` subtests assert nothing at all — `openssl` is absent from firebat, so each one skips and is then counted as a pass — so threat T-10-18 could only ever be closed by a human with a real browser, and now is.

## Carried to plan 10-06

**1. The composed-link half of the BASE_URL criterion is UNMET.**

Proven: the deployed unit environment on ser8 carries `BASE_URL=https://mealie.shad-bangus.ts.net`, it is not the module default `http://localhost:9000`, the settings object the link composer reads is live (`/api/app/about` reports `allowSignup:false`, matching the deployed `ALLOW_SIGNUP=false`), and the endpoint answers 200 at exactly that URL end to end.

Not proven: that a link **composed by the application** starts with it. Mealie 3.22.0 composes absolute URLs from `BASE_URL` in three places, and all three are unreachable today:

| Composer | Why it cannot be exercised yet |
|---|---|
| Invitation link | `POST /api/households/invitations` requires authentication and returns only `{token, usesLeft, groupId, householdId}`; the frontend concatenates the URL client-side |
| Password reset link | Composed inside the email service; SMTP is not configured, and minting a real reset token for the live admin account is not an acceptable probe |
| Shared recipe link | Requires a seeded recipe, which does not exist until 10-06 bootstraps |

The OpenAPI schema was searched exhaustively for an endpoint returning an absolute URL: `servers` is absent and the only base-URL-adjacent field is `CheckAppConfig.baseUrlSet`, a boolean behind admin authentication. The only remaining route today would be authenticating with the shipped default administrator credentials, which still work — deliberately not done. Plan 10-06 creates a real account and changes the admin credential; assert a genuine share link against the tsnet URL there.

**2. Five household subtests are red, exactly as the plan predicted.** The household area now runs with no escape-hatch variable for the first time. The failing subtest names, verbatim:

| Subtest | Message |
|---|---|
| `mealie_foods_seeded` | `'ingredient_foods' is empty` |
| `mealie_units_seeded` | `'ingredient_units' is empty` |
| `mealie_recipes_present` | `'recipes' is empty` |
| `mealie_recipe_images_present` | `the recipe image tree under /persist/var/lib/mealie/recipes is empty` |
| `default_admin_rejected` | `the shipped default administrator still authenticates (HTTP 200); change it before exposing Mealie` |

Nothing else fails. `test-mealie-service.sh` reports 8/12 and `test-mealie-endpoint.sh` reports 6/7. Plan 10-06 turns all five green; a failure anywhere else would be a real defect.

`default_admin_rejected` is now more urgent than it was before this plan: Mealie is no longer only LAN-reachable, it is reachable from any tailnet device at a trusted public HTTPS name, and the shipped defaults still authenticate.

**3. The `mealie` tsnet node is runtime Tailscale state, not repository state.** Reverting this phase, rolling firebat back to generation 73, or removing the vhost from `modules/gateway/Caddyfile` will **not** remove the node. It must be deleted by hand in the Tailscale admin console, or the name stays claimed and a later re-add may land on `mealie-1`. The same is true of the twelve pre-existing service nodes.

## Files Created/Modified

- `Makefile` - `status` now pings `$(call get-host-ip,$(host))` and prints the address used, instead of `$(host).internal`, a name that resolves nowhere.
- `secrets/shared.yaml` - `tailscale_authkey` rotated to a reusable, non-ephemeral key. Value never printed to a shell, a commit message, or any planning artifact.
- `baseline/preflight-firebat-2026-08-18.md` - reachability, generation 73 with generation 72 as the named recovery path, the pre-activation node list, and the gateway suite baseline.
- `baseline/incident-firebat-caddy-authkey-2026-08-18.md` - the outage record.
- `baseline/tsnet-endpoint-evidence-2026-08-18.md` - the Task 2 evidence chain and the human checkpoint result.
- `baseline/*.txt` - pre/post activation transcripts and node lists for per-test comparison.
- `deferred-items.md` - two new entries, described below.

No host module or Caddyfile change was needed. Plans 10-01 and 10-03 had already committed the configuration; this plan made it real.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] `make status` reported the entire fleet Offline**

- **Found during:** Task 1, the first precondition check
- **Issue:** the `status` target pinged `$(host).internal`, a name this repository configures nowhere and that resolves for none of the four hosts. Task 1's precondition is that firebat answers at its recorded address, and the tool meant to check that was structurally unable to.
- **Fix:** the target now pings `$(call get-host-ip,$(host))`, the resolver every other host target already calls, and prints the address it used so the report is checkable rather than merely coloured.
- **Files modified:** `Makefile`
- **Verification:** `make status` reports ser8 and firebat Online. pi4 and pi5 still report Offline and genuinely are — neither answers on its tailnet name or its `deploy.yaml` LAN address, and pi4 was last seen 64 days ago. That residual is a fleet condition no Phase 10 plan owns.
- **Committed in:** `e6547ca`

**2. [Rule 3 - Blocking] The shared Tailscale auth key was revoked, and `caddy.service` would not start on any configuration**

- **Found during:** Task 1, `make test-firebat`
- **Issue:** documented in full above. Latent for 64 days, unmasked by this plan's restart, blocking every path forward.
- **Fix:** the operator minted a reusable non-ephemeral key in the Tailscale admin console; it was written into `secrets/shared.yaml` via `make sops-edit-shared`.
- **Escalation, not self-resolution:** minting a Tailscale auth key requires the admin console and is not an executor action. Three shortcuts were explicitly declined — no Caddyfile change to disable the tsnet vhosts (a temporary mutilation in the repository for a fault fixable in minutes), no `TSNET_FORCE_LOGIN=1` (forcing a login with a credential the control plane says does not exist cannot succeed), and no `make switch-firebat` while the activation gate was red.
- **Verification:** `caddy.service` reached `active` with zero error-priority journal entries and all thirteen nodes, including `mealie`, registered.
- **Committed in:** `11e0fda`

---

**Total deviations:** 2 auto-fixed (both Rule 3 - blocking). One resolved inline; one escalated to the operator because the fix lived outside this repository.
**Impact on plan:** no scope creep. Both were prerequisites for running the plan at all, and the second is the plan's most valuable finding.

## Issues Encountered

- **The gateway suite cannot exit 0.** `https_sabnzbd` fails with `sabnzbd HTTPS returned unexpected code: 502`, before and after this activation. It is the gateway-visible symptom of the dead `sabnzbd.service` on ser8 that plan 10-04 diagnosed (uid drift to `38:194`, `sqlite3.OperationalError`), not a firebat or Caddy defect. Caddy returns 502 because the backend is down. The plan's acceptance criterion of a zero exit is therefore unreachable for a reason this plan does not own; the gate actually applied was the per-test comparison the plan's action text specifies. Post-activation the suite reports 26/27 Tailscale tests passing, up from 23/27, with `https_sabnzbd` the only remaining failure.

- **The suite's certificate coverage is fictional.** All eight `tls_*` subtests emit `openssl not available on firebat, skipping TLS certificate check` and are then counted as passes. No certificate is inspected for any node, on either side of this activation. A node serving an expired, self-signed, or wrong-subject certificate would score identically to a correct one. Not fixed here: adding `openssl` to firebat would change what `make test-firebat` activates, mid-activation ladder, and rewriting the check is a smoketest redesign Phase 10 does not own. Logged to `deferred-items.md`. A skip counted as a pass is worse than no test, because it reports coverage that does not exist — and any future plan tempted to replace this plan's human checkpoint with "the gateway suite covers TLS" would be wrong.

- **No source build occurred.** firebat's subgen torch closure was already present from Phase 9's switch to 26.05, so the multi-hour compile the plan budgeted for did not happen.

- **firebat's boot transition remains untested.** `bootctl list` reports the selected entry as `nixos-generation-64.conf` `(reported/absent)`, a file that no longer exists, so firebat has been switched several times since it last booted and the running kernel is older than the boot default. Pre-existing and not created by this plan, but a reboot of firebat is itself an unexercised transition. Recovery from a bad boot is `nixos-generation-72.conf` in the systemd-boot menu, which also crosses a channel boundary back to 25.11 — heavier than the ser8 268-to-269 rollback that plan 10-04 recorded.

## User Setup Required

None outstanding. One admin-console action was required mid-plan (minting the replacement auth key) and is complete.

One recommendation for the operator, not a blocker: in the Tailscale admin console, disable key expiry on the long-lived service nodes and record the new key's expiry date. This credential has gone bad three times, and each time it takes the entire gateway with it.

## Next Phase Readiness

MEAL-03's infrastructure is complete and proven from the outside rather than from the host that runs it. Plan 10-06 can bootstrap against a real trusted HTTPS endpoint.

Carried into 10-06: the composed-link assertion, the five red household subtests, and the still-live default administrator credentials — which are now reachable from any tailnet device rather than only from the LAN, so 10-06 should run promptly.

## Self-Check: PASSED

All four recorded artifacts exist on disk and all seven commit hashes resolve in git.

---
_Phase: 10-household-foundation-and-mealie_
_Completed: 2026-08-18_
