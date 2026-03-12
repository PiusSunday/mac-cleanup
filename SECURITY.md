# Security Policy

## Supported Versions

| Version | Supported              |
| ------- | ---------------------- |
| 0.2.x   | ✅ Current release     |
| < 0.2   | ❌ No longer supported |

## Reporting a Vulnerability

If you discover a security vulnerability in mac-cleanup, please report it responsibly:

1. **Do NOT open a public issue.** Security vulnerabilities should be reported privately.
2. **Email:** Send a detailed report to [Sundaypius2000@gmail.com](mailto:Sundaypius2000@gmail.com)
3. **Include:**
   - Description of the vulnerability
   - Steps to reproduce
   - Potential impact
   - Suggested fix (if any)

## Response Timeline

- **Acknowledgement:** Within 48 hours
- **Assessment:** Within 7 days
- **Fix/Release:** As soon as a patch is ready, typically within 14 days

## Scope

mac-cleanup operates on user files and system caches. The following are in scope for security reports:

- Unintended file deletion outside documented paths
- Command injection vulnerabilities
- Path traversal issues
- Privilege escalation
- Bypass of `dry_run_or_exec` safety mechanism

## Design Principles

- **Dry-run by default** — no files are deleted unless you explicitly confirm or pass the `--yes` flag
- **Confirmation required** — destructive actions require interactive confirmation unless `--yes` is provided
- **Never touches** system directories (`/System`, `/usr`, `/bin`, `/sbin`), keychains, or iPhone backups
- **Transparent** — all actions logged to `~/.mac-cleanup/cleanup.log`
