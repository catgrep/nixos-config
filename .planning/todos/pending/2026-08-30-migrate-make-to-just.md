---
created: 2026-08-31T01:15:00.000Z
title: Migrate from make/Makefile to just
area: tooling
severity: minor
files:
  - Makefile
---

## Problem

The Makefile is a command runner, not a build system - phony targets, host-suffixed target generation, env-var flags (NO_CONFIRM), and a hand-rolled help system - which is exactly the shape `just` handles natively with recipe arguments and built-in listing.

## Solution

Port the Makefile to a justfile: host-suffixed targets become recipes with a host argument (`just test ser8`), NO_CONFIRM becomes a flag or confirm-recipe, help comes from `just --list` with doc comments.
Add `just` to the dev shell, update CLAUDE.md/README command references, and check nothing else shells out to `make` (scripts, CI, agent docs).
Replace, don't keep both: delete the Makefile when the justfile reaches parity.
