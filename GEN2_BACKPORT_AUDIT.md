# Crystal 251 Gen 2 Backport Audit

Date: 2026-09-10  
Scope: `CRYSTAL_251` against the released Gen 2-capable `gen1recomp` engine in
`/opt/git/gen1recomp`.

## Executive conclusion

Crystal 251 is currently a Gen 1 overhaul, not a Gen 2-compatible mod. The
engine's released Gen 2 implementation is a second runtime (`Game2`, Gen 2
world, Gen 2 battle, and Gen 2 script VM). It is not a newer implementation of
the modules that Crystal 251 currently patches.

The correct end state is a dual-generation mod with three layers:

1. A shared Crystal data/feature layer: 251 species, Crystal move data,
   sprites, cries, type/evolution/item definitions, and feature policy.
2. A Gen 1 adapter: the existing runtime bridge and Kanto conversion rules,
   retained only where Gen 1 lacks a native consumer.
3. A Gen 2 adapter: registrations and hooks expressed in the Gen 2 schemas,
   with the released Gen 2 engine owning battle, world, script, breeding,
   evolution, catching, UI, clock, and save behavior.

Do not make the current `runtime_bridge.lua` pretend to drive Gen 2. That would
recreate the old engine in front of the proper Gen 2 implementation and will
either be inert or fail at boot.

## Baseline evidence

`python3 /opt/git/gen1recomp/tools/modkit.py gen2check . --notes --json`
currently reports:

| Result | Count |
|---|---:|
| Verdict | `will not work` |
| Fatal findings | 43 total, including the manifest gate |
| `MK402` unserved modules | 2 |
| `MK403` dead Gen 1 module paths | 4 |
| `MK404` absent Gen 2 members | 40 findings, 11 runtime sites before tests |
| `MK405` degraded members | 2 |
| `MK409` Gen 1 screen/version assumptions | 6 total, 2 runtime sites before tests |

The test directory contributes many expected Gen 1-only failures. The runtime
files themselves still have these blockers:

- `daycare.lua` and `sanctuaries.lua` require `src.script.Commands`, which
  Gen 2 never runs.
- `crystal_modes.lua`, `crystal_progression.lua`, `crystal_switching.lua`,
  and `runtime_bridge.lua` depend on Gen 1-only `BattleState` factories and
  turn/capture APIs.
- `daycare.lua` patches `OverworldController:onStepComplete`; Gen 2 exposes
  `world.stepped` instead.
- `crystal_gender.lua`, `crystal_summary.lua`, and `daycare.lua` patch Gen 1
  summary/naming screens which Gen 2 does not instantiate.
- `item_behaviors.lua` opens the Gen 1 `PartyMenu` screen id instead of
  `Gen2PartyMenu`.
- `crystal_scheduler.lua` relies on `BattleState:tryRun`, which is explicitly
  not backed on Gen 2.

The manifest also has no `games` or `gen2compat` declaration, so Gen 2 skips
the mod before any feature code can run.

## Current feature inventory and Gen 2 disposition

### Already shared or straightforward to adopt

These should use the public registry/hook surface in both generations, with
Gen 2-shaped records where the schema differs:

- 251 species and Pokédex size.
- Crystal moves 166–251 and patches to selected Kanto moves.
- Steel/Dark types and the Crystal type chart.
- Evolution methods and item-based trade-evolution substitutes.
- Items, balls, held-item definitions, HM06/HM07, and TM/HM compatibility.
- Pokémon icons, palettes, sprites, battle animation records, and cries.
- Wild encounter overlays and time-of-day policy.
- Trainer party curation.
- NPC trades, legendary encounters, and roaming state.
- Gender and shiny presentation.
- Evolution/capture/received/caught event integrations.
- Rendering hooks, battle overlays, low-HP presentation, and sprite lookup.

The released engine provides Gen 2 targets for `maps`, `tilesets`, `sprites`,
`text`, `encounters`, `trainers`, `palettes`, `icons`, `battle_anims`,
`constants`, `statuses`, `move_effects`, `item_effects`, `balls`, `ai_classes`,
and `evolution_methods`. It also provides Gen 2-only registries for
`held_items`, `phone_contacts`, `decorations`, `apricorns`, `landmarks`,
`radio_channels`, and `rom_text`.

### Requires a Gen 2-shaped registration path

The current code writes Gen 1 records. Each needs a translator or separate
Gen 2 source record:

| Current area | Current assumption | Required Gen 2 work |
|---|---|---|
| `pokemon` | Gen 1 `baseStats.special`, `level1Moves`, `levelMoves` shape | Emit Gen 2 `specialAttack`/`specialDefense`, `levelMoves`, `picSize`, breeding block, gender ratio, held-item pair, and Gen 2 evolution fields. Prefer the native Crystal cache/data when it is already present. |
| `encounters` / `ecology.lua` | Map id is the encounter id; Gen 1 ten-slot table | Translate to Gen 2 encounter kinds, time-of-day rates, fish/tree/rock/contest tables, and Gen 2 slot shape. Preserve Crystal 251's Kanto ecology only for a deliberate Kanto overlay. |
| `trainers.lua` | Individual Gen 1 trainer ids and parties | Translate to Gen 2 class/member records and native trainer attributes. Do not patch Gen 1 trainer rows on Gold/Silver/Crystal. |
| `maps` / `sanctuaries.lua` / `daycare.lua` | Gen 1 map/object/warp layout | Use Gen 2 map groups, object schema, collision field, warp group/map numbers, and Gen 2 map script hooks. A Kanto-only map must be a valid Gen 2 map record, not a Gen 1 record copied into `data.gen2Maps`. |
| `tilesets` | `walkable` field | Emit Gen 2 `collision` and Gen 2 tileset assets. |
| `text` and `text_pointers` | Gen 1 text labels and pointer tables | Use Gen 2 pointer ids for script text and `rom_text` for extracted engine labels. `text_pointers` has no Gen 2 consumer. |
| `battle_anims` | Gen 1 sequence/block animation records | Emit Gen 2 scripts, framesets, OAM sets, gfx, objects, and move mappings, or let native Crystal animations win. |
| `constants` | Gen 1 ordered lists and keys | Patch only keys consumed by Gen 2; ordered ROM-backed lists must be replaced with correct Gen 2 order, not appended casually. |
| `field` | Gen 1 grab-bag (`trades`, `tradeLocations`, `waterTilesets`) | Remove from the Gen 2 path. Route each feature to maps, encounters, `rom_text`, Gen 2 registries, or a native hook. |
| `map_scripts` | Lua row lists interpreted by Gen 1 | Not portable. Use Gen 2 VM events/specials/command hooks, or add a proper Gen 2 script dispatcher to the engine before registering this feature. |
| `link_fields` | Custom serialized fields for Unown/legendary state | Gen 2 link format currently has no mod fields. Keep these Gen 1-only, or obtain an engine-level Gen 2 wire-format extension before enabling Gen 2 link claims. |

### Must be rewritten around Gen 2 engine behavior

The custom battle implementation is the largest migration boundary. These
files directly assume Gen 1 `BattleState`, turn queues, battler construction,
capture, switching, and status internals:

- `battle/crystal_damage.lua`
- `battle/crystal_actions.lua`
- `battle/crystal_ai.lua`
- `battle/crystal_modes.lua`
- `battle/crystal_progression.lua`
- `battle/crystal_scheduler.lua`
- `battle/crystal_switching.lua`
- `battle/crystal_status.lua`
- `battle/multi_turn.lua`
- `battle/special_damage.lua`
- `effects.lua`
- `runtime_bridge.lua`

For Gen 2, the proper owners are the released `src/battle/gen2/*`,
`src/core/gen2/*`, and `src/ui/gen2/*` paths. The mod should contribute only
records, supported battle hooks, and missing Crystal-specific policy. In
particular:

- Replace `newWild` species rewriting with `encounter.species`.
- Replace `OverworldState:onStepComplete` with `world.stepped`.
- Replace custom capture/storage with `pokemon.caught` and the Gen 2 capture
  result path.
- Replace Gen 1 turn resolution and switch wrappers with Gen 2 battle events
  and native battle state.
- Do not call `BattleState.makeBattler`, `newWild`, `newTrainer`,
  `resolveTurn`, `catchAttempt`, or `storeCaughtMon` from the Gen 2 arm.
- Move Crystal-only behavior into `move_effects` records or a new shared
  engine hook only where the Gen 2 consumer actually reads it.

## Gen 2 engine features not represented in Crystal 251

The released Gen 2 codebase contains capabilities that are not merely
backports of the current Crystal 251 feature set. They need an explicit
product decision:

| Feature family | Disposition |
|---|---|
| Gold/Silver/Crystal boot, save, maps, scripts, native UI | Adopt automatically when targeting Gen 2; never emulate in the mod. |
| Clock, day/night, time-based encounters | Use native Gen 2 clock and `world.tod`; keep the mod's ecology policy as an overlay. |
| Native breeding, egg hatch, gender, held items, happiness, evolution | Use Gen 2 services. The current daycare implementation is a Gen 1 compatibility feature and should not replace native Gen 2 daycare. |
| Roamers, headbutt, rock encounters, Bug Contest | Use native systems. Note that the shared encounter hooks do not currently cover all three special encounter paths or roaming overrides. Add engine seams if Crystal 251 must alter them. |
| Pokegear, phone, radio, landmarks | Do not invent Kanto equivalents accidentally. Either add a clearly scoped Crystal/Kanto feature or leave the native Gen 2 systems untouched. |
| Apricorns, Kurt balls, decorations, mail, Mom shopping | Optional Gen 2-only enhancement; use the dedicated registries and Gen 2 UI, not Gen 1 item/menu patches. |
| Battle Tower, Trainer House, contests, photo/printer/diploma | Optional content expansion. Requires Gen 2 map/script/UI integration and its own save/state audit. |
| LAN/link battle and trade | Blocked for Crystal-specific custom fields until the Gen 2 wire format supports mod fields. Native Gen 2 link arenas can still work without those fields. |
| Survey zoom, tilt, widescreen, color modes, touch, pipelines | Engine-owned. Integrate only through render hooks and public options; do not copy engine UI or pipeline internals into the mod. |
| Followers | Native engine provides a follower implementation, but vanilla Gen 2 does not spawn one. Only enable a follower if Crystal 251 explicitly wants that feature. |

## Specific code changes required

### Phase 0 — establish the target contract

1. Decide whether the mod is:
   - Gen 1-only with Gen 2 engine features backported into Kanto, or
   - a dual-target Crystal 251 mod that also enhances native Gen 2 games.
2. For the stated goal, use the dual-target model and add
   `"games": ["gen1", "gen2"]` only after the Gen 2 arm is boot-clean.
3. Add a generation selector module based on `GameVersion.generation()` or
   the `game.ready` payload. Never use version allow-lists.
4. Keep import/cache handling generation-aware. A Gen 2 boot already has
   Crystal/Gold data; it should not blindly import and overwrite a Gen 2
   dataset with normalized Gen 1 rows.

### Phase 1 — make loading safe

1. Split `main.lua` into shared registration plus `installGen1()` and
   `installGen2()`.
2. Load Gen 1 runtime bridges only on generation 1.
3. Gate Gen 1-only modules (`Commands`, `MapScripts`, `SummaryMenu`,
   `NamingScreen`, `PartyMenu`, `OverworldController`) behind the Gen 1 arm.
4. Add Gen 2 screen ids through `Screens.GEN2_IDS` or register a mod-owned
   screen that is generation-neutral.
5. Make all tests generation-aware. Gen 1 parity tests should remain Gen 1
   tests; new Gen 2 tests should boot the Gen 2 harness and assert no boot
   errors.

### Phase 2 — move data onto native Gen 2 consumers

1. Build `lib/gen2_records.lua` (or equivalent) for Pokémon, encounters,
   trainers, maps, tilesets, animations, text, constants, and items.
2. Decide whether Crystal import remains required for Gen 2. Prefer native
   extracted Crystal data for a Crystal boot and use the user ROM only for
   assets the mod uniquely owns.
3. Convert custom item effects to Gen 2 `item_effects` and `held_items`.
4. Convert custom move behavior to Gen 2 `move_effects`; remove direct patches
   to Gen 1 `MoveEffects`, `EffectRegistry`, `Status`, and `BattleState` from
   the Gen 2 arm.
5. Replace map-script registrations with supported Gen 2 command/event seams.
   If custom NPC story is required, identify the smallest engine-side Gen 2
   script dispatcher needed and implement that before adding content.

### Phase 3 — implement the feature split

1. Retain the Gen 1 daycare, trade, HM, sanctuary, and Kanto ecology systems
   as Gen 1 adapters.
2. Let native Gen 2 daycare, breeding, evolution, capture, Pokegear, and
   roaming services run on Gen 2.
3. Add only Crystal 251 overlays that native Gen 2 does not already provide:
   additional species presentation, custom ecology, custom trainer rosters,
   Crystal-specific item/move records, and optional map/story content.
4. Reconcile overlapping mods through public registries and events rather
   than runtime monkey patches wherever possible.

### Phase 4 — verification and release gate

The release must pass all of the following:

- `gen2check . --notes` has no errors, no unresolved runtime sites, and no
  unsupported screen/version assumptions.
- Gen 1 headless load and the existing Crystal parity matrix remain green.
- Gen 2 headless load has zero boot errors and zero unsupported registry writes.
- Gold, Silver, and Crystal each boot with and without a Crystal ROM import,
  according to the chosen import contract.
- Native Gen 2 battle tests pass with the mod enabled.
- Wild, fishing, headbutt, rock, Bug Contest, swarm, and roaming encounter
  paths are tested separately.
- Daycare, eggs, held items, evolution, Pokédex, shiny/gender presentation,
  item use, HM behavior, and save/reload are tested in both arms where the
  feature exists.
- Link tests verify that custom Gen 1 fields are never advertised on Gen 2;
  either Gen 2 link works without them or the feature is explicitly disabled.
- Visual tests cover native and wide Gen 2 battle layouts, Crystal sprites,
  Unown forms, shiny palettes, menus, map objects, and imported assets.

## Recommended immediate next work

The next implementation task should not be a broad feature batch. It should
be the migration scaffold:

1. Add generation targeting to the manifest.
2. Introduce the generation selector and split `main.lua` loading.
3. Make `gen2check` clean for the entry path by disabling all Gen 1 runtime
   bridges on Gen 2.
4. Add a minimal Gen 2 boot test proving the mod loads with native Crystal
   data and zero errors.
5. Port one vertical slice end-to-end: species presentation plus one item and
   one encounter overlay, using Gen 2 record schemas and native consumers.

Only after that slice works should the full battle/evolution/daycare/story
features be migrated. This keeps the proper Gen 2 code authoritative and
prevents two incompatible implementations from gradually drifting apart.

