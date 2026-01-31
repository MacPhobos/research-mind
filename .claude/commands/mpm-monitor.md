---
namespace: mpm/system
command: monitor
aliases: [mpm-monitor]
migration_target: /mpm/system:monitor
category: system
description: Control monitoring server and dashboard
deprecated: true
deprecated_in: "5.5.0"
replacement: "skill:mpm-monitor"
---

> **Deprecated:** This command file is deprecated in favor of the `mpm-monitor` skill.
> For Claude Code 2.1.3+, use the skill-based `/mpm-monitor` command instead.
> This file is kept for backward compatibility with Claude Code < 2.1.3.

# /mpm-monitor

Manage Socket.IO monitoring server for real-time dashboard.

## Usage
```
/mpm-monitor [start|stop|restart|status|port] [options]
```

**Subcommands:**
- `start`: Start server (auto-selects port 8765-8785)
- `stop`: Stop running server
- `status`: Show server status
- `port <PORT>`: Start on specific port

**Key Options:**
- `--port PORT`: Specific port
- `--force`: Force kill to reclaim port
- `--foreground`: Run in foreground (default: background)

Dashboard: http://localhost:8766

See docs/commands/monitor.md for details.
