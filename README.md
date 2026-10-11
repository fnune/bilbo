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
  - The OPDS feed is at `https://bilbo.fnune.com/calibre/opds` — add it on
    the PocketBook under Settings -> Accounts -> OPDS catalog
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

### Secrets

Hand-placed files under `/etc/nixos/secrets`, mode 600. The `mosquitto-*` files
hold the password on one line and nothing else; Mosquitto hashes them at unit
start and strips the trailing newline. The `.env` files are systemd
`EnvironmentFile`s: one `KEY=value` per line, no `export`, no quotes, no spaces
around the `=`. None are optional, so a missing file fails its unit.

| File | Contents |
| --- | --- |
| `mosquitto-frigate-password` | plaintext password |
| `mosquitto-zigbee2mqtt-password` | plaintext password |
| `mosquitto-home-assistant-password` | plaintext password |
| `frigate.env` | `FRIGATE_MQTT_PASSWORD=` matching the Frigate one |
| `zigbee2mqtt.env` | `ZIGBEE2MQTT_CONFIG_MQTT_PASSWORD=` matching the Zigbee2MQTT one, `ZIGBEE2MQTT_CONFIG_FRONTEND_AUTH_TOKEN=`, and `ZIGBEE2MQTT_CONFIG_ADVANCED_NETWORK_KEY=` |
| `go2rtc.env` | `CAMERA_PASSWORD=` for the camera |
| `papra.env` | `AUTH_SECRET=`, `DOCUMENT_STORAGE_DOCUMENT_KEY_ENCRYPTION_KEYS=`, `DATABASE_ENCRYPTION_KEY=` and `ANTHROPIC_API_KEY=`, see [Papra](#papra) |

To generate the five machine-chosen ones consistently, as `root`:

```sh
cd /etc/nixos/secrets
umask 077
gen() { tr -dc A-Za-z0-9 </dev/urandom | head -c 32; }
f=$(gen); z=$(gen); h=$(gen); t=$(gen)
printf '%s\n' "$f" > mosquitto-frigate-password
printf '%s\n' "$z" > mosquitto-zigbee2mqtt-password
printf '%s\n' "$h" > mosquitto-home-assistant-password
printf 'FRIGATE_MQTT_PASSWORD=%s\n' "$f" > frigate.env
printf 'ZIGBEE2MQTT_CONFIG_MQTT_PASSWORD=%s\nZIGBEE2MQTT_CONFIG_FRONTEND_AUTH_TOKEN=%s\n' "$z" "$t" > zigbee2mqtt.env
chmod 600 mosquitto-*-password frigate.env zigbee2mqtt.env
```

`go2rtc.env` holds the camera's own password, so write it by hand. go2rtc is the
only service that opens the camera, and Frigate reads both streams from the
restream on localhost, so the camera credential never reaches Frigate's config or
database. It is interpolated into an RTSP URL, so avoid `@ : / ? #` or
percent-encode them.

The `ZIGBEE2MQTT_CONFIG_FRONTEND_AUTH_TOKEN` gates the Zigbee2MQTT frontend,
which is served from the public `bilbo.fnune.com` origin and can otherwise
re-pair or factory-reset devices.

`/etc/nixos/secrets/frigate-admin-password`, mode 600, holding the password of
Frigate's `admin` account, the one you log into Frigate's web UI with.

Frigate keeps review state per user, so the unreviewed list only agrees with what
you see in Frigate if Home Assistant asks as the same account. A dedicated
service account would report everything as unreviewed forever, because it never
reviews anything itself.

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
on 80 and 443. Frigate's jsmpeg upstream is hardcoded to `127.0.0.1:8082`, which
is why the homepage dashboard moved to 8084.

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
rebuild. Those files are not in this repository, and `nixos/backups.nix` only
covers `/mnt/mirrored`, so nothing under `/var/lib` is backed up. Losing the disk
loses the automations.

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

[Papra][papra] is the document archive. It has its own hostname, `docs.fnune.com`, because Papra only documents running at the root of a hostname. Cloudflare proxies that hostname, and `papra-access-app` in `remote/cloudflare/web.ts` puts it behind the same Cloudflare Access policy as `bilbo.fnune.com`. It runs from the nixpkgs module, listens on `127.0.0.1:1221` only, and keeps everything under `/mnt/mirrored/papra`.

#### Keys

> [!CAUTION]
> Losing `DOCUMENT_STORAGE_DOCUMENT_KEY_ENCRYPTION_KEYS` or `DATABASE_ENCRYPTION_KEY` loses every document, permanently. The files and the database on disk, and in every Borg archive, are useless without them. Borg does not back up `/etc/nixos/secrets`, so the backup does not contain the keys either. Store the whole of `papra.env` in Bitwarden, next to _Bilbo Borg + S3 + Pulumi Credentials_, as soon as you write it and again after any change.

| Line | What it does | If lost |
| --- | --- | --- |
| `DOCUMENT_STORAGE_DOCUMENT_KEY_ENCRYPTION_KEYS` | Key encryption key (KEK). Each document is encrypted with its own key, which is wrapped with this one and kept in the database. | Every document is unreadable |
| `DATABASE_ENCRYPTION_KEY` | Encrypts the SQLite database at rest, including the OCR text of every document | The database is unreadable, and with it the wrapped document keys |
| `AUTH_SECRET` | Signs session cookies and document share links | Everyone is logged out and share links stop working; regenerate it |
| `ANTHROPIC_API_KEY` | Auto-tagging | Issue a new one in the Anthropic Console |

Generate the file as `root`:

```sh
cd /etc/nixos/secrets
umask 077
hex() { head -c "$1" /dev/urandom | od -An -tx1 | tr -d ' \n'; }
{
  printf 'AUTH_SECRET=%s\n' "$(hex 48)"
  printf 'DOCUMENT_STORAGE_DOCUMENT_KEY_ENCRYPTION_KEYS=1:%s\n' "$(hex 32)"
  printf 'DATABASE_ENCRYPTION_KEY=%s\n' "$(hex 32)"
  printf 'ANTHROPIC_API_KEY=%s\n' 'sk-ant-...'
} > papra.env
chmod 600 papra.env
```

The `1:` prefix is the key's version. To rotate, append a new version, `1:<old>,2:<new>`, and keep the old one. Papra encrypts new documents with the highest version and still needs the old ones to read existing documents.

Document encryption only covers files uploaded while it is on, so both keys are in place from the first start.

#### First-time setup

1. Write `papra.env` as above and save it to Bitwarden.
2. In `remote/`, run `pulumi up` to create the Access application, then rebuild bilbo. `cloudflare-dyndns` creates the proxied DNS record.
3. Registration is off in `nixos/papra.nix`. To create the first user, append `AUTH_IS_REGISTRATION_ENABLED=true` to `papra.env` and run `systemctl restart papra`. This works because systemd lets `EnvironmentFile` override `Environment`.
4. Sign up at [Papra][papra]. The first user becomes the admin.
5. Remove that line from `papra.env` and restart again.
6. Sign in. Papra refuses with a request to verify the email address, and logs a verification email instead of sending one. Open its link:
    ```sh
    sudo journalctl -u papra --since -10min -o cat | grep -o 'https://docs.fnune.com/api/auth/verify-email?token=[^"\\]*' | tail -1
    ```

Papra 26.6.1 ignores `AUTH_IS_REGISTRATION_ENABLED` for email sign-up, which is fixed in 26.7.0. Until then, anyone who gets past Cloudflare Access can still create an account. `AUTH_IS_EMAIL_VERIFICATION_REQUIRED` keeps such accounts unable to sign in, because their verification links only reach this journal. Delete strays under Admin -> Users.

The `logger` email driver also means a password reset link lands in the same journal.

OCR runs on Tesseract for German, English and Spanish (`DOCUMENTS_OCR_LANGUAGES`).

Stored files are named `<organization id>/<year>/<month>/<document name>`, using the upload date. The names are readable but the contents are encrypted, so a file is only useful through Papra. `organization.name` only exists from Papra 26.7.0, and nixpkgs ships 26.6.1.

#### API clients

Anything that calls Papra's API from outside, such as a future script or an LLM tool on another host, has to get past Cloudflare Access before Papra sees it. Two ways:

- **Service token (preferred):** create one in Zero Trust under Access -> Service credentials, add a Service Auth policy for it to the Papra application, and send `CF-Access-Client-Id` and `CF-Access-Client-Secret` with every request, alongside the Papra API key. Declare the token and policy in `remote/cloudflare/` rather than in the dashboard.
- **Bypass policy:** skips Access for the matching requests, leaving the Papra API key as the only check. Use it only for a narrow path.

Clients get decrypted documents and OCR text from the API. They never need the encryption keys.

#### Auto-tagging

AI is on server-wide with `anthropic://claude-haiku-4-5`, at USD 1 per million input tokens and USD 5 per million output tokens. `AUTO_TAGGING_MODEL` overrides it for tagging alone. Tagging only runs where an organization opts in:

- Organization settings -> Auto tagging -> Enable auto tagging.
- Turn off "Create new tags" once the taxonomy exists, so new documents land on existing tags.
- The model reads each tag's name and description, so a precise description steers it more than anything else.
- "Max number of tags" defaults to 5.

#### Ingestion folder (not enabled)

Papra can import files dropped into a watched folder, for example Syncthing scans from a phone. It is off today. To enable it:

- Set `INGESTION_FOLDER_IS_ENABLED = true` and `INGESTION_FOLDER_ROOT_PATH` in `nixos/papra.nix`.
- Files go in `<root>/<organization id>/`, and the folder must be writable by the `papra` user.
- After import, files are deleted by default. `INGESTION_FOLDER_POST_PROCESSING_STRATEGY=move` keeps them instead.

Email intake (`INTAKE_EMAILS_IS_ENABLED`) is off too.

#### Backups

| What | Where | Backed up by |
| --- | --- | --- |
| Encrypted documents | `/mnt/mirrored/papra/documents` | Borg, weekly, and S3 |
| Encrypted database, consistent copy | `/mnt/mirrored/papra/db-snapshot` | Borg, weekly, and S3 |
| Live database | `/mnt/mirrored/papra/db` | Nothing: excluded from Borg |
| Keys | `/etc/nixos/secrets/papra.env` | Bitwarden only, by hand |

Borg copies files while services run, so its `preHook` stops Papra for the few seconds it takes to copy the database to `db-snapshot`, then starts it again. To restore, stop Papra, replace `db` with `db-snapshot` and `documents` with their restored copies, owned by `papra:papra`, put back `papra.env`, and start Papra.

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
behind a hand-written unit like `filebrowser` or under a unit whose name differs
from its option like `immich`, are listed by hand in `extraServices` and
`platform`. Add to those lists when a new unit takes its package from `pkgs`.

Comparing names means a package rebuilt at the same version, after a patch or a
dependency change, does not show up. Catching that needs real store paths, which
means building.

## Running in a VM

Warning: security measures are waived for the VM in order to facilitate testing.

```sh
# Build the VM:
nixos-rebuild build-vm --flake .#bilboVirtual

# Run the VM:
./result/bin/run-bilbo-vm
```

After having changed `configuration.nix` or any of its dependencies:

```sh
# Remove the VM's state:
rm ./bilbo.qcow2
```
