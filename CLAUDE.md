# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Purpose

This is a personal workspace repo for Evan (evman1811). It stores files and context from Claude Code sessions so they can be referenced across conversations.

## Saving to GitHub

To commit and push all current files:

```
git add -A && git commit -m "checkpoint: $(date +'%Y-%m-%d %H:%M')" && git push
```

The `.claude/settings.local.json` is force-tracked in this repo (overrides global gitignore) so Claude settings are preserved across sessions.

## Key files

- `.claude/settings.local.json` — permissions and hooks for this workspace
- `README.md` — basic usage notes

## GitHub remote

`https://github.com/evman1811/claude-workspace`
