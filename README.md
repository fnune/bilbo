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
| `mosquitto-bilbo-alerts-password` | plaintext password |
| `ntfy-password` | plaintext password, also typed into the phone |
| `frigate.env` | `FRIGATE_MQTT_PASSWORD=` matching the Frigate one |
| `zigbee2mqtt.env` | `ZIGBEE2MQTT_CONFIG_MQTT_PASSWORD=` matching the Zigbee2MQTT one, `ZIGBEE2MQTT_CONFIG_FRONTEND_AUTH_TOKEN=`, and `ZIGBEE2MQTT_CONFIG_ADVANCED_NETWORK_KEY=` |
| `go2rtc.env` | `CAMERA_PASSWORD=` for the camera |

To generate the machine-chosen ones consistently, as `root`:

```sh
cd /etc/nixos/secrets
umask 077
gen() { tr -dc A-Za-z0-9 </dev/urandom | head -c 32; }
f=$(gen); z=$(gen); h=$(gen); t=$(gen); a=$(gen); n=$(gen)
printf '%s\n' "$f" > mosquitto-frigate-password
printf '%s\n' "$z" > mosquitto-zigbee2mqtt-password
printf '%s\n' "$h" > mosquitto-home-assistant-password
printf '%s\n' "$a" > mosquitto-bilbo-alerts-password
printf '%s\n' "$n" > ntfy-password
printf 'FRIGATE_MQTT_PASSWORD=%s\n' "$f" > frigate.env
printf 'ZIGBEE2MQTT_CONFIG_MQTT_PASSWORD=%s\nZIGBEE2MQTT_CONFIG_FRONTEND_AUTH_TOKEN=%s\n' "$z" "$t" > zigbee2mqtt.env
chmod 600 mosquitto-*-password ntfy-password frigate.env zigbee2mqtt.env
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

### Notifications

Frigate keeps sending its own web push for camera events. Everything here is
about the machine: disks, backups, services, and the case where the camera is
armed but not actually recording.

Delivery is [ntfy][ntfy], self-hosted. It has its own hostname because it does
not run under a subpath. On Android, turn on instant delivery in the app and it
holds a websocket open to Bilbo, so notifications never touch Google's push
service.

There are four topics, and each one becomes its own notification channel on the
phone, so the quiet ones can be muted without touching the loud ones:

| Topic | Holds | How loud |
| --- | --- | --- |
| `bilbo-hardware` | A dying or dropped disk | Always urgent |
| `bilbo-surveillance` | The camera is armed but nothing is recording | Urgent |
| `bilbo-infra` | Backups, disk space, failed services, restarts | Normal, and only after the problem has lasted a while |
| `bilbo-digest` | The weekly summary | Silent |

Only the first two suggest what to do. The rest just say what happened.

On the phone: install ntfy, set `https://ntfy.fnune.com` as the default server,
sign in as `fausto` with the contents of `/etc/nixos/secrets/ntfy-password`, and
subscribe to the four topics. `ntfy-provision-account.service` owns that account.
After changing the password file, rerun it so the server catches up:

```sh
systemctl restart ntfy-provision-account.service
```

Four things publish:

- `bilbo-alerts.service` runs every two minutes and checks the mirror, the
  camera, Home Assistant, the watched units, the backup, disk space and Zigbee
- `smartd` reports disks that are failing but have not dropped out yet, which is
  the warning that arrives while there is still redundancy
- `bilbo-digest.service` sends the weekly summary on Monday morning
- Home Assistant publishes to `bilbo/notify` over MQTT, and
  `bilbo-notify-bridge.service` forwards it, so Home Assistant never holds the
  ntfy password

Nothing pages on first sight except a dying disk. Every other alert carries a
delay before it notifies and a longer one before it escalates, which is what
keeps a service that restarts itself from ever reaching the phone. The timers
live in `nixos/alerts.nix` as `minutes:priority` pairs.

State sits in `/var/lib/bilbo-alerts`, one file per alert holding when the
problem started and how far it has escalated. Deleting a file makes that alert
announce itself again. To check the path end to end:

```sh
bilbo-notify --topic infra --priority default --title "Test" --body "Ignore me"
```

Nothing outside the house can see whether Bilbo is alive, so a dead machine is
still silent. That needs a watcher somewhere else and does not exist yet.

[ntfy]: https://ntfy.sh

### Replacing a mirror disk

`/mnt/mirrored` is a RAID-1 pair, and it holds Immich plus everything Borg backs
up. When one disk goes, `/proc/mdstat` shows `[U_]` instead of `[UU]`. Nothing
stops working, because the surviving disk serves everything, but there is no
second copy until this is done.

`nixos-rebuild switch` does not repartition anything, so rebuilds stay safe while
the array is degraded. Disko only describes the layout at that point. Its
formatting script is a separate thing you would have to run by hand, and it wipes
both disks, so it is not part of this.

Find the disk that dropped out, and detach it if the array still lists it:

```sh
cat /proc/mdstat
mdadm --detail /dev/md/mirrored
mdadm --manage /dev/md/mirrored --remove /dev/sdb1
```

Power off, swap the disk, and boot again. Copy the partition layout from the
surviving disk onto the new one, then give it its own identifiers:

```sh
sgdisk --replicate=/dev/sdb /dev/sda
sgdisk --randomize-guids /dev/sdb
```

Add it back and wait. Resync runs in the background and the array is usable
throughout:

```sh
mdadm --manage /dev/md/mirrored --add /dev/sdb1
watch cat /proc/mdstat
```

The notification clears itself once `/proc/mdstat` reads `[UU]` again.

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
