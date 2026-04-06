#!/usr/bin/env bash

set -euo pipefail

required_cmake_version="3.24"
required_libei_version="1.3"
required_libportal_version="0.9.1"
fallback_libei_version="1.5.0"
fallback_libportal_version="0.9.1"

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

has_package() {
  apt-cache show "$1" >/dev/null 2>&1
}

pkg_mod_version() {
  pkg-config --modversion "$1" 2>/dev/null || true
}

pkg_mod_ge() {
  local module="$1"
  local min_version="$2"
  local current_version
  current_version="$(pkg_mod_version "${module}")"
  [[ -n "${current_version}" ]] && dpkg --compare-versions "${current_version}" ge "${min_version}"
}

resolve_meson_bin() {
  local candidate

  candidate="$(command -v meson || true)"
  if [[ -n "${candidate}" ]] && "${candidate}" --version >/dev/null 2>&1; then
    echo "${candidate}"
    return 0
  fi

  for candidate in /usr/bin/meson /bin/meson; do
    if [[ -x "${candidate}" ]] && "${candidate}" --version >/dev/null 2>&1; then
      echo "${candidate}"
      return 0
    fi
  done

  echo "error: could not find a working meson executable in PATH or /usr/bin" >&2
  exit 1
}

has_libportal_inputcapture_header() {
  if ! pkg-config --exists libportal; then
    return 1
  fi

  printf '#include <libportal/inputcapture.h>\nint main(void){return 0;}\n' | \
    cc -x c - -fsyntax-only $(pkg-config --cflags libportal) >/dev/null 2>&1
}

install_from_source_libei() {
  local tmpdir src_dir build_dir
  local meson_bin
  tmpdir="$(mktemp -d)"
  src_dir="${tmpdir}/libei"
  build_dir="${src_dir}/build"
  meson_bin="$(resolve_meson_bin)"

  echo "==> libei < ${required_libei_version}; installing libei ${fallback_libei_version} from source"
  git clone --depth 1 --branch "${fallback_libei_version}" \
    https://gitlab.freedesktop.org/libinput/libei.git "${src_dir}"

  "${meson_bin}" setup "${build_dir}" "${src_dir}" \
    -Dprefix=/usr/local \
    -Ddocumentation=[] \
    -Dtests=disabled \
    -Dliboeffis=disabled
  "${meson_bin}" compile -C "${build_dir}" -j"$(nproc)"
  "${sudo_cmd[@]}" "${meson_bin}" install -C "${build_dir}"
  "${sudo_cmd[@]}" ldconfig

  rm -rf "${tmpdir}"
}

install_from_source_libportal() {
  local tmpdir src_dir build_dir
  local meson_bin
  tmpdir="$(mktemp -d)"
  src_dir="${tmpdir}/libportal"
  build_dir="${src_dir}/build"
  meson_bin="$(resolve_meson_bin)"

  echo "==> libportal < ${required_libportal_version} or missing inputcapture API; installing libportal ${fallback_libportal_version} from source"
  git clone --depth 1 --branch "${fallback_libportal_version}" \
    https://github.com/flatpak/libportal.git "${src_dir}"

  "${meson_bin}" setup "${build_dir}" "${src_dir}" \
    -Dprefix=/usr/local \
    -Ddocs=false \
    -Dtests=false \
    -Dportal-tests=false \
    -Dintrospection=false \
    -Dvapi=false \
    -Dbackend-gtk3=disabled \
    -Dbackend-gtk4=disabled \
    -Dbackend-qt5=disabled \
    -Dbackend-qt6=disabled
  "${meson_bin}" compile -C "${build_dir}" -j"$(nproc)"
  "${sudo_cmd[@]}" "${meson_bin}" install -C "${build_dir}"
  "${sudo_cmd[@]}" ldconfig

  rm -rf "${tmpdir}"
}

required_packages=(
  build-essential
  ca-certificates
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
  libxkbcommon-x11-dev
  libxkbfile-dev
  libxrandr-dev
  libxtst-dev
  meson
  ninja-build
  pkg-config
  python3
  python3-jinja2
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
  if has_package "${pkg}"; then
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
  if has_package "${pkg}"; then
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

need_libei_source=false
if ! pkg_mod_ge "libei-1.0" "${required_libei_version}"; then
  need_libei_source=true
fi

need_libportal_source=false
if ! pkg_mod_ge "libportal" "${required_libportal_version}" || ! has_libportal_inputcapture_header; then
  need_libportal_source=true
fi

if [[ "${need_libei_source}" == true ]]; then
  install_from_source_libei
fi

if [[ "${need_libportal_source}" == true ]]; then
  install_from_source_libportal
fi

if ! pkg_mod_ge "libei-1.0" "${required_libei_version}"; then
  echo "error: libei ${required_libei_version}+ is required, found: $(pkg_mod_version libei-1.0)" >&2
  exit 1
fi

if ! pkg_mod_ge "libportal" "${required_libportal_version}"; then
  echo "error: libportal ${required_libportal_version}+ is required, found: $(pkg_mod_version libportal)" >&2
  exit 1
fi

if ! has_libportal_inputcapture_header; then
  echo "error: libportal/inputcapture.h was not found after dependency installation" >&2
  exit 1
fi

echo "==> dependencies installed successfully"
echo "==> next step: ./scripts/build-deb.sh"
