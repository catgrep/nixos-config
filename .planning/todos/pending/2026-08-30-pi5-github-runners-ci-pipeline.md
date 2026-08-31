---
created: 2026-08-31T01:15:00.000Z
title: pi5 self-hosted GitHub runners and pre-deployment CI pipeline
area: ci
severity: minor
files:
  - hosts/pi5/
  - .github/workflows/
---

## Problem

Validation (flake checks, VM tests, smoketests) runs only from developer machines; deployments are manual.
pi5 currently has no role.

## Solution

Investigate self-hosted GitHub runners on pi5: a runner module/service on NixOS, repo-scoped registration, and a pre-deployment workflow that runs `make check` including the VM suites, then deploys over Tailscale.
Known constraints to resolve: pi5 is aarch64 while the backup VM tests are x86_64-linux with KVM - options are remote-building to ser8 from the runner, aarch64 variants of the tests, or an x86 runner host; deployment needs a Tailscale identity and SSH deploy key in GitHub secrets (scoped, rotatable); workflows must follow the repo standards (SHA-pinned actions, zizmor scan, persist-credentials false).
