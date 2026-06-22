<img src="https://raw.githubusercontent.com/0xEuphonioux/SudoMe/main/share/icons/hicolor/scalable/apps/sudome-active.svg" width="128" align="right">

# SudoMe

### Transparent, free, and secure admin rights management for Linux.

_SudoMe_ is a free Linux application designed for modern enterprise environments. It gives users temporary `sudo` (administrator) privileges when needed without granting permanent admin rights. The application is built with simplicity, security, and transparency in mind. Users can set a timeframe to perform specific tasks, such as installing packages or configuring system settings.

Using a standard user account instead of an administrator account adds an extra layer of security to your Linux system and is considered a security best practice. We believe that all users, including developers, can benefit from using _SudoMe_.

**The current version of _SudoMe_ supports the following distributions:**

- Ubuntu 22.04 LTS and newer
- Debian 12 and newer
- Linux Mint 21 and newer
- Fedora 39 and newer
- RHEL / Rocky / AlmaLinux 9 and newer
- Arch Linux and derivatives
- openSUSE Leap / Tumbleweed

> **Inspired by [SAP Privileges for macOS](https://github.com/SAP/macOS-enterprise-privileges).**

<br/>

---

## Features

🛠️ **Easy install** — single `./install.sh` script, distro auto-detection

🚀 **Perfect for day-to-day use** — system tray icon shows status at a glance

🛜 **Works completely offline** — no internet connection required

⏰ **Turn on sudo anytime** — `sudome on` for instant admin rights

🔐 **Standard user security** — automatic revocation when timer expires

🧰 **MDM-ready** — configurable via `/etc/sudome/config.yaml`, deployable via Ansible/Puppet/Chef

⌨️ **CLI-first** — complete command-line interface with clear output

🔔 **Desktop notifications** — warns before sudo expires

🔁 **Renew expiring sudo** — extend at any time with `sudome renew`

🔒 **Polkit-backed** — all privileged operations go through PolicyKit authentication

📋 **Syslog audit logging** — every grant, revoke, and expiration is logged

🖥️ **GTK system tray** — GNOME/Ubuntu native, AppIndicator compatible

📦 **Packaging-ready** — DEB structure, install script, systemd integration

---

## Quick Start

```bash
# Install SudoMe
git clone https://github.com/0xEuphonioux/SudoMe.git
cd SudoMe
sudo ./install.sh

# Grant yourself 30 minutes of sudo
sudome on

# Grant yourself 60 minutes of sudo
sudome on 60

# Check your status
sudome status

# Extend your current grant
sudome renew

# Revoke immediately
sudome off
```

### Enable background auto-revocation

```bash
# Each user should run this once:
systemctl --user enable --now sudome-daemon.timer

# Check timer status:
systemctl --user status sudome-daemon.timer
```

This timer checks every 30 seconds and automatically revokes sudo when it expires.

---

## How It Works

```
User runs "sudome on"
       │
       ▼
┌──────────────────┐
│  sudome CLI/GUI  │  Polkit authentication dialog
└────────┬─────────┘
         │ pkexec
         ▼
┌──────────────────┐
│  sudome-helper   │  Runs as root: usermod -aG sudo <user>
│  (Polkit action) │  Writes expiry timestamp to /var/lib/sudome/
└────────┬─────────┘
         │
         ▼
┌──────────────────┐
│  User now has    │  ─────────────────────────────▶
│  sudo access!    │  │ systemd timer checks every 30s
└──────────────────┘  │
                       ▼
                  ┌──────────────────┐
                  │  sudome-daemon   │  When expired: usermod -G <user>
                  │  (systemd timer) │  Removes user from sudo group
                  └──────────────────┘
```

## Components

| Component | Location | Purpose |
|-----------|----------|---------|
| `sudome` | `/usr/bin/sudome` | CLI tool for grant/revoke/status |
| `sudome-gui` | `/usr/bin/sudome-gui` | GTK system tray application |
| `sudome-helper` | `/usr/lib/sudome/sudome-helper` | Polkit-backed privileged operations |
| `sudome-daemon` | `/usr/lib/sudome/sudome-daemon` | Background revoker (called by systemd timer) |
| `sudome-daemon.timer` | `/usr/share/systemd/user/` | systemd timer — fires every 30 seconds |
| `org.freedesktop.sudome.policy` | `/usr/share/polkit-1/actions/` | Polkit action definitions |

---

## Configuration

Configuration lives at `/etc/sudome/config.yaml`:

```yaml
# Default duration for sudo grants (minutes)
default_duration: 30

# Maximum allowed duration (minutes, 0 = unlimited)
max_duration: 480

# How often the daemon checks (seconds)
daemon_check_interval: 30

# Automatically revoke at user logout
revoke_on_logout: true

# Desktop notification before expiry (seconds before)
notify_before_expiry: 300

# Syslog audit logging
log_to_syslog: true
syslog_facility: "auth"

# Desktop notifications
desktop_notifications: true

# Optional webhook for SIEM integration
# webhook_url: "https://your-siem.example.com/hooks/sudome"
```

---

## Enterprise Deployment

### Ansible

```yaml
- name: Deploy SudoMe
  hosts: linux_workstations
  tasks:
    - name: Clone SudoMe
      git:
        repo: https://github.com/0xEuphonioux/SudoMe.git
        dest: /tmp/sudome
        version: main

    - name: Run installer
      command: ./install.sh
      args:
        chdir: /tmp/sudome
      become: yes

    - name: Enable daemon for all users
      shell: |
        for user in $(getent passwd | awk -F: '$3>=1000 && $3<60000{print $1}'); do
          su - "$user" -c "systemctl --user enable --now sudome-daemon.timer"
        done
      become: yes
```

### Monitoring

All events are logged to syslog with tag `sudome-helper`:

```bash
# View grant/revoke events:
journalctl -t sudome-helper

# View daemon events:
journalctl -t sudome-daemon

# Follow in real-time:
journalctl -t sudome-helper -f
```

Syslog format (same style as SAP Privileges):

```
Jun 22 10:58:07 hostname sudome-helper: Process sudome created at 
06/22/2026 10:58:07 PM by user klucano in session 2 with an 
elevation type of Default. action: 'grant' minutes: '30'
```

---

## Security

> [!IMPORTANT]
> Users with sudo privileges have extensive capabilities to make changes to a Linux system. This can include completely removing the _SudoMe_ application. Therefore, _SudoMe_ cannot guarantee that elevated permissions will be removed from the user account at all or on any specific schedule. _SudoMe_ cannot undo other changes made by a user — or processes acting as the user — when that user has elevated rights. Organizations should consider this when designing their client management, device compliance, security hardening, and auditing policies.

_SudoMe_ uses PolicyKit for authentication — no passwords are stored or transmitted. The privileged helper (`sudome-helper`) runs only the minimum required operations (`usermod` / `deluser`). The state directory (`/var/lib/sudome/`) is only writable by root. All operations are logged to syslog for audit trails.

---

## Comparison with SAP Privileges (macOS)

| Feature | SAP Privileges (macOS) | SudoMe (Linux) |
|---------|----------------------|----------------|
| **Platform** | macOS 11–26 | Ubuntu, Debian, Fedora, Arch |
| **Privilege system** | `admin` group | `sudo` group |
| **GUI** | Native macOS menu bar | GTK system tray (AppIndicator) |
| **CLI** | `PrivilegesCLI` | `sudome` |
| **Background daemon** | `PrivilegesDaemon` (XPC) | `sudome-daemon` (systemd timer) |
| **Privileged helper** | `PrivilegesHelper` (XPC) | `sudome-helper` (Polkit) |
| **Config management** | MDM profile | `/etc/sudome/config.yaml` |
| **Timeout** | Configurable (default 30 min) | Configurable (default 30 min) |
| **Audit logging** | ETW + syslog | syslog (logger) |
| **Webhooks** | ✅ | ✅ (configurable) |
| **Smart card/PIV** | ✅ | 🔜 planned |
| **Localized** | 41 languages | EN, DE, ES, FR (more planned) |
| **License** | Apache 2.0 | Apache 2.0 |

---

## Uninstall

```bash
sudo ./install.sh --uninstall
```

Or manually remove all files listed in the [Components](#components) section.

---

## Developing

```bash
# Clone the repo
git clone https://github.com/0xEuphonioux/SudoMe.git
cd SudoMe

# Install dev dependencies (Ubuntu/Debian)
sudo apt install python3 python3-gi gir1.2-gtk-3.0 \
  gir1.2-appindicator3-0.1 gir1.2-notify-0.7 python3-yaml \
  policykit-1
```

### Project structure

```
SudoMe/
├── sudome_cli/         CLI tool (Python 3)
├── sudome_helper/      Polkit helper (Bash)
├── sudome_daemon/      Background revoker (Python 3)
├── sudome_gui/         GTK system tray (Python 3)
├── share/              System integration files
│   ├── polkit-1/       Polkit actions
│   ├── dbus-1/         D-Bus configuration
│   ├── systemd/        systemd user units
│   ├── applications/   .desktop entry
│   └── icons/          Tray icons (SVG)
├── etc/sudome/         Default configuration
├── packaging/          Packaging scripts
└── install.sh          Installer (Bash)
```

---

## License

Copyright (c) 2026 0xEuphonioux and SudoMe contributors. Licensed under the Apache License 2.0. See [LICENSE](LICENSE) for details.

---

## Support

This project is provided 'as-is' with community support. Please open issues on GitHub for bugs, feature requests, or questions. Contributions are welcome!
