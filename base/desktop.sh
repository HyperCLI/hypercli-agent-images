hyper_desktop_enabled() {
  case "$(printf '%s' "${HYPER_DESKTOP_ENABLED:-0}" | tr '[:upper:]' '[:lower:]')" in
    1|true|yes|on|enabled) return 0 ;;
    *) return 1 ;;
  esac
}

hyper_configure_xfce_panel() {
  case "$(printf '%s' "${HYPER_DESKTOP_MANAGED_PANEL:-1}" | tr '[:upper:]' '[:lower:]')" in
    0|false|no|off|disabled) return 0 ;;
  esac

  local home_dir="${HOME:-/home/node}"
  local xfconf_dir="${home_dir}/.config/xfce4/xfconf/xfce-perchannel-xml"
  local panel_dir="${home_dir}/.config/xfce4/panel"
  rm -f "${home_dir}/Desktop/google-chrome.desktop"
  mkdir -p \
    "${xfconf_dir}" \
    "${panel_dir}/launcher-1" \
    "${panel_dir}/launcher-2" \
    "${panel_dir}/launcher-3"

  cp /usr/share/applications/google-chrome.desktop "${panel_dir}/launcher-1/google-chrome.desktop"
  cp /usr/share/applications/thunar.desktop "${panel_dir}/launcher-2/thunar.desktop"
  cp /usr/share/applications/xfce4-terminal.desktop "${panel_dir}/launcher-3/xfce4-terminal.desktop"

  cat >"${xfconf_dir}/xfce4-panel.xml" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>

<channel name="xfce4-panel" version="1.0">
  <property name="configver" type="int" value="2"/>
  <property name="panels" type="array">
    <value type="int" value="1"/>
    <property name="dark-mode" type="bool" value="false"/>
    <property name="panel-1" type="empty">
      <property name="position" type="string" value="p=10;x=640;y=760"/>
      <property name="position-locked" type="bool" value="true"/>
      <property name="length" type="uint" value="1"/>
      <property name="size" type="uint" value="52"/>
      <property name="plugin-ids" type="array">
        <value type="int" value="1"/>
        <value type="int" value="2"/>
        <value type="int" value="3"/>
      </property>
    </property>
  </property>
  <property name="plugins" type="empty">
    <property name="plugin-1" type="string" value="launcher">
      <property name="items" type="array">
        <value type="string" value="launcher-1/google-chrome.desktop"/>
      </property>
    </property>
    <property name="plugin-2" type="string" value="launcher">
      <property name="items" type="array">
        <value type="string" value="launcher-2/thunar.desktop"/>
      </property>
    </property>
    <property name="plugin-3" type="string" value="launcher">
      <property name="items" type="array">
        <value type="string" value="launcher-3/xfce4-terminal.desktop"/>
      </property>
    </property>
  </property>
</channel>
EOF
}

hyper_apply_xfce_panel() {
  case "$(printf '%s' "${HYPER_DESKTOP_MANAGED_PANEL:-1}" | tr '[:upper:]' '[:lower:]')" in
    0|false|no|off|disabled) return 0 ;;
  esac

  xfconf-query -c xfce4-panel -p /panels -r -R >/dev/null 2>&1 || true
  xfconf-query -c xfce4-panel -p /plugins -r -R >/dev/null 2>&1 || true
  xfconf-query -c xfce4-panel -p /panels -n -a -t int -s 1
  xfconf-query -c xfce4-panel -p /panels/panel-1/position -n -t string -s "p=10;x=640;y=760"
  xfconf-query -c xfce4-panel -p /panels/panel-1/position-locked -n -t bool -s true
  xfconf-query -c xfce4-panel -p /panels/panel-1/length -n -t uint -s 1
  xfconf-query -c xfce4-panel -p /panels/panel-1/size -n -t uint -s 52
  xfconf-query -c xfce4-panel -p /panels/panel-1/plugin-ids -n -a -t int -s 1 -t int -s 2 -t int -s 3
  xfconf-query -c xfce4-panel -p /plugins/plugin-1 -n -t string -s launcher
  xfconf-query -c xfce4-panel -p /plugins/plugin-1/items -n -a -t string -s launcher-1/google-chrome.desktop
  xfconf-query -c xfce4-panel -p /plugins/plugin-2 -n -t string -s launcher
  xfconf-query -c xfce4-panel -p /plugins/plugin-2/items -n -a -t string -s launcher-2/thunar.desktop
  xfconf-query -c xfce4-panel -p /plugins/plugin-3 -n -t string -s launcher
  xfconf-query -c xfce4-panel -p /plugins/plugin-3/items -n -a -t string -s launcher-3/xfce4-terminal.desktop
}

hyper_start_desktop() {
  if ! command -v Xvfb >/dev/null 2>&1 || \
     ! command -v x11vnc >/dev/null 2>&1 || \
     ! command -v websockify >/dev/null 2>&1 || \
     ! command -v dbus-launch >/dev/null 2>&1 || \
     ! command -v xfconf-query >/dev/null 2>&1 || \
     ! command -v xfwm4 >/dev/null 2>&1 || \
     ! command -v xfce4-panel >/dev/null 2>&1 || \
     ! command -v xfce4-terminal >/dev/null 2>&1 || \
     ! command -v thunar >/dev/null 2>&1; then
    echo "[desktop] desktop requested but desktop runtime packages are not installed" >&2
    exit 1
  fi

  export DISPLAY="${DISPLAY:-:99}"
  local desktop_port="${HYPER_DESKTOP_PORT:-${OPENCLAW_DESKTOP_PORT:-3000}}"
  local geometry="${HYPER_DESKTOP_GEOMETRY:-1280x800x24}"
  local vnc_port="${HYPER_VNC_PORT:-5900}"

  mkdir -p "${HOME:-/home/node}/.config/google-chrome"
  hyper_configure_xfce_panel
  echo "[desktop] starting ${DISPLAY}, noVNC port ${desktop_port}"

  Xvfb "${DISPLAY}" -screen 0 "${geometry}" -ac +extension RANDR &
  sleep 1
  eval "$(dbus-launch --sh-syntax)"
  export DBUS_SESSION_BUS_ADDRESS DBUS_SESSION_BUS_PID
  hyper_apply_xfce_panel
  xsetroot -solid "${HYPER_DESKTOP_BACKGROUND_COLOR:-#071A2F}" >/dev/null 2>&1 || true
  xfwm4 --replace >/tmp/xfwm4.log 2>&1 &
  xfce4-panel >/tmp/xfce4-panel.log 2>&1 &
  x11vnc -display "${DISPLAY}" -rfbport "${vnc_port}" -localhost -forever -shared -nopw >/tmp/x11vnc.log 2>&1 &
  websockify --web /usr/share/novnc/ "${desktop_port}" "localhost:${vnc_port}" >/tmp/novnc.log 2>&1 &
}
