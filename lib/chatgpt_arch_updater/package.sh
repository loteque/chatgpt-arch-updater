#!/usr/bin/env bash

build_package() {
  local build_dir="$WORK_DIR/build"
  rm -rf -- "$build_dir"
  mkdir -p "$build_dir/src/payload"
  read_deb_metadata
  dpkg-deb --extract "$LATEST_DEB" "$build_dir/src/payload"
  local escaped_version
  escaped_version=$(normalize_upstream_version "$DEB_VERSION")
  local dependencies
  dependencies=$(cat "$BASE_DIR/arch-dependencies" 2>/dev/null || true)
  cat >"$build_dir/PKGBUILD" <<EOF
pkgname=$PACKAGE_NAME
pkgver=$escaped_version
pkgrel=1
pkgdesc='Official ChatGPT desktop app by OpenAI, repackaged from its Debian package'
arch=('x86_64')
url='https://chatgpt.com/'
license=('custom')
depends=($(while IFS= read -r dep; do [[ -n "$dep" ]] && printf "'%s' " "$dep"; done <<<"$dependencies"))
options=('!strip')
package() {
  install -d "\$pkgdir"
  cp -a --no-preserve=ownership "\$srcdir/payload/." "\$pkgdir/"
  install -Dm644 "\$srcdir/payload/usr/share/doc/chatgpt/copyright" "\$pkgdir/usr/share/licenses/$PACKAGE_NAME/LICENSE" 2>/dev/null || true
}
EOF
  (cd "$build_dir" && makepkg --nodeps --force --noconfirm)
  mkdir -p "$DIST_DIR"
  local built
  built=$(find "$build_dir" -maxdepth 1 -type f -name "$PACKAGE_NAME-*.pkg.tar.*" -print -quit)
  [[ -n "$built" ]] || die 'makepkg did not produce a package'
  mv -f -- "$built" "$DIST_DIR/"
  printf '%s\n%s\n' "$DEB_VERSION" "$UPSTREAM_SHA256" >"$STATE_FILE.part"
  mv -f -- "$STATE_FILE.part" "$STATE_FILE"
  BUILT_PACKAGE="$DIST_DIR/$(basename "$built")"
  BUILT_VERSION="$DEB_VERSION"
  BUILT_NEW=1
}

download_indexed_deb() {
  require_package_tools
  [[ -n "${UPSTREAM_VERSION:-}" ]] || fetch_upstream_metadata
  LATEST_DEB="$BASE_DIR/chatgpt-latest.deb"
  mkdir -p "$BASE_DIR"
  if [[ -f "$LATEST_DEB" ]] && verify_deb_checksum "$LATEST_DEB" "$UPSTREAM_SHA256"; then
    return 0
  fi
  local tmp="$LATEST_DEB.part"
  rm -f -- "$tmp"
  curl --fail --location --silent --show-error --proto '=https' --proto-redir '=https' --tlsv1.2 \
    "${UPSTREAM_BASE_URL}${UPSTREAM_FILENAME}" --output "$tmp" || {
      rm -f -- "$tmp"
      die 'download of the versioned ChatGPT Debian package failed'
    }
  verify_deb_checksum "$tmp" "$UPSTREAM_SHA256" || {
    rm -f -- "$tmp"
    die 'downloaded Debian package did not match the SHA256 from OpenAI package index'
  }
  dpkg-deb --info "$tmp" >/dev/null 2>&1 || {
    rm -f -- "$tmp"
    die 'download is not a valid Debian package'
  }
  mv -f -- "$tmp" "$LATEST_DEB"
}

read_deb_metadata() {
  local control
  control=$(dpkg-deb --field "$LATEST_DEB" 2>/dev/null) || die 'cannot read Debian package metadata'
  DEB_PACKAGE=$(awk -F': ' '$1 == "Package" {print $2; exit}' <<<"$control")
  DEB_VERSION=$(awk -F': ' '$1 == "Version" {print $2; exit}' <<<"$control")
  DEB_ARCH=$(awk -F': ' '$1 == "Architecture" {print $2; exit}' <<<"$control")
  DEB_DEPENDS=$(dpkg-deb --field "$LATEST_DEB" Depends 2>/dev/null || true)
  [[ "$DEB_PACKAGE" == "$APP_DEB_NAME" ]] || die "unexpected Debian package name '$DEB_PACKAGE' (expected '$APP_DEB_NAME')"
  [[ "$DEB_VERSION" == "$UPSTREAM_VERSION" ]] || die 'Debian package version did not match the OpenAI package index'
  [[ "$DEB_ARCH" == amd64 ]] || die "unsupported Debian architecture '$DEB_ARCH'"
}

find_built_package() {
  local version=$1
  local package_version
  package_version=$(normalize_upstream_version "$version")
  find "$DIST_DIR" -maxdepth 1 -type f \
    -name "$PACKAGE_NAME-${package_version}-*.pkg.tar.*" -print -quit 2>/dev/null || true
}

pkg_check() {
  require_package_tools
  [[ -n "${UPSTREAM_VERSION:-}" ]] || fetch_upstream_metadata
  local installed_arch
  installed_arch=$(installed_arch_repository_version || true)
  if [[ -n "$installed_arch" ]]; then
    [[ -n "${ARCH_REPO_VERSION:-}" ]] || fetch_arch_repository_metadata
    if ! version_greater "$UPSTREAM_VERSION" "$installed_arch"; then
      info "ChatGPT is managed by pacman as $ARCH_REPO_PACKAGE $installed_arch; the Debian package is not newer."
      BUILT_PACKAGE=
      return 0
    fi
  fi
  mkdir -p "$DIST_DIR"

  local built state_version state_sha installed
  built=$(find_built_package "$UPSTREAM_VERSION")
  if [[ -n "$built" && -f "$STATE_FILE" ]]; then
    state_version=$(sed -n '1p' "$STATE_FILE")
    state_sha=$(sed -n '2p' "$STATE_FILE")
    if [[ "$state_version" == "$UPSTREAM_VERSION" && "$state_sha" == "$UPSTREAM_SHA256" ]]; then
      BUILT_PACKAGE=$built
      BUILT_VERSION=$UPSTREAM_VERSION
      BUILT_NEW=0
      info "$PACKAGE_NAME $UPSTREAM_VERSION is already built at $BUILT_PACKAGE"
      return 0
    fi
  fi

  download_indexed_deb
  read_deb_metadata
  dependency_report "$DEB_DEPENDS" || true
  installed=$(installed_version || true)
  if [[ -n "$installed" ]] && ! version_greater "$UPSTREAM_VERSION" "$installed"; then
    info "Installed version $installed is current or newer (upstream: $UPSTREAM_VERSION)."
    BUILT_PACKAGE=
    return 0
  fi

  build_package
  info "Built $PACKAGE_NAME $BUILT_VERSION at $BUILT_PACKAGE"
  notify_ready "$BUILT_VERSION"
}

check_and_build() {
  local result=0 installed_arch installed_custom
  version_check || result=$?
  if (( result != 0 && result != 1 )); then
    return "$result"
  fi

  installed_arch=$(installed_arch_repository_version || true)
  installed_custom=$(installed_version || true)

  local arch_newer=0 deb_newer=0 arch_package_newer=0
  version_greater "$ARCH_REPO_VERSION" "$UPSTREAM_VERSION" && arch_newer=1
  version_greater "$UPSTREAM_VERSION" "$ARCH_REPO_VERSION" && deb_newer=1
  if [[ -n "$installed_arch" ]] && package_version_greater "$ARCH_REPO_PKG_VERSION" "$installed_arch"; then
    arch_package_newer=1
  elif [[ -n "$installed_custom" ]] && package_version_greater "$ARCH_REPO_PKG_VERSION" "$installed_custom"; then
    arch_package_newer=1
  fi
  if [[ -t 0 ]] && (( arch_newer || deb_newer || arch_package_newer )); then
    printf '\nOpenAI has two package builds available. Choose one:\n' >&2
    printf '  1) Cancel\n  2) Install the OpenAI Arch package (%s)\n  3) Build the Debian package (%s) instead\n' \
      "$ARCH_REPO_PKG_VERSION" "$UPSTREAM_VERSION" >&2
    printf 'Choice [1-3, default 1]: ' >&2
    local choice
    IFS= read -r choice || choice=
    case "$choice" in
      2) install_arch_repository_package; return $? ;;
      3) pkg_check; return $? ;;
      *) info 'Check cancelled; no package was installed or built.'; return 0 ;;
    esac
  fi

  if (( result == 1 )); then
    if [[ -n "$installed_arch" ]]; then
      notify_arch_managed_update "$installed_arch" "$ARCH_REPO_PKG_VERSION"
    fi
    return 0
  fi

  if [[ -n "$installed_arch" ]]; then
    if version_greater "$UPSTREAM_VERSION" "$installed_arch"; then
      pkg_check
    elif package_version_greater "$ARCH_REPO_PKG_VERSION" "$installed_arch"; then
      notify_arch_managed_update "$installed_arch" "$ARCH_REPO_PKG_VERSION"
    else
      notify_arch_managed_update "$installed_arch" "$ARCH_REPO_PKG_VERSION"
    fi
    return $?
  fi

  if [[ -n "$installed_custom" ]] && ! version_greater "$UPSTREAM_VERSION" "$installed_custom"; then
    if package_version_greater "$ARCH_REPO_PKG_VERSION" "$installed_custom"; then
      info "The official OpenAI Arch package ($ARCH_REPO_PKG_VERSION) is newer. Run chatgpt-arch-updater --check in a terminal to choose a package."
    else
      info "Installed version $installed_custom is current or newer."
    fi
    return 0
  fi

  pkg_check
}

show_status() {
  local installed official state ready
  installed=$(installed_version || true)
  official=$(installed_arch_repository_version || true)
  state=$(cat "$STATE_FILE" 2>/dev/null || printf 'unknown')
  ready=$(find "$DIST_DIR" -maxdepth 1 -type f -name "$PACKAGE_NAME-*.pkg.tar.*" -printf '%f\n' 2>/dev/null | sort -V | tail -n1 || true)
  if [[ -n "$official" ]]; then
    printf 'Installed: %s %s (pacman-managed)\n' "$ARCH_REPO_PACKAGE" "$official"
  else
    printf 'Installed: %s\n' "${installed:-no}"
  fi
  printf 'Last built upstream version: %s\n' "$state"
  printf 'Package ready: %s\n' "${ready:-no}"
}

do_dry_run() {
  printf "Dry run: would fetch OpenAI's Debian package index and signed Arch repository database\n"
  printf 'Dry run: if the Debian version is newer than the installed app, would download and validate the Debian package, inspect dependencies, and build %s\n' "$PACKAGE_NAME"
  printf 'Dry run: installation would require --install and an explicit confirmation\n'
}

explicit_install() {
  pkg_check
  [[ -n "${BUILT_PACKAGE:-}" ]] || { info 'Nothing to install.'; return 0; }
  local discrepancies
  discrepancies=$(cat "$BASE_DIR/dependency-discrepancies" 2>/dev/null || true)
  if [[ -n "${discrepancies//[$'\n\t ']/}" ]]; then
    printf '\nReview these dependency discrepancies before continuing:\n' >&2
    sed 's/^/  - /' "$BASE_DIR/dependency-discrepancies" >&2
    printf '\nThis package includes upstream Debian binaries and unknown dependency mappings may prevent it from running.\n' >&2
    printf 'Type INSTALL UNSAFE to proceed: ' >&2
    local answer
    IFS= read -r answer || return 1
    [[ "$answer" == 'INSTALL UNSAFE' ]] || { info 'Installation cancelled.'; return 1; }
  else
    printf 'Type INSTALL to install %s: ' "$PACKAGE_NAME" >&2
    local answer
    IFS= read -r answer || return 1
    [[ "$answer" == INSTALL ]] || { info 'Installation cancelled.'; return 1; }
  fi
  local installed_arch
  installed_arch=$(installed_arch_repository_version || true)
  if [[ -n "$installed_arch" ]]; then
    printf '\nThe OpenAI Arch package %s is installed and owns the app files. To switch to the locally built Debian package, remove it first:\n' "$installed_arch" >&2
    printf '  sudo pacman -R %s\n  sudo pacman -U %q\n' "$ARCH_REPO_PACKAGE" "$BUILT_PACKAGE" >&2
    printf 'Type SWITCH TO LOCAL PACKAGE to continue: ' >&2
    local switch_answer
    IFS= read -r switch_answer || return 1
    [[ "$switch_answer" == 'SWITCH TO LOCAL PACKAGE' ]] || { info 'Package switch cancelled.'; return 1; }
    sudo pacman -R -- "$ARCH_REPO_PACKAGE" || return $?
  fi
  sudo pacman -U -- "$BUILT_PACKAGE" || return $?
  restart_chatgpt_app
}

install_arch_repository_package() {
  local installed_custom
  installed_custom=$(installed_version || true)
  if [[ -n "$installed_custom" ]]; then
    printf '\nThe locally repackaged package %s %s is installed. Switch to OpenAI’s signed Arch package with:\n' \
      "$PACKAGE_NAME" "$installed_custom" >&2
    printf '  sudo pacman -R %s\n  sudo pacman -Syu --needed %s\n' "$PACKAGE_NAME" "$ARCH_REPO_PACKAGE" >&2
    printf 'Type SWITCH TO ARCH PACKAGE to continue: ' >&2
    local answer
    IFS= read -r answer || return 1
    [[ "$answer" == 'SWITCH TO ARCH PACKAGE' ]] || { info 'Package switch cancelled.'; return 1; }
    sudo pacman -R -- "$PACKAGE_NAME" || return $?
  fi
  sudo pacman -Syu --needed "$ARCH_REPO_PACKAGE" || return $?
  restart_chatgpt_app
}

chatgpt_app_running() {
  pgrep -u "$(id -u)" -x ChatGPT >/dev/null 2>&1
}

restart_chatgpt_app() {
  local was_running=0
  chatgpt_app_running && was_running=1
  printf 'Restart ChatGPT now? [y/N]: ' >&2
  local answer
  IFS= read -r answer || answer=
  case "$answer" in
    y|Y) ;;
    *) info 'Leaving ChatGPT unchanged.'; return 0 ;;
  esac

  if (( was_running )); then
    pkill -TERM -u "$(id -u)" -x ChatGPT || {
      info 'Could not stop ChatGPT. Restart it manually to load the update.' >&2
      return 0
    }
    local attempt
    for ((attempt = 0; attempt < 100; attempt++)); do
      chatgpt_app_running || break
      sleep 0.1
    done
    if chatgpt_app_running; then
      info 'ChatGPT did not exit; restart it manually to load the update.' >&2
      return 0
    fi
  fi
  if ! command -v chatgpt >/dev/null 2>&1; then
    info 'The chatgpt launcher was not found; start the app manually to load the update.' >&2
    return 0
  fi
  nohup chatgpt >/dev/null 2>&1 </dev/null &
  if (( was_running )); then
    info 'Restarted ChatGPT with the updated package.'
  else
    info 'Opened ChatGPT with the updated package.'
  fi
}
