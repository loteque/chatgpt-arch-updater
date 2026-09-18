#!/usr/bin/env bash

ARCH_REPO_BASE_URL='https://persistent.oaistatic.com/codex-app-prod/linux'
ARCH_REPO_PACKAGE='chatgpt-bin'
ARCH_REPO_NAME='openai-chatgpt'
ARCH_REPO_KEY_FINGERPRINT='3BFA0E4AE8B8CC16A2D9BA684A3B4A566C4660E4'
ARCH_REPO_VERSION=''
ARCH_REPO_PKG_VERSION=''

fetch_arch_repository_metadata() {
  local architecture tmp db_url db_path sig_path index_member candidate_version key_path key_fingerprint parsed
  architecture=$(uname -m)
  [[ "$architecture" == x86_64 || "$architecture" == aarch64 ]] || die "unsupported architecture for OpenAI Arch repository: $architecture"
  local tool
  for tool in curl gpg bsdtar; do
    command -v "$tool" >/dev/null 2>&1 || die "required command not found: $tool"
  done

  mkdir -p "$BASE_DIR"
  tmp=$(mktemp -d "${TMPDIR:-/tmp}/chatgpt-arch-updater-repo.XXXXXXXX") || die 'could not create temporary directory for the Arch repository check'
  db_url="$ARCH_REPO_BASE_URL/arch/$architecture/$ARCH_REPO_NAME.db"
  db_path="$tmp/$ARCH_REPO_NAME.db"
  sig_path="$db_path.sig"
  if ! curl --fail --location --silent --show-error --proto '=https' --proto-redir '=https' --tlsv1.2 "$db_url" --output "$db_path" || \
     ! curl --fail --location --silent --show-error --proto '=https' --proto-redir '=https' --tlsv1.2 "$db_url.sig" --output "$sig_path"; then
    rm -rf -- "$tmp"
    die 'could not fetch the live OpenAI Arch repository database and signature'
  fi

  index_member=$(bsdtar -tf "$db_path" 2>/dev/null | awk -v prefix="$ARCH_REPO_PACKAGE-" '$0 ~ ("^" prefix "[^/]+/desc$") { print; count++ } END { if (count != 1) exit 1 }') || {
    rm -rf -- "$tmp"
    die "the OpenAI Arch repository database did not contain exactly one $ARCH_REPO_PACKAGE package entry"
  }
  parsed=$(bsdtar -xOf "$db_path" "$index_member" 2>/dev/null | awk '
    /^%NAME%$/ { if (getline > 0) name = $0 }
    /^%VERSION%$/ { if (getline > 0) version = $0 }
    /^%ARCH%$/ { if (getline > 0) architecture = $0 }
    END { if (name == "" || version == "" || architecture == "") exit 1; printf "%s\t%s\t%s\n", name, version, architecture }
  ') || {
    rm -rf -- "$tmp"
    die 'could not read ChatGPT package metadata from the OpenAI Arch repository database'
  }
  IFS=$'\t' read -r ARCH_REPO_PACKAGE ARCH_REPO_PKG_VERSION architecture <<<"$parsed"
  [[ "$ARCH_REPO_PACKAGE" == chatgpt-bin && "$architecture" == "$(uname -m)" ]] || {
    rm -rf -- "$tmp"
    die 'the OpenAI Arch repository database has unexpected package metadata'
  }
  [[ "$ARCH_REPO_PKG_VERSION" =~ ^[0-9][A-Za-z0-9.+:_~-]*-[0-9][A-Za-z0-9.+_~-]*$ ]] || {
    rm -rf -- "$tmp"
    die 'the OpenAI Arch repository package version has an unexpected format'
  }

  candidate_version=${ARCH_REPO_PKG_VERSION%-*}
  key_path="$tmp/repository-signing-key.gpg"
  if ! curl --fail --location --silent --show-error --proto '=https' --proto-redir '=https' --tlsv1.2 \
    "$ARCH_REPO_BASE_URL/arch/$candidate_version/repository-signing-key.gpg" --output "$key_path"; then
    rm -rf -- "$tmp"
    die 'could not fetch the OpenAI Arch repository signing key'
  fi
  mkdir -m 700 "$tmp/gnupg"
  key_fingerprint=$(gpg --homedir "$tmp/gnupg" --batch --show-keys --with-colons "$key_path" 2>/dev/null | \
    awk -F: '$1 == "pub" { primary=1 } $1 == "sub" { primary=0 } $1 == "fpr" && primary { print toupper($10); primary=0 }') || {
    rm -rf -- "$tmp"
    die 'the OpenAI Arch repository signing key could not be read'
  }
  [[ "$key_fingerprint" == "$ARCH_REPO_KEY_FINGERPRINT" ]] || {
    rm -rf -- "$tmp"
    die 'the OpenAI Arch repository signing-key fingerprint did not match the pinned OpenAI key'
  }
  if ! gpg --homedir "$tmp/gnupg" --batch --no-autostart --import "$key_path" >/dev/null 2>&1 || \
     ! gpg --homedir "$tmp/gnupg" --batch --no-autostart --no-auto-key-retrieve --no-auto-key-import \
       --verify "$sig_path" "$db_path" >/dev/null 2>&1; then
    rm -rf -- "$tmp"
    die 'the OpenAI Arch repository database signature verification failed'
  fi

  ARCH_REPO_VERSION=$candidate_version
  rm -rf -- "$tmp"
}

installed_arch_repository_version() {
  pacman -Q "$ARCH_REPO_PACKAGE" 2>/dev/null | awk '{print $2}' || true
}

notify_arch_managed_update() {
  local installed=$1 latest=$2
  local message="ChatGPT is managed by pacman as $ARCH_REPO_PACKAGE $installed. OpenAI's signed Arch repository has $ARCH_REPO_PACKAGE $latest. Update with: sudo pacman -Syu $ARCH_REPO_PACKAGE"
  local notice_file="$BASE_DIR/arch-managed-notice" notice_key="$installed:$latest"
  [[ -f "$notice_file" && $(cat "$notice_file") == "$notice_key" ]] && return 0
  if [[ ! -t 1 ]] && command -v notify-send >/dev/null 2>&1; then
    notify-send 'ChatGPT is managed by pacman' "$message" || info "$message"
  else
    info "$message"
  fi
  mkdir -p "$BASE_DIR"
  printf '%s\n' "$notice_key" >"$notice_file.part"
  mv -f -- "$notice_file.part" "$notice_file"
}
