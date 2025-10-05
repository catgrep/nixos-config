# TODO

# networking
- [ ] centralize the ip addresses, see `experiment/deploy.yaml`
- [ ] (maybe) add static ips outside of DHCP range for homelab servers
- [ ] look into tailscale for public access to `vofi.app` services
- [x] ~~add dedicated domains for sonarr, radarr, and transmission~~ **COMPLETED** - domains configured in Caddy (sonarr.vofi, radarr.vofi, torrent.vofi)
- [x] ~~system users and media group~~ **COMPLETED** - media services use dedicated users in media group

# data management
- [x] ~~use ZFS and erase your darlings~~ **COMPLETED** for ser8 - root filesystem rolls back on boot
- [ ] use ZFS and erase your darlings for firebat
- [ ] configure timeshare SMB for MBP backups
- [ ] configure borg for cloud backups
- [ ] configure homelab server backups
- [x] ~~ZFS automatic snapshots~~ **COMPLETED** - ser8 has weekly scrubs and automatic snapshots

# infra / code quality
- [ ] refactor `modules`
- [x] ~~`ser8` -> `beelink`~~ **COMPLETED** - renamed from beelink-homelab to ser8
- [ ] provision pi5's for standalone k8s dev cluster
- [x] ~~refactor users~~ **COMPLETED** - users moved to top-level `users/` directory

# security / sops
- [ ] add `secrets/secrets.yaml` to share adguard creds (`pi4`) with prometheus (`firebat`)

- [ ] add sops user credentials for
  - [x] ~~jellyfin~~ **COMPLETED** - API key configured
  - [ ] sonarr
  - [ ] radarr
  - [x] ~~transmission~~ **REPLACED** - using qBittorrent instead
  - [ ] qbittorrent
  - [ ] prowlarr

- [ ] harden system users and groups
- [x] ~~add nordvpn integration~~ **COMPLETED** - NordVPN WireGuard with network namespace isolation

# services
- [ ] setup home-assistant server (maybe one of the `pi5`s?)
- [ ] setup tplink cameras for home-assistant server
- [ ] setup gerrit
- [ ] add grafana dashboards to make use of exported prom metrics
- [x] ~~isolate torrent clients~~ **COMPLETED** - qBittorrent runs in NordVPN network namespace
  - [ ] sonarr (currently not isolated)
  - [ ] radarr (currently not isolated)
  - [x] ~~transmission~~ **REPLACED** - using qBittorrent with VPN isolation
- [x] ~~add FlareSolverr~~ **COMPLETED** - enabled on ser8
- [x] ~~add Prowlarr indexer~~ **COMPLETED** - configured with dedicated domain
- [x] ~~add AllDebrid proxy~~ **COMPLETED** - integrated with Transmission API

# CI / CD
Have no CI / CD pipelines setup, just individual targets
- [ ] setup CI, preferably internal once gerrit is up

Need
- [ ] format checks
- [ ] config validations for non-nix
- [ ] smoketests
- [ ] End to End testing with VMs

Better to test pre-deployment with VMs and virtual network (it would be nice to have generic scaffolding / template that can be reused)

# new items (discovered during documentation review)
- [ ] complete Home Assistant automation module (currently planned)
- [ ] complete Gerrit development module (currently planned)
- [ ] add Grafana dashboards for ZFS monitoring (exporter already configured)
- [ ] document MergerFS configuration and usage
- [ ] add monitoring for NordVPN connection status
- [ ] configure nginx reverse proxy for qBittorrent (currently using basic proxy)
- [ ] implement proper SSL certificates instead of Caddy's local CA for public access
- [ ] add backup strategy for ZFS snapshots to remote location
- [ ] document hardware acceleration setup for Jellyfin
- [ ] improve secrets management - currently media services share secrets

# long-term
- [ ] split out tooling / scripts into a separate flake or pure nix so it can be more easily reused by others
- [ ] add detailed git book documentation so others don't have to scourge the internet and convoluted nix docs, articles, and discourse threads
- [ ] consider migrating from individual systemd services to Kubernetes for media stack
