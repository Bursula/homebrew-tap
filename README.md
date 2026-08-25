# Bursula distribution

This repository is the public distribution point for the Bursula CLI. The application source is maintained separately.

## Homebrew

Install Bursula on macOS with:

```bash
brew install bursula/tap/bursula
bursula --version
bursula doctor
```

Homebrew installs the released npm package and builds its native SQLite dependency for the local Node.js runtime.

## Docker

Run the multi-platform Linux image with:

```bash
docker run --rm ghcr.io/bursula/bursula:latest
docker run --rm ghcr.io/bursula/bursula:latest --version
```

Without a command, the image prints state-aware setup or operating guidance and does not start an invoice run. For reproducible deployments, replace `latest` with a released version such as `0.3.5`. The image supports Linux AMD64 and ARM64.

For Docker on a laptop or desktop, export the version-matched Compose file, Chromium seccomp profile, example environment, and setup instructions directly from the image:

```bash
docker run --rm ghcr.io/bursula/bursula:0.3.5 deployment export | tar -x && ./bursula/install.sh
```

The installer prepares the deployment without starting setup, then prints the short `./bursula setup`, `status`, `run`, and `doctor` commands.

For Synology DSM, Kubernetes, NAS, server, or another container environment, review the full deployment documentation before starting.

For Synology DSM and unattended Docker installations, use the checked-in [Compose file](./compose.yaml), [Chromium seccomp profile](./docker/seccomp_profile.json), and [DSM setup guide](./docs/synology-dsm.md).

## Activation and documentation

Bursula requires a valid customer license for configuration and invoice runs. Product documentation is available at [bursula.com](https://bursula.com).

Release tarballs, checksums, and metadata are published on the [Releases page](https://github.com/Bursula/homebrew-tap/releases).
