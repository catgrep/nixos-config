# Prompt for the orchestrator session

Paste the block below into a new Claude Code session opened in `~/github/catgrep/nixos-config`.

---

You are the orchestrator for the Home Manager migration described in `.planning/home-manager-migration-plan.md`.
Read that file in full before doing anything else, then `CLAUDE.md`, then `.planning/home-manager-migration-review-codex.md`.
Section 11 of the plan is written for you and overrides anything you would otherwise assume.

Your job is to manage the run, not to edit files yourself.

1. Execute Phases 0, 1, 2, 3, 3b and 4 in order, then the docs part of Phase 5, one sub-agent per phase.
   Spawn each sub-agent with a fresh context and give it: the path to the plan, the phase name, the ground rules and commit style from section 11 verbatim, and the instruction to report back with the phase's Verify output, `git log --oneline` for its commits, and an explicit list of anything skipped or blocked.
   Do not start a phase until the previous one is committed and reviewed.
2. Human-gated work is deferred, never interleaved.
   Sub-agents do everything that is repo-only or Mac user-level, including `nh home switch`.
   They must not run `nh darwin switch`, `hm brew cleanup --force`, `rustup self uninstall`, `make sops-edit-*`, or anything that mutates ser8, firebat, pi4 or pi5.
   When a phase reaches such a step, the sub-agent prepares the exact command, records it, and continues with the rest of the phase.
   After the last agent phase, present the gated list from section 11 to me in order, one command at a time, and run each only after I approve it in this session.
3. After every phase, run a Codex review of that phase's commits with sandboxing off, using the exact command in the Orchestration subsection of section 11 (`codex exec --dangerously-bypass-approvals-and-sandbox --ephemeral ...`), writing the result to `.planning/reviews/phase-N-codex.md`.
   Read the review, decide which findings hold up, have a sub-agent apply those, and commit the review file with `planning: record the codex review of phase N`, listing rejected findings and the reason in the commit body.
   Only then start the next phase.
4. Commit rules for every agent in this run: local `main` only, never push, never open a pull request, never amend a commit that existed before the session, never sign (`git -c commit.gpgsign=false`), never add a co-author, one logical change per commit, subject at most 72 characters with the area prefix table from section 11, body wrapped at 72 columns.
5. In this sandbox, `nix` commands that fetch, lock or evaluate impurely need `export XDG_CONFIG_HOME=<scratchpad>/xdg` first; pass that on to sub-agents.
6. Report to me at the end of every phase in one short message: what was delivered, the review outcome, what was deferred to the gated list, and the commit range.
   Do not ask me questions that the plan already answers; if the plan is genuinely silent on something that changes the outcome, stop and ask.

Start with Phase 0.
