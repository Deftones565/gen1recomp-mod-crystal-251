# Crystal move parity workflow

This workflow covers the complete Crystal move set. Crystal 251 runs the
complete Generation II move table on the Generation I battle shell: moves
1 through 251 use Crystal metadata, type-based physical/special categories,
effect chances, and Crystal command/effect routing.

The parity suite is intentionally red until every move is implemented. It
contains a canonical manifest of all 86 moves, verifies the imported ROM data,
rejects placeholder effects, and runs at least one behavioral contract for
each move.

## Source of truth

Use one pinned Pokemon Crystal revision for all work:

- ROM revision: the supported Crystal v1.1 SHA-1 entry in `addresses.lua`
- disassembly reference: a pinned `pret/pokecrystal` commit
- move metadata: `data/moves/moves.asm`
- effect dispatch: `data/battle/effect_command_pointers.asm`
- effect implementation: `engine/battle/move_effects/*.asm` and
  `engine/battle/effect_commands.asm`

Do not implement from a modern wiki description. Later generations changed
many moves.

## Test layers

1. **Import contract**
   - Index, power, type, accuracy, PP, effect chance, and animation byte match
     the locally extracted Crystal ROM.
   - Every move from 166 through 251 appears exactly once.

2. **Registry contract**
   - The move resolves to a real effect record.
   - `implemented=false` placeholders are rejected.
   - Moves 1 through 251 resolve to the imported Crystal move rows after the
     mod loads.

3. **Deterministic effect contract**
   - Scripted RNG forces hit, miss, minimum, maximum, and secondary-effect
     branches.
   - State changes are asserted directly: HP, status, stages, PP, weather,
     hazards, trapping, forced moves, delayed actions, and switch state.

4. **Turn integration contract**
   - Effects that cross turn boundaries are tested through turn-start,
     turn-end, faint, and switch events rather than by calling a helper in
     isolation.

5. **Regression contract**
   - Run the complete engine suite after each effect batch.
   - A new Gen II mechanic may add an engine seam, but that seam must remain
     inactive for Gen I moves unless Crystal explicitly interacts with one
     of them, such as Rollout observing Defense Curl.

## Per-move implementation loop

For each failing move:

1. Open its row in `_move_parity_spec.lua` and run only that probe while
   developing.
2. Read the Crystal move row and the exact effect-command implementation.
3. Write or expand the test before changing runtime code. Include the normal
   case, failure case, and any boundary that changes state.
4. Decide where the behavior belongs:
   - `effects.lua` for a move-local handler or callback.
   - `EffectRegistry.lua` for a reusable damaging-pipeline stage.
   - `BattleState.lua` for ordering, switching, delayed actions, or state that
     spans turns.
   - Pokemon/save schemas only when the move requires persistent data, such
     as held items for Thief.
5. Implement the smallest reusable engine seam. Dispatch by Gen II move ID or
   a Crystal-only effect record so old moves remain untouched.
6. Run the targeted parity suite.
7. Run the complete modkit tier and engine tests.
8. Update the move's comments with the pinned Crystal source routine and any
   deliberate engine representation choice.

## Recommended implementation batches

### Batch 1: imported chance and straightforward shared mechanics

Correct the secondary-effect chance path and finish the moves that reuse a
simple existing mechanic:

- Powder Snow, Sludge Bomb, Mud-Slap, Octazooka, Zap Cannon, Icy Wind, Spark
- Steel Wing, DynamicPunch, DragonBreath, Iron Tail, Metal Claw
- Crunch, AncientPower, Shadow Ball, Rock Smash
- Cotton Spore, Scary Face, Sweet Kiss, Charm, Sweet Scent
- Mach Punch, ExtremeSpeed, Faint Attack, Vital Throw
- Bone Rush, Giga Drain, Milk Drink, Megahorn, Aeroblast, Cross Chop

### Batch 2: self-contained Crystal state

These can be implemented without party switching or delayed-action support:

- Sketch, Triple Kick, Mind Reader, Lock-On, Nightmare, Flame Wheel, Snore
- Curse, Flail, Reversal, Conversion 2, Spite
- Protect, Detect, Endure, Belly Drum, Foresight, Destiny Bond
- Rollout, False Swipe, Swagger, Fury Cutter, Attract, Sleep Talk
- Return, Present, Frustration, Safeguard, Pain Split, Sacred Fire, Magnitude
- Encore, Rapid Spin, Hidden Power, Twister, Mirror Coat, Psych Up

### Batch 3: field and side state

- Spikes
- Perish Song
- Sandstorm
- Rain Dance
- Sunny Day
- Whirlpool
- Spider Web and Mean Look escape/switch restrictions
- Morning Sun, Synthesis, and Moonlight weather healing

### Batch 4: party, switch, and delayed-action infrastructure

Implement the shared engine systems first, then the moves:

- Nullable held-item state, then Thief
- Switch interception, then Pursuit
- Switch-with-state-transfer, then Baton Pass
- Delayed attack queue, then Future Sight
- Eligible-party hit enumeration, then Beat Up

## Required edge cases for exact parity

A move is not complete after its main success path works. Add relevant cases
from this list:

- accuracy failure and semi-invulnerability
- type immunity and substitute behavior
- target fainting before a secondary effect
- user fainting from recoil, Curse cost, or Destiny Bond
- full HP, 1 HP, stage limits, zero PP, and invalid last move
- switching either participant
- called moves through Sleep Talk, Metronome, or Mirror Move
- consecutive-use reset rules
- wild, trainer, and link-battle persistence differences
- weather expiration and residual ordering
- interaction with Protect, Safeguard, Foresight, Spikes, trapping, and
  Defense Curl

## Commands

Run the Crystal move suite directly:

```bash
CRYSTAL_ROM="/path/to/Pokemon Crystal.gbc" \
  luajit mods/CRYSTAL_251/tests/move_parity_test.lua
```

Run all shipped mod tests:

```bash
CRYSTAL_ROM="/path/to/Pokemon Crystal.gbc" luajit tests/run_modkit.lua
```

Run syntax checks for the move files:

```bash
for file in \
  mods/CRYSTAL_251/effects.lua \
  mods/CRYSTAL_251/tests/_move_parity_spec.lua \
  mods/CRYSTAL_251/tests/move_parity_test.lua
do
  texluac -p "$file" || exit 1
done
```

Run the complete engine suite before committing a parity batch:

```bash
luajit tests/run_tests.lua
```

## Definition of done

Generation II move parity is complete only when:

- all 86 manifest entries pass their behavior probes;
- no move uses an `implemented=false` effect;
- every probabilistic branch is tested at both sides of its threshold;
- switch, turn, faint, party, and delayed effects have integration tests;
- ordinary Gen I move definitions remain unchanged except for the audited
  Crystal command-family overrides;
- the full modkit and engine test tiers pass.

## Exhaustive milestone runner

Patch 0025 adds a single runner for the complete mechanical parity matrix:

```bash
CRYSTAL_ROM="/path/to/Pokemon Crystal.gbc" \
  luajit mods/CRYSTAL_251/tests/run_crystal_parity.lua
```

`crystal_exhaustive_parity_test.lua` independently audits all 251 imported move
records, command scripts, effect registrations, and every ordinary damaging
move at minimum, maximum, and critical damage rolls. Fire- and Water-type
moves also receive clear-weather, rain, and sun vectors. The runner then
executes the dedicated status, item, switching, AI, scheduler, battle-mode,
link, capture, progression, PP, multi-turn, and special-damage suites.

`crystal_full_battle_test.lua` is the state-machine layer above those focused
probes. It invokes the real party-menu callbacks and drains complete battle
queues while varying stale insertion indexes, trap families, battle modes,
switch directions, Pursuit interception, Baton Pass state transfer, Spikes,
faint replacement, and end-of-turn execution.

## Mechanical completion

Patch 0026 removes the temporary unimplemented-effect registration path,
installs the runtime bridge only after imported data is configured, and adds an
idempotent integration audit. A successful `run_crystal_parity.lua` execution
therefore represents mechanically complete Crystal battles. Remaining work is
presentation parity: cries, animated battle sprites, move animations, weather
visuals, and message timing.
