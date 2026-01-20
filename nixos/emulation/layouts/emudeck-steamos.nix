# https://emudeck.github.io/cheat-sheet/
{
  romFolder = system: system;

  # https://emudeck.github.io/save-management/steamos/save-management/
  saveFolder = system:
    {
      # nintendo
      gb = "Gambatte";
      gbc = "Gambatte";
      sgb = "Gambatte";
      gba = "mGBA";
      nes = "Mesen";
      famicom = "Mesen";
      fds = "Mesen";
      snes = "Snes9x";
      sfc = "Snes9x";
      snesna = "Snes9x";
      sneshd = "Snes9x";
      satellaview = "Snes9x";
      sufami = "Snes9x";
      n64 = "Mupen64Plus-Next";
      n64dd = "Mupen64Plus-Next";
      nds = "melonDS";
      virtualboy = "Beetle VB";
      pokemini = "PokeMini";
      gamecube = "dolphin/GC";
      gc = "dolphin/GC";
      wii = "dolphin/Wii";
      primehacks = "dolphin/Wii";
      n3ds = "citra/sdmc";
      wiiu = "cemu/saves";
      switch = "ryujinx/saves";

      # sega
      genesis = "Genesis Plus GX";
      megadrive = "Genesis Plus GX";
      megadrivejp = "Genesis Plus GX";
      genesiswide = "Genesis Plus GX Wide";
      mastersystem = "Genesis Plus GX";
      gamegear = "Genesis Plus GX";
      sg-1000 = "Genesis Plus GX";
      segacd = "Genesis Plus GX";
      megacd = "Genesis Plus GX";
      megacdjp = "Genesis Plus GX";
      sega32x = "PicoDrive";
      sega32xjp = "PicoDrive";
      sega32xna = "PicoDrive";
      saturn = "Beetle Saturn";
      saturnjp = "Beetle Saturn";
      dreamcast = "Flycast";
      naomi = "Flycast";
      naomi2 = "Flycast";
      naomigd = "Flycast";
      atomiswave = "Flycast";

      # sony
      psx = "duckstation/saves";
      ps2 = "pcsx2/sstates";
      ps3 = "rpcs3/saves";
      psp = "PPSSPP";
      psvita = "vita3k/saves";

      # nec
      pcengine = "Beetle PCE";
      pcenginecd = "Beetle PCE";
      tg16 = "Beetle PCE";
      tg-cd = "Beetle PCE";
      supergrafx = "Beetle SuperGrafx";
      pcfx = "Beetle PC-FX";

      # snk
      neogeo = "FinalBurn Neo";
      neogeocd = "NeoCD";
      neogeocdjp = "NeoCD";
      ngp = "Beetle NeoPop";
      ngpc = "Beetle NeoPop";

      # atari
      atari2600 = "Stella";
      atari5200 = "a5200";
      atari7800 = "ProSystem";
      atari800 = "Atari800";
      atarixe = "Atari800";
      atarilynx = "Beetle Lynx";
      atarijaguar = "BigPEmu";
      atarist = "Hatari";

      # other consoles
      "3do" = "Opera";
      colecovision = "blueMSX";
      intellivision = "FreeIntv";
      odyssey2 = "O2EM";
      videopac = "O2EM";
      vectrex = "vecx";
      channelf = "FreeChaF";
      wonderswan = "Beetle Cygne";
      wonderswancolor = "Beetle Cygne";
      supervision = "Potator";

      # computers
      amiga = "PUAE";
      amiga1200 = "PUAE";
      amiga600 = "PUAE";
      amigacd32 = "PUAE";
      cdtv = "PUAE";
      c64 = "VICE x64sc";
      c16 = "VICE xplus4";
      vic20 = "VICE xvic";
      msx = "blueMSX";
      msx1 = "blueMSX";
      msx2 = "blueMSX";
      msxturbor = "blueMSX";
      dos = "DOSBox Pure";
      pc = "DOSBox Pure";
      pc88 = "QUASI88";
      pc98 = "Neko Project II kai";
      x68000 = "PX68K";
      zxspectrum = "Fuse";
      zx81 = "EightyOne";
      amstradcpc = "Caprice32";
      scummvm = "ScummVM";

      # arcade
      arcade = "FinalBurn Neo";
      fba = "FinalBurn Neo";
      fbneo = "FinalBurn Neo";
      cps = "FinalBurn Neo";
      cps1 = "FinalBurn Neo";
      cps2 = "FinalBurn Neo";
      cps3 = "FinalBurn Neo";
      mame = "MAME 2003-Plus";
      daphne = "DirkSimple";
    }
    .${
      system
    }
    or null;

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
      ps2 = "pcsx2";
      ps3 = "rpcs3";
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
