# Operator inputs

Everything the deployment and update flows need, where each value comes from,
and where it is stored. Secrets go in the encrypted vault; everything else in
plain YAML. Nothing is read from environment variables.

Every file below that holds a value of your deployment is git-ignored and lives
only in your clone. You create it from the tracked `*.example` next to it; the
README section "Before your first deploy" lists them and what to back up.

| Input | Where it is stored | Secret |
|---|---|---|
| Server address | `inventory/hosts.yml` → `ansible_host` (git-ignored) | no |
| SSH key for root | your `~/.ssh`, installed with `scripts/setup-ssh-access.sh` | your key |
| Cameras (name, RTSP URLs) | `group_vars/all/vault.yml` (git-ignored) → `vault_cameras` | yes (URLs embed camera passwords) |
| Bootstrap admin and viewer credentials | `group_vars/all/vault.yml` → `vault_bootstrap_*` | yes |
| Cloudflare Tunnel connector token | `group_vars/all/vault.yml` → `vault_cloudflare_tunnel_token` | yes |
| Public hostname | `inventory/hosts.yml` → `nvr_hostname` (git-ignored) | no |
| Vault password | `.vault_pass` (git-ignored) | yes |

## 1. Server

A fresh Ubuntu 24.04 LTS server with a public IP. The flows refuse any other
release. You need root access by SSH key and nothing else: no password is ever
accepted by the flows.

- Create the inventory from its template and put the address in it as
  `ansible_host`: `cp inventory/hosts.yml.example inventory/hosts.yml`.
- Install your key for root once with `scripts/setup-ssh-access.sh` (it asks
  for the root password a single time and does not store it).
- Check: `ssh -o BatchMode=yes root@<address> id` prints `uid=0`.

## 2. Cameras

The server pulls RTSP from each camera, so every camera must be reachable from
the server's network (public IP and port forward, or any route you provide).
The examine step probes every URL from the server before deploying.

In `group_vars/all/vault.yml`:

```yaml
vault_cameras:
  - name: front-door                       # unique; lowercase letters, digits, dashes
    main_url: "rtsp://user:pass@203.0.113.21:554/cam/realmonitor?channel=1&subtype=0"
    sub_url:  "rtsp://user:pass@203.0.113.21:554/cam/realmonitor?channel=1&subtype=1"  # optional
  - name: backyard
    main_url: "rtsp://user:pass@203.0.113.22:554/stream1"
```

- `main_url` is the full-resolution stream and is what gets recorded.
- `sub_url` is optional. When present, motion detection runs on it instead of
  the main stream, which cuts CPU use considerably. Most cameras expose one
  (Dahua: `subtype=1`; Hikvision: `/Streaming/Channels/102`; Reolink:
  `_sub`).
- URLs must start with `rtsp://` or `rtsps://`.

## 3. Bootstrap accounts

Two accounts are created on the NVR's first start, and only then:

```yaml
vault_bootstrap_admin_username: admin
vault_bootstrap_admin_password: "a-strong-temporary-password"
vault_bootstrap_viewer_username: user
vault_bootstrap_viewer_password: "another-temporary-password"
```

Change both passwords in the motionEye web interface after the first login.
Later deploys and updates never reset them. When you run `make verify` or
`make update` after rotating, pass the current passwords as
`make verify ADMIN_PASSWORD=... VIEWER_PASSWORD=...`. Make exports them into the
environment, where the verify role reads them; they are not echoed, not put on an
`ansible-playbook` command line, and not written anywhere. Unset or empty values
fall back to the bootstrap passwords. Calling `ansible-playbook` directly, export
the two variables or pass `-e nvr_admin_password=... -e nvr_viewer_password=...`.

## 4. Cloudflare (done by you in the dashboard)

The NVR is reachable only through a Cloudflare Tunnel, with a Cloudflare Access
login wall in front of motionEye's own login. The server opens no web ports and
TLS is Cloudflare's. **You create the tunnel, the public hostname and the Access
application in the dashboard; the repo does none of it.** The flows need two
things from you: the tunnel's connector token (vault) and the hostname you
published (`nvr_hostname`). Verification then checks that the hostname is
served and that it sits behind Access.

You need a Cloudflare account with a domain on Cloudflare nameservers (free
plan is enough) and a Zero Trust organisation (free plan). Dashboard labels
change now and then; each step names the page and what the field is for, so
you can find it if a label moved.

### 4.1 Zero Trust, first time only

1. Open <https://dash.cloudflare.com>, pick the account, click **Zero Trust**
   in the left sidebar (or open <https://one.dash.cloudflare.com>).
2. First visit: choose a **team name** (an internal identifier, it becomes the
   `<team>.cloudflareaccess.com` login page), pick the **Free** plan and
   complete the payment step; the free plan is not charged.
3. Make sure the one-time PIN login method exists: **Zero Trust → Integrations →
   Identity providers**. If **One-time PIN** is not listed under your identity
   providers, click **Add new identity provider → One-time PIN** and save. New
   organisations usually have it already.

### 4.2 Create the tunnel and copy its connector token

1. **Zero Trust → Networking → Tunnels → Create a tunnel**. Choose the
   **Cloudflared** connector type if asked, name the tunnel (for example
   `motion-eye`), click **Create tunnel** / **Save tunnel**.
2. The next page shows install commands per operating system. Pick any OS. The
   last command ends with a long string starting with `eyJ`. That string is the
   connector token. Copy only the string.

   **Do not run that command on the server.** The flow runs the connector in
   Docker from the token; a second connector installed by hand would compete
   with it.
3. Put the token in the vault (section 5 explains the vault):

   ```yaml
   vault_cloudflare_tunnel_token: "eyJ..."
   ```

4. Click **Next** / **Continue** past the "waiting for connector" step; the
   connector appears once `make init` or `make deploy` has run.

To see the token again later: open the tunnel, **Overview** tab, **Add a
replica**, and copy the `eyJ...` string out of the command shown (do not run it).

### 4.3 Publish the hostname to the NVR

1. Open the tunnel (**Networking → Tunnels**, click its name), go to the
   **Routes** tab (older UI: **Public Hostname** tab).
2. **Add route → Published application** (older UI: **Add a public hostname**).
3. Fill in:

   | field | value |
   |---|---|
   | Subdomain | the name you want, e.g. `motioneye` |
   | Domain | your domain, from the drop-down |
   | Path | leave empty |
   | Service URL (older UI: Type + URL) | `http://motioneye:8765` (older UI: type **HTTP**, URL `motioneye:8765`) |

   `motioneye` is the container name on the Docker network the connector
   shares with the NVR. `localhost` would point at the connector container
   itself and fail with HTTP 502.
4. Save the route. Cloudflare creates the DNS record for you.
5. Put the full hostname in `inventory/hosts.yml`, under the `nvr` host:

   ```yaml
   nvr_hostname: nvr.example.com
   ```

### 4.4 Put Cloudflare Access in front of it

Without this step the motionEye login page is open to the whole internet and
`make verify` fails on purpose.

1. **Zero Trust → Access controls → Applications → Create new application**
   (older UI: **Access → Applications → Add an application**).
2. Choose **Self-hosted and private** (older UI: **Self-hosted**).
3. Name the application (for example `NVR`), then **Add public hostname** and
   select the subdomain and domain from 4.3. Leave the path empty.
4. Under **Access policies**, create a policy:

   | field | value |
   |---|---|
   | Policy name | e.g. `household` |
   | Action | **Allow** |
   | Include rule: Selector | **Emails** |
   | Include rule: Value | every email address that may log in, one per entry |

   Leave Require and Exclude empty.
5. Under the identity provider / login methods section, make sure
   **One-time PIN** is enabled for this application. Turn off others you do
   not use.
6. **Session Duration**: how long a browser stays logged in to Access before
   the PIN is asked again. The maximum (**1 month**) is the right setting
   here; the camera UI still has its own password, and this is what removes
   the daily PIN prompt.
7. Click through the remaining tabs with defaults and **Create** / **Save**.

To change who may log in later, edit the policy's Emails list in this same
place. Nothing in the repo changes.

### 4.5 Check it worked

After `make init` (or `make deploy` plus `make verify`):

- `make verify` prints `connector ready; https://<nvr_hostname>/ redirects to
  Cloudflare Access`. That line is the proof of 4.2 to 4.4.
- Opening `https://<nvr_hostname>` in a browser shows the Cloudflare Access
  page, asks for your email, sends a PIN, and then shows the motionEye login.

What a failing `make verify` means:

| message | missing step |
|---|---|
| `cloudflared reports the tunnel is not ready` | token wrong or stale (4.2), or the connector container is down |
| `returned HTTP 200` ... `reachable WITHOUT a login wall` | no Access application for the hostname (4.4) |
| `HTTP 530` or `did not answer` | hostname not published on this tunnel (4.3), or DNS not yet propagated |

### 4.6 If the token leaks, or you start over

- **Rotate the token**: open the tunnel, **Overview** tab, **Refresh token**,
  copy the new `eyJ...` string into the vault, run `make deploy`. The old token
  can no longer start a connector.
- **Tunnel deleted or account lost**: nothing in the repo can recreate it.
  Repeat 4.2 to 4.4 with a new tunnel, put the new token in the vault, run
  `make deploy` then `make verify`. `state/cloudflare.yml` (git-ignored) is
  rewritten with the new tunnel id.

A connector token grants the right to serve your hostname; treat it like a
password. It lives only in the encrypted vault and on the server.

## 5. Vault

```sh
umask 077; echo 'choose-a-long-vault-password' > .vault_pass
cp group_vars/all/vault.yml.example group_vars/all/vault.yml
$EDITOR group_vars/all/vault.yml
ansible-vault encrypt group_vars/all/vault.yml     # or: make vault-encrypt
```

Both files are git-ignored and never committed, not even encrypted: the repo
is a template others clone. Back up the encrypted `group_vars/all/vault.yml`
and `.vault_pass` separately, off this machine; without both you re-enter every
secret. Every flow stops immediately if either file is missing. `make lint`
refuses a plaintext vault and any tracked per-deployment file.

## 6. Validation

`make check` validates all of the above without touching the server: vault
readable, camera names unique and well formed, URLs are RTSP, the connector
token present and shaped like one, the hostname fully qualified, and (for the
initial deployment) both bootstrap credentials present. A leftover
`cloudflare_mode` from an older clone is refused with a message saying what to
delete.
