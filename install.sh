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