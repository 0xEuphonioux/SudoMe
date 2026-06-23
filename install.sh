#!/bin/bash
# SudoMe Install Script
# Installs all components for temporary sudo privilege elevation.
#
# Usage:
#   sudo ./install.sh              # Full install (system-wide)
#   sudo ./install.sh --uninstall   # Remove SudoMe
#
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

# ── Colors ──────────────────────────────────────────────────────────────
RED='\033[91m'; GREEN='\033[92m'; YELLOW='\033[93m'; CYAN='\033[96m'
BOLD='\033[1m'; RESET='\033[0m'

info()  { echo -e "  ${CYAN}→${RESET} $*"; }
ok()    { echo -e "  ${GREEN}✓${RESET} $*"; }
warn()  { echo -e "  ${YELLOW}⚠${RESET} $*"; }
err()   { echo -e "  ${RED}✗${RESET} $*"; }
header() { echo -e "\n${BOLD}${CYAN}═══ $* ═══${RESET}"; }

# ── Paths ──────────────────────────────────────────────────────────────
INSTALL_PREFIX="/usr"
LIB_DIR="${INSTALL_PREFIX}/lib/sudome"
BIN_DIR="${INSTALL_PREFIX}/bin"
SHARE_DIR="${INSTALL_PREFIX}/share"
ETC_DIR="/etc/sudome"
STATE_DIR="/var/lib/sudome"
POLKIT_DIR="${SHARE_DIR}/polkit-1/actions"
DBUS_DIR="${SHARE_DIR}/dbus-1/system.d"
SYSTEMD_USER_DIR="${SHARE_DIR}/systemd/user"
ICON_DIR="${SHARE_DIR}/icons/hicolor/scalable/apps"
APPS_DIR="${SHARE_DIR}/applications"

# ── Source paths (relative to script) ──────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_HELPER="${SCRIPT_DIR}/sudome_helper/sudome-helper"
SRC_CLI="${SCRIPT_DIR}/sudome_cli/sudome"
SRC_DAEMON="${SCRIPT_DIR}/sudome_daemon/sudome-daemon"
SRC_GUI="${SCRIPT_DIR}/sudome_gui/sudome-gui"
SRC_POLKIT="${SCRIPT_DIR}/share/polkit-1/actions/org.freedesktop.sudome.policy"
SRC_DBUS="${SCRIPT_DIR}/share/dbus-1/system.d/org.freedesktop.sudome.conf"
SRC_SERVICE="${SCRIPT_DIR}/share/systemd/user/sudome-daemon.service"
SRC_TIMER="${SCRIPT_DIR}/share/systemd/user/sudome-daemon.timer"
SRC_DESKTOP="${SCRIPT_DIR}/share/applications/sudome.desktop"
SRC_CONFIG="${SCRIPT_DIR}/etc/sudome/config.yaml"
SRC_RSYSLOG="${SCRIPT_DIR}/share/rsyslog.d/99-sudome.conf"

# ── Check root ──────────────────────────────────────────────────────────
require_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}${BOLD}This script must be run as root (sudo).${RESET}"
        exit 1
    fi
}

# ── Detect distro ──────────────────────────────────────────────────────
detect_distro() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        echo "$ID"
    else
        echo "unknown"
    fi
}

# ── Install dependencies ───────────────────────────────────────────────
install_deps() {
    local distro
    distro=$(detect_distro)
    
    header "Installing dependencies for $distro"

    case "$distro" in
        ubuntu|debian|pop|linuxmint|elementary|zorin)
            info "Detected Debian-based distro"
            apt-get update -qq
            
            # Detect Ubuntu version for AppIndicator package
            APPINDICATOR_PKG="gir1.2-appindicator3-0.1"
            if [[ -f /etc/os-release ]]; then
                . /etc/os-release
                if [[ "$ID" == "ubuntu" ]] && [[ "${VERSION_ID%.*}" -ge 24 ]]; then
                    APPINDICATOR_PKG="gir1.2-ayatanaappindicator3-0.1"
                fi
            fi
            
            apt-get install -y -qq \
                python3 \
                python3-gi \
                python3-dbus \
                gir1.2-gtk-3.0 \
                "$APPINDICATOR_PKG" \
                gir1.2-notify-0.7 \
                python3-yaml \
                policykit-1 \
                pkexec \
                libpolkit-agent-1-0 \
                dbus \
                2>&1 | grep -v "^$" || true
            ;;
        fedora|rhel|centos|rocky|almalinux)
            info "Detected RHEL-based distro"
            dnf install -y \
                python3 \
                python3-gobject \
                gtk3 \
                libappindicator-gtk3 \
                libnotify \
                python3-pyyaml \
                polkit \
                2>&1 | grep -v "^$" || true
            ;;
        arch|manjaro|endeavouros)
            info "Detected Arch-based distro"
            pacman -S --noconfirm --needed \
                python \
                python-gobject \
                gtk3 \
                libappindicator-gtk3 \
                libnotify \
                python-yaml \
                polkit \
                2>&1 | grep -v "^$" || true
            ;;
        opensuse*|suse)
            info "Detected SUSE-based distro"
            zypper install -y \
                python3 \
                python3-gobject \
                gtk3 \
                libappindicator3-1 \
                libnotify4 \
                python3-PyYAML \
                polkit \
                2>&1 | grep -v "^$" || true
            ;;
        *)
            warn "Unknown distro '$distro'. Please install dependencies manually:"
            echo "  - python3, python3-gi, python3-yaml"
            echo "  - GTK 3 (gir1.2-gtk-3.0)"
            echo "  - AppIndicator (gir1.2-appindicator3-0.1)"
            echo "  - Notifications (gir1.2-notify-0.7)"
            echo "  - PolicyKit (policykit-1)"
            ;;
    esac

    ok "Dependencies installed"
}

# ── Install SudoMe ─────────────────────────────────────────────────────
do_install() {
    require_root
    
    # ── Banner ────────────────────────────────────────────────────────
    echo -e "${RESET}"
    echo -e "${BOLD}${GREEN}    ╔══════════════════════════════════════════════════════════╗${RESET}"
    echo -e "${BOLD}${GREEN}    ║${RESET}  ${BOLD}${CYAN}   ███████╗██╗   ██╗██████╗  ██████╗ ███╗   ███╗███████╗${BOLD}${GREEN}  ║${RESET}"
    echo -e "${BOLD}${GREEN}    ║${RESET}  ${BOLD}${CYAN}   ██╔════╝██║   ██║██╔══██╗██╔═══██╗████╗ ████║██╔════╝${BOLD}${GREEN}  ║${RESET}"
    echo -e "${BOLD}${GREEN}    ║${RESET}  ${BOLD}${CYAN}   ███████╗██║   ██║██║  ██║██║   ██║██╔████╔██║█████╗  ${BOLD}${GREEN}  ║${RESET}"
    echo -e "${BOLD}${GREEN}    ║${RESET}  ${BOLD}${CYAN}   ╚════██║██║   ██║██║  ██║██║   ██║██║╚██╔╝██║██╔══╝  ${BOLD}${GREEN}  ║${RESET}"
    echo -e "${BOLD}${GREEN}    ║${RESET}  ${BOLD}${CYAN}   ███████║╚██████╔╝██████╔╝╚██████╔╝██║ ╚═╝ ██║███████╗${BOLD}${GREEN}  ║${RESET}"
    echo -e "${BOLD}${GREEN}    ║${RESET}  ${BOLD}${CYAN}   ╚══════╝ ╚═════╝ ╚═════╝  ╚═════╝ ╚═╝     ╚═╝╚══════╝${BOLD}${GREEN}  ║${RESET}"
    echo -e "${BOLD}${GREEN}    ║${RESET}                                                      ${BOLD}${GREEN}║${RESET}"
    echo -e "${BOLD}${GREEN}    ║${RESET}  ${BOLD}${RED}v2.0.0${RESET}  │  Temporary sudo privilege elevation       ${BOLD}${GREEN}║${RESET}"
    echo -e "${BOLD}${GREEN}    ║${RESET}  ${CYAN}github.com/0xEuphonioux/SudoMe${RESET}                   ${BOLD}${GREEN}║${RESET}"
    echo -e "${BOLD}${GREEN}    ╚══════════════════════════════════════════════════════════╝${RESET}"
    echo -e ""
    echo -e "  ${RED}▲${RESET} ${BOLD}${YELLOW}WARNING:${RESET} This script will install system-wide components."
    echo -e "  ${RED}▲${RESET} It requires ${BOLD}root${RESET} and will modify system configuration."
    echo -e ""

    install_deps

    echo -e ""
    echo -e "  ${CYAN}[*]${RESET} ${BOLD}Initializing installation sequence...${RESET}"
    sleep 0.3
    echo -e "  ${GREEN}[+]${RESET} Target distro: ${BOLD}$(detect_distro)${RESET}"
    sleep 0.2
    echo -e "  ${GREEN}[+]${RESET} Install prefix: ${BOLD}${INSTALL_PREFIX}${RESET}"
    sleep 0.2
    echo -e "  ${GREEN}[+]${RESET} Dependencies resolved"
    sleep 0.2
    echo -e ""

    header "Deploying payload"

    RSYSLOG_DIR="/etc/rsyslog.d"
    
    # ── Create directories ──
    info "Creating directories..."
    mkdir -p "$LIB_DIR" "$ETC_DIR" "$STATE_DIR" "$POLKIT_DIR" \
             "$DBUS_DIR" "$SYSTEMD_USER_DIR" "$ICON_DIR" "$APPS_DIR"

    # ── Install helper ──
    info "Installing sudo helper..."
    install -m 755 "$SRC_HELPER" "${LIB_DIR}/sudome-helper"
    ok "Helper → ${LIB_DIR}/sudome-helper"

    # ── Install daemon ──
    info "Installing daemon..."
    install -m 755 "$SRC_DAEMON" "${LIB_DIR}/sudome-daemon"
    ok "Daemon → ${LIB_DIR}/sudome-daemon"

    # ── Install CLI ──
    info "Installing CLI..."
    install -m 755 "$SRC_CLI" "${BIN_DIR}/sudome"
    ok "CLI → ${BIN_DIR}/sudome"

    # ── Install GUI ──
    info "Installing GUI..."
    install -m 755 "$SRC_GUI" "${BIN_DIR}/sudome-gui"
    ok "GUI → ${BIN_DIR}/sudome-gui"

    # ── Install Polkit policy ──
    info "Installing Polkit policy..."
    install -m 644 "$SRC_POLKIT" "${POLKIT_DIR}/org.freedesktop.sudome.policy"
    ok "Policy → ${POLKIT_DIR}/org.freedesktop.sudome.policy"

    # ── Install D-Bus config ──
    info "Installing D-Bus config..."
    install -m 644 "$SRC_DBUS" "${DBUS_DIR}/org.freedesktop.sudome.conf"
    ok "D-Bus config → ${DBUS_DIR}/org.freedesktop.sudome.conf"

    # ── Install icons ──
    info "Installing tray icons..."
    install -m 644 "${SCRIPT_DIR}/share/icons/hicolor/scalable/apps/sudome-active.svg" "${ICON_DIR}/sudome-active.svg"
    install -m 644 "${SCRIPT_DIR}/share/icons/hicolor/scalable/apps/sudome-inactive.svg" "${ICON_DIR}/sudome-inactive.svg"
    install -m 644 "${SCRIPT_DIR}/share/icons/hicolor/scalable/apps/sudome-expiring.svg" "${ICON_DIR}/sudome-expiring.svg"
    ok "Icons → ${ICON_DIR}/"

    # ── Install systemd units ──
    info "Installing systemd user units..."
    install -m 644 "$SRC_SERVICE" "${SYSTEMD_USER_DIR}/sudome-daemon.service"
    install -m 644 "$SRC_TIMER" "${SYSTEMD_USER_DIR}/sudome-daemon.timer"
    ok "systemd units installed"

    # ── Install desktop entry ──
    info "Installing desktop entry..."
    install -m 644 "$SRC_DESKTOP" "${APPS_DIR}/sudome.desktop"
    ok "Desktop entry → ${APPS_DIR}/sudome.desktop"

    # ── Install autostart entry (launches on login) ──
    AUTOSTART_DIR="/etc/xdg/autostart"
    if [[ -d "$AUTOSTART_DIR" ]]; then
        info "Installing autostart entry..."
        install -m 644 "$SRC_DESKTOP" "${AUTOSTART_DIR}/sudome.desktop"
        ok "Autostart → ${AUTOSTART_DIR}/sudome.desktop"
    fi

    # ── Install config ──
    info "Installing configuration..."
    if [[ ! -f "${ETC_DIR}/config.yaml" ]]; then
        install -m 644 "$SRC_CONFIG" "${ETC_DIR}/config.yaml"
        ok "Config → ${ETC_DIR}/config.yaml"
    else
        warn "Config already exists at ${ETC_DIR}/config.yaml (not overwritten)"
        info "Reference config: ${SRC_CONFIG}"
    fi

    # ── Install rsyslog forwarding config ──
    if [[ -d "$RSYSLOG_DIR" ]]; then
        info "Installing rsyslog forwarding config..."
        if [[ ! -f "${RSYSLOG_DIR}/99-sudome.conf" ]]; then
            install -m 644 "$SRC_RSYSLOG" "${RSYSLOG_DIR}/99-sudome.conf"
            ok "rsyslog config → ${RSYSLOG_DIR}/99-sudome.conf"
            info "SudoMe events logged to /var/log/sudome.log"
            info "To forward to a remote syslog server, edit ${RSYSLOG_DIR}/99-sudome.conf"
        else
            warn "rsyslog config already exists (not overwritten)"
        fi
    else
        warn "rsyslog not found — skipping syslog forwarding config"
        info "Install rsyslog for remote syslog support: sudo apt install rsyslog"
    fi

    # ── Set state dir permissions ──
    chmod 755 "$STATE_DIR"
    ok "State directory: $STATE_DIR"

    # ── Reload systemd, Polkit, D-Bus ──
    header "Reloading system services"
    
    info "Reloading systemd user daemon..."
    systemctl --user daemon-reload 2>/dev/null || true
    
    # Enable and start the daemon for the current user
    info "Starting SudoMe daemon (monitors lock, sleep, shutdown, expiry)..."
    
    # Get the real user (not root) who ran sudo
    REAL_USER="${SUDO_USER:-$USER}"
    if [[ "$REAL_USER" != "root" ]]; then
        # Enable the service to start on login
        su - "$REAL_USER" -c "systemctl --user enable sudome-daemon.service" 2>/dev/null || true
        
        # Start it now
        su - "$REAL_USER" -c "systemctl --user start sudome-daemon.service" 2>/dev/null || true
        
        ok "Daemon started for user '$REAL_USER'"
        info "Each additional user should run:"
    else
        info "Each user should run:"
    fi
    echo -e "       ${CYAN}systemctl --user enable --now sudome-daemon.service${RESET}"
    
    info "Restarting polkit..."
    systemctl restart polkit 2>/dev/null || service polkit restart 2>/dev/null || true
    
    info "Reloading D-Bus..."
    systemctl reload dbus 2>/dev/null || service dbus reload 2>/dev/null || true

    # ── Done ──
    echo
    echo -e "  ${GREEN}[✓]${RESET} Polkit policy registered"
    echo -e "  ${GREEN}[✓]${RESET} D-Bus configuration loaded"
    echo -e "  ${GREEN}[✓]${RESET} systemd daemon deployed"
    echo -e ""
    echo -e "${BOLD}${GREEN}    ╔══════════════════════════════════════════════════════════╗${RESET}"
    echo -e "${BOLD}${GREEN}    ║${RESET}                                                      ${BOLD}${GREEN}║${RESET}"
    echo -e "${BOLD}${GREEN}    ║${RESET}         ${BOLD}SudoMe v2.0.0 installed successfully${RESET}          ${BOLD}${GREEN}║${RESET}"
    echo -e "${BOLD}${GREEN}    ║${RESET}                                                      ${BOLD}${GREEN}║${RESET}"
    echo -e "${BOLD}${GREEN}    ╚══════════════════════════════════════════════════════════╝${RESET}"
    echo
    echo -e "  ${BOLD}${CYAN}COMMANDS${RESET}"
    echo -e "  ─────────────────────────────────────────────"
    echo -e "  ${BOLD}sudome on${RESET}                     Grant 30 min sudo"
    echo -e "  ${BOLD}sudome on 60 -r \"Installing Docker\"${RESET}  Grant 60 min + reason"
    echo -e "  ${BOLD}sudome status${RESET}                Check current status"
    echo -e "  ${BOLD}sudome off${RESET}                   Revoke immediately"
    echo -e "  ${BOLD}sudome renew${RESET}                 Extend current grant"
    echo
    echo -e "  ${BOLD}${RED}AUTO-REVOCATION TRIGGERS${RESET}"
    echo -e "  ─────────────────────────────────────────────"
    echo -e "    ${CYAN}Screen lock${RESET}         → sudo revoked"
    echo -e "    ${CYAN}System sleep${RESET}        → sudo revoked"
    echo -e "    ${CYAN}Time/date change${RESET}     → sudo revoked"
    echo -e "    ${CYAN}Shutdown/restart${RESET}     → sudo revoked (all users)"
    echo -e "    ${CYAN}Timer expiry${RESET}         → sudo revoked"
    echo
    echo -e "  ${BOLD}${GREEN}GUI${RESET}"
    echo -e "  ─────────────────────────────────────────────"
    echo -e "  ${BOLD}sudome-gui${RESET}                  Launch system tray app"
    echo -e "  ${CYAN}Auto-starts on login${RESET}        via /etc/xdg/autostart/"
    echo
}

# ── Uninstall SudoMe ───────────────────────────────────────────────────
do_uninstall() {
    require_root

    header "Uninstalling SudoMe"

    info "Stopping daemons..."
    systemctl --user stop sudome-daemon.service 2>/dev/null || true
    systemctl --user disable sudome-daemon.service 2>/dev/null || true
    systemctl --user stop sudome-daemon.timer 2>/dev/null || true
    systemctl --user disable sudome-daemon.timer 2>/dev/null || true

    info "Removing files..."
    rm -f "${LIB_DIR}/sudome-helper"
    rm -f "${LIB_DIR}/sudome-daemon"
    rm -f "${BIN_DIR}/sudome"
    rm -f "${BIN_DIR}/sudome-gui"
    rm -f "${POLKIT_DIR}/org.freedesktop.sudome.policy"
    rm -f "${DBUS_DIR}/org.freedesktop.sudome.conf"
    rm -f "${SYSTEMD_USER_DIR}/sudome-daemon.service"
    rm -f "${SYSTEMD_USER_DIR}/sudome-daemon.timer"
    rm -f "${APPS_DIR}/sudome.desktop"
    rm -f "/etc/xdg/autostart/sudome.desktop"
    rm -f "${ICON_DIR}/sudome-active.svg"
    rm -f "${ICON_DIR}/sudome-inactive.svg"
    rm -f "${ICON_DIR}/sudome-expiring.svg"

    info "Preserving config and state (remove manually if desired):"
    echo "    ${ETC_DIR}"
    echo "    ${STATE_DIR}"

    info "Reloading systemd..."
    systemctl --user daemon-reload 2>/dev/null || true
    systemctl restart polkit 2>/dev/null || service polkit restart 2>/dev/null || true
    systemctl reload dbus 2>/dev/null || service dbus reload 2>/dev/null || true

    ok "SudoMe uninstalled"
}

# ── Main ───────────────────────────────────────────────────────────────
case "${1:-}" in
    --uninstall|-u|remove)
        do_uninstall
        ;;
    --help|-h)
        echo "Usage: sudo ./install.sh [--uninstall]"
        echo ""
        echo "  (no args)    Install SudoMe system-wide"
        echo "  --uninstall  Remove SudoMe"
        ;;
    *)
        do_install
        ;;
esac
