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

MQTT is shared by Frigate, Zigbee2MQTT and Home Assistant. Mosquitto only
listens on `127.0.0.1` and every client authenticates, so create these files as
`root` before the first rebuild. The `mosquitto-*` files hold a plaintext
password that Mosquitto hashes when the unit starts; the passwords in the `.env`
files must match them exactly.

```sh
mkdir -p /etc/nixos/secrets
chmod 700 /etc/nixos/secrets

# One password per client. Any long random string will do:
openssl rand -base64 24 > /etc/nixos/secrets/mosquitto-frigate-password
openssl rand -base64 24 > /etc/nixos/secrets/mosquitto-zigbee2mqtt-password
openssl rand -base64 24 > /etc/nixos/secrets/mosquitto-home-assistant-password
```

`/etc/nixos/secrets/frigate.env`, where `FRIGATE_MQTT_PASSWORD` matches
`mosquitto-frigate-password`:

```sh
FRIGATE_MQTT_PASSWORD=...
```

`/etc/nixos/secrets/go2rtc.env`, holding the camera's own password. go2rtc is
the only service that connects to the camera — Frigate reads both streams back
from go2rtc's restream on localhost, so the camera credential never reaches
Frigate's config or database:

```sh
CAMERA_PASSWORD=...
```

`/etc/nixos/secrets/zigbee2mqtt.env`, where the MQTT password matches
`mosquitto-zigbee2mqtt-password`. The auth token gates the Zigbee2MQTT frontend,
which is reachable from the public `bilbo.fnune.com` origin and can otherwise
re-pair or factory-reset your devices:

```sh
ZIGBEE2MQTT_CONFIG_MQTT_PASSWORD=...
ZIGBEE2MQTT_CONFIG_FRONTEND_AUTH_TOKEN=...
```

### Camera

Do this over the camera's own web UI, on the LAN, before it is wired into
anything else:

- Change the default password. Do this first.
- Disable every cloud, P2P and UPnP option you can find.
- Set the main stream to H.264. H.265 works for recording but breaks live view
  in most browsers.
- Note the substream's real resolution. Frigate detects on the substream, and
  Anpviz substreams are sometimes too small to detect on reliably — if it is
  below roughly 640x480, enable a third stream and use that instead.
- Confirm the RTSP paths. `nixos/frigate.nix` assumes the Hikvision-style
  `stream0` (main) and `stream1` (sub). Verify with:

  ```sh
  ffprobe rtsp://admin:PASSWORD@CAMERA_IP:554/stream0
  ffprobe rtsp://admin:PASSWORD@CAMERA_IP:554/stream1
  ```

Then, in the FritzBox, since it has no VLANs:

- Give the camera a static IPv4 lease.
- Create a Zugangsprofil with no internet access and apply it to the camera.
  This is the substitute for putting the camera on its own VLAN, and it is the
  only thing stopping the camera from talking to its vendor.

Finally, replace the placeholders in `nixos/frigate.nix`:
`REPLACE_WITH_CAMERA_IP`, the two stream paths, and the `detect` width and
height, which must match the substream you picked.

### Frigate

Frigate gets its own hostname rather than a subpath, because subpath proxying
breaks its websockets and its service worker. Caddy terminates TLS and forwards
to the nginx vhost that the NixOS module insists on building; nginx listens on
`127.0.0.1:8971` so it stays out of Caddy's way on ports 80 and 443.

The camera is opened once, by go2rtc, which restreams both the main and the
substream on localhost. Frigate pulls detect and record from that restream
rather than from the camera, which keeps the camera to a single connection and
gives the live view MSE and WebRTC instead of the much heavier jsmpeg fallback.
The NixOS Frigate module does not configure go2rtc itself — it only proxies to
it — so `nixos/frigate.nix` enables `services.go2rtc` and hands the same stream
definitions to both.

nixpkgs ships no OpenVINO model — only the TFLite CPU one and the OpenVINO
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
actually working — the inference speed is on the System Metrics page, and should
land around 26-28 ms:

```sh
journalctl -u frigate.service | grep -i openvino
intel_gpu_top
```

If OpenVINO fails to initialise on the iGPU — the J4125's UHD 600 has been
reported to need a 5.x kernel, and this machine is on 6.x — change `device` in
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

Plug the ZBDongle-P into a USB 2.0 port using one of the extension cables —
never directly into the chassis or a USB 3.0 port, whose 2.4 GHz noise will wreck
the Zigbee mesh. Then find its stable device path and replace
`REPLACE_WITH_DONGLE_SERIAL` in `nixos/zigbee2mqtt.nix`:

```sh
ls -l /dev/serial/by-id/
```

Pairing is disabled in the committed config. Enable joining from the
[Zigbee2MQTT][zigbee2mqtt] frontend only while adding a device, then turn it off
again. For the Innr bulbs:

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
*not* in this repository — back them up with the rest of `/var/lib`.

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
