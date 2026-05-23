# AGENTS.md

Guidance for agents working in this repository.

## File Naming

- Use alphabetic names for newly created files whenever possible.
- `_` and `-` are the only common accepted delimiters in filenames.
- Avoid creating filenames whose base name contains `+`, spaces, or other punctuation unless explicitly requested.

## Project Memory

- Treat this file as the shared cross-agent context for Codex, Claude, Gemini, Cursor, Antigravity, and other coding agents.
- Keep durable project facts, architecture decisions, recurring implementation patterns, and non-obvious bug fixes here.
- Prefer concise, current notes over long transcripts. Remove or update stale guidance when project decisions change.
- If a task produces context future agents should know, update this file or add a focused document under `docs/` and link it here.
