# Crystal backport verification

Updated 2026-09-15. Scope: Crystal mechanics and data in the Red/Blue/Yellow
Kanto runtime. The backport source is the Gen II implementation already in
`gen1recomp/src/battle/gen2` and `gen1recomp/src/core/gen2`, with custom adapters
where its native battle, overworld and save shapes differ from Kanto.

## Resolved findings

- **Split stats for every species:** the original Gen I Special override and
  higher-of-two fallback are removed. Host stat recalculations return Crystal
  Special Attack and Special Defense for all 251 species. Existing save records
  refresh their legacy `special` alias to Special Attack; the alias remains for
  Kanto serialization and completeness checks. The ROM-backed acquisition suite
  adds 1,255 checks covering all species, recalculation and saved-stat refresh.
- **Patch lifetime:** every permanent engine-table installer participates in a
  reversible patch journal. Disable for the active game, successful uninstall,
  failed installation and runtime replacement restore original functions and
  installer flags. Disabling another game does not affect the active session.
  Later mods retain their own replacements; captured Crystal wrappers fall
  back to the original function after cleanup. Deferred Day Care installation
  cannot revive a disabled generation. Nested `ItemEffects.BALLS` entries and
  the friendship bridge are included in cleanup coverage.
- **Walking friendship:** Day Care owns the shared modulo-256 step counter.
  Friendship advances every second wrap (512 footfalls). The world observer
  no longer awards it again, and the hatch phase keeps its early return.
- **Friendship events:** successful vitamins and X items, completed TM teaching,
  Gym battles, fainting and field-poison fainting now reach the custom service.
  Failed/cancelled teaching does not award friendship. Capture records retain
  the Kanto map id so battle level-ups can use Crystal's caught-at-home bonus.
  Existing numeric Gen II caught-location handling remains available.
- **Clock and evolution:** START uses a properly scoped Clock dependency.
  Friendship evolution reads Kanto's `game.overworld`, with a shared clock
  fallback. The time hook composes with the ecology observer, making normal
  night encounters and Umbreon evolution reachable.
- **Roamers:** all 22 graph nodes exist and have grass encounters in Kanto.
  Old Johto map ids migrate while preserving HP and DVs and leaving caught or
  defeated slots inactive. Ordinary wild-battle completion reads the actual
  Kanto event shape. Legendary DV generation now accepts the correct RNG range.
- **Celebi:** its declared Champion progression flag is enforced before natural
  or forced encounter selection.
- **Original move families:** importing a Crystal effect id no longer replaces
  drain, recoil, Explosion, Dream Eater, Pay Day, Hyper Beam, Mirror Move,
  Metronome, Mimic, Conversion, Teleport and charge moves with empty records.
  Recovery distinguishes Rest from half-HP moves. The adapter records Dig/Fly
  identity for Crystal hit/weather rules and includes it in link state checks.
  Jump Kick crash fainting enters the ordinary faint pipeline.
- **Turn scheduling:** action residuals run once after the acting side, with
  entry-turn and faint guards. Shared phases resolve Future Sight, weather,
  trapping, Perish Song, recovery, defrost, screens and counters in order.
  Weather expires before another damaging tick. Dedicated timing and full
  battle regressions cover this behavior.
- **Machines:** the existing Kanto TM rewards retain their original moves.
  Kanto species retain native machine compatibility alongside imported Crystal
  compatibility, avoiding TMs with no eligible recipients. All 50 live TMs and
  seven HMs have acquisition and actual item-use checks.

## Active custom implementations

| System | Mod-owned adapter or implementation |
|---|---|
| Day Care, breeding, hatching and NPC flow | `daycare.lua`, `core/gen2/Breeding.lua` |
| Clock, friendship, evolution and roaming | `core/gen2/Clock.lua`, `Happiness.lua`, `HappinessBridge.lua`, `Roamers.lua`, `main.lua`, `ecology.lua`, `legendaries.lua` |
| Split stats, damage, criticals and type chart | `battle/crystal_stats.lua`, `crystal_damage.lua`, `battle/gen2/Damage.lua` |
| All 251 move records and command dispatch | `effects.lua`, `battle/crystal_classic_effects.lua`, `move_scripts.lua`, `command_interpreter.lua` |
| Status and multi-turn state | `battle/crystal_status.lua`, `multi_turn.lua`, `special_damage.lua` |
| Turn order, switching, Baton Pass and Pursuit | `battle/gen2/TurnOrder.lua`, `crystal_scheduler.lua`, `crystal_switching.lua` |
| AI, obedience, PP and trainer items | `battle/crystal_ai.lua`, `crystal_actions.lua`, `battle/gen2/Ai.lua` |
| Capture, experience, rewards and held items | `battle/crystal_progression.lua`, `crystal_items.lua`, `item_behaviors.lua` |
| Battle modes, link fields and deterministic state | `battle/crystal_modes.lua` |
| Summary, gender, cries and animations | `battle/crystal_summary.lua`, `crystal_gender.lua`, `crystal_presentation.lua`, `lib/crystal_cry.lua` |
| Engine patch ownership and cleanup | `lib/runtime_patches.lua` and watched runtime installers |

Presence of a copied module alone is not the completion criterion. The new
service test loads the real ROM and invokes registered hooks, item handlers,
field poison and evolution checks. The original-move test checks every imported
effect for a working handler or an explicit damage-hook owner, then exercises
representative move-family behavior through the Kanto BattleState.

## Verification

Run from `/opt/git/gen1recomp`:

```sh
CRYSTAL_ROM="/path/to/English Crystal v1.1.gbc" luajit mods/CRYSTAL_251/tests/run_crystal_parity.lua
```

**Result: 52/52 required suites passed.** This includes 1,479 engine patch
restoration checks, 88 lifecycle checks, 85 service integration checks, 308
original-move checks, 745 full-battle checks and the 8,149-check move/damage
matrix.

The runner executes 52 required headless suites, requires a readable ROM,
rejects skipped required suites, and reports all failing suites. The supplied
English Crystal v1.1 ROM was used (MD5 `301899b8087289a6436b0a241fbbb474`).
The aggregate item audit reruns some component suites; suite counts are not
counts of independent game states or a proof of every cartridge edge case.

The special-evolution integration suite adds 425 checks using the supplied ROM:
all eight friendship branches at the 219/220 threshold, Eevee's 04:00 and
18:00 boundaries, actual Rare Candy and battle experience through evolution
application and Pokédex updates, all three Tyrogue stat outcomes, converted
trade levels, and every stone/item evolution through Bag use. Presentation
callbacks are advanced headlessly; this does not test the evolution movie.
Everstone now blocks level and stat evolution as well as friendship, while
deliberate item use remains allowed, matching the local Gen II engine.
The experience adapter now returns and commits the engine's deferred level-up
steps, awarding friendship on each committed level instead of referencing an
undefined battle. This preserves the after-battle evolution trigger.

The visual raster test retains the original 556-image golden and checks
transparency masks for all 686 current sheets, including the newer animations,
Day Care icons and egg artwork. This is headless image validation, not an
interactive visual playthrough.

Two optional STADIUM2_IMPORTER integration tests require that separate mod's
`lib/battle.lua`, which is absent from this installation. They and interactive
visual drivers are explicitly outside the required runner. No optional skip is
included in its pass count. Live network sessions and a full manual campaign
have not been exercised.

The older `GEN2_BACKPORT_AUDIT.md` proposes migration to the engine's separate
native Gen II runtime. Johto-specific Pokegear, phone/radio, Kurt crafting and
world events from that proposal are not Kanto features implemented by this
mechanics backport.

## Evolution, legendary and capture audit

The additional ROM-backed acquisition suite passes **9,146 checks**:

- All **122 evolution branches** win the real evolution dispatcher under the
  appropriate level, item, friendship/time or Tyrogue stat condition. Every
  required evolution item has a registered Kanto shop or pickup source.
- All **11 legendary/mythical encounters** have connected Kanto maps, enter
  catchable battles, and successfully store their caught Pokemon. The six
  stationary encounters are located through actual map objects and scripts;
  the five roaming/random encounters are selected through `encounter.roll`
  and initialized by `BattleState:enter`.
- All **12 supported ball types** exercise the actual capture path: 11 through
  the Bag, plus Safari Ball through the Safari menu. Tests verify consumption,
  party storage, Friend Ball friendship, full-party box storage, and the trainer
  capture restriction.
- The catch implementation is now backported directly from the local engine's
  `src/battle/gen2/Catching.lua` into `battle/gen2/Catching.lua`. The Kanto
  adapter converts HP/stat fields, status ids, fishing state, weights, genders
  and RNG conventions. Tests compare its results against the local Gen II
  engine over all supported balls, status conditions, HP precision boundaries
  and catch-roll boundaries. This replaces the earlier duplicated formula,
  including its different HP rounding and equality behavior. The public
  `catch.rate` hook still participates in Kanto captures.

Encounter locations and progression:

| Pokemon | Encounter location | Gate |
|---|---|---|
| Articuno | Seafoam Islands B4F | Native Seafoam puzzle and Surf access |
| Zapdos | Power Plant | Native Surf access |
| Moltres | Victory Road 2F | Native badge/Victory Road access |
| Mewtwo | Cerulean Cave B1F | Native post-Champion cave access |
| Mew | Cerulean Cave B1F | Eight badges and native cave access |
| Raikou, Entei, Suicune | Kanto roaming routes | Secret Key |
| Ho-Oh | Pokemon Tower 7F | Eight badges and Mr. Fuji rescued |
| Lugia | Tidal Cave, via the island south of Cinnabar | Eight badges |
| Celebi | Viridian Forest | Champion defeated |

These are headless gameplay and map-connectivity checks. They do not substitute
for a manual walk through every collision tile or a full campaign playthrough.
