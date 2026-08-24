# Dead qBittorrent Download-Client Deregistration (D-16)

Date: 2026-08-24
Host: ser8 (192.168.68.65)

Context: plan 12-04 removed `setup_qbittorrent_client` from `orchestration.nix` and switched that
removal live on ser8, so the qBittorrent download-client entries these apps previously carried can
no longer be silently re-added by orchestration on the next activation. This task removes the
now-dead entries from the apps that still had them.

## Radarr

- API: `GET /api/v3/downloadclient` (port 7878).
- Found: entry `id 3`, `name: "qBittorrent"`, `implementation: "QBittorrent"`.
- Action: `DELETE /api/v3/downloadclient/3` — HTTP 200.
- Verified: re-queried `GET /api/v3/downloadclient` afterward — remaining entries are `NZBGet` (id 5),
  `SABnzbd` (id 4), and a pre-existing disabled `Transmission` entry (id 2, `enable: false`, unrelated
  to qBittorrent and out of this task's scope — left untouched). No entry named "qBittorrent" or with
  `implementation: "QBittorrent"` remains.

## Sonarr

- API: `GET /api/v3/downloadclient` (port 8989).
- Found: entry `id 3`, `name: "qBittorrent"`, `implementation: "QBittorrent"` (same shape as Radarr's).
- Action: `DELETE /api/v3/downloadclient/3` — HTTP 200.
- Verified: re-queried `GET /api/v3/downloadclient` afterward — remaining entries are `NZBGet` (id 5),
  `SABnzbd` (id 4), and the same pre-existing disabled `Transmission` entry (id 2, untouched). No
  entry named "qBittorrent" or with `implementation: "QBittorrent"` remains.

## Prowlarr

- Checked `GET /api/v1/applications` (port 9696): only the two expected app-sync connections,
  `Radarr` (id 2) and `Sonarr` (id 1). No qBittorrent-related application entry.
- Checked `GET /api/v1/downloadclient` (Prowlarr also exposes its own download-client list, used for
  its manual-search "add to client" feature): entries are `NZBGet` (id 6), `SABnzbd` (id 5), and the
  same disabled `Transmission` (id 2, untouched, unrelated to qBittorrent). No qBittorrent entry
  found here either.
- **Finding: nothing to remove.** Prowlarr never carried a qBittorrent download-client or application
  entry — recorded here as the explicit "not present" outcome rather than forcing an unnecessary
  delete call.

## Summary

| App | qBittorrent entry found? | Action | Result |
|-----|---------------------------|--------|--------|
| Radarr | Yes (`downloadclient` id 3) | `DELETE /api/v3/downloadclient/3` | Removed, verified absent |
| Sonarr | Yes (`downloadclient` id 3) | `DELETE /api/v3/downloadclient/3` | Removed, verified absent |
| Prowlarr | No | None (nothing to remove) | Confirmed absent in both `applications` and `downloadclient` |

No decrypted API key value appears anywhere in this file — every API key was resolved to its
`/run/secrets/<app>_api_key` path via `nix eval` and read transiently inside each `curl` invocation
over SSH, never echoed or written to disk.
