# Crystal 251

Crystal 251 is a self-contained Gen1Recomp overhaul. It reads data and sprites
from your own English Pokemon Crystal ROM, then expands Pokemon Red, Blue, or
Yellow to all 251 Generation II Pokemon. No ROM and no extracted Nintendo
assets are included in this mod.

## Disabling and uninstalling

Runtime patches are restored when Crystal 251 is disabled for the active game,
when uninstall succeeds, and when the engine ends or replaces the game session.
Disabling Crystal for another game does not change the active game's patches.
The engine still applies content and enablement choices at game boot; after
turning Crystal back on, start that game again to load its content and patches.

New runtime installers must use `lib/runtime_patches.lua`: watch each shared
engine table before changing it and decorate the installer with
`RuntimePatches.installers`. Deferred installers must use
`RuntimePatches.callback` so an old callback cannot reinstall a disabled patch.
Installation flags belong on watched tables, not in module-local variables.

## ROM setup

The release does not include a Pokemon Crystal ROM. Use your own legally dumped
English copy.

The recommended setup is to place the ROM at this exact path inside the mod:

```text
baseroms/crystal.gbc
```

For a downloaded release ZIP:

1. Open the downloaded `CRYSTAL_251` release ZIP with an archive manager.
2. Open the empty `baseroms` folder included in the archive.
3. Add your ROM as `crystal.gbc`.
4. Install the modified ZIP through the game's mod manager.

Do not add an extra folder around the release contents. The archive should look
like this:

```text
CRYSTAL_251-<version>.zip
├── manifest.json
├── main.lua
├── lib/
└── baseroms/
    └── crystal.gbc
```

If the mod is already extracted, use the same location relative to the mod
folder:

```text
CRYSTAL_251/baseroms/crystal.gbc
```

The following filenames are recognized at either the mod root or inside
`baseroms/`:

```text
pokemon_crystal.gbc
pokemon_crystal_version.gbc
crystal.gbc
baserom.gbc
```

Use one of these filenames exactly, including capitalization. The filename only
helps the importer locate the file; the ROM is validated by content, so renaming
an unsupported revision will not make it compatible.

The importer accepts the English UE releases:

- Crystal v1.0: SHA-1 `f4cd194bdee0d04ca4eac29e09b8e4e9d818c133`
- Crystal v1.1: SHA-1 `f2f52230b536214ef7c9924f483392993e226cfb`

## First import

Start the game with Crystal 251 enabled after placing the ROM. The importer
loads the Crystal data and artwork automatically during startup. Keep the ROM in
the installed mod so it remains available on future starts.

If the import does not start, confirm that:

- The ROM is inside the installed mod, preferably at `baseroms/crystal.gbc`.
- Its SHA-1 matches one of the supported releases above.
- The ZIP has `manifest.json` at its root and is not wrapped in another directory.
- The mod is installed and enabled for the current game.

The in-game importer is available from **OPTIONS → CRYSTAL ROM** for updates.
The launcher manages the required ROM before game startup.

## What changes

- Imports all 251 species, all 251 Crystal moves, base stats, types, learnsets,
  TM/HM compatibility, evolutions, palettes, front/back sprites, shiny sprites,
  normal battle animation frames for every species and Unown form, Crystal cries, and all 26 Unown forms.
- Keeps the original Generation I Special stat for Pokemon 1–151. For Pokemon
  152–251, the single Gen I Special is the higher of Crystal's Special Attack
  and Special Defense for compatibility with Kanto data consumers. Battles use
  separate Crystal Special Attack and Special Defense stats and stages.
- Adds Steel and Dark and applies the Generation II type chart.
- Uses a backport of Gen1Recomp's Gen II catching module for ordinary and
  specialty balls, including its HP precision and status rules. Kanto's Bag,
  Safari menu, throw animations and party/box storage remain the interface.
  All 122 evolution branches and all 11 legendary/mythical battle-and-capture
  paths have ROM-backed regression checks.
- Evolves Kadabra and Haunter at level 36, and Machoke and Graveler at level
  40. Generation II trade evolutions instead work by using the required item
  directly on the Pokemon: King's Rock, Metal Coat, Dragon Scale, or Up-Grade.
  Every required item is sold in Kanto. Espeon and Umbreon use high friendship
  during day/morning and night respectively; Tyrogue retains its three stat checks.
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
- Uses a shared Crystal clock for the START menu, time-based evolution, and
  morning/day/night encounters. TIME SPAWNS OFF selects the balanced all-day table.
- Friendship evolution requires 220 happiness and a level-up. Eevee becomes
  Espeon from 04:00–17:59 or Umbreon from 18:00–03:59. Everstone blocks
  friendship, level and Tyrogue stat evolution; deliberate item use still works.
- Keeps Kanto TM contents and their original compatibility while adding Crystal
  compatibility. Walking, vitamins, TMs, Gym battles, fainting, field poison and
  leveling use the custom friendship service. Walking awards one point per 512
  steps through the Day Care counter; eggs never receive friendship awards.
- Moves the roaming beasts through encounter-capable Kanto routes and migrates
  old Johto locations without reviving caught beasts or losing their DVs/HP.
- Finds a supported, predictably named ROM at the mod root or in its
  `baseroms/` folder and imports it automatically.
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
When Roaming Events is enabled, its Mew owns that encounter and Crystal 251
suppresses its own Mew so the two mods cannot create duplicates.

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
- Imports all 251 species cry descriptors as data-only chip programs synthesized
  by the engine at playback time.
- Routes every Generation II move through a recomp-native animation record
  chosen from the matching impact, projectile, status, or field-effect family,
  and adds weather and residual presentation for rain, sun, sandstorm,
  Whirlpool, and Nightmare.
- Keeps the completed Crystal battle mechanics isolated from presentation so
  animation settings cannot alter damage, status, PP, AI, or turn ordering.

## Backport verification

The custom adapters use the Gen II code in Gen1Recomp as their local source and
bridge it to the Kanto battle, overworld, item and save interfaces. See
[BACKPORT_VERIFICATION.md](BACKPORT_VERIFICATION.md) for coverage and limits.

From the `gen1recomp` engine root, run:

```sh
CRYSTAL_ROM="/path/to/English Crystal v1.1.gbc" luajit mods/CRYSTAL_251/tests/run_crystal_parity.lua
```

This runner requires the ROM and rejects skipped required suites. Optional
Stadium 2 importer checks and interactive visual drivers are separate.
