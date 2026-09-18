# ChatGPT Arch Updater (alpha)

Purpose-built updater for OpenAI's official ChatGPT Debian package. It downloads the `.deb`, inspects its metadata, extracts its payload without root, and builds a local pacman package named `chatgpt-official-bin`.

This project does not translate arbitrary Debian packages. Debian dependencies are compared against a small, explicit mapping table in `lib/chatgpt_arch_updater/dependencies.sh`. Unknown dependencies and Debian/Arch package-name mismatches are shown as discrepancies. They do not prevent building the package. Before installation, the user must review the report and type exactly `INSTALL UNSAFE` if any discrepancy exists.

## Requirements

- Arch Linux, `bash`, `curl`, `dpkg-deb`, `gnupg`, `libarchive`, `makepkg`, `pacman`, `systemctl`, and `notify-send` (notification is best-effort).
- A working pacman package build environment and user-level systemd.
- Internet access to OpenAI's official static package host.

## Install the updater

Build and install the updater package, enable its user timer, and trigger an initial check:

```sh
make install-updater
```

This builds as your user, explicitly installs the updater package with `sudo pacman -U`, enables and starts the user timer, and launches one initial check. The package puts the command at `/usr/bin/chatgpt-arch-updater` and its user units under `/usr/lib/systemd/user`. It does not install ChatGPT. A graphical user session is needed for desktop notifications.

For a user-local install without pacman, `make install-user` remains available and performs the same timer setup.

## Commands

```sh
chatgpt-arch-updater --status
chatgpt-arch-updater --dry-run
chatgpt-arch-updater --verchk
chatgpt-arch-updater --pkgchk
chatgpt-arch-updater --check
chatgpt-arch-updater --install
chatgpt-arch-updater --time 6h
chatgpt-arch-updater --time 1d
chatgpt-arch-updater --time 1w
chatgpt-arch-updater --time 1m
```

`--verchk` fetches OpenAI's Debian package index and the live signed OpenAI Arch repository database, then reports both ChatGPT versions and which is newer. The Arch database signature is verified against OpenAI's pinned repository key before its version is trusted. It exits with status 1 when the installed app is current, status 0 when either source has a newer version, and status 2 on error. `--pkgchk` downloads the versioned Debian package only when a matching built package is not already ready, verifies its SHA256 from the index, reviews dependencies, and builds the Arch package as needed. In a terminal, `--check` reports both versions and offers to cancel, install OpenAI's Arch package, or build the Debian package when their versions differ. The weekly timer runs `--check` without a terminal; it never installs ChatGPT.

`--time Nh` accepts an hourly interval from `1h` through `8760h`; `1d`, `1w`, and `1m` set daily, weekly, and monthly calendar schedules. It writes a user systemd drop-in, enables and restarts the timer, and triggers one immediate check. The default remains weekly. `--status` reports the installed version, last built version, and whether a package is ready. `--dry-run` reports the planned actions without downloading, building, or installing.

`--install` checks for/builds the latest Debian package, displays dependency discrepancies, and asks for confirmation. If the dependency comparison found any discrepancy, only the exact response `INSTALL UNSAFE` authorizes installation. Otherwise, the user must type `INSTALL`. If switching from the official Arch package to the local Debian repack, it displays the removal and install commands and requires the additional phrase `SWITCH TO LOCAL PACKAGE` before invoking pacman.

## Data and safety

Downloads, extracted files, build files, and generated packages live under `${XDG_CACHE_HOME:-$HOME/.cache}/chatgpt-arch-updater`. Build operations run as the invoking user. No service runs as root. Timer checks never invoke sudo.

The updater reads OpenAI's amd64 Debian `Packages` index and fetches the online `openai-chatgpt.db` from OpenAI's Arch repository. It verifies the Arch database signature against OpenAI's pinned signing-key fingerprint, then reads the `chatgpt-bin` version without downloading the app package. It downloads the versioned Debian package only when needed, verifies its SHA256 against the index, and confirms the Debian metadata identifies `chatgpt` at the indexed version before extraction.

When `chatgpt-bin` is installed, automatic checks report that ChatGPT is managed by pacman and that updates are applied with `sudo pacman -Syu chatgpt-bin`. If a newer Debian version is available, the updater follows the existing local build-and-notify flow. When switching an existing local `chatgpt-official-bin` installation to the OpenAI Arch package, the interactive check suggests:

```sh
sudo pacman -R chatgpt-official-bin
sudo pacman -Syu --needed chatgpt-bin
```

When a new package is ready, the notification's **Open help** action opens a terminal and shows `chatgpt-arch-updater --help`. After a successful `--install`, the updater asks whether to restart ChatGPT so the updated version is loaded. Answering yes closes and relaunches a running app, or opens the app if it was not running; the default is no. The notification helper looks for common terminal emulators or uses `CHATGPT_ARCH_UPDATER_TERMINAL`/`TERMINAL` if set. Notification actions depend on desktop notification support; without action support, the updater sends a regular notification.

This is alpha software. Review the package contents and dependency report before installing. Debian dependency version constraints are not translated into pacman version constraints; mapped Arch package names are included as runtime dependencies, and discrepancies are clearly reported.

## Continuous integration and releases

GitHub Actions runs `make check` on every push and pull request, then builds the updater package in an Arch Linux environment and saves it as a workflow artifact. To publish a versioned release, update `pkgver` or `pkgrel` in `packaging/updater/PKGBUILD`, commit the change, create a matching tag in the form `v<pkgver>-<pkgrel>` (for example, `v0.1.0-7`), and push the tag. The workflow verifies that the tag matches the package version and attaches the built `.pkg.tar.zst` to the GitHub release.
