#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
source "$ROOT/lib/chatgpt_arch_updater/common.sh"
source "$ROOT/lib/chatgpt_arch_updater/arch-repository.sh"
source "$ROOT/lib/chatgpt_arch_updater/dependencies.sh"
source "$ROOT/lib/chatgpt_arch_updater/package.sh"
source "$ROOT/lib/chatgpt_arch_updater/timer.sh"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
BASE_DIR=$tmp
DIST_DIR=$tmp/dist
mkdir -p "$DIST_DIR"

if map_debian_dependency libc6 | grep -qx glibc; then :; else
  printf 'libc6 mapping failed\n' >&2; exit 1
fi
if map_debian_dependency definitely-not-a-real-dependency >/dev/null; then
  printf 'unknown dependency was accepted\n' >&2; exit 1
fi
if dependency_report 'libc6, definitely-not-a-real-dependency'; then
  printf 'unknown dependency report was not flagged\n' >&2; exit 1
fi
grep -q 'Unrecognized Debian dependency: definitely-not-a-real-dependency' "$tmp/dependency-discrepancies"
dependency_report 'libc6, libusb-1.0-0 (>= 2.0), xz-utils'
[[ $(wc -l <"$tmp/arch-dependencies") -eq 3 ]] || {
  printf 'mapped dependency list was not written one package per line\n' >&2; exit 1;
}
grep -qx 'libusb' "$tmp/arch-dependencies"
grep -qx 'xz' "$tmp/arch-dependencies"

cat >"$tmp/Packages" <<'EOF'
Package: chatgpt
Version: 26.915.31945
Architecture: amd64
Filename: pool/main/c/chatgpt/chatgpt_26.915.31945_amd64.deb
SHA256: aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
EOF
cat >"$tmp/arch-desc" <<'EOF'
%NAME%
chatgpt-bin

%VERSION%
26.915.31945-1

%ARCH%
x86_64
EOF
printf 'fake repository database\n' >"$tmp/openai-chatgpt.db"
printf 'fake repository signature\n' >"$tmp/openai-chatgpt.db.sig"
printf 'fake repository key\n' >"$tmp/repository-signing-key.gpg"
fixture="$tmp/Packages"
curl() {
  local output=
  while (($#)); do
    if [[ "$1" == --output ]]; then output=$2; shift 2; else shift; fi
  done
  cp "$fixture" "$output"
}
UPSTREAM_INDEX="$tmp/Packages-amd64"
fetch_upstream_metadata
[[ "$UPSTREAM_VERSION" == 26.915.31945 && "$UPSTREAM_SHA256" == \
  aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa ]] || {
  printf 'OpenAI package index fields were not parsed\n' >&2; exit 1;
}
mkdir -p "$tmp/bin"
cat >"$tmp/bin/curl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$CHATGPT_ARCH_UPDATER_TEST_CURL_LOG"
output=
url=
while (($#)); do
  if [[ "$1" == --output ]]; then output=$2; shift 2
  elif [[ "$1" == http* ]]; then url=$1; shift
  else shift; fi
done
case "$url" in
  */Packages) cp "$CHATGPT_ARCH_UPDATER_TEST_INDEX" "$output" ;;
  */openai-chatgpt.db.sig) cp "$CHATGPT_ARCH_UPDATER_TEST_ARCH_SIG" "$output" ;;
  */openai-chatgpt.db) cp "$CHATGPT_ARCH_UPDATER_TEST_ARCH_DB" "$output" ;;
  */repository-signing-key.gpg) cp "$CHATGPT_ARCH_UPDATER_TEST_ARCH_KEY" "$output" ;;
  *) printf 'unexpected test download URL: %s\n' "$url" >&2; exit 1 ;;
esac
EOF
cat >"$tmp/bin/pacman" <<'EOF'
#!/usr/bin/env bash
[[ "$1" == -Q ]] || exit 1
case "$2" in
  chatgpt-official-bin) [[ -n "${CHATGPT_ARCH_UPDATER_TEST_INSTALLED_VERSION:-}" ]] || exit 1
    printf 'chatgpt-official-bin %s\n' "$CHATGPT_ARCH_UPDATER_TEST_INSTALLED_VERSION" ;;
  chatgpt-bin) [[ -n "${CHATGPT_ARCH_UPDATER_TEST_ARCH_INSTALLED_VERSION:-}" ]] || exit 1
    printf 'chatgpt-bin %s\n' "$CHATGPT_ARCH_UPDATER_TEST_ARCH_INSTALLED_VERSION" ;;
  *) exit 1 ;;
esac
EOF
cat >"$tmp/bin/bsdtar" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == -tf ]]; then
  printf 'chatgpt-bin-26.915.31945-1/desc\n'
elif [[ "$1" == -xOf ]]; then
  cat "$CHATGPT_ARCH_UPDATER_TEST_ARCH_DESC"
else
  exit 2
fi
EOF
cat >"$tmp/bin/gpg" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$CHATGPT_ARCH_UPDATER_TEST_GPG_LOG"
for arg in "$@"; do
  if [[ "$arg" == --show-keys ]]; then
    if [[ "${CHATGPT_ARCH_UPDATER_TEST_BAD_KEY:-0}" == 1 ]]; then
      printf 'pub:-:4096:1:4A3B4A566C4660E4:1785898069::::::scSC::::::23::0:\nfpr:::::::::AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA:\n'
    else
      printf 'pub:-:4096:1:4A3B4A566C4660E4:1785898069::::::scSC::::::23::0:\nfpr:::::::::3BFA0E4AE8B8CC16A2D9BA684A3B4A566C4660E4:\n'
    fi
    exit 0
  fi
done
[[ "${CHATGPT_ARCH_UPDATER_TEST_BAD_SIGNATURE:-0}" != 1 ]] || exit 1
exit 0
EOF
cat >"$tmp/bin/systemctl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$CHATGPT_ARCH_UPDATER_TEST_SYSTEMCTL_LOG"
EOF
cat >"$tmp/bin/sudo" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$CHATGPT_ARCH_UPDATER_TEST_SUDO_LOG"
EOF
chmod +x "$tmp/bin/curl" "$tmp/bin/pacman" "$tmp/bin/bsdtar" "$tmp/bin/gpg" "$tmp/bin/systemctl" "$tmp/bin/sudo"
unset -f curl
PATH="$tmp/bin:$PATH"
export PATH CHATGPT_ARCH_UPDATER_TEST_INDEX="$fixture"
export CHATGPT_ARCH_UPDATER_TEST_CURL_LOG="$tmp/curl.log"
export CHATGPT_ARCH_UPDATER_TEST_ARCH_DB="$tmp/openai-chatgpt.db"
export CHATGPT_ARCH_UPDATER_TEST_ARCH_SIG="$tmp/openai-chatgpt.db.sig"
export CHATGPT_ARCH_UPDATER_TEST_ARCH_KEY="$tmp/repository-signing-key.gpg"
export CHATGPT_ARCH_UPDATER_TEST_ARCH_DESC="$tmp/arch-desc"
export CHATGPT_ARCH_UPDATER_TEST_GPG_LOG="$tmp/gpg.log"
cli_env=(PATH="$tmp/bin:$PATH" CHATGPT_ARCH_UPDATER_LIBDIR="$ROOT/lib/chatgpt_arch_updater"
  CHATGPT_ARCH_UPDATER_DATA_DIR="$tmp/cli-data"
  XDG_CONFIG_HOME="$tmp/cli-config"
  CHATGPT_ARCH_UPDATER_TEST_INDEX="$fixture"
  CHATGPT_ARCH_UPDATER_TEST_CURL_LOG="$tmp/curl.log"
  CHATGPT_ARCH_UPDATER_TEST_ARCH_DB="$tmp/openai-chatgpt.db"
  CHATGPT_ARCH_UPDATER_TEST_ARCH_SIG="$tmp/openai-chatgpt.db.sig"
  CHATGPT_ARCH_UPDATER_TEST_ARCH_KEY="$tmp/repository-signing-key.gpg"
  CHATGPT_ARCH_UPDATER_TEST_ARCH_DESC="$tmp/arch-desc")
set +e
env "${cli_env[@]}" CHATGPT_ARCH_UPDATER_TEST_INSTALLED_VERSION=26.915.31945 \
  "$ROOT/bin/chatgpt-arch-updater" --verchk >/dev/null 2>&1
rc=$?
set -e
[[ $rc -eq 1 ]] || { printf '--verchk must return 1 for equal versions\n' >&2; exit 1; }
env "${cli_env[@]}" CHATGPT_ARCH_UPDATER_TEST_INSTALLED_VERSION=26.903.61454 \
  "$ROOT/bin/chatgpt-arch-updater" --verchk >/dev/null
env "${cli_env[@]}" CHATGPT_ARCH_UPDATER_TEST_INSTALLED_VERSION=26.915.31945 \
  "$ROOT/bin/chatgpt-arch-updater" --check >/dev/null
! grep -q 'chatgpt_[0-9].*_amd64.deb' "$tmp/curl.log" || {
  printf '--check downloaded the Debian package when versions were equal\n' >&2; exit 1;
}
grep -q 'openai-chatgpt.db.sig' "$tmp/curl.log"
grep -q 'repository-signing-key.gpg' "$tmp/curl.log"
grep -q -- '--verify' "$tmp/gpg.log" || {
  printf 'OpenAI Arch repository database signature was not verified\n' >&2; exit 1;
}
set +e
env "${cli_env[@]}" CHATGPT_ARCH_UPDATER_TEST_INSTALLED_VERSION=26.915.31945 CHATGPT_ARCH_UPDATER_TEST_BAD_KEY=1 "$ROOT/bin/chatgpt-arch-updater" --verchk >/dev/null 2>&1
rc=$?
set -e
[[ $rc -eq 2 ]] || { printf 'untrusted OpenAI Arch signing key was not rejected\n' >&2; exit 1; }
set +e
env "${cli_env[@]}" CHATGPT_ARCH_UPDATER_TEST_INSTALLED_VERSION=26.915.31945 CHATGPT_ARCH_UPDATER_TEST_BAD_SIGNATURE=1 "$ROOT/bin/chatgpt-arch-updater" --verchk >/dev/null 2>&1
rc=$?
set -e
[[ $rc -eq 2 ]] || { printf 'invalid OpenAI Arch repository signature was not rejected\n' >&2; exit 1; }
if command -v script >/dev/null 2>&1; then
  sed -i 's/26\.915\.31945-1/26.916.10000-1/' "$tmp/arch-desc"
  export CHATGPT_ARCH_UPDATER_LIBDIR="$ROOT/lib/chatgpt_arch_updater"
  export CHATGPT_ARCH_UPDATER_DATA_DIR="$tmp/menu-data"
  export CHATGPT_ARCH_UPDATER_TEST_SUDO_LOG="$tmp/menu-sudo.log"
  printf '2\n' | script -qec "$ROOT/bin/chatgpt-arch-updater --check" /dev/null >"$tmp/menu.log" 2>&1
  grep -q 'Install the OpenAI Arch package' "$tmp/menu.log" || {
    printf 'manual check did not offer the newer Arch repository package\n' >&2; exit 1;
  }
  grep -qx 'pacman -Syu --needed chatgpt-bin' "$tmp/menu-sudo.log" || {
    printf 'choosing the Arch package did not run its pacman installation path\n' >&2; exit 1;
  }
  sed -i 's/26\.916\.10000-1/26.915.31945-1/' "$tmp/arch-desc"
fi
require_version_tools() { :; }
installed_version() { printf '%s\n' 26.915.31945-1; }
if version_check; then
  printf 'equal installed and upstream versions were reported as different\n' >&2; exit 1
else
  [[ $? -eq 1 ]] || { printf 'equal version check returned the wrong status\n' >&2; exit 1; }
fi
installed_version() { printf '%s\n' 26.903.61454-1; }
version_check >/dev/null || { printf 'new upstream version was not detected\n' >&2; exit 1; }

fetch_upstream_metadata() { UPSTREAM_VERSION=26.915.31945; }
fetch_arch_repository_metadata() { ARCH_REPO_VERSION=26.915.31945; ARCH_REPO_PKG_VERSION=26.915.31945-1; }
installed_arch_repository_version() { printf '26.903.61454-1\n'; }
installed_version() { return 1; }
version_check >/dev/null || { printf 'new Debian version was not detected for the installed Arch package\n' >&2; exit 1; }
fetch_arch_repository_metadata() { ARCH_REPO_VERSION=26.915.31945; ARCH_REPO_PKG_VERSION=26.915.31945-2; }
installed_arch_repository_version() { printf '26.915.31945-1\n'; }
if version_check >/dev/null; then :; else
  printf 'new Arch package release was not detected when upstream app versions matched\n' >&2; exit 1;
fi
fetch_arch_repository_metadata() { ARCH_REPO_VERSION=26.916.10000; ARCH_REPO_PKG_VERSION=26.916.10000-1; }
installed_arch_repository_version() { printf '26.903.61454-1\n'; }
fetch_upstream_metadata() { UPSTREAM_VERSION=26.903.61454; }
notify-send() { return 1; }
check_and_build >/dev/null
grep -qx '26.903.61454-1:26.916.10000-1' "$BASE_DIR/arch-managed-notice" || {
  printf 'an Arch-managed update notice was not recorded\n' >&2; exit 1;
}

systemctl() { printf '%s\n' "$*" >>"$tmp/systemctl.log"; }
XDG_CONFIG_HOME="$tmp/config" set_check_interval 6h >/dev/null
grep -qx 'OnUnitActiveSec=6h' "$tmp/config/systemd/user/chatgpt-arch-updater.timer.d/override.conf"
XDG_CONFIG_HOME="$tmp/config" set_check_interval 1d >/dev/null
grep -qx 'OnCalendar=daily' "$tmp/config/systemd/user/chatgpt-arch-updater.timer.d/override.conf"
if grep -q '^OnUnitActiveSec=[^[:space:]]' "$tmp/config/systemd/user/chatgpt-arch-updater.timer.d/override.conf"; then
  printf 'old hourly override remained after switching to a calendar interval\n' >&2; exit 1
fi

env "${cli_env[@]}" CHATGPT_ARCH_UPDATER_TEST_SYSTEMCTL_LOG="$tmp/cli-systemctl.log" \
  "$ROOT/bin/chatgpt-arch-updater" --time 4h >/dev/null
grep -qx 'OnUnitActiveSec=4h' "$tmp/cli-config/systemd/user/chatgpt-arch-updater.timer.d/override.conf"
grep -q '^--user enable --now chatgpt-arch-updater.timer$' "$tmp/cli-systemctl.log"

mkdir -p "$tmp/bin"
cat >"$tmp/bin/notify-send" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$CHATGPT_ARCH_UPDATER_TEST_NOTIFY_LOG"
printf 'default\n'
EOF
cat >"$tmp/bin/fake-terminal" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >"$CHATGPT_ARCH_UPDATER_TEST_TERMINAL_LOG"
EOF
chmod +x "$tmp/bin/notify-send" "$tmp/bin/fake-terminal"
PATH="$tmp/bin:$PATH" CHATGPT_ARCH_UPDATER_TERMINAL=fake-terminal \
  CHATGPT_ARCH_UPDATER_TEST_NOTIFY_LOG="$tmp/notify.log" \
  CHATGPT_ARCH_UPDATER_TEST_TERMINAL_LOG="$tmp/terminal.log" \
  bash "$ROOT/lib/chatgpt_arch_updater/notification-launch.sh" 26.915.31945
grep -q -- '--action=default=Open help' "$tmp/notify.log"
grep -q -- '--help' "$tmp/terminal.log"

notify-send() { return 1; }
CHATGPT_ARCH_UPDATER_LIBDIR="$tmp/empty-lib" notify_ready 26.915.31945 >/dev/null

cat >"$tmp/bin/chatgpt" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
cat >"$tmp/bin/nohup" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$CHATGPT_ARCH_UPDATER_TEST_LAUNCH_LOG"
EOF
chmod +x "$tmp/bin/chatgpt" "$tmp/bin/nohup"
CHATGPT_ARCH_UPDATER_TEST_LAUNCH_LOG="$tmp/launch.log"
export CHATGPT_ARCH_UPDATER_TEST_LAUNCH_LOG
chatgpt_app_running() { [[ ! -e "$tmp/app-stopped" ]]; }
pkill() { touch "$tmp/app-stopped"; }
printf 'y\n' | PATH="$tmp/bin:$PATH" restart_chatgpt_app >/dev/null 2>&1
for _ in {1..20}; do [[ -e "$tmp/launch.log" ]] && break; sleep 0.05; done
grep -qx chatgpt "$tmp/launch.log" || {
  printf 'accepting the restart prompt did not relaunch ChatGPT\n' >&2; exit 1;
}
rm -f "$tmp/app-stopped" "$tmp/launch.log"
printf 'n\n' | PATH="$tmp/bin:$PATH" restart_chatgpt_app >/dev/null 2>&1
[[ ! -e "$tmp/app-stopped" && ! -e "$tmp/launch.log" ]] || {
  printf 'declining the restart prompt changed the running app\n' >&2; exit 1;
}

pkg_check() {
  BUILT_PACKAGE="$tmp/dist/chatgpt-official-bin-test.pkg.tar.zst"
  BUILT_VERSION=1.0
  printf 'Unrecognized Debian dependency: test-lib\n' >"$BASE_DIR/dependency-discrepancies"
}
sudo() { printf '%s\n' "$*" >>"$tmp/sudo.log"; }
installed_version() { printf '26.903.61454-1\n'; }
installed_arch_repository_version() { return 1; }

if printf 'INSTALL\n' | explicit_install >/dev/null 2>&1; then
  printf 'weak confirmation unexpectedly authorized installation\n' >&2; exit 1
fi
[[ ! -e "$tmp/sudo.log" ]] || { printf 'sudo ran without the required phrase\n' >&2; exit 1; }
printf 'INSTALL UNSAFE\n' | explicit_install >/dev/null 2>&1
grep -qx 'pacman -U -- /.*chatgpt-official-bin-test.pkg.tar.zst' "$tmp/sudo.log" || {
  printf 'exact unsafe confirmation did not invoke pacman -U\n' >&2; exit 1;
}
printf 'SWITCH TO ARCH PACKAGE\n' | install_arch_repository_package >/dev/null 2>&1
grep -qx 'pacman -R -- chatgpt-official-bin' "$tmp/sudo.log" || {
  printf 'switch to the OpenAI Arch package did not remove the local repack\n' >&2; exit 1;
}
grep -qx 'pacman -Syu --needed chatgpt-bin' "$tmp/sudo.log" || {
  printf 'switch to the OpenAI Arch package did not use the full system upgrade\n' >&2; exit 1;
}
installed_arch_repository_version() { printf '26.915.31945-1\n'; }
printf 'INSTALL UNSAFE\nSWITCH TO LOCAL PACKAGE\n\n' | explicit_install >/dev/null 2>&1
grep -qx 'pacman -R -- chatgpt-bin' "$tmp/sudo.log" || {
  printf 'switch to the local Debian repack did not remove the official Arch package\n' >&2; exit 1;
}
printf 'dependency mapping checks passed\n'
