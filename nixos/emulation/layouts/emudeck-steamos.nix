# https://emudeck.github.io/cheat-sheet/
{
  devicePaths = {
    roms = "roms";
    saves = "saves";
    bios = "bios";
  };

  romFolder = system: system;

  # https://emudeck.github.io/save-management/steamos/save-management/
  saveFolder = system: let
    mappings = {
      # nintendo
      gb = { base = "gambatte"; target = "retroarch/saves/Gambatte"; };
      gbc = { base = "gambatte"; target = "retroarch/saves/Gambatte"; };
      sgb = { base = "gambatte"; target = "retroarch/saves/Gambatte"; };
      gba = { base = "mgba"; target = "retroarch/saves/mGBA"; };
      nes = { base = "mesen"; target = "retroarch/saves/Mesen"; };
      famicom = { base = "mesen"; target = "retroarch/saves/Mesen"; };
      fds = { base = "mesen"; target = "retroarch/saves/Mesen"; };
      snes = { base = "snes9x"; target = "retroarch/saves/Snes9x"; };
      sfc = { base = "snes9x"; target = "retroarch/saves/Snes9x"; };
      snesna = { base = "snes9x"; target = "retroarch/saves/Snes9x"; };
      sneshd = { base = "snes9x"; target = "retroarch/saves/Snes9x"; };
      satellaview = { base = "snes9x"; target = "retroarch/saves/Snes9x"; };
      sufami = { base = "snes9x"; target = "retroarch/saves/Snes9x"; };
      n64 = { base = "mupen64plus"; target = "retroarch/saves/Mupen64Plus-Next"; };
      n64dd = { base = "mupen64plus"; target = "retroarch/saves/Mupen64Plus-Next"; };
      nds = { base = "melonds"; target = "melonds/saves"; };
      virtualboy = { base = "beetle-vb"; target = "retroarch/saves/Beetle VB"; };
      pokemini = { base = "pokemini"; target = "retroarch/saves/PokeMini"; };
      gamecube = { base = "dolphin-gc"; target = "dolphin/GC"; };
      gc = { base = "dolphin-gc"; target = "dolphin/GC"; };
      wii = { base = "dolphin-wii"; target = "dolphin/Wii"; };
      primehacks = { base = "dolphin-wii"; target = "dolphin/Wii"; };
      n3ds = { base = "azahar"; target = "azahar/saves"; };
      wiiu = { base = "cemu"; target = "Cemu/saves"; };
      switch = { base = "ryujinx"; target = "ryujinx/saves"; };

      # sega
      genesis = { base = "genesis-plus-gx"; target = "retroarch/saves/Genesis Plus GX"; };
      megadrive = { base = "genesis-plus-gx"; target = "retroarch/saves/Genesis Plus GX"; };
      megadrivejp = { base = "genesis-plus-gx"; target = "retroarch/saves/Genesis Plus GX"; };
      genesiswide = { base = "genesis-plus-gx-wide"; target = "retroarch/saves/Genesis Plus GX Wide"; };
      mastersystem = { base = "genesis-plus-gx"; target = "retroarch/saves/Genesis Plus GX"; };
      gamegear = { base = "genesis-plus-gx"; target = "retroarch/saves/Genesis Plus GX"; };
      sg-1000 = { base = "genesis-plus-gx"; target = "retroarch/saves/Genesis Plus GX"; };
      segacd = { base = "genesis-plus-gx"; target = "retroarch/saves/Genesis Plus GX"; };
      megacd = { base = "genesis-plus-gx"; target = "retroarch/saves/Genesis Plus GX"; };
      megacdjp = { base = "genesis-plus-gx"; target = "retroarch/saves/Genesis Plus GX"; };
      sega32x = { base = "picodrive"; target = "retroarch/saves/PicoDrive"; };
      sega32xjp = { base = "picodrive"; target = "retroarch/saves/PicoDrive"; };
      sega32xna = { base = "picodrive"; target = "retroarch/saves/PicoDrive"; };
      saturn = { base = "beetle-saturn"; target = "retroarch/saves/Beetle Saturn"; };
      saturnjp = { base = "beetle-saturn"; target = "retroarch/saves/Beetle Saturn"; };
      dreamcast = { base = "flycast"; target = "retroarch/saves/Flycast"; };
      naomi = { base = "flycast"; target = "retroarch/saves/Flycast"; };
      naomi2 = { base = "flycast"; target = "retroarch/saves/Flycast"; };
      naomigd = { base = "flycast"; target = "retroarch/saves/Flycast"; };
      atomiswave = { base = "flycast"; target = "retroarch/saves/Flycast"; };

      # sony
      psx = { base = "duckstation"; target = "duckstation/saves"; };
      ps2 = { base = "pcsx2"; target = "pcsx2/saves"; };
      psp = { base = "ppsspp"; target = "ppsspp/saves"; };
      psvita = { base = "vita3k"; target = "Vita3K/saves"; };

      # nec
      pcengine = { base = "beetle-pce"; target = "retroarch/saves/Beetle PCE"; };
      pcenginecd = { base = "beetle-pce"; target = "retroarch/saves/Beetle PCE"; };
      tg16 = { base = "beetle-pce"; target = "retroarch/saves/Beetle PCE"; };
      tg-cd = { base = "beetle-pce"; target = "retroarch/saves/Beetle PCE"; };
      supergrafx = { base = "beetle-supergrafx"; target = "retroarch/saves/Beetle SuperGrafx"; };
      pcfx = { base = "beetle-pcfx"; target = "retroarch/saves/Beetle PC-FX"; };

      # snk
      neogeo = { base = "fbneo"; target = "retroarch/saves/FinalBurn Neo"; };
      neogeocd = { base = "neocd"; target = "retroarch/saves/NeoCD"; };
      neogeocdjp = { base = "neocd"; target = "retroarch/saves/NeoCD"; };
      ngp = { base = "beetle-neopop"; target = "retroarch/saves/Beetle NeoPop"; };
      ngpc = { base = "beetle-neopop"; target = "retroarch/saves/Beetle NeoPop"; };

      # atari
      atari2600 = { base = "stella"; target = "retroarch/saves/Stella"; };
      atari5200 = { base = "a5200"; target = "retroarch/saves/a5200"; };
      atari7800 = { base = "prosystem"; target = "retroarch/saves/ProSystem"; };
      atari800 = { base = "atari800"; target = "retroarch/saves/Atari800"; };
      atarixe = { base = "atari800"; target = "retroarch/saves/Atari800"; };
      atarilynx = { base = "beetle-lynx"; target = "retroarch/saves/Beetle Lynx"; };
      atarijaguar = { base = "bigpemu"; target = "bigpemu/saves"; };
      atarist = { base = "hatari"; target = "retroarch/saves/Hatari"; };

      # other consoles
      "3do" = { base = "opera"; target = "retroarch/saves/Opera"; };
      colecovision = { base = "bluemsx"; target = "retroarch/saves/blueMSX"; };
      intellivision = { base = "freeintv"; target = "retroarch/saves/FreeIntv"; };
      odyssey2 = { base = "o2em"; target = "retroarch/saves/O2EM"; };
      videopac = { base = "o2em"; target = "retroarch/saves/O2EM"; };
      vectrex = { base = "vecx"; target = "retroarch/saves/vecx"; };
      channelf = { base = "freechaf"; target = "retroarch/saves/FreeChaF"; };
      wonderswan = { base = "beetle-cygne"; target = "retroarch/saves/Beetle Cygne"; };
      wonderswancolor = { base = "beetle-cygne"; target = "retroarch/saves/Beetle Cygne"; };
      supervision = { base = "potator"; target = "retroarch/saves/Potator"; };

      # computers
      amiga = { base = "puae"; target = "retroarch/saves/PUAE"; };
      amiga1200 = { base = "puae"; target = "retroarch/saves/PUAE"; };
      amiga600 = { base = "puae"; target = "retroarch/saves/PUAE"; };
      amigacd32 = { base = "puae"; target = "retroarch/saves/PUAE"; };
      cdtv = { base = "puae"; target = "retroarch/saves/PUAE"; };
      c64 = { base = "vice-x64sc"; target = "retroarch/saves/VICE x64sc"; };
      c16 = { base = "vice-xplus4"; target = "retroarch/saves/VICE xplus4"; };
      vic20 = { base = "vice-xvic"; target = "retroarch/saves/VICE xvic"; };
      msx = { base = "bluemsx"; target = "retroarch/saves/blueMSX"; };
      msx1 = { base = "bluemsx"; target = "retroarch/saves/blueMSX"; };
      msx2 = { base = "bluemsx"; target = "retroarch/saves/blueMSX"; };
      msxturbor = { base = "bluemsx"; target = "retroarch/saves/blueMSX"; };
      dos = { base = "dosbox-pure"; target = "retroarch/saves/DOSBox Pure"; };
      pc = { base = "dosbox-pure"; target = "retroarch/saves/DOSBox Pure"; };
      pc88 = { base = "quasi88"; target = "retroarch/saves/QUASI88"; };
      pc98 = { base = "np2kai"; target = "retroarch/saves/Neko Project II kai"; };
      x68000 = { base = "px68k"; target = "retroarch/saves/PX68K"; };
      zxspectrum = { base = "fuse"; target = "retroarch/saves/Fuse"; };
      zx81 = { base = "eightyone"; target = "retroarch/saves/EightyOne"; };
      amstradcpc = { base = "caprice32"; target = "retroarch/saves/Caprice32"; };
      scummvm = { base = "scummvm"; target = "scummvm/saves"; };

      # arcade
      arcade = { base = "fbneo"; target = "retroarch/saves/FinalBurn Neo"; };
      fba = { base = "fbneo"; target = "retroarch/saves/FinalBurn Neo"; };
      fbneo = { base = "fbneo"; target = "retroarch/saves/FinalBurn Neo"; };
      cps = { base = "fbneo"; target = "retroarch/saves/FinalBurn Neo"; };
      cps1 = { base = "fbneo"; target = "retroarch/saves/FinalBurn Neo"; };
      cps2 = { base = "fbneo"; target = "retroarch/saves/FinalBurn Neo"; };
      cps3 = { base = "fbneo"; target = "retroarch/saves/FinalBurn Neo"; };
      mame = { base = "mame2003plus"; target = "retroarch/saves/MAME 2003-Plus"; };
      daphne = { base = "dirksimple"; target = "retroarch/saves/DirkSimple"; };
    };
  in mappings.${system} or null;

  biosFolder = system:
    {
      dreamcast = "dc";
      naomi = "dc";
      naomi2 = "dc";
      naomigd = "dc";
      atomiswave = "dc";
      saturn = "saturn";
      saturnjp = "saturn";
      segacd = "segacd";
      megacd = "segacd";
      megacdjp = "segacd";
      pcenginecd = "pcengine";
      tg-cd = "pcengine";
      pcfx = "pcfx";
      nds = "nds";
      n3ds = "citra";
      psx = "duckstation";
      ps2 = "pcsx2";
      psp = "ppsspp";
      psvita = "vita3k";
      wiiu = "cemu";
      switch = "switch";
      xbox = "xemu";
    }
    .${
      system
    }
    or null;
}
