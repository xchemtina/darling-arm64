#!/usr/bin/env bash
# Runs INSIDE the Ubuntu 24.04 aarch64 VM (`darling-ns`).
#
# Prepares the host side of deepai-org's ARM64 Darling "north star" reproduction:
# Docker + git + gh only. Every build dependency lives in their container image
# (arm64v8/ubuntu:24.04, clang + llvm-18), never on this host — that is an
# explicit safety boundary of their guide.
#
# Their requirements: native aarch64, Ubuntu 24.04 reference host, Docker Engine,
# gh authenticated for private repos, >=16GB RAM, >=200GB free workspace,
# no QEMU / no x86 / no Darling LKM / no host-wide Darling install.
set -euo pipefail

log() { printf '\n=== %s ===\n' "$*"; }

log "host preconditions"
echo "arch:  $(uname -m)   (must be aarch64)"
echo "distro: $(. /etc/os-release && echo "$PRETTY_NAME")"
echo "cores: $(nproc)   RAM: $(free -g | awk '/^Mem:/{print $2}')GB"
df -h "$HOME" | tail -1

[ "$(uname -m)" = aarch64 ] || { echo "FATAL: not aarch64"; exit 2; }

log "installing host tooling (docker, git, gh) — NOT build deps"
sudo apt-get update -qq
sudo apt-get install -y --no-install-recommends \
    ca-certificates curl git docker.io

# gh is not in Ubuntu 24.04's default archive; use GitHub's apt repo.
if ! command -v gh >/dev/null; then
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
        | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
    sudo chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
        | sudo tee /etc/apt/sources.list.d/github-cli.list >/dev/null
    sudo apt-get update -qq
    sudo apt-get install -y --no-install-recommends gh
fi

log "enabling docker for this user"
sudo systemctl enable --now docker
sudo usermod -aG docker "$USER" || true

log "versions"
git --version; gh --version | head -1
sudo docker version --format '  server {{.Server.Version}} / {{.Server.Arch}}' 2>/dev/null || sudo docker --version

log "done — next: authenticate gh, then 61-northstar-clone.sh"
