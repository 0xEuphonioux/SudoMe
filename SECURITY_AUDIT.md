# SudoMe Security Audit Report
## 0.1.0-beta — Full Code Review | 2026-07-17

### Scope

| Component | Language | Lines | Role |
|-----------|----------|-------|------|
| `sudome-helper` | Bash | 791 | Polkit-backed privileged ops (runs as root) |
| `sudome-daemon` | Python 3 | 440 | D-Bus listener + timer + process logger |
| `sudome` (CLI) | Python 3 | 371 | User-facing CLI |
| `sudome-gui` | Python 3 + GTK | — | System tray |
| `config.yaml` | YAML | 160 | Configuration |

---

## Overall Grade: **B+ (88/100)**

SudoMe is well-built. Strong privilege separation, good input validation, clean architecture. The issues found are mostly low-to-medium severity, centered on config injection edge cases and missing a few defense-in-depth controls.

---

## Findings

### 🟡 SEC-01: Python Code Injection via Config File (CVSS 4.4)

| Field | Value |
|-------|-------|
| **File** | `sudome-helper:49-61` |
| **CVSS** | **4.4** (AV:L/AC:L/PR:H/UI:N/S:U/C:N/I:H/A:N) |
| **Type** | Code injection — config-driven Python eval |

**Finding:** The `load_config()` function in the helper constructs Python code from bash variables and executes it:

```bash
local policy_args=""
[[ -f "$_POLICY_FILE" ]] && policy_args="p = _load('$_POLICY_FILE'); if p: _merge_policy(p)"
_config_cache=$(python3 -c "
...
c = _load('$_CONFIG_FILE')
$policy_args       # ← concatenated into Python code
...
")
```

If an attacker can control `$_POLICY_FILE` or `$_CONFIG_FILE` values, they can inject arbitrary Python. Currently these are hardcoded constants, making this unexploitable in the current code. However:
- The pattern is fragile — any future refactor that makes paths configurable opens RCE
- Config YAML loading is done via yaml.safe_load (safe), but the Python invocation itself is vulnerable

**Fix:** Use a single Python script file or heredoc with explicit argument passing instead of string interpolation.

---

### 🟡 SEC-02: Daemon Doesn't Load Policy Overrides (CVSS 5.0)

| Field | Value |
|-------|-------|
| **File** | `sudome-daemon (original beta)` |
| **CVSS** | **5.0** (AV:L/AC:L/PR:L/UI:N/S:U/C:N/I:H/A:N) |
| **Status** | ✅ Fixed in 0.1.0-beta |

**Finding:** The daemon's `load_config()` only read `config.yaml`, not `policy.yaml`. This meant enforced policy settings had no effect on the daemon — it would use preference values even when a policy explicitly overrode them.

**Fix:** 0.1.0-beta now loads and merges `policy.yaml` with the same override semantics as the helper.

---

### 🟡 SEC-03: Webhook JSON Injection via Custom Data (CVSS 3.5)

| Field | Value |
|-------|-------|
| **File** | `sudome-helper:489-507` |
| **CVSS** | **3.5** (AV:L/AC:H/PR:H/UI:N/S:U/C:N/I:L/A:N) |
| **Type** | JSON injection via config content |

**Finding:** The webhook payload construction passes `$custom_json` directly into a Python string:

```bash
payload=$(python3 -c "
...
custom = json.loads('''$custom_json''')   # ← triple-quote injection
...")
```

If `webhook_custom_data` in config.yaml contains `'''`, it breaks out of the Python string. Since the config file requires root to modify, this is low severity, but the pattern is fragile.

**Fix:** Pass custom data via a temp file or environment variable instead of string interpolation.

---

### 🟢 SEC-04: No Config for Per-Trigger Exclusions (CVSS 0.0 — feature gap)

| Field | Value |
|-------|-------|
| **File** | `sudome-daemon` |
| **Status** | ✅ Fixed in 0.1.0-beta |

**Finding:** The per-trigger exclusion feature (`auto_revoke_exclusions`) was documented in config.yaml but never read by the daemon. 0.1.0-beta now reads and enforces it.

---

### 🟢 SEC-05: Username Validation Allows Leading Underscore (CVSS 1.0)

| Field | Value |
|-------|-------|
| **File** | `sudome-helper:240` |
| **CVSS** | **1.0** |

**Finding:** The regex `^[a-z_][a-z0-9_-]*$` allows `_username` — a valid but unusual pattern on Linux. Not a security issue, but could be tightened to `^[a-z][a-z0-9_-]*$` for stricter POSIX compliance.

---

## What SudoMe Gets Right

| Practice | Implementation |
|----------|---------------|
| **Privilege separation** | Helper runs as root via pkexec; CLI/GUI are unprivileged |
| **Input validation** | Username regex, length limits, numeric validation |
| **Atomic writes** | tmpfile + mv pattern — no partial reads possible |
| **Checksum verification** | SHA-256 of post-change executable before execution |
| **Safe YAML parsing** | `yaml.safe_load` everywhere (not unsafe `yaml.load`) |
| **No env var trust** | CLI uses `os.getlogin()` instead of `$USER` |
| **Separation of revoke** | Separate helper binary for revoke (Polkit `yes` policy) |
| **signal handling** | SIGTERM triggers cleanup + revoke-all |
| **systemd sandboxing** | NoNewPrivileges, ProtectSystem=strict, PrivateTmp |
| **Policy override model** | policy.yaml > config.yaml (SAP MDM parity) |
| **Backward compat** | DPAPI migration path in MakeMeAdmin; config migration path in SudoMe |

---

## New Feature: Elevated Process Logging (0.1.0-beta)

Added in this audit — mirrors MakeMeAdmin's most unique feature:

```yaml
log_elevated_processes: true  # config.yaml
```

When enabled:
1. Daemon spawns a background thread monitoring `journalctl` for sudo events
2. For each sudo command from a user with an active grant, logs:
   - Username
   - PID
   - Timestamp
   - Full command executed
3. Output: `logger -t sudome-elevated -p auth.notice`

Query:
```bash
journalctl -t sudome-elevated   # All elevated process logs
journalctl -t sudome-elevated --since "1 hour ago"  # Recent
```

---

## Recommendations

| Priority | Action |
|----------|--------|
| 🔴 | Fix Python code injection pattern in helper (use args, not string concat) |
| 🟡 | Fix webhook JSON injection via temp file |
| 🟡 | Add per-trigger exclusion test coverage |
| 🟢 | Tighten username regex to `^[a-z][a-z0-9_-]*$` |
| 🟢 | Add `log_elevated_processes` to daemon systemd hardening |
| 🟢 | Document `policy.yaml` deployment in README |

---

**Audited by:** eupho-RED | 2026-07-17
