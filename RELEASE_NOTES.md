# Crystal 251 — Gen II runtime and evolution fixes

This update fixes persistent mod patches, completes missing Gen II runtime
wiring, and repairs capture and evolution behavior in the Kanto campaign.

## Changes

- Restore Crystal's engine patches when the mod is disabled for the active
  game, uninstalled, or replaced by another runtime. Failed activation also
  cleans up its patches.
- Connect catching to the local recomp's Gen II implementation, including
  specialty balls, HP rounding, status bonuses and capture-roll boundaries.
  Captures work through the Bag and Safari flow, with party or PC storage.
- Fix battle experience processing so queued level-ups apply correctly and
  award friendship before the after-battle evolution check.
- Verify all eight friendship evolution branches at 220 happiness. Eevee
  evolves into Espeon from 04:00–17:59 and Umbreon from 18:00–03:59 after
  gaining a level, including with Rare Candy.
- Fix Everstone protection for level and Tyrogue stat evolutions. Deliberate
  item evolution remains available, matching the local Gen II engine.
- Verify Tyrogue's three stat branches, converted trade evolutions and every
  stone/item evolution through the actual item-use flow.
- Fix Day Care walking friendship timing and connect item, teaching, Gym,
  fainting and field-poison events to the custom friendship service.
- Repair Kanto roaming locations and preserve roaming state when migrating
  older saves. Enforce Celebi's Champion requirement.
- Restore missing classic move effects and correct residual-effect timing,
  weather expiration and related battle interactions.
- Preserve Kanto TM moves and compatibility while adding Crystal compatibility.

## Verification

All 52 required regression suites passed using an English Crystal v1.1 ROM.
Coverage includes 425 focused special-evolution checks, all 122 imported
evolution branches, all 12 supported ball types, and actual battle/capture
paths for all 11 legendary and mythical species.

These are headless gameplay checks, not a manual campaign playthrough or
verification of the evolution movie. Optional Stadium 2 integration suites
are excluded. See [BACKPORT_VERIFICATION.md](BACKPORT_VERIFICATION.md) for scope.

## Updating

Restart the game after updating. Keep your existing save and your own supported
English Crystal ROM; no ROM is included with this mod.
