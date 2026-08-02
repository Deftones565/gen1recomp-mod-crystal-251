# Crystal 251

Crystal 251 is a self-contained Gen1Recomp overhaul. It reads data and sprites
from your own English Pokemon Crystal ROM, then expands Pokemon Red, Blue, or
Yellow to all 251 Generation II Pokemon. No ROM and no extracted Nintendo
assets are included in this mod.

## Install and import

1. Copy the `CRYSTAL_251` folder into the game's `mods` folder.
2. Enable **Crystal 251** in the launcher and start the game.
3. Choose **IMPORT CRYSTAL** on the title screen.
4. Select a supported Pokemon Crystal ROM. If a file picker is unavailable,
   place the `.gbc` file beside the game and try again.
5. Let the import finish, then restart when prompted.

When an update changes the generated-asset format, **IMPORT CRYSTAL** appears
again automatically. Reimport the same ROM so stale sprites are replaced. A
reimport deletes the previous `crystal_251/generated/` assets first; it does
not touch game saves, screenshots, other mods, or their generated files.
After a successful import, the same title-menu action remains available as
**REIMPORT CRYSTAL** for manually rebuilding the generated assets.

The import accepts the English UE releases:

- Crystal v1.0: SHA-1 `f4cd194bdee0d04ca4eac29e09b8e4e9d818c133`
- Crystal v1.1: SHA-1 `f2f52230b536214ef7c9924f483392993e226cfb`

Generated content is stored in Gen1Recomp's writable save-data directory under
`crystal_251/`. It is intentionally excluded from Git and mod packages. The ROM
is read during import and is not copied into the mod.

## What changes

- Imports all 251 species, all 251 Crystal moves, base stats, types, learnsets,
  TM/HM compatibility, evolutions, palettes, front/back sprites, shiny sprites,
  and all 26 Unown forms.
- Keeps the original Generation I Special stat for Pokemon 1–151. For Pokemon
  152–251, the single Gen I Special is the higher of Crystal's Special Attack
  and Special Defense. This mirrors the practical Time Capsule constraint while
  preserving each Johto Pokemon's stronger special identity.
- Adds Steel and Dark and applies the Generation II type chart.
- Converts happiness evolutions to levels, trade evolutions to evolution items,
  Espeon/Umbreon to Sun Stone/Moon Stone, and Tyrogue to its three stat checks.
- Adds HM06 Whirlpool and HM07 Waterfall to the HM rules.
- Rebuilds wild ecology as a progressive Kanto ecosystem. Early routes keep
  common low-level species, caves and landmarks use habitat-appropriate pools,
  rare base forms appear in plausible locations, and most final evolutions are
  earned by evolving rather than crowded into wild tables.
- Rebuilds trainer parties around class identity, location, and progression.
  Bird Keepers use actual bird families, specialists keep coherent themes,
  ordinary trainers favor local species, and bosses retain their original ace.
- Adds seven one-time Crystal-inspired trades without replacing any native
  Red, Blue, or Yellow trade: Abra/Machop, Bellsprout/Onix, Krabby/Voltorb,
  Dragonair/Dodrio, Haunter/Xatu, Chansey/Aerodactyl, and Dugtrio/Magneton.
- Documents every reviewed party, its theme, original roster, and curated
  roster in [TRAINER_PARTY_AUDIT.md](TRAINER_PARTY_AUDIT.md).
- When Dramatic Shape is enabled, its public morning/day/evening/night value
  selects time-specific encounters. Crystal 251 does not modify or depend on
  Dramatic Shape internals. Without a time provider, one balanced all-day table
  is used, so the mod remains fully functional on its own.
- Uses stable DV-derived Unown letters. Forms survive saving and link transfer.
- Uses Crystal shiny colors in SGB and Advanced color modes.
- Mattes the sprites' boundary-connected color-0 background to transparency,
  so battle art composes cleanly over Dramatic Shape and widescreen fields.

## Legendary encounters

- Raikou, Entei, and Suicune begin roaming after obtaining the Secret Key.
- A new grassy island lies directly south of Cinnabar. Surf through the new
  channel and its Swimmer gauntlet to reach it. Wild land encounters occur
  only in the tall grass, while the surrounding water has a separate ocean
  habitat. The Tidal Cave door appears after all eight badges are earned;
  inside, Lugia waits as a level-60 overworld sprite encounter.
- Ho-Oh appears as a level-60 overworld sprite between the statues on Pokemon
  Tower 7F after rescuing Mr. Fuji and earning all eight badges. A new Lavender
  resident hints at the strange bird from the beginning without naming it.
- Lugia and Ho-Oh use their dedicated two-frame Crystal map sprites. These are
  extracted from the user's supported Crystal ROM during import; the mod does
  not include or redistribute the graphics.
- Mew appears in Cerulean Cave B1F after all eight badges.
- Celebi appears in Viridian Forest after defeating the Champion.

Lugia and Ho-Oh behave like the original Generation I legendary birds: interact
with the visible sprite to begin a one-time static battle, and any non-blackout
ending removes that sprite. The three roaming beasts retain their DVs, HP, and
status and flee like Generation II roamers. By default a KO does not permanently
remove a roaming/random legendary; **KO REMOVES LEGEND** enables that behavior.
**TEST LEGENDARY** opens the sanctuary gates and makes an eligible random
legendary immediate for testing. When Roaming Events is enabled, its Mew owns
that encounter and Crystal 251 suppresses its own Mew so the two mods cannot
create duplicates.

## Compatibility

This is an overhaul and must be enabled on both sides of a link session with the
same mod version and imported content. It is designed to coexist with Dramatic
Shape, Habitat Guide, Quality of Life, Enhanced Music, and Shiny Indicators.
Another mod that rewrites Pokemon, moves, trainers, encounters, types, or
evolutions may conflict even when the launcher can load both.

**TIME SPAWNS** defaults to **AUTO**. Set it to **OFF** to use the all-day
tables even when Dramatic Shape is active. Habitat Guide 1.2.2 or newer labels
sources as MORN, DAY, NIGHT, or ALL DAY to match the active behavior.

Removing the mod from a save that contains Pokemon 152–251 makes those records
unusable until the mod is enabled again. Keep a backup before changing overhaul
mods.

## Preview limitations

- Resting Crystal battle sprites are imported, but Crystal's multi-frame battle
  animation scripts are not yet reproduced.
- Generation II cry programs are not yet imported.
- Moves with a direct Generation I equivalent are exact. Several Generation II
  effects have native implementations, while the remaining effects currently
  use a conservative fallback pending full battle-engine parity.

The data layout and behavior cross-checks are based on `pret/pokecrystal`.
