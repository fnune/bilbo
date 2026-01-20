# https://emudeck.github.io/cheat-sheet/
{
  romFolder = system: system;

  # https://emudeck.github.io/save-management/steamos/save-management/
  saveFolder = system:
    {
      # nintendo
      gb = "retroarch/saves/Gambatte";
      gbc = "retroarch/saves/Gambatte";
      sgb = "retroarch/saves/Gambatte";
      gba = "retroarch/saves/mGBA";
      nes = "retroarch/saves/Mesen";
      famicom = "retroarch/saves/Mesen";
      fds = "retroarch/saves/Mesen";
      snes = "retroarch/saves/Snes9x";
      sfc = "retroarch/saves/Snes9x";
      snesna = "retroarch/saves/Snes9x";
      sneshd = "retroarch/saves/Snes9x";
      satellaview = "retroarch/saves/Snes9x";
      sufami = "retroarch/saves/Snes9x";
      n64 = "retroarch/saves/Mupen64Plus-Next";
      n64dd = "retroarch/saves/Mupen64Plus-Next";
      nds = "melonds/saves";
      virtualboy = "retroarch/saves/Beetle VB";
      pokemini = "retroarch/saves/PokeMini";
      gamecube = "dolphin/GC";
      gc = "dolphin/GC";
      wii = "dolphin/Wii";
      primehacks = "dolphin/Wii";
      n3ds = "azahar/saves";
      wiiu = "Cemu/saves";
      switch = "ryujinx/saves";

      # sega
      genesis = "retroarch/saves/Genesis Plus GX";
      megadrive = "retroarch/saves/Genesis Plus GX";
      megadrivejp = "retroarch/saves/Genesis Plus GX";
      genesiswide = "retroarch/saves/Genesis Plus GX Wide";
      mastersystem = "retroarch/saves/Genesis Plus GX";
      gamegear = "retroarch/saves/Genesis Plus GX";
      sg-1000 = "retroarch/saves/Genesis Plus GX";
      segacd = "retroarch/saves/Genesis Plus GX";
      megacd = "retroarch/saves/Genesis Plus GX";
      megacdjp = "retroarch/saves/Genesis Plus GX";
      sega32x = "retroarch/saves/PicoDrive";
      sega32xjp = "retroarch/saves/PicoDrive";
      sega32xna = "retroarch/saves/PicoDrive";
      saturn = "retroarch/saves/Beetle Saturn";
      saturnjp = "retroarch/saves/Beetle Saturn";
      dreamcast = "retroarch/saves/Flycast";
      naomi = "retroarch/saves/Flycast";
      naomi2 = "retroarch/saves/Flycast";
      naomigd = "retroarch/saves/Flycast";
      atomiswave = "retroarch/saves/Flycast";

      # sony
      psx = "duckstation/saves";
      ps2 = "pcsx2/sstates";
      ps3 = "rpcs3/trophy";
      psp = "ppsspp/saves";
      psvita = "Vita3K/saves";

      # nec
      pcengine = "retroarch/saves/Beetle PCE";
      pcenginecd = "retroarch/saves/Beetle PCE";
      tg16 = "retroarch/saves/Beetle PCE";
      tg-cd = "retroarch/saves/Beetle PCE";
      supergrafx = "retroarch/saves/Beetle SuperGrafx";
      pcfx = "retroarch/saves/Beetle PC-FX";

      # snk
      neogeo = "retroarch/saves/FinalBurn Neo";
      neogeocd = "retroarch/saves/NeoCD";
      neogeocdjp = "retroarch/saves/NeoCD";
      ngp = "retroarch/saves/Beetle NeoPop";
      ngpc = "retroarch/saves/Beetle NeoPop";

      # atari
      atari2600 = "retroarch/saves/Stella";
      atari5200 = "retroarch/saves/a5200";
      atari7800 = "retroarch/saves/ProSystem";
      atari800 = "retroarch/saves/Atari800";
      atarixe = "retroarch/saves/Atari800";
      atarilynx = "retroarch/saves/Beetle Lynx";
      atarijaguar = "bigpemu/saves";
      atarist = "retroarch/saves/Hatari";

      # other consoles
      "3do" = "retroarch/saves/Opera";
      colecovision = "retroarch/saves/blueMSX";
      intellivision = "retroarch/saves/FreeIntv";
      odyssey2 = "retroarch/saves/O2EM";
      videopac = "retroarch/saves/O2EM";
      vectrex = "retroarch/saves/vecx";
      channelf = "retroarch/saves/FreeChaF";
      wonderswan = "retroarch/saves/Beetle Cygne";
      wonderswancolor = "retroarch/saves/Beetle Cygne";
      supervision = "retroarch/saves/Potator";

      # computers
      amiga = "retroarch/saves/PUAE";
      amiga1200 = "retroarch/saves/PUAE";
      amiga600 = "retroarch/saves/PUAE";
      amigacd32 = "retroarch/saves/PUAE";
      cdtv = "retroarch/saves/PUAE";
      c64 = "retroarch/saves/VICE x64sc";
      c16 = "retroarch/saves/VICE xplus4";
      vic20 = "retroarch/saves/VICE xvic";
      msx = "retroarch/saves/blueMSX";
      msx1 = "retroarch/saves/blueMSX";
      msx2 = "retroarch/saves/blueMSX";
      msxturbor = "retroarch/saves/blueMSX";
      dos = "retroarch/saves/DOSBox Pure";
      pc = "retroarch/saves/DOSBox Pure";
      pc88 = "retroarch/saves/QUASI88";
      pc98 = "retroarch/saves/Neko Project II kai";
      x68000 = "retroarch/saves/PX68K";
      zxspectrum = "retroarch/saves/Fuse";
      zx81 = "retroarch/saves/EightyOne";
      amstradcpc = "retroarch/saves/Caprice32";
      scummvm = "scummvm/saves";

      # arcade
      arcade = "retroarch/saves/FinalBurn Neo";
      fba = "retroarch/saves/FinalBurn Neo";
      fbneo = "retroarch/saves/FinalBurn Neo";
      cps = "retroarch/saves/FinalBurn Neo";
      cps1 = "retroarch/saves/FinalBurn Neo";
      cps2 = "retroarch/saves/FinalBurn Neo";
      cps3 = "retroarch/saves/FinalBurn Neo";
      mame = "retroarch/saves/MAME 2003-Plus";
      daphne = "retroarch/saves/DirkSimple";
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
