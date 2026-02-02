# Grafana Dashboards

This directory contains pre-downloaded Grafana dashboard JSON files with datasource variables already replaced.

## Datasource Variables

All `${DS_*}` variables have been replaced with `Prometheus`:
- `${DS_PROMETHEUS}` → `Prometheus`
- `${DS_PROMETHEUS-MAIN}` → `Prometheus`
- `${DS_THEMIS}` → `Prometheus`
- `${DS_RANCHER_MONITORING}` → `Prometheus`
- `${VAR_PORT_NODE_EXPORTER}` → `9100`

## Dashboard Sources

| Dashboard | Source | ID | Revision |
|-----------|--------|-----|----------|
| node-exporter | Grafana Labs | 1860 | 37 |
| zfs | Grafana Labs | 7845 | 4 |
| prometheus | Grafana Labs | 3662 | 2 |
| frigate | Grafana Labs | 24165 | 1 |
| jellyfin | rebelcore/jellyfin_grafana | N/A | master |
| sonarr | Grafana Labs | 12530 | 1 |
| radarr | Grafana Labs | 12896 | 1 |
| systemd | Grafana Labs | 1617 | 1 |
| adguard | Grafana Labs | 13330 | 3 |
| caddy | Grafana Labs | 22870 | 3 |
| services | Grafana Labs | 22161 | 1 |

## Updating Dashboards

To update a dashboard:

1. Download the new version:
   ```bash
   curl -sL "https://grafana.com/api/dashboards/<ID>/revisions/<REV>/download" > dashboards/<name>.json
   ```

2. Replace datasource variables:
   ```bash
   sed -i.bak \
     -e 's/\${DS_PROMETHEUS}/Prometheus/g' \
     -e 's/\${DS_[^}]*}/Prometheus/g' \
     dashboards/<name>.json && rm dashboards/<name>.json.bak
   ```

3. Commit the changes:
   ```bash
   git add dashboards/<name>.json
   git commit -m "dashboards: Update <name> to revision <REV>"
   ```

## Customizing Dashboards

Feel free to customize dashboards directly! Changes will be preserved in git.

Common customizations:
- Adjust refresh intervals
- Modify panel layouts
- Change color schemes
- Add/remove metrics
- Update thresholds
