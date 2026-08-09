# Crystal 251

Crystal 251 is a self-contained Gen1Recomp overhaul. It reads data and sprites
from your own English Pokemon Crystal ROM, then expands Pokemon Red, Blue, or
Yellow to all 251 Generation II Pokemon. No ROM and no extracted Nintendo
assets are included in this mod.

## Install and import

1. Copy the `CRYSTAL_251` folder into the game's `mods` folder.
2. Enable **Crystal 251** in the launcher and start the game.
3. Choose **IMPORT CRYSTAL** on the title screen.
4. Crystal 251 first looks beside the desktop game executable/app and in
   `baseroms/`. Linux AppImage, Linux portable/ARM, Windows, macOS, and source
   launches are handled separately so the physical game folder is used rather
   than an AppImage mount or app-bundle interior. On Android, iOS, and Xbox,
   sandboxed package storage is not treated as a sibling-ROM folder. If no
   supported ROM is found automatically, Android opens its native system file
   picker and desktop builds use their supported picker; `baseroms/` remains
   available everywhere the platform exposes writable game storage. The filename does not matter;
   supported ROMs are identified by SHA-1.
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
is read during import and is not copied into the mod. Import failures remain on
screen until dismissed, print the exact failing stage and traceback to the
terminal, and are saved to `crystal_251/import_error.log`. Stadium 2 extraction
failures are saved separately to `crystal_251/stadium2/import_error.log`, including
archive offsets, file indexes, and retained parser errors.

## What changes

- Imports all 251 species, all 251 Crystal moves, base stats, types, learnsets,
  TM/HM compatibility, evolutions, palettes, front/back sprites, shiny sprites,
  normal battle animation frames for every species and Unown form, Crystal cries, and all 26 Unown forms.
- Keeps the original Generation I Special stat for Pokemon 1–151. For Pokemon
  152–251, the single Gen I Special is the higher of Crystal's Special Attack
  and Special Defense. This mirrors the practical Time Capsule constraint while
  preserving each Johto Pokemon's stronger special identity.
- Adds Steel and Dark and applies the Generation II type chart.
- Converts happiness evolutions to levels, trade evolutions to evolution items,
  Espeon/Umbreon to Sun Stone/Moon Stone, and Tyrogue to its three stat checks.
- Adds HM06 Whirlpool and HM07 Waterfall to the HM rules and to ordinary
  progression. Lance gives HM06 after the Rocket Hideout Giovanni victory,
  while HM07 is an item-ball pickup deep in Seafoam Islands beside Articuno.
  These preserve Crystal's Rocket-operation gift and ice-cave pickup methods
  in the conversion's Kanto-only world.
- Replaces Kanto's single-mon Generation I Day Care with Crystal's split
  two-attendant flow. The existing Day Care Man owns the first slot, an
  appended Day Care Lady owns the second, and an appended Route 5 Day Care Man
  appears outside when an Egg is waiting. Deposited Pokemon appear as their
  ROM-derived two-frame Crystal menu icons, wander around the house, and report
  the pair's compatibility when spoken to. Both boarded Pokemon gain experience
  per step; compatible pairs use Crystal egg groups, gender, OT IDs and
  DV-family checks to produce Eggs with Crystal species, inherited DVs,
  inherited moves, fees, hatch cycles, party presentation and hatching behavior.
  Hatching a species not previously owned opens its full Pokédex entry before
  the nickname prompt; repeat hatches proceed directly to naming.
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
  selects time-specific encounters. Without a time provider, one balanced
  all-day table is used, so the mod remains fully functional on its own.
- With Dramatic Shape 1.6.0 or newer installed, Crystal 251 requests the
  shared Stadium 2 importer for National Dex 1–251. When Shiny Indicators is
  also enabled, both owned mods coordinate through one live bridge: Shiny
  Indicators supplies the 1–151 base path and Crystal 251 upgrades it to 251
  without wrapping Dramatic Shape twice or adding duplicate options rows. Put
  any correctly dumped Pokemon Stadium 2 (US) ROM beside the desktop game or
  in `baseroms/`; the filename can be anything ending in `.z64`, `.n64`, or `.v64`.
  The model build starts automatically when its cache is absent or incomplete.
  OPTIONS -> STADIUM 2 ROM also checks the automatic locations first, then opens
  the native Android system picker or the desktop file picker only when no
  supported ROM is found. A 251 cache satisfies the
  151-only setup; enabling Crystal 251 upgrades a 151 cache. Normal and
  Crystal-DV shiny packs are generated separately. Stadium 2 display-list
  groups that intentionally have no texture are retained with a generated
  Crystal-palette material instead of being discarded. Neither the engine nor
  Dramatic Shape is modified, and Stadium 1 packs are ignored while the shared
  bridge is active.
- Put a supported Pokemon Crystal ROM beside the desktop game or in `baseroms/` and
  Crystal 251 imports it automatically when `content.json` is missing, its
  schema is obsolete, or any generated sprite/cry file recorded by the cache is
  missing. The `.gbc` filename can be anything; the ROM is matched by SHA-1. The
  same import is available manually from OPTIONS -> CRYSTAL ROM and the title menu.
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

## Battle presentation

- Imports Crystal's normal front-sprite animation scripts, frame replacement
  tables, bitmasks, and shiny animation frames from the selected ROM.
- Extracts all 251 species cry descriptors and renders their Crystal sound
  programs to portable WAV files during import.
- Routes every Generation II move through a recomp-native animation record
  chosen from the matching impact, projectile, status, or field-effect family,
  and adds weather and residual presentation for rain, sun, sandstorm,
  Whirlpool, and Nightmare.
- Keeps the completed Crystal battle mechanics isolated from presentation so
  animation settings cannot alter damage, status, PP, AI, or turn ordering.

The data layout and behavior cross-checks are based on `pret/pokecrystal`.

## Mechanical parity tests

Run the complete Crystal battle parity matrix with a supported ROM:

```bash
CRYSTAL_ROM="/path/to/Pokemon Crystal.gbc" \
  luajit mods/CRYSTAL_251/tests/run_crystal_parity.lua
```

The runner covers all 251 move records and command streams, deterministic
damage vectors, statuses, held items, switching, AI, end-of-turn ordering,
battle modes, link synchronization, capture, experience, money, and level-up
handling. `crystal_full_battle_test.lua` additionally drives complete
BattleState queue and party-menu sequences for trapped switching, replacement,
Pursuit, Baton Pass, Spikes, residual release, simultaneous switches, and
volatile-state cleanup.

Audit all 50 TMs and seven HMs—including their ordinary acquisition sources,
Crystal compatibility, accepted applications, rejection paths, and TM/HM
consumption contracts—with:

```bash
CRYSTAL_ROM="/path/to/Pokemon Crystal.gbc" \
  luajit mods/CRYSTAL_251/tests/crystal_machine_full_audit_test.lua
```

The corresponding in-game visual smoke test drives the real Bag, boot text,
`ABLE / NOT ABLE` party display, incompatible rejection, successful teaching,
TM consumption, and HM retention for all 57 machines. It writes three captures
per machine plus a final PASS screen:

```bash
SHOT_DIR=/tmp/crystal-tmhm-visual \
POKEPORT_DRIVER=mods/CRYSTAL_251/tests/crystal_tmhm_visual_driver.lua \
POKEPORT_TOUCH=0 POKEPORT_SPEED=20 CRYSTAL_TM_VISUAL_ALL_PAIRS=0 \
  love .
```

Set `CRYSTAL_TM_VISUAL_ALL_PAIRS=1` to exercise every one of the imported
Crystal compatibility pairs instead of one positive/negative pair per machine.

- Stadium 2 compatibility reads the National Dex model table and the separate Pokemon pose table. Each per-species pose bundle is opened recursively, and its raw relocatable skeletal records are decoded without requiring Stadium 1's `FRAGMENT` wrapper. Decoded motion tracks are packed against each imported skeleton. Missing or still-unknown pose records no longer block model import; those species use a one-frame rest-pose fallback and are reported separately.

- Stadium 2 battle meshes are CPU-skinned at a maximum presentation rate of
  60 Hz. Animation time, camera placement, send-out scaling, and battle logic
  continue at the renderer's normal rate; high-refresh displays reuse the last
  skinned mesh between presentation samples instead of repeating the complete
  bone walk, vertex transform, and GPU upload at 120–240 Hz.
- Stadium 2 pose children are decoded through their real footer layout: word
  zero points to a standard skeletal-animation header at the end of the file,
  while packed transform streams and channel records precede it. This removes
  the false header scan that left every imported model in its rest pose.
