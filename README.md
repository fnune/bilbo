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
[sops-nix]: https://github.com/Mic92/sops-nix
[agenix]: https://github.com/ryantm/agenix

### Secrets

These are hand-placed files under `/etc/nixos/secrets`, following the same
pattern `nixos/backups.nix` already uses for the Borg passphrase and the rclone
config. Nothing here is declarative: the files are invisible to this repository
and to `nixos-rebuild`, so a fresh machine needs them recreated by hand before
the first build of these services will start. Moving the whole repository to
[sops-nix][sops-nix] or [agenix][agenix], which keep encrypted secrets in git and
decrypt them at activation, is the obvious upgrade and would cover the Borg
secrets too.

Six files are needed. Three of them have to agree with each other, because
Mosquitto listens only on `127.0.0.1` and every client authenticates:

| File | Contents |
| --- | --- |
| `mosquitto-frigate-password` | plaintext password |
| `mosquitto-zigbee2mqtt-password` | plaintext password |
| `mosquitto-home-assistant-password` | plaintext password |
| `frigate.env` | `FRIGATE_MQTT_PASSWORD=` matching the Frigate one |
| `zigbee2mqtt.env` | `ZIGBEE2MQTT_CONFIG_MQTT_PASSWORD=` matching the Zigbee2MQTT one, plus `ZIGBEE2MQTT_CONFIG_FRONTEND_AUTH_TOKEN=` |
| `go2rtc.env` | `CAMERA_PASSWORD=` for the camera itself |

The `mosquitto-*` files hold the password on a single line and nothing else;
Mosquitto hashes it into `/etc/mosquitto/passwd` when the unit starts, and the
trailing newline is stripped. The `.env` files are systemd `EnvironmentFile`s, so
each line is `KEY=value` with no `export`, no quotes and no spaces around the
`=`. None of these paths are optional in the unit definitions, so a missing file
fails the service rather than starting it unauthenticated.

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

`go2rtc.env` is the exception: its value is the password you set in the camera's
own web UI, so write it by hand and `chmod 600` it. go2rtc is the only service
that opens the camera, and Frigate reads both streams back from the restream on
localhost, so the camera credential never reaches Frigate's config or database.
Because the password is interpolated into an RTSP URL, avoid `@ : / ? #` in it or
percent-encode them.

The `ZIGBEE2MQTT_CONFIG_FRONTEND_AUTH_TOKEN` gates the Zigbee2MQTT frontend,
which is reachable from the public `bilbo.fnune.com` origin and can otherwise
re-pair or factory-reset your devices.

### Camera

The Anpviz IPC-D3243W-S runs OEM Hikvision-lineage firmware and sits at
`192.168.178.109`, hardcoded in `nixos/frigate.nix`. Its streams, as measured
with `ffprobe`:

| Path | Resolution | Role |
| --- | --- | --- |
| `stream0` | 2560x1440 at 25 fps | record |
| `stream1` | 640x360 at 25 fps | detect |
| `stream2` | does not exist | |

Both are H.265 as shipped. Recording is a stream copy so H.265 costs nothing
there, but it makes live view and playback unreliable outside Safari, so set both
to H.264 in the camera UI. `detect.width` and `detect.height` in
`nixos/frigate.nix` are pinned to the measured 640x360; Frigate can probe this
itself, but pinning it avoids falling back to a wrong default if the probe fails
at startup. Re-measure with:

```sh
ffprobe rtsp://admin:PASSWORD@192.168.178.109:554/stream1
```

In the camera's own web UI:

- Change the default password. It ships as `123456`.
- Under Service Ports, disable ONVIF, HIK (port 8000) and DAHUA (port 37777).
  HIK and DAHUA are unauthenticated control protocols and were both reachable on
  the LAN out of the box. Nothing here uses them: Frigate only needs RTSP, and
  ONVIF would only matter for a PTZ camera. The Control Protocol on 8091 only
  serves the vendor's discovery tool and can go too, now the address is fixed.
- Under Date & Time, set NTP to `192.168.178.1`, the timezone to GMT+01:00, and
  enable DST with the European rules: last Sunday of March at 02:00 to last
  Sunday of October at 03:00. The NTP server field looks like a fixed dropdown
  but accepts free text. This only affects the timestamp burnt into the picture,
  since Frigate stamps recordings itself.

Then, in the FritzBox, which has no VLANs:

- Give the camera a static IPv4 lease, since the address is hardcoded. Leave the
  camera itself on DHCP so the address is only configured in one place.
- Under Internet -> Filters -> Parental Controls, set the camera's access profile
  to the built-in `Blocked`. This is the substitute for putting the camera on its
  own VLAN, and it is the only thing stopping it from talking to its vendor. It
  blocks internet only, so RTSP from bilbo still works. The camera was reaching
  for `google.cn` before this was applied.

Do not add a port forward to the camera. It is reached through bilbo.

### Frigate

Frigate gets its own hostname rather than a subpath, because subpath proxying
breaks its websockets and its service worker. Caddy terminates TLS and forwards
to the nginx vhost that the NixOS module insists on building; nginx listens on
`127.0.0.1:8971` so it stays out of Caddy's way on ports 80 and 443.

The camera is opened once, by go2rtc, which restreams both the main and the
substream on localhost. Frigate pulls detect and record from that restream
rather than from the camera, which keeps the camera to a single connection and
gives the live view MSE and WebRTC instead of the much heavier jsmpeg fallback.
The NixOS Frigate module does not configure go2rtc itself; it only proxies to
it, so `nixos/frigate.nix` enables `services.go2rtc` and hands the same stream
definitions to both.

nixpkgs ships no OpenVINO model, only the TFLite CPU one and the OpenVINO
labelmap. The `frigate-openvino-model` unit therefore pulls the official Frigate
container image with `skopeo` and extracts `/openvino-model` out of it before
`frigate.service` starts. It runs once, skips instantly when the model is
already on disk, and fails loudly rather than letting Frigate start without a
detector. To refresh it after a Frigate version bump:

```sh
rm -rf /var/lib/frigate/openvino-model
systemctl restart frigate-openvino-model
```

On first start Frigate prints a generated admin password:

```sh
journalctl -u frigate.service | grep 'Password:'
```

Log in at [Frigate][frigate] and change it. Then check that the GPU detector is
actually working. The inference speed is on the System Metrics page, and should
land around 26-28 ms:

```sh
journalctl -u frigate.service | grep -i openvino
intel_gpu_top
```

If OpenVINO fails to initialise on the iGPU, and the J4125's UHD 600 has been
reported to need a 5.x kernel while this machine is on 6.x, change `device` in
`nixos/frigate.nix` from `"GPU"` to `"CPU"` first. That keeps the same model and
is usually still faster than the TFLite CPU detector. Only if that also fails,
replace the whole `detectors` and `model` block with:

```nix
detectors.cpu.type = "cpu";
```

and drop the `model` block entirely, which lets the bundled TFLite model take
over. At 5 fps on one camera, ~150 ms inference is still adequate.

Recordings are event-only: nothing continuous is kept, and footage overlapping
alerts and detections is retained for 30 days. `/var/lib/frigate/recordings` is
a symlink to `/mnt/downloads-2t/frigate/recordings` so clips land on the 2 TB
disk instead of the root partition, and `adjustMountPoints` in `nixos/drives.nix`
skips that directory so it does not chown every recording to `fausto` on each
boot. If Frigate has already written recordings to the root partition, move them
across before the symlink can be created.

Detection accuracy on one indoor camera depends far more on motion masks than on
raw compute. Draw them in the Frigate UI under Settings once real footage exists.

### Zigbee and lighting

Plug the ZBDongle-P into a USB 2.0 port using one of the extension cables, never
directly into the chassis or a USB 3.0 port, whose 2.4 GHz noise will wreck the
Zigbee mesh.

`nixos/zigbee2mqtt.nix` ships a udev rule that matches the dongle on its USB
vendor, product and manufacturer strings and gives it `/dev/zigbee`. That avoids
publishing the dongle's serial number in this public repository, and sidesteps
the `/dev/serial/by-id` directory being `0700 root:root`. Swapping in a different
CC2652P stick means updating the rule; `udevadm info -a -n /dev/ttyUSB0` prints
the attributes to match on.

Joining is off by default in Zigbee2MQTT 2.x and is a runtime setting rather than
a config file one. Enable it from the [Zigbee2MQTT][zigbee2mqtt] frontend only
while adding a device, then turn it off again. For the Innr bulbs:

- The wall switch has to stay permanently on, or the bulbs are unreachable.
  A Zigbee wall remote or button is worth adding so there is a physical control
  that does not cut power; without one, the phone is the only control.
- Set the power-on behaviour to `previous` in the device's Zigbee2MQTT settings,
  so an outage does not bring the bedroom back at full-brightness cold white.

### Home Assistant

[Home Assistant][home-assistant] owns the lighting. Its base configuration is
declarative, but automations, scenes, scripts and dashboards are deliberately
left UI-editable so the bedroom schedule can be retuned from the phone without a
rebuild. Those live in `/var/lib/hass/{automations,scenes,scripts}.yaml` and are
*not* in this repository, so back them up with the rest of `/var/lib`.

On first run, create the owner account, then add the MQTT integration by hand
under Settings -> Devices & Services -> Add integration -> MQTT, pointing at
`127.0.0.1:1883` with the `home-assistant` user and its password. It cannot be
declared in Nix because MQTT is set up through a config flow.

Once MQTT is connected, the Innr bulbs appear automatically through Zigbee2MQTT's
discovery, and Frigate publishes its cameras and sensors the same way. The
richer Frigate dashboard card is a HACS integration and is not installed here;
the MQTT-discovered entities are enough for notifications and automations.

The `input_boolean.away` toggle is declared in Nix so the entity always exists,
and gates the occupancy-simulation schedule. Build the automations on top of it
in the UI:

- Trigger on sunset with a random offset, condition on `input_boolean.away`
  being on, then turn the bedroom light on. Add a second automation for a random
  time later in the evening that turns it off.
- Because every deterrent automation is conditioned on `away`, normal use at
  home is never fought by the schedule, and manual control never has to fight
  the automation. Flip the toggle from the dashboard when you leave.

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
