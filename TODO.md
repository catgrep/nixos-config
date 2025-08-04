# TODO

# networking
- [ ] centralize the ip addresses, see `experiment/deploy.yaml`
- [ ] (maybe) add static ips outside of DHCP range for homelab servers
- [ ] look into tailscale for public access to `vofi.app` services
- [ ] add dedicated domains for sonarr, radarr, and transmission, as well as system users and add them to media group

# data management
- [ ] use ZFS and erase your darlings for firebat
- [ ] configure timeshare SMB for MBP backups
- [ ] configure borg for cloud backups
- [ ] configure homelab server backups

# infra / code quality
- [ ] refactor `modules`
- [ ] `beelink-homelab` -> `beelink` (or just name the servers something else), but should probably keep mDNS incase the DNS server ever fails
- [ ] provision pi5's for standalone k8s dev cluster

# security / sops
- [ ] add `secrets/secrets.yaml` to share adguard creds (`pi4`) with prometheus (`firebat`)

- [ ] add sops user credentials for
  - [ ] jellyfin
  - [ ] sonarr
  - [ ] radarr
  - [ ] transmission

- [ ] harden system users and groups

# services
- [ ] setup home-assistant server (maybe one of the `pi5`s?)
- [ ] setup tplink cameras for home-assistant server
- [ ] setup gerrit
- [ ] add grafana dashboards to make use of exported prom metrics
- [ ] isolate torrent clients in VMs / containers
  - [ ] sonarr
  - [ ] radarr
  - [ ] transmission

# CI / CD
Have no CI / CD pipelines setup, just individual targets
- [ ] setup CI, preferably internal once gerrit is up

Need
- [ ] format checks
- [ ] config validations for non-nix
- [ ] smoketests
- [ ] End to End testing with VMs

Better to test pre-deployment with VMs and virtual network (it would be nice to have generic scaffolding / template that can be reused)

# long-term
- [ ] split out tooling / scripts into a separate flake or pure nix so it can be more easily reused by others
- [ ] add detailed git book documentation so others don't have to scourge the internet and convoluted nix docs, articles, and discourse threads
