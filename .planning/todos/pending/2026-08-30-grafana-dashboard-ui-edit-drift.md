---
created: 2026-08-31T01:45:00.000Z
title: Close the Grafana dashboard UI-edit drift trap
area: gateway
severity: minor
files:
  - modules/gateway/grafana.nix
  - dashboards/README.md
---

## Problem

Originates from the v1.1 milestone research (ARCHITECTURE.md Pattern 1 "consistent declarative provisioning", PITFALLS.md pitfall 6 on provisioned-resource editability in .planning/milestones/v1.1-research/).
Dashboards are file-provisioned from nix-store symlinks with allowUiUpdates = true (modules/gateway/grafana.nix), so the UI permits saving changes - but those saves land only in grafana.db, and the next rebuild that touches any dashboard swaps the store path and restarts Grafana (restartTriggers), silently clobbering every UI edit.
dashboards/README.md compounds the trap: "Feel free to customize dashboards directly! Changes will be preserved in git" is only true for edits made to the JSON files, not UI edits, and nothing says so.
The README source table is also stale: uptime.json (home-grown in v1.1 plan 05-02, extended by the alerting consolidation) has no entry, so a future updater could wrongly assume it has an upstream to re-download.

## Solution

Pick one editing contract and make the config and README tell the same story.
Preferred: set allowUiUpdates = false so the repo is unambiguously canonical and the UI clearly labels dashboards as provisioned, and document the workflow for changes - edit the JSON (or prototype in the UI, export via the share/JSON-model view, then write the export back to dashboards/ and commit).
Alternatively keep allowUiUpdates = true but document that UI edits are throwaway prototypes that must be exported before the next deploy.
Either way, fix dashboards/README.md: add uptime.json to the table marked as locally maintained (no upstream ID), and state the UI-edit caveat next to the "customize directly" advice.
Repo PR guidance already requires exported JSON diffs or screenshots for Grafana changes, which fits the export-back workflow.
