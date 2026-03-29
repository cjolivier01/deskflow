#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
build_dir="${BUILD_DIR:-${repo_root}/build-deb}"
generator="${CMAKE_GENERATOR:-Ninja}"
install_prefix="${CMAKE_INSTALL_PREFIX:-/usr}"
jobs="${JOBS:-$(nproc)}"

if ! command -v cmake >/dev/null 2>&1; then
  echo "error: cmake is required but was not found in PATH" >&2
  exit 1
fi

if [[ "${generator}" == "Ninja" ]] && ! command -v ninja >/dev/null 2>&1; then
  echo "error: Ninja generator requested but ninja is not installed" >&2
  exit 1
fi

echo "==> cleaning build directory: ${build_dir}"
rm -rf "${build_dir}"

echo "==> configuring CMake"
cmake \
  -S "${repo_root}" \
  -B "${build_dir}" \
  -G "${generator}" \
  -DBUILD_INSTALLER=ON \
  -DCMAKE_INSTALL_PREFIX="${install_prefix}"

echo "==> building package target"
cmake --build "${build_dir}" -j"${jobs}" --target package

mapfile -t debs < <(find "${build_dir}" -maxdepth 1 -type f -name "*.deb" | sort)
if [[ "${#debs[@]}" -eq 0 ]]; then
  echo "error: package target completed, but no .deb file was found in ${build_dir}" >&2
  exit 1
fi

deb="${debs[$((${#debs[@]} - 1))]}"

echo "==> package built: ${deb}"
echo "==> install command:"
echo "sudo apt install -y \"${deb}\""
