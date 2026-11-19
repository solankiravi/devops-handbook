#!/usr/bin/env bash
# Install the local DevOps toolchain on Ubuntu: Git, Docker, Go, kubectl, Podman, kind, and k9s.
set -euo pipefail

KIND_VERSION="v0.33.0"

log() {
  printf '\n==> %s\n' "$*"
}

die() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

if [[ "${EUID}" -eq 0 ]]; then
  die "Run this script as a regular user with sudo access, not as root."
fi

command -v sudo >/dev/null 2>&1 || die "sudo is required."
command -v apt-get >/dev/null 2>&1 || die "This script supports apt-based systems (Ubuntu)."

export DEBIAN_FRONTEND=noninteractive
export PATH="/usr/local/bin:/snap/bin:${PATH}"

log "Updating package index"
sudo apt-get update

log "Installing Git"
sudo apt-get install -y git

log "Installing Docker"
sudo apt-get install -y ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

. /etc/os-release
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu ${VERSION_CODENAME} stable" |
  sudo tee /etc/apt/sources.list.d/docker.list >/dev/null

sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

if command -v systemctl >/dev/null 2>&1; then
  sudo systemctl enable --now docker
fi
sudo usermod -aG docker "${USER}"

log "Installing Go"
command -v snap >/dev/null 2>&1 || die "snap is required to install Go and kubectl."
sudo snap install go --classic

log "Installing kubectl"
sudo snap install kubectl --classic

log "Installing Podman"
sudo apt-get install -y podman

log "Installing kind ${KIND_VERSION}"
kind_tmp="$(mktemp -d)"
trap 'rm -rf "${kind_tmp}"' EXIT
GOBIN="${kind_tmp}" go install "sigs.k8s.io/kind@${KIND_VERSION}"
sudo install -m 0755 "${kind_tmp}/kind" /usr/local/bin/kind
rm -rf "${kind_tmp}"
trap - EXIT

log "Installing k9s"
sudo apt-get install -y wget
k9s_tmp="$(mktemp -d)"
trap 'rm -rf "${k9s_tmp}"' EXIT
wget -O "${k9s_tmp}/k9s_linux_amd64.deb" https://github.com/derailed/k9s/releases/latest/download/k9s_linux_amd64.deb
sudo apt-get install -y "${k9s_tmp}/k9s_linux_amd64.deb"
rm -rf "${k9s_tmp}"
trap - EXIT

log "Installed versions"
git --version
docker --version
go version
kubectl version --client
podman --version
kind version
k9s version

cat <<EOF

Tools are installed.
Log out and back in (or run 'newgrp docker') before using Docker without sudo.
EOF
