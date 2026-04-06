#!/usr/bin/env bash

set -euo pipefail

required_cmake_version="3.24"

if ! command -v apt-get >/dev/null 2>&1; then
  echo "error: apt-get was not found; this script supports Ubuntu/Debian systems" >&2
  exit 1
fi

if [[ -r /etc/os-release ]]; then
  # shellcheck disable=SC1091
  source /etc/os-release
  if [[ "${ID:-}" != "ubuntu" && "${ID_LIKE:-}" != *ubuntu* ]]; then
    echo "warning: this script targets Ubuntu, detected: ${PRETTY_NAME:-unknown}" >&2
  fi
fi

if [[ "${EUID}" -eq 0 ]]; then
  sudo_cmd=()
elif command -v sudo >/dev/null 2>&1; then
  sudo_cmd=(sudo)
else
  echo "error: sudo is required when not running as root" >&2
  exit 1
fi

required_packages=(
  build-essential
  cmake
  devscripts
  doxygen
  git
  help2man
  libei-dev
  libglib2.0-dev
  libgmock-dev
  libgtest-dev
  libgtk-3-dev
  libportal-dev
  libssl-dev
  libx11-dev
  libxinerama-dev
  libxkbcommon-dev
  libxkbfile-dev
  libxrandr-dev
  libxtst-dev
  ninja-build
  pkg-config
  qt6-base-dev
  qt6-tools-dev
  xorg-dev
)

# Not required for a basic build, but useful for richer packaging/docs workflows.
optional_packages=(
  graphviz
  qt6-base-dev-tools
  qt6-l10n-tools
  qt6-svg-dev
  qt6-svg-plugins
  qt6-tools-dev-tools
)

echo "==> refreshing apt package index"
"${sudo_cmd[@]}" apt-get update

install_packages=()
missing_required_packages=()
for pkg in "${required_packages[@]}"; do
  if apt-cache show "${pkg}" >/dev/null 2>&1; then
    install_packages+=("${pkg}")
  else
    missing_required_packages+=("${pkg}")
  fi
done

if [[ "${#missing_required_packages[@]}" -gt 0 ]]; then
  echo "error: missing required packages on this Ubuntu release:" >&2
  printf "  - %s\n" "${missing_required_packages[@]}" >&2
  echo "hint: use a newer Ubuntu release with Qt6/libei/libportal development packages." >&2
  exit 1
fi

missing_optional_packages=()
for pkg in "${optional_packages[@]}"; do
  if apt-cache show "${pkg}" >/dev/null 2>&1; then
    install_packages+=("${pkg}")
  else
    missing_optional_packages+=("${pkg}")
  fi
done

echo "==> installing Deskflow build dependencies (${#install_packages[@]} packages)"
"${sudo_cmd[@]}" env DEBIAN_FRONTEND=noninteractive \
  apt-get install -y --no-install-recommends "${install_packages[@]}"

if [[ "${#missing_optional_packages[@]}" -gt 0 ]]; then
  echo "==> optional packages not available on this release (skipped):"
  printf "  - %s\n" "${missing_optional_packages[@]}"
fi

if ! command -v cmake >/dev/null 2>&1; then
  echo "error: cmake is still unavailable after installation" >&2
  exit 1
fi

cmake_version="$(cmake --version | awk 'NR==1 {print $3}')"
if ! dpkg --compare-versions "${cmake_version}" ge "${required_cmake_version}"; then
  echo "error: cmake ${required_cmake_version}+ is required, found ${cmake_version}" >&2
  exit 1
fi

echo "==> dependencies installed successfully"
echo "==> next step: ./scripts/build-deb.sh"
