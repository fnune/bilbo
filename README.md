# Bilbo

My media server.

## First-time setup

### Services

Before starting, run:

```sh
mkdir /mnt/downloads-1t/Books
mkdir /mnt/downloads-1t/Movies
mkdir /mnt/downloads-2t/Series
```

Now, configure each service:

- [NZBGet][nzbget]
  - Visit [NZBGet][nzbget]—the default credentials are `nzbget`/`tegbzn6789`
  - In Security: and change the username and password
  - In Paths: set `MainPath` to `/mnt/downloads-1t/.nzbget`
  - In Categories: set the `DestDir` for "Books", "Movies" and "Series" to
    `/mnt/downloads-{1,2}t/{Books,Movies,Series}`, and whatever else is necessary
  - In News Servers: configure your server
    - Use port `563` for SSL
    - Enable encryption
    - Bump the connection limit to whatever your server allows (`50`)
- [Radarr][radarr] and [Sonarr][sonarr], and other "arr"s
  - For Radarr, go to Settings -> Profiles and set the language to "Original"
    in all profiles
  - For both:
    - Go to Settings -> Indexers and add NZBGeek
    - Go to Settings -> Download Clients and add NZBGet
- [Calibre][calibre]
  - On first run, point it at `/mnt/downloads-1t/Books` (initialize a Calibre
    library there with `calibredb` if `metadata.db` does not yet exist)
  - The Kobo syncs through `https://calibre.fnune.com/kobo/<token>`, the only
    path that hostname serves to the internet. Generate the token under the
    user's profile in calibre-web.
- [Jellyfin][jellyfin]
  - Visit [Jellyfin][jellyfin] and create the admin user
  - Create a media library for Movies in `/mnt/downloads-1t/Movies`
  - Create a media library for Series in `/mnt/downloads-2t/Series`

[jellyfin]: https://bilbo.fnune.com/jellyfin
[nzbget]: https://bilbo.fnune.com/nzbget
[radarr]: https://bilbo.fnune.com/radarr
[sonarr]: https://bilbo.fnune.com/sonarr
[calibre]: https://bilbo.fnune.com/calibre
[frigate]: https://frigate.fnune.com
[home-assistant]: https://home.fnune.com
[papra]: https://docs.fnune.com
[zigbee2mqtt]: https://bilbo.fnune.com/zigbee2mqtt

### Network

Caddy serves every hostname on 443 with a Let's Encrypt certificate. The DNS
challenge issues the certificates, so a hostname does not need to be reachable
from the internet.

| Hostname | Who | How |
| --- | --- | --- |
| `bilbo.fnune.com` (subpaths), `immich`, `frigate`, `home`, `docs`, `health`, `notify` | your devices | DNS record points at the WireGuard address. Caddy drops connections from outside the tunnel. |
| `photos.fnune.com` | anyone with a share link | Immich Public Proxy. It serves only what Immich shares. |
| `calibre.fnune.com` | the Kobo | `/kobo/*` only. The token is in the URL. |
| `watch.fnune.com` | guests with a Jellyfin account | Jellyfin at `/jellyfin` |
| `http://192.168.178.36/...` | the LAN and the TV | plain HTTP, same subpaths as `bilbo.fnune.com` |

The dyndns timers in `nixos/caddy.nix` keep the public records on the household address. Pulumi owns the private records (`remote/cloudflare/dns.ts`).

To add a private service, add a subpath to `adminSubpaths` in `nixos/caddy.nix`. To add a public one, add a hostname to `public` with its own site block, and decide what the internet may see.

#### WireGuard

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

### Secrets

Secrets are encrypted in `secrets/bilbo.yaml`. `sops-nix` decrypts them at boot with bilbo's SSH host key. Nothing is placed on the machine by hand.

- Edit: `sops secrets/bilbo.yaml`. Set one entry: `sops set secrets/bilbo.yaml '["key"]' '"value"'`.
- Keys: the admin age key is in `~/.config/sops/age/keys.txt`, and a copy is in Bitwarden. `.sops.yaml` lists the recipients. To add a recipient, add its public key there and run `sops updatekeys secrets/bilbo.yaml`.
- Each module declares the entries it reads. A missing entry fails the build, not the unit.

| Entry | Contents | Source |
| --- | --- | --- |
| `cloudflare-dns-token` | DNS write on the zone, for dyndns and the certificate challenge | `pulumi stack output bilboDnsTokenValue --show-secrets` in `remote/` |
| `wireguard-private-key` | bilbo's WireGuard key | `wg genkey` |
| `borg-passphrase`, `rclone-conf`, `borg-s3-bucket-name` | the off-site backup | `pulumi stack output` in `remote/` |
| `anthropic-api-key` | Pincho's LLM | the Anthropic console |
| `papra-env` | Papra's environment file, see its section | generated once |
| `mosquitto-*-password` | one MQTT password per client. Frigate's and Zigbee2MQTT's environment files use the same entries. | generated |
| `zigbee2mqtt-frontend-auth-token` | gates the Zigbee2MQTT frontend, which can re-pair or reset devices | generated |
| `zigbee2mqtt-network-key` | the Zigbee network key. A change means re-pairing every device. | generated once |
| `camera-password` | the camera's password, used only by go2rtc | the camera's web UI |
| `frigate-admin-password` | Frigate's `admin` account, which Home Assistant also uses | Frigate's web UI |

To generate the random ones:

```sh
gen() { tr -dc A-Za-z0-9 </dev/urandom | head -c 32; }
for k in mosquitto-frigate-password mosquitto-zigbee2mqtt-password mosquitto-home-assistant-password zigbee2mqtt-frontend-auth-token; do
  sops set secrets/bilbo.yaml "[\"$k\"]" "\"$(gen)\""
done
```

go2rtc is the only service that opens the camera. Frigate reads both streams from the restream on localhost, so the camera password never reaches Frigate's config or database. The password goes into an RTSP URL, so avoid `@ : / ? #` or percent-encode them.

Frigate keeps review state per user. The unreviewed list in Home Assistant agrees with Frigate only if Home Assistant asks as the same account.

### Camera

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

### Frigate

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

Frigate prints a generated admin password on first start:

```sh
journalctl -u frigate.service | grep 'Password:'
```

Log in at [Frigate][frigate], change it, and check inference speed on the System
Metrics page:

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

### Zigbee

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

### Home Assistant

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

### Papra

[Papra][papra] is the document archive, reachable over the VPN only like the other private hostnames. Its data lives in `/mnt/mirrored/papra`.

#### Keys

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

#### First-time setup

1. Generate `papra-env` and save a copy to Bitwarden.
2. Rebuild.
3. Set `AUTH_IS_REGISTRATION_ENABLED = true` in `papra.nix`, rebuild, sign up, then set it back and rebuild again. The first user becomes the admin.
4. Sign in. Papra asks to verify the email address and writes the link to the journal instead of sending it:
    ```sh
    sudo journalctl -u papra --since -10min -o cat | grep -o 'https://docs.fnune.com/api/auth/verify-email?token=[^"\\]*' | tail -1
    ```

Email verification is required because Papra does not fully enforce closed registration: unverified accounts cannot sign in. Password reset links land in the journal too.

#### API clients

Clients reach the API over the VPN with a Papra API key; nothing else stands in front of it.

#### Auto-tagging

AI runs on Claude Haiku. Enable it per organization under Settings -> Auto tagging. Turn off "Create new tags" once the tags are settled, and give each tag a description, which is what steers the model.

#### Ingestion folder

Off for now. `INGESTION_FOLDER_IS_ENABLED` makes Papra import files dropped into `<root>/<organization id>/`, for example Syncthing scans from a phone.

#### Backups

Borg covers `/mnt/mirrored/papra/documents` and `db-snapshot`, a copy of the database taken with Papra briefly stopped. The live `db` is excluded. The keys are in `secrets/bilbo.yaml` and in Bitwarden.

### Pincho and the museum map

Two small apps of my own run as system services with their own users.

- Pincho (`nixos/pincho.nix`): the code is in `/srv/pincho`, user data in `/var/lib/pincho`. `deploy.sh` in the Pincho repository builds locally, syncs the tree to `/srv/pincho` and restarts the unit through a passwordless sudo rule. The unit snapshots the user data files into `/var/lib/pincho/backups` on every start and keeps the last 20. The Anthropic key comes from sops.
- Museum map (`nixos/smb-jahreskarte.nix`): a static page and a stdlib Python server in `/srv/smb-jahreskarte`, edited in place. Its state file lives next to it.

Both are served under `bilbo.fnune.com` and have no login of their own; the tunnel is the gate.

### Backups

The Borg job in `nixos/backups.nix` runs weekly over `/mnt/mirrored`, Home Assistant's and Zigbee2MQTT's state and Pincho's data, then mirrors the repository to S3 Deep Archive with `rclone sync`. The bucket keeps deleted and overwritten objects as noncurrent versions for 180 days (`remote/aws/backups.ts`), so a damaged local repository does not destroy the off-site copy on the next run. Restoring is documented in `remote/README.md`.

A run that fails, including a failed S3 upload, notifies like any other failed unit. `backup-freshness` checks daily that the last successful run is less than 8 days old, which catches a timer that stopped firing. It also fails until the first successful run after deploying, so start one with `systemctl start borgbackup-job-mirrored`.

### Monitoring

Alerts go to ntfy at [notify.fnune.com][ntfy], topic `bilbo`, over the VPN only. Subscribe to it in the ntfy app with that server. Notifications arrive only while the tunnel is up. `notify TITLE MESSAGE [PRIORITY]` posts to it from the host.

What notifies on its own (`nixos/monitoring.nix`):

- Any failed systemd service, with its last journal lines, at most once an hour per unit
- smartd warnings for any disk, plus a short self-test nightly and a long one monthly
- mdadm events on the mirror: a failed or missing disk, a degraded array
- Every fail2ban ban
- Backups, see [Backups](#backups)

[Beszel][beszel] shows disks, SMART, the mirror, temperatures, the iGPU, network and systemd services over time. Its alerts live in its database, so set them up once by hand:

- Visit [Beszel][beszel] and create the admin user. Only the first user can sign up. The hub then lists bilbo on its next restart.
- In Settings -> Notifications, add `ntfy://127.0.0.1:2586/bilbo?scheme=http`
- In the systems table, turn on alerts: status, disk usage at 85%, temperature, and bandwidth for traffic spikes

For downloads, add an ntfy connection in Sonarr and Radarr (Settings -> Connect -> ntfy) with server `http://127.0.0.1:2586` and topic `bilbo`, on grab, import and health issues. Their calendars show what's coming next.

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
./update.sh --diff-only --since HEAD~3
```

The commit takes `flake.lock` alone, under the subject `Upgrade packages` with
the report as its body, so `git log` says which versions moved. Anything else in
the tree, staged or not, is left where it is. A failed evaluation commits
nothing and leaves the updated lock in the working tree.

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
