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
| `frigate.env` | `FRIGATE_MQTT_PASSWORD=` matching the Frigate one |
| `zigbee2mqtt.env` | `ZIGBEE2MQTT_CONFIG_MQTT_PASSWORD=` matching the Zigbee2MQTT one, and `ZIGBEE2MQTT_CONFIG_FRONTEND_AUTH_TOKEN=` |
| `go2rtc.env` | `CAMERA_PASSWORD=` for the camera |

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

For the Innr bulbs:

- The wall switch must stay on or the bulbs are unreachable. A Zigbee remote is
  worth adding so there is a physical control that does not cut power.
- Set power-on behaviour to `previous`, so an outage does not bring the bedroom
  back at full-brightness cold white.

### Home Assistant

[Home Assistant][home-assistant] owns the lighting. Its base configuration is
declarative. Automations, scenes and scripts are
`!include`d from `/var/lib/hass` so they stay editable from the UI without a
rebuild. Those files are not in this repository; back them up with `/var/lib`.

On first run create the owner account, then add MQTT under Settings -> Devices &
Services -> Add integration -> MQTT, pointing at `127.0.0.1:1883` as
`home-assistant`. It cannot be declared in Nix because MQTT uses a config flow.

Once MQTT is up, the bulbs arrive through Zigbee2MQTT discovery and Frigate
publishes its cameras and sensors the same way.

`input_boolean.away` exists to gate the deterrent lighting and notifications.
Frigate's own web push can be switched at runtime by publishing to
`frigate/notifications/set`, so an automation can silence it while you are home
rather than duplicating notifications in Home Assistant.

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
