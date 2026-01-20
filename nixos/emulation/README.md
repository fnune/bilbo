# Emulation

ROM library management with Syncthing sync to multiple devices.

## Concepts

- System: a gaming platform (gb, snes, psx, switch, etc.)
- Layout: how a setup (EmuDeck, NextUI) organizes ROMs, saves, and BIOS
- Target: a specific device with a layout and system list

## Directory structure

```
/mnt/downloads-2t/Emulation/
├── roms/{system}/           # canonical ROM storage
├── bios/{name}/             # BIOS files by emulator/system
├── saves/{core}/            # saves organized by core name
├── _targets/{target}/       # per-target views (symlinks)
│   ├── roms/
│   ├── saves/
│   └── bios/
└── _config/                 # served via Caddy at /emulation/
```

## Adding a target

In `default.nix`:

```nix
targets.mytarget = {
  layout = "existing-or-new-layout";
  systems = systems;
};
```

## Adding a layout

Create `layouts/{name}.nix` with:

```nix
{
  romFolder = system: { gb = "gb"; ... }.${system} or null;
  saveFolder = system: { gb = "Gambatte"; ... }.${system} or null;
  biosFolder = system: { dreamcast = "dc"; ... }.${system} or null;
}
```

Then import it in `default.nix`.

## Syncthing setup

After deploying, access Syncthing at `/syncthing/`.

Folders are pre-configured:

- `{target}-roms`: Send Only
- `{target}-saves`: Send & Receive
- `{target}-bios`: Send Only

Add target devices manually in the web UI.

## RetroArch settings

For cross-device save compatibility, configure RetroArch on all devices:

```
Settings > Saving:
- Sort Saves into Folders by Core Name: ON
- Sort Save States into Folders by Core Name: ON
- Sort Saves into Folders by Content Directory: OFF
- Sort Save States into Folders by Content Directory: OFF
```

## Adding ROMs

```sh
sftp -i ~/.ssh/<key> <user>@<host>:/mnt/downloads-2t/Emulation/
```

Or use filebrowser at `/filebrowser/`.
