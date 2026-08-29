# Docker and Synology DSM

The official Bursula image is the supported Docker runtime. It contains Chromium, Xvfb, and an opt-in web setup with an embedded noVNC browser and is published for Linux AMD64 and ARM64.

Normal runs do not expose a browser port. Chromium remains headed but draws to the virtual Xvfb display. noVNC is enabled only while a human completes login, MFA, consent, or reauthentication.

## Export the matching deployment files

For Docker Desktop on a laptop or desktop, export the Compose file, Chromium seccomp profile, example environment, and concise instructions directly from the versioned image:

```bash
docker run --rm ghcr.io/bursula/bursula:0.3.15 deployment export | tar -x && ./bursula/install.sh
```

The installer prepares the local files and validates Compose without starting a container. Afterwards, run `cd bursula` and use `./bursula setup`, `./bursula status`, `./bursula run`, or `./bursula doctor`. Synology DSM, Kubernetes, NAS, server, and other orchestrated deployments need environment-specific storage, permissions, networking, secret management, and scheduling; review the rest of this document before starting.

## Kubernetes

Kubernetes does not consume the Compose file directly. Follow the [Kubernetes deployment guide](./kubernetes.md) for persistent claims, a temporary setup Deployment reached only through `kubectl port-forward`, a non-overlapping CronJob, secrets, and the Chromium seccomp profile.

## Persistent paths

The container runs as UID/GID `1000:1000` and uses these paths:

| Container path | Purpose | Backup |
| --- | --- | --- |
| `/home/node/.bursula` | License, configurations, browser profiles, SQLite catalog, document store, and run state | Required; sensitive |
| `/invoices` | Example local-folder delivery target | According to retention policy |
| `/run/secrets` | Read-only noVNC and target credential files | Store separately and securely |

Create host directories before starting the container and make the state and invoice directories writable by UID 1000. On a regular Docker host:

```bash
mkdir -p .bursula-data .bursula-invoices .bursula-secrets
sudo chown -R 1000:1000 .bursula-data .bursula-invoices .bursula-secrets
chmod 700 .bursula-data .bursula-invoices .bursula-secrets
```

On Synology DSM, use persistent directories such as:

```text
/volume1/docker/bursula/data
/volume1/docker/bursula/invoices
/volume1/docker/bursula/secrets
```

Copy `compose.yaml` and `docker/seccomp_profile.json` into that directory, retaining the `docker` subdirectory, and set absolute paths in a sibling `.env` file. The profile is the Playwright 1.62.1 Docker seccomp profile: it retains a syscall allowlist while permitting the user-namespace operations required by Chromium's sandbox. Do not replace it with `seccomp=unconfined` or add `--no-sandbox`.

```dotenv
BURSULA_IMAGE=ghcr.io/bursula/bursula:0.3.15
BURSULA_CONFIG_PATH=/volume1/docker/bursula/data
BURSULA_INVOICE_PATH=/volume1/docker/bursula/invoices
BURSULA_SECRETS_PATH=/volume1/docker/bursula/secrets
BURSULA_NOVNC_BIND=127.0.0.1
```

Keep the setup port bound to `127.0.0.1`. Its HTTP/WebSocket transport is not encrypted and must not be exposed directly to the LAN or internet, including on a trusted network. Use an SSH tunnel for every setup and reauthentication session. Enable DSM SSH access only for the setup window, then open this tunnel from the administrator workstation and leave it running:

```bash
ssh -N -L 6080:127.0.0.1:6080 DSM-USER@NAS-IP
```

An authenticated HTTPS reverse proxy or encrypted VPN can replace the SSH tunnel only if it provides equivalent transport protection and the setup port remains unreachable outside that protected path.

## Initial browser login

Browser profiles are tied to Linux and the container CPU architecture. Do not copy a profile from macOS, Windows, or a NAS with another architecture.

The embedded remote display uses a one-line, exactly eight-character internal VNC password. You never enter or see this password in the web UI; the one-time setup link supplies it to the embedded viewer. If `/run/secrets/novnc-password` is not mounted, the setup container creates a random private password under the persistent Bursula state directory and immediately continues starting the web setup. Existing externally managed password files remain supported. To create one explicitly, set `secrets_directory` to the same host directory used by `BURSULA_SECRETS_PATH`; Compose does not export values from `.env` into your shell:

```bash
secrets_directory=.bursula-secrets
# On the DSM layout shown above, use:
# secrets_directory=/volume1/docker/bursula/secrets
sudo sh -c "openssl rand -hex 4 > '$secrets_directory/novnc-password'"
sudo chmod 600 "$secrets_directory/novnc-password"
sudo chown 1000:1000 "$secrets_directory/novnc-password"
```

Start the temporary web setup service:

```bash
docker compose --profile setup run --rm --service-ports setup
```

The container prints a one-time URL such as `http://127.0.0.1:6080/#token=…`. Open that exact URL through the SSH tunnel. If this installation is not activated, upload the issued `.lic` file first. Bursula validates its signature, validity period, and `setup` entitlement before storing it privately inside the mapped `/home/node/.bursula` state. The browser and integration list are not exposed by the setup API until that validation succeeds.

Then choose the integration, enter a descriptive name, review the generated editable configuration ID, select the initial import range, and choose the delivery target ID. The Docker web setup creates a local-folder target at `/invoices` and attaches it to the connection automatically. Click **Start login**, complete login and MFA in the embedded browser, then click **Login completed**. During login Chromium has no Playwright or DevTools connection. Bursula closes Chromium, removes its profile locks, stores the confirmed profile in the mapped state directory, and finishes the target configuration. The first normal run performs the provider-specific session check.

The same page can configure more integrations. Click **Finish setup** when done, then close the SSH tunnel and disable DSM SSH again. The setup token is regenerated for every server start and is required by both the setup API and remote-display connection. Only one setup or run may use a given configuration at a time.

## Manage delivery targets

The web setup already creates and attaches a local invoice-folder target. Use the CLI when you want to add another reusable local-folder target or attach a target to another existing connection. The example Compose file maps the invoice directory to `/invoices`:

```bash
docker compose run --rm bursula \
  configure target:local-folder --id invoice-archive --path /invoices
docker compose run --rm bursula \
  targets attach invoice-archive --for personal-chatgpt --yes
```

For Lexware Office, mount the key as a file below `/run/secrets` and reference only its container path:

```bash
docker compose run --rm -it bursula \
  configure target:lexware-office --id lexware --token-file /run/secrets/lexware-api-key
docker compose run --rm bursula \
  targets attach lexware --for personal-chatgpt --yes
```

## Container help and state

Running the image without a command does not start an invoice run. It reads the mounted state and prints the relevant next steps: initial deployment instructions when no valid license is present, web setup when the license is valid but no automation exists, or run and maintenance commands when configurations are ready.

```bash
docker run --rm ghcr.io/bursula/bursula:0.3.15
docker compose run --rm bursula container help
```

A bare `docker run` without a state volume always appears unconfigured because the container is ephemeral. The Compose form mounts the configured state and can therefore report its actual status.

## Run once or on a schedule

The `bursula` Compose service explicitly performs one `run --all` execution and then exits:

```bash
docker compose run --rm bursula
```

Use the host scheduler rather than a scheduler inside the container. On DSM, create a Control Panel Task Scheduler entry owned by an account allowed to use Container Manager. Its command can be:

```bash
cd /volume1/docker/bursula && docker compose --env-file .env run --rm bursula
```

Use DSM notifications or retained task output to observe the exit code. Exit code `2` requires reauthentication; exit code `3` can indicate interaction or a concurrent operation; exit code `4` means the installed license is missing, invalid, expired, not yet valid, or lacks the required `run` entitlement. Start the web setup again and upload a valid `.lic` file. The existing SQLite operation leases prevent two runs from modifying the same configuration concurrently.

## Updates and backups

Pull the selected image tag before the next scheduled run:

```bash
docker compose pull
```

For reproducible deployments, set `BURSULA_IMAGE` in `.env` to a released version instead of `latest`. Back up the complete mapped `data` directory only while no configuration or run command is active. Treat the backup as a credential because it contains the portable license file and its browser profiles may contain authenticated sessions. An offline license cannot be revoked before its signed expiry and validation depends on the container host having a correct system clock.

Restore browser state only to Linux on the same CPU architecture. If the architecture changes, retain delivered invoices and other non-browser records as required, but recreate each browser configuration in the new container.

## Local image development

The local Docker workflow is available through npm and automatically selects the `bursula:dev` image instead of trying to pull GHCR. Its host mounts remain inside the working tree as the hidden, ignored directories `.bursula-data`, `.bursula-invoices`, and `.bursula-secrets`:

```bash
npm run docker:build
npm run docker:doctor
npm run docker:setup
npm run docker:run
```

Normal Docker runs record the virtual browser display temporarily. Successful runs discard the recording. If a run returns `reauth_required`, `interaction_required`, `provider_unavailable`, or `partial_failure`, the latest recording is retained at `.bursula-data/diagnostics/<configuration-id>/last-failed-run.mp4`; the CLI also prints the corresponding container path. A later successful run removes that previous failure recording. Treat this file as sensitive because it can contain account and invoice information.

On the first `docker:setup` call, the npm tool generates an internal eight-character VNC password in `.bursula-secrets/novnc-password`, starts the setup service, and opens its one-time URL in the default browser on macOS. The password is not printed and does not need to be entered. Later setup calls reuse it; delete the file if you want it regenerated.

Upload the issued `.lic` file when prompted. It is stored under `.bursula-data/secrets/license/license.lic`, not in `.bursula-secrets`, so scheduled containers automatically reuse the activation through the existing state mount. Then choose the integration, name, generated/editable ID, and initial import range in the web page. Complete the provider login in the embedded browser and click **Login completed**. The manual browser is then closed and its profile saved without attaching browser automation during login. The setup command therefore takes no integration arguments:

```bash
npm run docker:run -- local-audible
npm run docker:cli -- configurations list
npm run docker:cli -- --version
```

For a non-Docker installation, activate from the terminal with `bursula license install /path/to/file.lic` and inspect it with `bursula license status`. Treat the original and installed `.lic` files as sensitive portable bearer credentials.

Set `BURSULA_DEV_IMAGE` only when a different local image tag is required.

Direct `docker run` users must apply the same profile and provide a larger shared-memory mount:

```bash
docker run --rm \
  --security-opt seccomp=./docker/seccomp_profile.json \
  --shm-size 1g \
  --volume ./.bursula-data:/home/node/.bursula \
  ghcr.io/bursula/bursula:0.3.15
```
