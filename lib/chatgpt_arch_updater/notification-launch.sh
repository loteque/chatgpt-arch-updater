#!/usr/bin/env bash
set -euo pipefail

version=${1:?missing package version}
command -v notify-send >/dev/null 2>&1 || exit 0

# The default action is invoked when the notification itself is clicked.
action=$(notify-send --app-name='ChatGPT Arch Updater' \
  --action=default='Open help' \
  'ChatGPT package ready' \
  "chatgpt-official-bin $version is ready. Click Open help to view updater help." 2>/dev/null || true)
[[ "$action" == default ]] || exit 0

help_command='chatgpt-arch-updater --help; printf "\\nPress Enter to close this terminal. "; read -r'
terminal=${CHATGPT_ARCH_UPDATER_TERMINAL:-${TERMINAL:-}}

if [[ -n "$terminal" ]] && ! command -v "$terminal" >/dev/null 2>&1; then
  printf 'Configured terminal was not found: %s\n' "$terminal" >&2
  exit 1
fi

if [[ -z "$terminal" ]]; then
  for candidate in kitty foot alacritty konsole gnome-terminal kgx xfce4-terminal xterm; do
    if command -v "$candidate" >/dev/null 2>&1; then
      terminal=$candidate
      break
    fi
  done
fi

if [[ -z "$terminal" ]]; then
  notify-send 'ChatGPT Arch Updater' 'No supported terminal was found. Set CHATGPT_ARCH_UPDATER_TERMINAL to your terminal command.' 2>/dev/null || true
  exit 1
fi

case "${terminal##*/}" in
  gnome-terminal|kgx) exec "$terminal" -- bash -lc "$help_command" ;;
  xfce4-terminal) exec "$terminal" --command="bash -lc '$help_command'" ;;
  *) exec "$terminal" -e bash -lc "$help_command" ;;
esac
