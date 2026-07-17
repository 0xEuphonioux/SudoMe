<p align="right">
  <img src="https://raw.githubusercontent.com/0xEuphonioux/SudoMe/main/share/icons/hicolor/scalable/apps/sudome-active.svg" height="128">
</p>

# SudoMe

### Transparent, free, and secure admin rights management for Linux.

_SudoMe_ gives users temporary `sudo` privileges when needed without granting permanent admin rights. Built for enterprise environments with automatic revocation, audit logging, webhook/SIEM integration, and Polkit-backed security. One click to elevate, automatic rollback when you're done.

**Inspired by [SAP Privileges for macOS](https://github.com/SAP/macOS-enterprise-privileges).**

<br/>

## Install

```bash
git clone https://github.com/0xEuphonioux/SudoMe.git && cd SudoMe && sudo ./install.sh
```

That's it. The installer auto-detects your distro, installs dependencies, and starts the system tray. Choose CLI-only or CLI+GUI during install.

**Supports:** Ubuntu 22.04+, Debian 12+, Fedora 39+, RHEL 9+, Arch, openSUSE

<br/>

## Features

| Category | Feature |
|----------|---------|
| 🔐 **Security** | Polkit authentication every grant, no credentials stored, helper runs as root via pkexec only |
| ⏱️ **Auto-revoke** | Timer expiry, screen lock, system sleep, time/date change, shutdown — all trigger immediate revocation |
| 🛡️ **Excluded users** | Service accounts immune to auto-revoke (`auto_revoke_excluded_users`) |
| 📋 **Reason enforcement** | Require reasons for elevation with configurable min/max length and preset lists |
| 🔄 **Post-change actions** | Run scripts after every grant/revoke with SHA-256 checksum verification |
| 🌐 **Webhooks** | HTTP POST to SIEM on grant/revoke/renew with custom JSON payload |
| 🔔 **Renewal notifications** | Proactive desktop notification 60s before expiry with renew prompt |
| 🖥️ **System tray** | GNOME/KDE/XFCE native AppIndicator with live countdown timer |
| ⌨️ **CLI** | `sudome on/off/status/renew` with colored output and expiry countdown |
| 📊 **Audit logging** | Structured syslog events, journalctl integration, SAP Privileges-compatible format |
| 📝 **Process logging** | `log_elevated_processes` audits every command run under active grants via syslog |
| ⚙️ **Enterprise config** | Everything controlled via `/etc/sudome/config.yaml` — deploy with Ansible, Puppet, Chef |
| 🔒 **Hardened daemon** | systemd sandboxing: no new privileges, protect system, private /tmp, zero capabilities |
| 🌍 **Cross-distro** | Single install script, auto-detects package manager and dependencies |

<br/>

## Quick Start

```bash
# One-liner install
git clone https://github.com/0xEuphonioux/SudoMe.git && cd SudoMe && sudo ./install.sh

# Grant 30 minutes of sudo
sudome on

# Grant 60 minutes with a reason
sudome on 60 -r "Installing Docker"

# Check status
sudome status

# Extend current grant
sudome renew

# Revoke immediately
sudome off
```

<br/>

## Architecture

```
User clicks "SudoMe!" or runs "sudome on"
       │
       ▼
┌──────────────────┐
│  sudome CLI/GUI  │  Polkit authentication dialog (auth_self)
└────────┬─────────┘
         │ pkexec
         ▼
┌──────────────────┐
│  sudome-helper   │  Runs as root: usermod -aG sudo <user>
│  (Polkit action) │  Atomic write of expiry timestamp
└────────┬─────────┘  ────► Post-change action (script)
         │                   ────► Webhook POST (SIEM)
         ▼                   ────► Desktop notification
┌──────────────────┐         ────► Syslog audit event
│  User has sudo!  │
│  Countdown starts│
└────────┬─────────┘
         │
    ┌────┴──────────────────────────┐
    ▼                               ▼
┌──────────────┐           ┌──────────────────┐
│ sudome-daemon│ (10s poll)│  D-Bus listener  │
│ Timer expiry │           │  Lock / Sleep    │
│ + renewal    │           │  Time change     │
│ notification │           │  Shutdown (TERM) │
└──────┬───────┘           └────────┬─────────┘
       │ pkexec (revoke, no auth)   │
       └──────────┬─────────────────┘
                  ▼
          ┌──────────────┐
          │ sudo REVOKED  │
          └──────────────┘
```

<br/>

## Components

| Component | Path | Purpose |
|-----------|------|---------|
| `sudome` | `/usr/bin/sudome` | CLI tool — grant, revoke, status, renew |
| `sudome-gui` | `/usr/bin/sudome-gui` | GTK3 system tray with live countdown |
| `sudome-helper` | `/usr/lib/sudome/sudome-helper` | Polkit-backed privileged operations (root) |
| `sudome-helper-revoke` | `/usr/lib/sudome/sudome-helper-revoke` | Separate exec for revoke (Polkit `yes` policy) |
| `sudome-daemon` | `/usr/lib/sudome/sudome-daemon` | Long-running D-Bus listener + timer check |
| Polkit policy | `/usr/share/polkit-1/actions/` | Grant=`auth_self`, Revoke=`yes` |
| D-Bus config | `/usr/share/dbus-1/system.d/` | Locked-down bus access |
| systemd service | `/usr/share/systemd/user/` | Hardened user service |

<br/>

## Enterprise Configuration

Full configuration reference at `/etc/sudome/config.yaml`:

```yaml
# ── Timing ──
default_duration: 30          # Default grant duration (minutes)
max_duration: 480             # Hard limit on requested duration

# ── Excluded users (immune to ALL auto-revoke) ──
auto_revoke_excluded_users:
  - svc_backup
  - emergency_admin

# ── Revocation triggers ──
revoke_on_screen_lock: true
revoke_on_sleep: true
revoke_on_time_change: true
revoke_on_shutdown: true

# ── Reason enforcement ──
require_reason: false          # Set to true to mandate reasons
reason_min_length: 10
reason_max_length: 256
reason_presets:                # User must pick from this list
  - "Installing software"
  - "System configuration"
  - "Troubleshooting"
reason_strict_presets: false   # true = no custom reasons allowed

# ── Post-change actions ──
post_change_executable: "/usr/local/bin/sudome-audit.sh"
post_change_executable_checksum: "sha256hex..."   # Optional integrity check
pass_reason_to_executable: true

# ── Webhooks (SIEM) ──
webhook_url: "https://siem.example.com/hooks/sudome"
webhook_custom_data:
  environment: "production"
webhook_timeout: 10

# ── Notifications ──
notify_before_expiry: 300      # Warn 5 min before expiry
renewal_notification_interval: 60   # Renew prompt 60s before
allow_privilege_renewal: true

# ── Audit ──
log_elevated_processes: true   # Log every command run under active grants
```

Deploy via Ansible:

```yaml
- name: Deploy SudoMe config
  copy:
    src: sudome-config.yaml
    dest: /etc/sudome/config.yaml
    mode: 0644
```

<br/>

## Audit & Monitoring

```bash
# View all grant/revoke events
journalctl -t sudome-helper

# View daemon events (auto-revoke, renewal notifications)
journalctl -t sudome-daemon

# View elevated process log (commands run under active grants)
journalctl -t sudome-elevated

# Follow in real-time
journalctl -t sudome-helper -f

# Remote syslog forwarding
echo '*.* @your-syslog-server:514' > /etc/rsyslog.d/99-sudome.conf
systemctl restart rsyslog
```

Syslog format (SAP Privileges-compatible):

```
Jun 22 10:58:07 hostname sudome-helper: Process sudome created at
06/22/2026 10:58:07 PM by user jsmith in session 2 with an
elevation type of Default. action: 'grant' minutes: '30'
```

<br/>

## Comparison with SAP Privileges

| Feature | SAP Privileges (macOS) | SudoMe (Linux) |
|---------|----------------------|----------------|
| **Platform** | macOS 11–26 | Ubuntu, Debian, Fedora, Arch, openSUSE |
| **Privilege system** | `admin` group | `sudo` group |
| **GUI** | NSStatusItem menu bar | GTK3 AppIndicator system tray |
| **CLI** | `PrivilegesCLI` (Swift) | `sudome` (Python 3) |
| **Daemon** | `PrivilegesDaemon` (launchd root) | `sudome-daemon` (systemd user, hardened) |
| **Auth** | LocalAuthentication / Smart Card | Polkit `auth_self` + PAM |
| **Auto-revoke** | Timer, login, lock, time change | Timer, lock, sleep, time change, shutdown |
| **Excluded users** | ✅ per-trigger exclusion lists | ✅ global exclusion list |
| **Reason enforcement** | Required, presets, min/max | Required, presets, strict mode, min/max |
| **Post-change actions** | ✅ with checksum verification | ✅ with checksum verification |
| **Webhooks** | ✅ with queue and retry | ✅ JSON POST with custom data |
| **Renewal** | ✅ with notification | ✅ with proactive notification |
| **MDM / Config** | 50+ macOS profile keys | YAML config, Ansible/Puppet/Chef |
| **Tamper protection** | Endpoint Security extension | systemd sandboxing (NoNewPrivileges, ProtectSystem) |
| **Audit logging** | Unified log + ETW | syslog + journalctl |
| **Smart card / PIV** | ✅ | 🔜 PAM integration planned |
| **License** | Apache 2.0 | Apache 2.0 |

<br/>

## Security

> [!IMPORTANT]
> Users with sudo privileges can remove SudoMe or make unrestricted system changes. SudoMe cannot guarantee revocation on any specific schedule. Organizations should layer this with client management, compliance monitoring, and auditing policies.

SudoMe's security model:

- **No credential storage** — Polkit authenticates via PAM, no passwords saved
- **Privilege separation** — Polkit policy: grant requires `auth_self`, revoke is `yes` (instant, no prompt)
- **Input validation** — Username sanitized (`^[a-z_][a-z0-9_-]*$`), minutes validated as integer, reason length enforced
- **Atomic writes** — State files written via tmpfile+mv, no partial reads
- **systemd hardening** — `NoNewPrivileges`, `ProtectSystem=strict`, `PrivateTmp`, zero capabilities, restricted address families
- **D-Bus lockdown** — Only `at_console` users can communicate; default policy = deny all

<br/>

## Uninstall

```bash
sudo ./install.sh --uninstall
```

<br/>

## License

Copyright (c) 2026 0xEuphonioux and SudoMe contributors. Apache License 2.0.

## Changelog

### v2.3 — Elevated Process Logging
- **New:** `log_elevated_processes` config option — audits every command run under an active sudo grant via `journalctl -t sudome-elevated`
- **Fix:** SEC-01 — helper argument injection hardening (+224 lines)
- **Fix:** Daemon race condition on expiry check (+312 lines refactor)
- **Docs:** Added SAP vs MakeMeAdmin vs SudoMe comparison matrix (`COMPARISON_REPORT.md`)
- **Docs:** Full security audit report (`SECURITY_AUDIT.md`) — Grade B+ (88/100)

### v2.2 — Webhooks & Post-Change Actions
- Webhook HTTP POST to SIEM on grant/revoke/renew with custom JSON payload
- Post-change executable with SHA-256 checksum verification
- Reason enforcement with presets, strict mode, min/max length

### v2.1 — Cross-Distro Support
- Fedora 39+, RHEL 9+, Arch, openSUSE support
- Auto-detection of package manager and dependencies in install script

### v2.0 — Initial Release
- Polkit-backed grant/revoke with system tray + CLI
- Timer, screen lock, sleep, time change, shutdown auto-revoke
- systemd sandboxing, D-Bus lockdown, structured syslog audit
