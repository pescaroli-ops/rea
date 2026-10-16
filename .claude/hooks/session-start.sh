#!/bin/bash
# Prepares a Claude Code cloud session: submodules, pinned Node/npm, deps, build.
set -euo pipefail

if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

cd "$CLAUDE_PROJECT_DIR"

git submodule update --init --recursive

node_version="$(tr -d '[:space:]v' < .nvmrc)"
npm_version="$(node -p "require('./package.json').packageManager.split('@')[1]" 2>/dev/null || sed -n 's/.*"packageManager": *"npm@\([^"]*\)".*/\1/p' package.json)"
node_dir="/opt/node-v${node_version}"

if [ "$("$node_dir/bin/node" -v 2>/dev/null)" != "v${node_version}" ]; then
  tmp="$(mktemp -d)"
  archive="node-v${node_version}-linux-x64.tar.xz"
  curl -fsSL "https://nodejs.org/dist/v${node_version}/${archive}" -o "$tmp/$archive"
  (cd "$tmp" && curl -fsSL "https://nodejs.org/dist/v${node_version}/SHASUMS256.txt" | grep " ${archive}\$" | sha256sum -c -)
  mkdir -p "$node_dir"
  tar -xJf "$tmp/$archive" -C "$node_dir" --strip-components=1
  rm -rf "$tmp"
fi
export PATH="$node_dir/bin:$PATH"

if [ "$(npm -v)" != "$npm_version" ]; then
  npm install -g "npm@${npm_version}"
fi

if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
  echo "export PATH=\"$node_dir/bin:\$PATH\"" >> "$CLAUDE_ENV_FILE"
fi

npm install --no-audit --no-fund
npm run build:cached
