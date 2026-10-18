# Bilbo

My media server.

## First-time setup

If you restore from Borg in step 5, skip steps 6 to 8.

1. Install NixOS from this flake.
2. Make the SSH host key a sops recipient. On bilbo, run `nix-shell -p ssh-to-age --run 'ssh-to-age < /etc/ssh/ssh_host_ed25519_key.pub'`. Put the output under `&bilbo` in `.sops.yaml`. Run `sops updatekeys secrets/bilbo.yaml`.
3. Add the missing entries from the [secrets table](#secrets).
4. Run `sudo nixos-rebuild switch --flake .#bilbo`.
5. To restore, follow [Restoring from backups](remote/README.md#restoring-from-backups).
6. In the Add New dialog of Radarr and Sonarr, select "1080p, then 720p" one time.
7. [Calibre][calibre]: make a Kobo sync token in the user profile. On the Kobo, set `https://calibre.fnune.com/kobo/<token>`.
8. Do the setup in [Camera](#camera), [Zigbee](#zigbee), [Home Assistant](#home-assistant) and [Papra](#papra).

[jellyfin]: https://bilbo.fnune.com/jellyfin
[nzbget]: https://bilbo.fnune.com/nzbget
[radarr]: https://bilbo.fnune.com/radarr
[sonarr]: https://bilbo.fnune.com/sonarr
[prowlarr]: https://bilbo.fnune.com/prowlarr
[bazarr]: https://bilbo.fnune.com/bazarr
[calibre]: https://bilbo.fnune.com/calibre
[frigate]: https://frigate.fnune.com
[home-assistant]: https://home.fnune.com
[papra]: https://docs.fnune.com
[zigbee2mqtt]: https://bilbo.fnune.com/zigbee2mqtt
[seerr]: https://requests.fnune.com

## Network

Caddy serves every hostname on 443 with a Let's Encrypt certificate. The DNS
challenge issues the certificates, so a hostname does not need to be reachable
from the internet.

| Hostname | Who | How |
| --- | --- | --- |
| `bilbo.fnune.com` (subpaths), `immich`, `frigate`, `home`, `docs`, `health`, `notify`, `requests` | your devices | DNS record points at the WireGuard address. Caddy drops connections from outside the tunnel. |
| `photos.fnune.com` | anyone with a share link | Immich Public Proxy. It serves only what Immich shares. |
| `calibre.fnune.com` | the Kobo | `/kobo/*` only. The token is in the URL. |
| `watch.fnune.com` | guests with a Jellyfin account | Jellyfin at `/jellyfin` |
| `sourcesli.st` | anyone | The sourcesli.st [app](#apps). Its record is set by hand in Cloudflare, as a CNAME to `ip.fnune.com`, which `dyndns` keeps on the household address. |
| `http://192.168.178.36/...` | the LAN and the TV | plain HTTP, same subpaths as `bilbo.fnune.com` |

The public hostnames sit behind CrowdSec (`nixos/crowdsec.nix`). It reads their Caddy logs, and Caddy's bouncer refuses IPs it has banned, plus those on the community blocklist. LAN and VPN addresses are never banned. `sudo cscli decisions list` shows active bans, `sudo cscli decisions delete --ip <ip>` lifts one. If CrowdSec is down, the bouncer lets traffic through.

The `dyndns` service keeps the public records on the household address, every 5 minutes. Pulumi owns the private records (`remote/cloudflare/dns.ts`).

`bilbo.fnune.com/` serves a start page linking every service. It is hand-written HTML in `nixos/start-page/index.html`; add a link there when adding a service.

To add a private service, add a subpath to `adminSubpaths` in `nixos/caddy.nix`; for an app of my own, see [Apps](#apps). To add a public one, add a hostname to `public` with its own site block, and decide what the internet may see.

### WireGuard

Your devices reach bilbo through WireGuard. The endpoint is `wireguard.fnune.com:51820`, forwarded on the router. The private hostnames resolve everywhere but connect only through the tunnel, so apps use one URL at home and away.

To add a device:

1. Let the WireGuard app generate a key pair.
2. Add the public key to `devices` in `nixos/wireguard.nix`, with the next free address. Rebuild.
3. Enter these fields in the app:

```ini
[Interface]
PrivateKey = <generated on the device>
Address = 10.100.0.<n>/32
DNS = 1.1.1.1

[Peer]
PublicKey = aVdLGe76+qHh25zQBy3zfb3qp35IeZU4DWZvrowUX0g=
Endpoint = wireguard.fnune.com:51820
AllowedIPs = 10.100.0.0/24
PersistentKeepalive = 25
```

Only traffic for bilbo enters the tunnel, so it can stay on. The `DNS` line is necessary on phones: apps use the carrier's resolver, which can keep an old address for a long time. Android runs one VPN at a time. The TV stays on the LAN address.

On melian and feanor, `home-manager` creates the NetworkManager connection and prints the public key (`modules/system/wireguard.nix` in `home.nix`).

## Secrets

Secrets are encrypted in `secrets/bilbo.yaml`. `sops-nix` decrypts them at boot with bilbo's SSH host key. Nothing is placed on the machine by hand.

- Edit: `sops secrets/bilbo.yaml`. Set one entry: `sops set secrets/bilbo.yaml '["key"]' '"value"'`.
- Keys: the admin age key is in `~/.config/sops/age/keys.txt`, and a copy is in Bitwarden. `.sops.yaml` lists the recipients. To add a recipient, add its public key there and run `sops updatekeys secrets/bilbo.yaml`.
- Each module declares the entries it reads. A missing entry fails the build, not the unit.

| Entry | Contents | Source |
| --- | --- | --- |
| `cloudflare-dns-token` | DNS write on the zone, for dyndns and the certificate challenge | `pulumi stack output bilboDnsTokenValue --show-secrets` in `remote/` |
| `wireguard-private-key` | bilbo's WireGuard key | `wg genkey` |
| `borg-passphrase`, `rclone-conf`, `borg-s3-bucket-name` | the off-site backup | `pulumi stack output` in `remote/` |
| `radarr-api-key`, `sonarr-api-key` | Radarr's and Sonarr's own API keys, which everything else uses to reach them | any 32 hex characters: `openssl rand -hex 16` |
| `opensubtitles-username`, `opensubtitles-password` | Bazarr's OpenSubtitles.com account, by username, not email | opensubtitles.com |
| `bazarr-username`, `bazarr-password` | Bazarr's web login | choose one |
| `nzbgeek-api-key` | Prowlarr's NZBgeek indexer | nzbgeek.info -> My Account |
| `eweka-username`, `eweka-password` | NZBGet's news server login | Eweka account |
| `nzbget-username`, `nzbget-password` | NZBGet's web login, also used by Radarr and Sonarr | choose one |
| `jellyfin-admin-username`, `jellyfin-admin-password` | Jellyfin's admin, which also becomes Seerr's admin | choose one |
| `radarr-username`, `radarr-password`, and the same for `sonarr` and `prowlarr` | each app's web login | the current one, or choose one |
| `beszel-email`, `beszel-password` | Beszel's admin | choose one |
| `anthropic-api-key` | Pincho's LLM | the Anthropic console |
| `papra-env` | Papra's environment file, see its section | generated once |
| `mosquitto-*-password` | one MQTT password per client. Frigate's and Zigbee2MQTT's environment files use the same entries. | generated |
| `zigbee2mqtt-frontend-auth-token` | gates the Zigbee2MQTT frontend, which can re-pair or reset devices | generated |
| `zigbee2mqtt-network-key` | the Zigbee network key. A change means re-pairing every device. | generated once |
| `camera-password` | the camera's password, used only by go2rtc | the camera's web UI |
| `frigate-admin-password` | Frigate's `admin` account, which Home Assistant also uses | choose one, at least 12 characters |

To generate the random ones:

```sh
gen() { tr -dc A-Za-z0-9 </dev/urandom | head -c 32; }
for k in mosquitto-frigate-password mosquitto-zigbee2mqtt-password mosquitto-home-assistant-password zigbee2mqtt-frontend-auth-token; do
  sops set secrets/bilbo.yaml "[\"$k\"]" "\"$(gen)\""
done
```

go2rtc is the only service that opens the camera. Frigate reads both streams from the restream on localhost, so the camera password never reaches Frigate's config or database. The password goes into an RTSP URL, so avoid `@ : / ? #` or percent-encode them.

Frigate keeps review state per user. The unreviewed list in Home Assistant agrees with Frigate only if Home Assistant asks as the same account.

## Camera

Anpviz IPC-D3243W-S at `192.168.178.109`, on OEM Hikvision-lineage firmware.

| Path | Stream | Role |
| --- | --- | --- |
| `stream0` | 2560x1440 at 25 fps | record |
| `stream1` | 640x360 at 25 fps | detect |
| `stream2` | does not exist | |

Both ship as H.265; set them to H.264, since H.265 makes live view and playback
unreliable outside Safari. `detect.width` and `detect.height` in
`nixos/frigate.nix` are pinned to `stream1`, so re-measure after changing the
substream:

```sh
ffprobe rtsp://admin:PASSWORD@192.168.178.109:554/stream1
```

In the camera web UI:

- Change the password. It ships as `123456`.
- Service Ports: disable ONVIF, HIK (8000) and DAHUA (37777). HIK and DAHUA are
  unauthenticated control protocols, open by default. Only RTSP is used.
  Control Protocol (8091) serves the vendor discovery tool and can go too.
- Date & Time: NTP `192.168.178.1`, timezone GMT+01:00, DST on from the last
  Sunday of March at 02:00 to the last Sunday of October at 03:00. The NTP field
  looks like a fixed dropdown but takes free text.

In the FritzBox, which has no VLANs:

- Static IPv4 lease, since `nixos/frigate.nix` hardcodes the address. The camera
  itself stays on DHCP.
- Internet -> Filters -> Parental Controls: set the access profile to `Blocked`.
  This stands in for a camera VLAN. It blocks internet only, so RTSP still works.

No port forward to the camera.

## Frigate

Frigate has its own hostname because subpath proxying breaks its websockets and
service worker. The NixOS module force-enables nginx and builds its own vhost, so
that vhost is pinned to `127.0.0.1:8971` and Caddy fronts it, keeping Caddy alone
on 80 and 443. Frigate's jsmpeg upstream is hardcoded to `127.0.0.1:8082`, so
nothing else may take that port.

go2rtc holds the only connection to the camera and restreams both streams on
localhost; Frigate reads detect and record from the restream. The NixOS Frigate
module does not configure go2rtc, only proxies to it, so `nixos/frigate.nix`
enables `services.go2rtc` and hands the same stream definitions to both.

nixpkgs ships no detection model, and the OpenVINO detector has no download
fallback, so `nixos/frigate.nix` builds one. It fetches the YOLO11n weights from
the Ultralytics release and exports them to ONNX at 320x320 in a derivation,
using `python3Packages.ultralytics`. The export runs offline in the build
sandbox, so the model is reproducible from this repository with no manual step.
OpenVINO reads ONNX directly, and needs the `.onnx` extension to detect the
format, which is why the derivation produces a directory rather than a bare file.

Two model notes, both learned the hard way:

- `model_type = "yolox"` does not work on OpenVINO in Frigate 0.17.1. Its decode
  function assigns six values into a seven-column row, so it raises as soon as
  anything passes the confidence mask. It silently detects nothing.
- YOLO26 does not work either. Its NMS-free head emits `[1, 300, 6]`, while the
  `yolo-generic` parser expects the classic `[1, 84, N]` layout that YOLO11
  produces.

Check inference speed on the System Metrics page in [Frigate][frigate]:

```sh
journalctl -u frigate.service | grep -i openvino
intel_gpu_top
```

If OpenVINO will not start on the iGPU, set `device` to `"CPU"` in
`nixos/frigate.nix`, which keeps the same model. Failing that, replace the
`detectors` and `model` blocks with `detectors.cpu.type = "cpu"` to fall back to
the bundled TFLite model, at roughly 150 ms.

Recordings are event-only, retained 30 days for alerts and detections.
`/var/lib/frigate/recordings` symlinks to `/mnt/downloads-2t/frigate/recordings`,
and `adjustMountPoints` in `nixos/drives.nix` skips that path so it does not
chown every clip to `fausto` on each boot.

Draw motion masks in the Frigate UI once there is real footage. They matter more
than compute for detection accuracy.

## Zigbee

Plug the ZBDongle-P into a USB 2.0 port using an extension cable, never directly
into the chassis or a USB 3.0 port, whose 2.4 GHz noise wrecks the Zigbee mesh.

`nixos/zigbee2mqtt.nix` carries a udev rule matching the dongle on its USB
vendor, product and manufacturer strings, giving it `/dev/zigbee`. That keeps the
serial number out of this public repository and sidesteps `/dev/serial/by-id`
being `0700 root:root`. For a different stick, `udevadm info -a -n /dev/ttyUSB0`
prints the attributes to match on.

Joining is a runtime setting in Zigbee2MQTT 2.x, not a config file one. Enable it
from the [Zigbee2MQTT][zigbee2mqtt] frontend only while adding a device.

If devices report in but every command fails with `NWK_NO_ROUTE`, the dongle's
radio has wedged on transmit: unplug it and plug it back in.

Pin the network parameters, never `GENERATE` them: the module rewrites
`configuration.yaml` from the store on every start, so a generated network only
survives until the next rebuild. Starting a fresh one means deleting
`/var/lib/zigbee2mqtt/coordinator_backup.json` and re-pairing every device.

For the Innr bulbs:

- The wall switch must stay on or the bulbs are unreachable. A Zigbee remote is
  worth adding so there is a physical control that does not cut power.
- Set power-on behaviour to `previous`, so an outage does not bring the bulbs
  back at full-brightness cold white.

## Home Assistant

[Home Assistant][home-assistant] owns the lighting. Its base configuration is
declarative. Automations, scenes and scripts are
`!include`d from `/var/lib/hass` so they stay editable from the UI without a
rebuild. Those files are not in this repository; the Borg job in
`nixos/backups.nix` covers them along with the Zigbee2MQTT state.

On first run create the owner account, then add MQTT under Settings -> Devices &
Services -> Add integration -> MQTT, pointing at `127.0.0.1:1883` as
`home-assistant`. It cannot be declared in Nix because MQTT uses a config flow.

Once MQTT is up, the bulbs arrive through Zigbee2MQTT discovery and Frigate
publishes its cameras and sensors the same way.

`input_boolean.away` exists to gate the deterrent lighting and notifications.
Frigate's own web push can be switched at runtime by publishing to
`frigate/notifications/set`, so an automation can silence it while you are home
rather than duplicating notifications in Home Assistant.

## Papra

[Papra][papra] is the document archive, reachable over the VPN only like the other private hostnames. Its data lives in `/mnt/mirrored/papra`.

### Keys

> [!CAUTION]
> Losing `DOCUMENT_STORAGE_DOCUMENT_KEY_ENCRYPTION_KEYS` or `DATABASE_ENCRYPTION_KEY` loses every document, backups included. The `papra-env` entry in `secrets/bilbo.yaml` is in this repository, but keep a copy in Bitwarden and update it there after any change.

To generate the file once:

```sh
hex() { head -c "$1" /dev/urandom | od -An -tx1 | tr -d ' \n'; }
{
  printf 'AUTH_SECRET=%s\n' "$(hex 48)"
  printf 'DOCUMENT_STORAGE_DOCUMENT_KEY_ENCRYPTION_KEYS=1:%s\n' "$(hex 32)"
  printf 'DATABASE_ENCRYPTION_KEY=%s\n' "$(hex 32)"
  printf 'ANTHROPIC_API_KEY=%s\n' 'sk-ant-...'
} | sops set secrets/bilbo.yaml '["papra-env"]' "\"$(cat)\""
```

To rotate the document key, append a new version (`1:<old>,2:<new>`) and keep the old one.

### First-time setup

1. Generate `papra-env` and save a copy to Bitwarden.
2. Rebuild.
3. Set `AUTH_IS_REGISTRATION_ENABLED = true` in `papra.nix`, rebuild, sign up, then set it back and rebuild again. The first user becomes the admin.
4. Sign in. Papra asks to verify the email address and writes the link to the journal instead of sending it:
    ```sh
    sudo journalctl -u papra --since -10min -o cat | grep -o 'https://docs.fnune.com/api/auth/verify-email?token=[^"\\]*' | tail -1
    ```

Email verification is required because Papra does not fully enforce closed registration: unverified accounts cannot sign in. Password reset links land in the journal too.

### API clients

Clients reach the API over the VPN with a Papra API key; nothing else stands in front of it.

### Auto-tagging

AI runs on Claude Haiku. Enable it per organization under Settings -> Auto tagging. Turn off "Create new tags" once the tags are settled, and give each tag a description, which is what steers the model.

### Ingestion folder

Off for now. `INGESTION_FOLDER_IS_ENABLED` makes Papra import files dropped into `<root>/<organization id>/`, for example Syncthing scans from a phone.

### Backups

Borg covers `/mnt/mirrored/papra/documents` and `db-snapshot`, a copy of the database taken with Papra briefly stopped. The live `db` is excluded. The keys are in `secrets/bilbo.yaml` and in Bitwarden.

## Apps

Small apps of my own, each in a private repository whose flake has a default package. `nixos/apps.nix` gives each one a hardened service with its own user and `/var/lib/<name>`, and a Caddy route.

| App | Where | Module |
| --- | --- | --- |
| [Tashi](https://github.com/fnune/tashi) | `bilbo.fnune.com/apps/tashi` | `nixos/tashi.nix` |
| [Museum map](https://github.com/fnune/smb) | `bilbo.fnune.com/apps/smb` | `nixos/smb.nix` |
| [sourcesli.st](https://github.com/fnune/sourcesli.st) | `sourcesli.st`, public | `nixos/sourceslist.nix` |

- An app is VPN-only at `/apps/<name>` unless it sets `exposure = "public"` and a `hostname`. Caddy forwards the path unchanged, so the app must serve under `basePath`.
- A public app gets the CrowdSec bouncer, an optional per-IP `rateLimit` and a `<name>-traffic-alert` timer that tells ntfy about unusual traffic. Its visits show up in the [traffic report](#monitoring). Setting `exposure` back to `vpn` takes it off the internet.
- To ship a change, push it to the app's `main`, then run `nix flake update <name>` here and rebuild. The inputs are private: Nix on bilbo reads them with the `github-read-token` secret, a fine-grained token with read-only Contents access. Wherever you run `nix flake update`, Nix needs the same `access-tokens` setting.
- To add one, add its flake as an input and to `appsOverlay` in `flake.nix`, and give it a module that sets `bilbo.apps.<name>`.

Tashi keeps the last 20 snapshots of its data in `/var/lib/tashi/backups`, taken on every start. sourcesli.st runs its own Postgres 18 on port 5433, refills it from the Ultimate Debian Database every night (`sourceslist-ingest`) and keeps nothing worth backing up.

## Backups

For files kept only for safekeeping, copy them into `/mnt/mirrored/archive` with `scp` or `sftp://bilbo/mnt/mirrored/archive`. The backup covers it like the rest of `/mnt/mirrored`.

The Borg job in `nixos/backups.nix` runs daily over `/mnt/mirrored`, Home Assistant's and Zigbee2MQTT's state, Pincho's data, and the Jellyfin, Radarr, Sonarr, Bazarr, Prowlarr and Seerr state (users, watch history, quality profiles; logs and cover art are left out). On Sundays `borgbackup-offsite-mirrored` mirrors the repository to S3 Deep Archive with `rclone sync`, holding Borg's lock so a daily run cannot change it mid-upload. It stays weekly because Deep Archive bills deleted objects for 180 days. The bucket keeps deleted and overwritten objects as noncurrent versions for 180 days (`remote/aws/backups.ts`), so a damaged local repository does not destroy the off-site copy on the next run. Restoring is documented in `remote/README.md`.

Restores are tested on a schedule, at idle priority. On the 2nd of each month, `backup-restore-check-local` runs `borg check --verify-data` and compares a few restored photos with the originals. Each quarter, `backup-restore-start-remote` thaws a random 10 GB of the off-site repository (Bulk tier, about $0.03, inside the free monthly egress) and `backup-restore-check-remote` compares it byte for byte with the local copy three days later. Each sends "verified" to ntfy when it passes.

A run that fails, including a failed S3 upload, notifies like any other failed unit. `backup-freshness` checks daily that the last local run is less than 2 days old and the last upload less than 8, which catches a timer that stopped firing. It also fails until the first successful run of each after deploying, so start them with `systemctl start borgbackup-job-mirrored borgbackup-offsite-mirrored`.

## Monitoring

Alerts go to ntfy at [notify.fnune.com][ntfy], topic `bilbo`, over the VPN only. Subscribe to it in the ntfy app with that server. Notifications arrive only while the tunnel is up. `notify TITLE MESSAGE [PRIORITY]` posts to it from the host.

What notifies on its own (`nixos/monitoring.nix`):

- Any failed systemd service, with its last journal lines, at most once an hour per unit
- smartd warnings for any disk, plus a short self-test nightly and a long one monthly
- mdadm events on the mirror: a failed or missing disk, a degraded array
- Every fail2ban ban
- Backups, see [Backups](#backups)

[Beszel][beszel] shows disks, SMART, the mirror, temperatures, the iGPU, network and systemd services over time. Its alerts (status, disk at 85%, temperature at 80 °C, bandwidth at 100 MB/s) go to ntfy (`nixos/monitoring.nix`).

[`bilbo.fnune.com/traffic`](https://bilbo.fnune.com/traffic) is a GoAccess report of every public hostname's Caddy log, per hostname, updated every 10 minutes: visitors, pages, status codes and the busiest addresses.

For downloads, Sonarr and Radarr notify on grab, import, upgrade and health issues (`nixos/arr-settings.nix`). Their calendars show what's coming next.

[ntfy]: https://notify.fnune.com
[beszel]: https://health.fnune.com

## Updating packages

Run `./update.sh` instead of `nix flake update`. It updates the inputs, then
evaluates the config twice, once against the old lock and once against the new
one, and prints every package that changed version. Nothing is built and nothing
is switched, so it costs a nixpkgs source fetch and about half a minute.

```sh
./update.sh                          # update, report, commit
./update.sh --no-commit              # leave flake.lock in the working tree
./update.sh --diff-only              # report an update that is already committed
./update.sh --diff-only --since @----
```

The commit takes `flake.lock` alone, under the subject `Upgrade packages` with
the report as its body, so `jj log` says which versions moved. Anything else in
the working copy stays in `@`. A failed evaluation commits nothing and leaves
the updated lock in the working copy.

The report has three sections: `Services` for anything with an enabled
`services.<name>.package`, `Platform` for the kernel and the media and hardware
packages under it, and `System packages` for `environment.systemPackages`.

`lib/versions.nix` decides what is tracked. The services pass only visits option
names that own a systemd unit, because touching a removed or renamed module
calls `abort`, which `tryEval` cannot catch. Packages that skip that pass, either
behind a hand-written unit or under a unit whose name differs from its option
like `immich`, are listed by hand in `extraServices` and
`platform`. Add to those lists when a new unit takes its package from `pkgs`.

Comparing names means a package rebuilt at the same version, after a patch or a
dependency change, does not show up. Catching that needs real store paths, which
means building.
