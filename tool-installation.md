# Setup

Install the handbook toolchain on Ubuntu with `tool-installation.sh`.

The script installs:

| Tool | How it is installed |
| --- | --- |
| Git | `apt` |
| Docker Engine, Buildx, and Compose | Docker’s official apt repository |
| Go | `snap` (classic confinement) |
| kubectl | `snap` (classic confinement) |
| Podman | `apt` |
| kind v0.33.0 | `go install`, then copied to `/usr/local/bin` |
| k9s | GitHub `.deb` for `linux_amd64`, installed with `apt` |

## Prerequisites

- Ubuntu with `apt` and `snap`
- A user account that can use `sudo`
- Network access to Ubuntu, Docker, Snap, and Go module downloads

Run the script as that user. Do not run it as root. The script calls `sudo` for the steps that need it.

## Install

```bash
chmod +x tool-installation.sh
./tool-installation.sh
```

Re-running the script is safe. Package installs and the Docker apt source are written again, and `kind` is replaced at `/usr/local/bin/kind`.

## After installation

The script adds your user to the `docker` group. Group membership applies to new login sessions. Log out and back in, or run:

```bash
newgrp docker
```

`go` and `kubectl` from snap are on `/snap/bin`, which is already on the default Ubuntu `PATH`.

## Verify

```bash
git --version
docker --version
docker compose version
go version
kubectl version --client
podman --version
kind version
k9s version
```

`docker version` should succeed without `sudo` after the new login session.
