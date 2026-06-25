# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Purpose

This is a personal workspace repo for Evan (evman1811). It stores files and context from Claude Code sessions so they can be referenced across conversations.

## Saving to GitHub

**Commit and push regularly throughout any work session** — after each meaningful change, not just at the end. This ensures no progress is ever lost and the GitHub history accurately reflects what was done and why.

Commit message rules:
- Use the imperative mood: "add X", "fix Y", "update Z"
- Be specific about what changed and why, not just what file was touched
- One logical change per commit — don't bundle unrelated changes

To commit and push:

```
git add -A && git commit -m "your message here" && git push
```

The `.claude/settings.local.json` is force-tracked in this repo (overrides global gitignore) so Claude settings are preserved across sessions.

## Key files

- `.claude/settings.local.json` — permissions and hooks for this workspace
- `README.md` — basic usage notes

## GitHub remote

`https://github.com/evman1811/claude-workspace`
