#!/usr/bin/env bash

UPSTREAM_BASE_URL="https://persistent.oaistatic.com/codex-app-prod/linux/deb/"
UPSTREAM_INDEX_URL="${UPSTREAM_BASE_URL}dists/stable/main/binary-amd64/Packages"
PACKAGE_NAME="chatgpt-official-bin"
APP_DEB_NAME="chatgpt"
BASE_DIR="${CHATGPT_ARCH_UPDATER_DATA_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/chatgpt-arch-updater}"
WORK_DIR="$BASE_DIR/work"
DIST_DIR="$BASE_DIR/dist"
STATE_FILE="$BASE_DIR/state"
UPSTREAM_INDEX="$BASE_DIR/Packages-amd64"
LATEST_DEB=""

die() { printf 'error: %s\n' "$*" >&2; exit 2; }
info() { printf '%s\n' "$*"; }

require_version_tools() {
  local tool
  for tool in curl pacman gpg bsdtar; do
    command -v "$tool" >/dev/null 2>&1 || die "required command not found: $tool"
  done
  [[ $(uname -m) == x86_64 ]] || die "alpha currently supports x86_64 only (found $(uname -m))"
}

require_package_tools() {
  local tool
  for tool in curl dpkg dpkg-deb makepkg pacman sha256sum vercmp; do
    command -v "$tool" >/dev/null 2>&1 || die "required command not found: $tool"
  done
  [[ $(uname -m) == x86_64 ]] || die "alpha currently supports x86_64 only (found $(uname -m))"
}

fetch_upstream_metadata() {
  mkdir -p "$BASE_DIR"
  local tmp="$UPSTREAM_INDEX.part" fields
  rm -f -- "$tmp"
  curl --fail --location --silent --show-error --proto '=https' --proto-redir '=https' --tlsv1.2 \
    "$UPSTREAM_INDEX_URL" --output "$tmp" || { rm -f -- "$tmp"; die 'could not fetch OpenAI package index'; }
  fields=$(awk -v RS='' -v FS='\n' -v wanted="$APP_DEB_NAME" '
    {
      package = version = architecture = filename = sha256 = ""
      for (i = 1; i <= NF; i++) {
        line = $i
        if (index(line, "Package: ") == 1) package = substr(line, 10)
        else if (index(line, "Version: ") == 1) version = substr(line, 10)
        else if (index(line, "Architecture: ") == 1) architecture = substr(line, 15)
        else if (index(line, "Filename: ") == 1) filename = substr(line, 11)
        else if (index(line, "SHA256: ") == 1) sha256 = substr(line, 9)
      }
      if (package == wanted && architecture == "amd64") {
        printf "%s\t%s\t%s\n", version, filename, sha256
        found++
      }
    }
    END { if (found != 1) exit 1 }
  ' "$tmp") || { rm -f -- "$tmp"; die 'package index did not contain exactly one amd64 ChatGPT entry'; }
  mv -f -- "$tmp" "$UPSTREAM_INDEX"
  IFS=$'\t' read -r UPSTREAM_VERSION UPSTREAM_FILENAME UPSTREAM_SHA256 <<<"$fields"
  [[ "$UPSTREAM_VERSION" =~ ^[A-Za-z0-9.+:~_-]+$ ]] || die 'upstream version contains unexpected characters'
  [[ "$UPSTREAM_FILENAME" == "pool/main/c/chatgpt/chatgpt_${UPSTREAM_VERSION}_amd64.deb" ]] || die 'unexpected Debian package filename in package index'
  [[ "$UPSTREAM_SHA256" =~ ^[[:xdigit:]]{64}$ ]] || die 'package index has an invalid SHA256 checksum'
}

read_deb_metadata() {
  local control
  control=$(dpkg-deb --field "$LATEST_DEB" 2>/dev/null) || die 'cannot read Debian package metadata'
  DEB_PACKAGE=$(awk -F': ' '$1 == "Package" {print $2; exit}' <<<"$control")
  DEB_VERSION=$(awk -F': ' '$1 == "Version" {print $2; exit}' <<<"$control")
  DEB_ARCH=$(awk -F': ' '$1 == "Architecture" {print $2; exit}' <<<"$control")
  DEB_DEPENDS=$(dpkg-deb --field "$LATEST_DEB" Depends 2>/dev/null || true)
  [[ "$DEB_PACKAGE" == "$APP_DEB_NAME" ]] || die "unexpected Debian package name '$DEB_PACKAGE' (expected '$APP_DEB_NAME')"
  [[ -n "$DEB_VERSION" ]] || die 'Debian package has no version field'
  [[ "$DEB_ARCH" == amd64 ]] || die "unsupported Debian architecture '$DEB_ARCH'"
}

version_greater() {
  local incoming installed_pkgver
  incoming=$(normalize_upstream_version "$1")
  installed_pkgver=${2%-*}
  [[ $(vercmp "$incoming" "$installed_pkgver") -gt 0 ]]
}

package_version_greater() {
  [[ $(vercmp "$1" "$2") -gt 0 ]]
}

normalize_upstream_version() {
  printf '%s' "$1" | sed 's/[^A-Za-z0-9.+_]/./g'
}

installed_pkgver() {
  local version
  version=$(installed_arch_repository_version)
  [[ -n "$version" ]] || version=$(installed_version)
  [[ -n "$version" ]] || return 1
  printf '%s' "${version%-*}"
}

report_version_comparison() {
  local custom official
  custom=$(installed_version || true)
  official=$(installed_arch_repository_version || true)
  printf 'Latest OpenAI Debian package: %s\n' "$UPSTREAM_VERSION"
  printf 'Latest OpenAI Arch repository package (%s): %s\n' "$ARCH_REPO_PACKAGE" "$ARCH_REPO_PKG_VERSION"
  if [[ -n "$official" ]]; then
    printf 'Installed app package: %s %s (pacman-managed)\n' "$ARCH_REPO_PACKAGE" "$official"
  elif [[ -n "$custom" ]]; then
    printf 'Installed app package: %s %s (locally repackaged)\n' "$PACKAGE_NAME" "$custom"
  else
    printf 'Installed app package: none detected\n'
  fi
  if version_greater "$ARCH_REPO_VERSION" "$UPSTREAM_VERSION"; then
    printf 'Newest published version: OpenAI Arch repository (%s)\n' "$ARCH_REPO_PKG_VERSION"
  elif version_greater "$UPSTREAM_VERSION" "$ARCH_REPO_VERSION"; then
    printf 'Newest published version: OpenAI Debian package (%s)\n' "$UPSTREAM_VERSION"
  else
    printf 'Newest published version: same upstream version in both repositories\n'
  fi
}

version_check() {
  require_version_tools
  fetch_upstream_metadata
  fetch_arch_repository_metadata
  report_version_comparison
  local installed_arch installed_custom installed
  installed_arch=$(installed_arch_repository_version || true)
  installed_custom=$(installed_version || true)
  if [[ -n "$installed_arch" ]]; then
    installed=$installed_arch
  else
    installed=$installed_custom
  fi
  if [[ -n "$installed" ]]; then
    if version_greater "$UPSTREAM_VERSION" "$installed"; then
      info "The Debian package is newer than the installed app ($installed)."
      return 0
    fi
    if [[ -n "$installed_arch" ]] && package_version_greater "$ARCH_REPO_PKG_VERSION" "$installed_arch"; then
      info "An update is available for the installed pacman-managed app."
      return 0
    fi
    if [[ -n "$installed_custom" ]] && package_version_greater "$ARCH_REPO_PKG_VERSION" "$installed_custom"; then
      info "The OpenAI Arch repository has a newer ChatGPT package."
      return 0
    fi
    info "Installed ChatGPT version $installed is current or newer."
    return 1
  fi
  info 'No ChatGPT package is installed; the Debian build is available if you want to install it.'
  return 0
}

verify_deb_checksum() {
  local file=$1 expected=$2
  printf '%s  %s\n' "$expected" "$file" | sha256sum --check --status
}

installed_version() {
  pacman -Q "$PACKAGE_NAME" 2>/dev/null | awk '{print $2}' || true
}

notify_ready() {
  local version=$1
  if command -v notify-send >/dev/null 2>&1; then
    local libdir=${CHATGPT_ARCH_UPDATER_LIBDIR:-/usr/lib/chatgpt-arch-updater}
    if command -v systemd-run >/dev/null 2>&1 && [[ -f "$libdir/notification-launch.sh" ]] && \
       systemd-run --user --quiet --collect \
         --unit="chatgpt-arch-updater-notify-${BASHPID}-${RANDOM}" \
         --setenv="CHATGPT_ARCH_UPDATER_LIBDIR=$libdir" \
         bash "$libdir/notification-launch.sh" "$version"; then
      return 0
    fi
    if notify-send 'ChatGPT package ready' "chatgpt-official-bin $version is built. Run chatgpt-arch-updater --install to review and install it."; then
      return 0
    fi
    info "ChatGPT package $version is ready. Run chatgpt-arch-updater --install to review and install it."
  else
    info "ChatGPT package $version is ready. Run chatgpt-arch-updater --install to review and install it."
  fi
  return 0
}
