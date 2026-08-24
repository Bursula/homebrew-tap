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
docker run --rm ghcr.io/bursula/bursula:latest --version
```

For reproducible deployments, replace `latest` with a released version such as `0.3.0`. The image supports Linux AMD64 and ARM64.

## Activation and documentation

Bursula requires a valid customer license for configuration and invoice runs. Product documentation is available at [bursula.com](https://bursula.com).

Release tarballs, checksums, and metadata are published on the [Releases page](https://github.com/Bursula/homebrew-tap/releases).
