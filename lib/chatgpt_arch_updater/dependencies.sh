#!/usr/bin/env bash

# Deliberately narrow mapping for the official ChatGPT Debian package only.
# Debian alternative groups are considered covered when any alternative maps.
map_debian_dependency() {
  case "$1" in
    libc6) printf '%s' glibc ;;
    libasound2|libasound2t64) printf '%s' alsa-lib ;;
    libatk1.0-0|libatk1.0-0t64) printf '%s' atk ;;
    libatk-bridge2.0-0|libatk-bridge2.0-0t64) printf '%s' at-spi2-core ;;
    libatspi2.0-0|libatspi2.0-0t64) printf '%s' at-spi2-core ;;
    libcairo2) printf '%s' cairo ;;
    libcups2|libcups2t64) printf '%s' libcups ;;
    libdbus-1-3) printf '%s' dbus ;;
    libdrm2) printf '%s' libdrm ;;
    libexpat1) printf '%s' expat ;;
    libgbm1) printf '%s' mesa ;;
    libgcc-s1) printf '%s' gcc-libs ;;
    libstdc++6) printf '%s' gcc-libs ;;
    libgdk-pixbuf-2.0-0) printf '%s' gdk-pixbuf2 ;;
    libglib2.0-0|libglib2.0-0t64) printf '%s' glib2 ;;
    libglib2.0-bin|kde-cli-tools|kde-runtime|trash-cli|gvfs-bin) printf '%s' xdg-utils ;;
    libgtk-3-0|libgtk-3-0t64) printf '%s' gtk3 ;;
    libgl1) printf '%s' libglvnd ;;
    libnotify4) printf '%s' libnotify ;;
    libnspr4) printf '%s' nspr ;;
    libnss3) printf '%s' nss ;;
    libpango-1.0-0) printf '%s' pango ;;
    libssl3) printf '%s' openssl ;;
    libtss2-esys-3.0.2-0|libtss2-mu0|libtss2-mu-4.0.1-0t64|libtss2-tcti-device0) printf '%s' tpm2-tss ;;
    libudev1) printf '%s' systemd-libs ;;
    libusb-1.0-0) printf '%s' libusb ;;
    libx11-6) printf '%s' libx11 ;;
    libx11-xcb1) printf '%s' libx11 ;;
    libxcb1) printf '%s' libxcb ;;
    libxcb-dri3-0) printf '%s' libxcb ;;
    libxcomposite1) printf '%s' libxcomposite ;;
    libxdamage1) printf '%s' libxdamage ;;
    libxext6) printf '%s' libxext ;;
    libxfixes3) printf '%s' libxfixes ;;
    libxkbcommon0) printf '%s' libxkbcommon ;;
    libxrandr2) printf '%s' libxrandr ;;
    libxrender1) printf '%s' libxrender ;;
    libxshmfence1) printf '%s' libxshmfence ;;
    libxss1) printf '%s' libxss ;;
    libxtst6) printf '%s' libxtst ;;
    libxxf86vm1) printf '%s' libxxf86vm ;;
    mesa-vulkan-drivers) printf '%s' mesa ;;
    vulkan-icd) printf '%s' vulkan-icd-loader ;;
    xdg-utils) printf '%s' xdg-utils ;;
    xz-utils) printf '%s' xz ;;
    libgbm-dev|libgtk-4-1|libwebkit2gtk-4.0-37|libappindicator3-1|libayatana-appindicator3-1) ;;
    *) return 1 ;;
  esac
}

dependency_report() {
  local raw=${1:-} group atom name mapped
  local -a dependencies=() mappings=() unknown=() discrepancies=()
  local IFS=,
  read -ra dependencies <<<"$raw"
  for group in "${dependencies[@]}"; do
    group=${group#${group%%[![:space:]]*}}
    group=${group%${group##*[![:space:]]}}
    [[ -z "$group" ]] && continue
    local -a alternatives=()
    IFS='|' read -ra alternatives <<<"$group"
    for atom in "${alternatives[@]}"; do
      atom=${atom%%(*}
      atom=${atom%%:*}
      atom=${atom#${atom%%[![:space:]]*}}
      atom=${atom%${atom##*[![:space:]]}}
      [[ -z "$atom" ]] && continue
      if mapped=$(map_debian_dependency "$atom"); then
        if [[ -n "$mapped" ]]; then
          local found=0 existing
          for existing in "${mappings[@]}"; do [[ "$existing" == "$mapped" ]] && found=1; done
          (( found )) || mappings+=("$mapped")
        else
          discrepancies+=("Known Debian dependency has no Arch package mapping: $atom")
        fi
      else
        unknown+=("$atom")
      fi
    done
    if (( ${#alternatives[@]} > 1 )); then
      discrepancies+=("Debian alternatives need review: $group")
    fi
  done
  for name in "${unknown[@]}"; do discrepancies+=("Unrecognized Debian dependency: $name"); done
  : >"$BASE_DIR/arch-dependencies"
  for mapped in "${mappings[@]}"; do
    printf '%s\n' "$mapped" >>"$BASE_DIR/arch-dependencies"
  done
  printf '%s\n' "${discrepancies[@]:-}" >"$BASE_DIR/dependency-discrepancies"
  if ((${#discrepancies[@]})); then
    printf 'Dependency discrepancies:\n' >&2
    printf '  - %s\n' "${discrepancies[@]}" >&2
    return 1
  fi
  printf 'Mapped Debian dependencies to Arch packages: %s\n' "${mappings[*]:-(none)}"
  return 0
}
