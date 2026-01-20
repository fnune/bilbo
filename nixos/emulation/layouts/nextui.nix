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

  saveFolder = system: let
    mappings = {
      gb = { base = "gambatte"; target = "GB"; };
      gbc = { base = "gambatte"; target = "GBC"; };
      gba = { base = "mgba"; target = "GBA"; };
      nes = { base = "mesen"; target = "FC"; };
      famicom = { base = "mesen"; target = "FC"; };
      snes = { base = "snes9x"; target = "SFC"; };
      sfc = { base = "snes9x"; target = "SFC"; };
      genesis = { base = "genesis-plus-gx"; target = "MD"; };
      megadrive = { base = "genesis-plus-gx"; target = "MD"; };
      mastersystem = { base = "genesis-plus-gx"; target = "MS"; };
      gamegear = { base = "genesis-plus-gx"; target = "GG"; };
      segacd = { base = "genesis-plus-gx"; target = "SEGACD"; };
      psx = { base = "duckstation"; target = "PS"; };
      nds = { base = "melonds"; target = "NDS"; };
      dreamcast = { base = "flycast"; target = "DC"; };
      pcengine = { base = "beetle-pce"; target = "PCE"; };
      tg16 = { base = "beetle-pce"; target = "PCE"; };
      neogeo = { base = "fbneo"; target = "FBN"; };
      arcade = { base = "fbneo"; target = "FBN"; };
      fbneo = { base = "fbneo"; target = "FBN"; };
      atarilynx = { base = "beetle-lynx"; target = "LYNX"; };
      pokemini = { base = "pokemini"; target = "PKM"; };
      pico8 = { base = "pico8"; target = "PICO"; };
    };
  in mappings.${system} or null;

  biosFolder = system:
    {
      dreamcast = "DC";
    }
    .${
      system
    }
    or null;
}
