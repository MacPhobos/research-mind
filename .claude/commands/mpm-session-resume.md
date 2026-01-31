---
namespace: mpm/session
command: resume
aliases: [mpm-session-resume]
migration_target: /mpm/session:resume
category: session
description: Load context from paused session
deprecated: true
deprecated_in: "5.5.0"
replacement: "skill:mpm-session-resume"
---

> **Deprecated:** This command file is deprecated in favor of the `mpm-session-resume` skill.
> For Claude Code 2.1.3+, use the skill-based `/mpm-session-resume` command instead.
> This file is kept for backward compatibility with Claude Code < 2.1.3.

# /mpm-session-resume

Load and display context from most recent paused session.

## Usage
```
/mpm-resume
```

**What it shows:**
- Session summary and time elapsed
- Completed work and current tasks
- Git context and recent commits
- Next recommended actions

**Session location:** `.claude-mpm/sessions/session-*.md`

**Token usage:** ~20-40k tokens (10-20% of context budget)

**Note:** Reads existing sessions (created automatically at 70% context). Does NOT create new files.

See docs/features/session-auto-resume.md for details.
