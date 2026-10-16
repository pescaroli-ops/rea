#!/bin/bash
# Installs the free analysis providers REA can use on Linux x64, pinned to the
# versions and digests the repository verifies. Idempotent.
set -euo pipefail

tools=/opt/rea-tools
mkdir -p "$tools"

fetch_verified() { # url sha256 destination
  local tmp
  tmp="$(mktemp)"
  curl -fsSL --retry 3 "$1" -o "$tmp"
  echo "$2  $tmp" | sha256sum -c - >/dev/null
  mv "$tmp" "$3"
}

packages=()
command -v tshark >/dev/null || packages+=(tshark)
command -v sigrok-cli >/dev/null || packages+=(sigrok-cli)
command -v adb >/dev/null || packages+=(adb)
command -v apktool >/dev/null || packages+=(apktool)
command -v javac >/dev/null || packages+=(openjdk-21-jdk)
if [ "${#packages[@]}" -gt 0 ]; then
  apt-get update -qq
  DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "${packages[@]}" >/dev/null
fi

ghidra_dir=/opt/ghidra/ghidra_12.1.4_PUBLIC
if [ ! -x "$ghidra_dir/support/analyzeHeadless" ]; then
  zip="$(mktemp --suffix=.zip)"
  fetch_verified https://github.com/NationalSecurityAgency/ghidra/releases/download/Ghidra_12.1.4_build/ghidra_12.1.4_PUBLIC_20260921.zip \
    ddac49f903da9d5bac833e5cc79395098b9c33cfd3279be5f31bd00387d2d4db "$zip"
  mkdir -p /opt/ghidra
  python3 -I -m zipfile -e "$zip" /opt/ghidra/
  rm -f "$zip"
  chmod +x "$ghidra_dir/ghidraRun" "$ghidra_dir"/support/* "$ghidra_dir"/Ghidra/Features/*/os/linux_x86_64/*
fi

jadx_jar="$tools/jadx/jadx-headless-mcp-0.7.1-all.jar"
if [ ! -f "$jadx_jar" ]; then
  mkdir -p "$tools/jadx"
  fetch_verified https://github.com/1013503897/jadx-headless-mcp/releases/download/v0.7.1/jadx-headless-mcp-0.7.1-all.jar \
    6e5eacf500b64292bfb73c49797c1958f6ee44646e43e868039ae7feb573ff75 "$jadx_jar"
fi

wakaru="$tools/wakaru/wakaru"
if [ ! -x "$wakaru" ]; then
  mkdir -p "$tools/wakaru"
  curl -fsSL --retry 3 https://github.com/pionxzh/wakaru/releases/download/v1.14.0/wakaru-linux-x64.tar.gz |
    tar -xzf - -C "$tools/wakaru" wakaru
  if ! echo "664fa06782a61eda7ed15885134b52525fd565dd77607e642062ceb6cd927c38  $wakaru" | sha256sum -c - >/dev/null; then
    rm -f "$wakaru"
    exit 1
  fi
fi

install_venv() { # name requirement...
  local venv="$tools/venv-$1"
  shift
  if ! "$venv/bin/pip" show "${1%%==*}" >/dev/null 2>&1; then
    python3 -m venv "$venv"
    "$venv/bin/pip" install -q "$@"
  fi
}
install_venv pwntools 'pwntools==4.15.0' 'pyelftools==0.33' 'unicorn==2.1.2'
install_venv unblob 'unblob==26.6.4'
install_venv mitmproxy 'mitmproxy==12.2.3'

if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
  cat >> "$CLAUDE_ENV_FILE" <<ENV
export GHIDRA_INSTALL_DIR="$ghidra_dir"
export JAVA_HOME="$(dirname "$(dirname "$(readlink -f "$(command -v javac)")")")"
export REA_JADX_MCP_JAR="$jadx_jar"
export REA_WAKARU_COMMAND="$wakaru"
export REA_PWNTOOLS_PYTHON="$tools/venv-pwntools/bin/python"
export REA_UNBLOB_COMMAND="$tools/venv-unblob/bin/unblob"
export REA_MITMDUMP_COMMAND="$tools/venv-mitmproxy/bin/mitmdump"
ENV
fi
