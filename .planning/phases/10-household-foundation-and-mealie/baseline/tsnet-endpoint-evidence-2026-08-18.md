# Tsnet endpoint evidence (plan 10-05, Task 2, 2026-08-18)

Captured after firebat was switched to generation 74, the configuration
carrying the `mealie` tsnet vhost.

## The node registered

`tailscale status` on firebat, diffed by node name against
`tailscale-nodes-firebat-pre-activation.txt`:

| | Count | Delta |
|---|---|---|
| pre-activation | 29 | baseline |
| post-activation | 30 | `+mealie` |

Nodes added: `mealie` only.
Nodes removed: none.

Full post-activation output: `tailscale-nodes-firebat-post-activation.txt`.

```
100.85.94.86     mealie               <owner-redacted>  linux    -
```

Every one of the twelve pre-existing service nodes re-registered after the
auth key rotation, so the rotation restored the whole gateway rather than only
unblocking the new node.

## Assumption A5, resolved as fact

RESEARCH.md assumption A5 held that adding a tsnet vhost needs no Tailscale
admin-console action because the shared authentication key covers new nodes.

**An admin-console action WAS required**, but not for the reason A5 contemplated.
The key itself had been revoked upstream; see
`incident-firebat-caddy-authkey-2026-08-18.md`.
Once a valid reusable non-ephemeral key was in place, the `mealie` node claimed
its name with **no ACL edit, no node approval, and no per-node console action**.

So A5 splits into two claims:

| Claim | Verdict |
|---|---|
| A new tsnet node needs no ACL edit or console approval | **TRUE**, now evidenced |
| The shared key can be assumed valid because eleven nodes already use it | **FALSE**, and it is the part that failed |

Phases 12 and 13 each add three more tsnet nodes.
They should carry a **valid, reusable, non-ephemeral auth key** as an explicit
precondition, and verify it by restarting Caddy on purpose rather than trusting
a process that has been up for weeks.

## DNS resolves from a tailnet member

From firebat: `dig +short mealie.shad-bangus.ts.net` -> `100.85.94.86`
From the developer workstation (`bob-mac-1`, tailnet member): same address.

## HTTPS answers, and it is not a 502

| Probe origin | Result |
|---|---|
| firebat | `http_code=200` |
| developer workstation (tailnet member) | `http_code=200`, `remote_ip=100.85.94.86`, `ssl_verify_result=0` |

Not `502` and not `000`, which are the two statuses the plan's acceptance
criterion names specifically.

`ssl_verify_result=0` means curl's own chain validation succeeded against the
system trust store, with no `-k` and no custom CA bundle.
That is necessary but not sufficient for the browser checkpoint, which is why
the checkpoint still exists.

### First request needs a certificate-issuance window

The first gateway suite run after activation failed `https_mealie` with
`mealie HTTPS connection failed` while `tailscale_nodes` and `dns_mealie` had
already flipped to passing.
The certificate was being issued at that moment:

```
start date: Aug 18 18:55:26 2026 GMT
```

A re-run minutes later passed.
This is a cold-start artifact of Tailscale's ACME issuance on the first request
to a brand-new tsnet node, not a defect, but a suite run immediately after a
new tsnet vhost is added should be expected to fail this one subtest once.

## The certificate is from a public authority

```
subject:     CN=mealie.shad-bangus.ts.net
issuer:      C=US; O=Let's Encrypt; CN=YE1
start date:  Aug 18 18:55:26 2026 GMT
expire date: Nov 16 18:55:25 2026 GMT
```

Let's Encrypt, obtained through Tailscale's ACME integration, not the local
certificate authority the `.vofi` LAN names use.

This does **not** discharge the human checkpoint.
`curl` validating a chain against the system trust store is a different act
from a phone browser validating it, and the gateway suite's own eight `tls_*`
subtests assert nothing at all because `openssl` is absent from firebat.

## The proxy hop genuinely reaches ser8

Correlated with a unique path so the result cannot be confused with a cached
response or with something else answering:

Request from the developer workstation:
`GET https://mealie.shad-bangus.ts.net/gsd-proxy-probe-1787082984`

ser8's `mealie` journal, same second:

```
INFO 2026-08-18T12:56:24 - [100.119.109.112:0] 404 Not Found "GET /gsd-proxy-probe-1787082984 HTTP/1.1"
```

Two things this proves beyond reachability:

1. The request traversed the full path: tailnet client -> firebat tsnet
   listener -> `192.168.68.65:9000` -> `mealie.service`.
   The `404` is Mealie's own response to a path that does not exist, so Mealie
   handled the request.
2. `100.119.109.112` is the **workstation's** tailnet address, not firebat's.
   Caddy is forwarding the real client address through to the backend, so
   RESEARCH.md Pitfall 2's forwarded-header concern is satisfied for the
   client-IP half.

## Base URL: what is proven and what is not

| Evidence | Result |
|---|---|
| Deployed unit environment on ser8 | `BASE_URL=https://mealie.shad-bangus.ts.net` |
| Is it the module loopback default? | No. Default is `http://localhost:9000` |
| Runtime settings parsed by the app | `/api/app/about` reports `allowSignup:false`, matching `ALLOW_SIGNUP=false`, so the settings object the link composer reads is live |
| Reachable at exactly that URL end to end | Yes, HTTP 200 through the tsnet vhost |
| **A link composed by the application** | **NOT PROVEN** |

The last row is an unmet acceptance criterion and is recorded as such rather
than glossed.

Mealie v3.22.0 composes absolute URLs from `BASE_URL` in exactly three places,
and every one of them is unreachable right now:

| Composer | Why it cannot be exercised yet |
|---|---|
| Invitation link | `POST /api/households/invitations` requires authentication, and returns only `{token, usesLeft, groupId, householdId}` — the frontend concatenates the URL client-side |
| Password reset link | Composed inside the email service; SMTP is not configured, and minting a real reset token for the live admin account is not an acceptable probe |
| Shared recipe link | Requires a seeded recipe, which does not exist until plan 10-06 bootstraps |

The OpenAPI schema was searched exhaustively for an endpoint returning an
absolute URL: `servers` is absent, and the only base-URL-adjacent field is
`CheckAppConfig.baseUrlSet`, a boolean behind admin authentication.

The only remaining route to a composed link today would be to authenticate with
the **shipped default administrator credentials**, which still work.
That was deliberately not done: this plan's own checkpoint instructs the human
not to log in with those defaults, and doing the same thing over the API to
satisfy a criterion would contradict the plan's stated intent for the sake of a
green mark.

**Carried to plan 10-06**, which creates a real account and changes the admin
credential. At that point a genuine share link can be generated and asserted
against `https://mealie.shad-bangus.ts.net`.

## Human checkpoint: the browser accepts the certificate

The blocking checkpoint was resolved **`approved`** on 2026-08-18.

| Criterion | Result |
|---|---|
| Page loads and shows Mealie's login screen | yes |
| Certificate warning, interstitial, or insecure indicator | none |
| Issuer inspected from certificate details | Let's Encrypt, a public authority |
| Local certificate authority (the one the `.vofi` names use) | not involved |
| Logged in with the shipped default administrator | no, per the checkpoint instruction |
| Device and browser recorded | **NOT recorded** — see below |

The human confirmed a tailnet household device in a normal browser window, but
did not name the specific device or browser, and the plan's acceptance criterion
asked for both.
That gap is recorded rather than invented: writing a plausible device string
here would be a fabricated observation, which is worse than an acknowledged hole.

What the checkpoint does discharge is the thing it existed for.
Threat T-10-18 (an untrusted certificate accepted out of habit) is closed: a real
browser chain validation succeeded against a public issuer, which neither `curl`
over ssh nor the suite's vacuous `tls_*` subtests could establish.

## The tsnet node is runtime state, not repository state

The `mealie` node now exists in the Tailscale admin console and persists there
**independently of this repository**.

Reverting this phase, rolling firebat back to generation 73, or removing the
vhost from `modules/gateway/Caddyfile` will **not** remove the node.
It must be deleted by hand in the Tailscale admin console, or the name stays
claimed and a later re-add may land on `mealie-1`.

The same is true of the twelve pre-existing service nodes.
