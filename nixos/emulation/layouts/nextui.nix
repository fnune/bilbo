# https://nextui.loveretro.games/
{
  romFolder = system:
    {
      gb = "Game Boy (GB)";
      gbc = "Game Boy Color (GBC)";
      gba = "Game Boy Advance (GBA)";
      nes = "Nintendo (FC)";
      famicom = "Famicom (FC)";
      snes = "Super Nintendo (SFC)";
      sfc = "Super Famicom (SFC)";
      genesis = "Sega Genesis (MD)";
      megadrive = "Mega Drive (MD)";
      mastersystem = "Master System (MS)";
      gamegear = "Game Gear (GG)";
      segacd = "Sega CD (SEGACD)";
      psx = "PlayStation (PS)";
      nds = "Nintendo DS (NDS)";
      dreamcast = "Dreamcast (DC)";
      pcengine = "PC Engine (PCE)";
      tg16 = "TurboGrafx-16 (PCE)";
      neogeo = "Neo Geo (FBN)";
      arcade = "Arcade (FBN)";
      fbneo = "FinalBurn Neo (FBN)";
      atarilynx = "Atari Lynx (LYNX)";
      pokemini = "Pokemon Mini (PKM)";
      pico8 = "Pico-8 (PICO)";
    }
    .${
      system
    }
    or null;

  saveFolder = system:
    {
      gb = "GB";
      gbc = "GBC";
      gba = "GBA";
      nes = "FC";
      famicom = "FC";
      snes = "SFC";
      sfc = "SFC";
      genesis = "MD";
      megadrive = "MD";
      mastersystem = "MS";
      gamegear = "GG";
      segacd = "SEGACD";
      psx = "PS";
      nds = "NDS";
      dreamcast = "DC";
      pcengine = "PCE";
      tg16 = "PCE";
      neogeo = "FBN";
      arcade = "FBN";
      fbneo = "FBN";
      atarilynx = "LYNX";
      pokemini = "PKM";
      pico8 = "PICO";
    }
    .${
      system
    }
    or null;

  biosFolder = system:
    {
      dreamcast = "DC";
    }
    .${
      system
    }
    or null;
}
