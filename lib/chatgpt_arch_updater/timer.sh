#!/usr/bin/env bash

set_check_interval() {
  local interval=${1:-} content dir file hours
  case "$interval" in
    1d) content='OnCalendar=daily' ;;
    1w) content='OnCalendar=weekly' ;;
    1m) content='OnCalendar=monthly' ;;
    *)
      if [[ "$interval" =~ ^([1-9][0-9]{0,3})h$ ]]; then
        hours=${BASH_REMATCH[1]}
        (( hours <= 8760 )) || die 'hour interval must be between 1h and 8760h'
        content="OnUnitActiveSec=${hours}h"
      else
        die 'time must be Nh (1h through 8760h), 1d, 1w, or 1m'
      fi
      ;;
  esac

  dir="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user/chatgpt-arch-updater.timer.d"
  file="$dir/override.conf"
  mkdir -p "$dir"
  cat >"$file.part" <<EOF
[Timer]
OnCalendar=
OnActiveSec=
OnUnitActiveSec=
RandomizedDelaySec=0
$content
EOF
  mv -f -- "$file.part" "$file"
  systemctl --user daemon-reload || die 'could not reload the user systemd manager'
  systemctl --user enable --now chatgpt-arch-updater.timer || die 'could not enable and start the updater timer'
  systemctl --user start chatgpt-arch-updater.service || die 'could not trigger the initial updater check'
  info "Check interval set to $interval; timer is enabled and the initial check has started."
}
