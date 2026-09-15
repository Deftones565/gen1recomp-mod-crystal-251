local RuntimePatches = require("mods.CRYSTAL_251.lib.runtime_patches")
local Effects = {}
Effects.CHANCE_EFFECTS = {}

-- Crystal-only effects use stable byte ids.  The move table is canonicalized
-- from Crystal for all 251 moves, including moves 1..165; this module owns the
-- Crystal effect records that the Gen I battle shell dispatches.
function Effects.install(mod)
  local MoveEffects = require("src.battle.MoveEffects")
  local EffectRegistry = RuntimePatches.watch(require("src.battle.EffectRegistry"))
  local TypeChart = require("src.battle.TypeChart")
  local CrystalDamage = require("mods.CRYSTAL_251.battle.crystal_damage")
  local Gen2Effects = require("mods.CRYSTAL_251.battle.gen2.Effects")
  local CrystalStats = require("mods.CRYSTAL_251.battle.crystal_stats")
  local SpecialDamage = require("mods.CRYSTAL_251.battle.special_damage")
  local MultiTurn = require("mods.CRYSTAL_251.battle.multi_turn")
  local CrystalStatus = require("mods.CRYSTAL_251.battle.crystal_status")
  local CrystalSwitching = require("mods.CRYSTAL_251.battle.crystal_switching")
  local CrystalItems = require("mods.CRYSTAL_251.battle.crystal_items")
  local CrystalScheduler = require("mods.CRYSTAL_251.battle.crystal_scheduler")
  local CrystalProgression = require("mods.CRYSTAL_251.battle.crystal_progression")
  local Gen2TurnOrder = require("mods.CRYSTAL_251.battle.gen2.TurnOrder")
  local registered = {}
  if not EffectRegistry._crystal251InvulnerabilityBridge then
    EffectRegistry._crystal251InvulnerabilityBridge = true
    local runDamaging = EffectRegistry.runDamaging
    EffectRegistry.runDamaging = function(battle, ctx, record)
      local target = ctx and ctx.target
      local hidden
      if target and target.invulnerable and record and record.hitInvulnerable
          and record.hitInvulnerable(ctx) then
        hidden = target.invulnerable
        target.invulnerable = nil
      end
      local accuracy = battle.accuracyRoll
      local contextAccuracy = ctx and ctx.accuracyRoll
      if record and record.accuracy then
        ctx.accuracyRoll = function()
          return accuracy(battle, ctx.move, ctx.user, ctx.target)
        end
        battle.accuracyRoll = function()
          return record.accuracy(ctx)
        end
      end

      local ok, result = pcall(runDamaging, battle, ctx, record)

      battle.accuracyRoll = accuracy
      if ctx then ctx.accuracyRoll = contextAccuracy end
      if hidden then target.invulnerable = hidden end
      if not ok then error(result, 0) end
      return result
    end
  end
  local function name(ctx, battler)
    return battler.isPlayer and battler.name or ("Enemy " .. battler.name)
  end
  local function record(code, kind, run, extra)
    local id = ("CRYSTAL_EFFECT_%02X"):format(code)
    local def = extra or {}
    def.kind = kind or def.kind or "full"
    -- Keep secondary-effect probability inside CRYSTAL_251.  Released engine
    -- builds do not interpret the newer useEffectChance record hint, so
    -- relying on it makes every imported chance-based effect unconditional.
    -- Consuming the byte here also keeps the mod compatible with engines that
    -- do understand the hint: remove it from the registered record so the
    -- chance is never rolled twice.
    if def.useEffectChance and run ~= nil then
      local effectRun = run
      Effects.CHANCE_EFFECTS[id] = true
      def.useEffectChance = nil
      run = function(ctx)
        local chance = ctx.move.effectChance or 0
        if chance <= 0 or ctx.rng(0, 255) >= chance then return {} end
        return effectRun(ctx)
      end
    end
    if run ~= nil then def.run = run end
    mod.content.move_effects:register(id, def)
    registered[code] = true
  end

  -- Old and new command-specific damage moves share the same mod-local
  -- interpreter records. The corresponding move rows are patched to these raw
  -- Crystal effect ids after the ROM cache is loaded in main.lua.
  for _, code in ipairs({ 0x1a, 0x26, 0x28, 0x29, 0x57, 0x58, 0x59 }) do
    record(code, "full", nil, SpecialDamage.record())
  end
  for _, code in ipairs({ 0x1b, 0x1d, 0x2c, 0x4d, 0x51 }) do
    record(code, "full", nil, MultiTurn.record())
  end

  local function isType(battler, wanted)
    for _, typeId in ipairs(battler.curTypes or {}) do
      if typeId == wanted then return true end
    end
    return false
  end

  local function rngRange(ctx, low, high)
    local value = ctx.rng(low, high)
    if value < low then return low end
    if value > high then return high end
    return value
  end

  local function statusSide(status)
    return function(ctx)
      return ctx.inflict(ctx.target, status, {
        secondary = true, moveType = ctx.move.type, source = ctx.move.id,
      })
    end
  end

  local function confuseTarget(ctx, target, secondary)
    return CrystalStatus.confuse(ctx, target, secondary)
  end

  local function thawUser(ctx)
    if ctx.user.mon.status ~= "FRZ" then return end
    ctx.user.mon.status = nil
    ctx.say(name(ctx, ctx.user) .. " was defrosted!")
  end

  local function snapshotLinkItems(battle)
    if not battle or battle.kind ~= "link" or battle.crystalOriginalHeldItems then
      return
    end
    local playerParty = battle.game and battle.game.save and battle.game.save.party or {}
    local enemyParty = battle.enemyParty or {}
    local snapshot = { player = {}, enemy = {} }
    for i, mon in ipairs(playerParty) do snapshot.player[i] = mon.heldItem or false end
    for i, mon in ipairs(enemyParty) do snapshot.enemy[i] = mon.heldItem or false end
    battle.crystalOriginalHeldItems = snapshot
  end

  local function restoreLinkItems(battle)
    local snapshot = battle and battle.crystalOriginalHeldItems
    if not snapshot then return end
    local playerParty = battle.game and battle.game.save and battle.game.save.party or {}
    local enemyParty = battle.enemyParty or {}
    for i, item in pairs(snapshot.player or {}) do
      if playerParty[i] then playerParty[i].heldItem = item ~= false and item or nil end
    end
    for i, item in pairs(snapshot.enemy or {}) do
      if enemyParty[i] then enemyParty[i].heldItem = item ~= false and item or nil end
    end
    battle.crystalOriginalHeldItems = nil
  end

  local function screenSide(battle, battler)
    battle.crystalScreens = battle.crystalScreens or { player={}, enemy={} }
    return battler.isPlayer and battle.crystalScreens.player
      or battle.crystalScreens.enemy
  end

  local function syncScreens(battle, battler)
    if not (battle and battler) then return end
    local side = screenSide(battle, battler)
    battler.reflectTurns = side.reflectTurns
    battler.lightScreenTurns = side.lightScreenTurns
    battler.reflect = side.reflectTurns and side.reflectTurns > 0 or nil
    battler.lightScreen = side.lightScreenTurns and side.lightScreenTurns > 0 or nil
  end

  local function startScreen(ctx, field, label)
    local side = screenSide(ctx.battle, ctx.user)
    local turns = field .. "Turns"
    if side[turns] and side[turns] > 0 then return { "But, it failed!" } end
    side[turns] = 5
    syncScreens(ctx.battle, ctx.user)
    return { name(ctx, ctx.user) .. label }
  end

  -- Crystal-owned major-status and volatile families. Old Kanto moves are
  -- selectively routed to these raw effect ids by crystal_status.patchMoves.
  record(1, "primary", function(ctx)
    local messages = ctx.inflict(ctx.target, "SLP", {
      moveType=ctx.move.type, source=ctx.move.id,
    })
    return #messages > 0 and messages or { "But, it failed!" }
  end, { accuracyChecked=true })
  record(2, "secondary", statusSide("PSN"), { useEffectChance=true })
  record(4, "secondary", statusSide("BRN"), { useEffectChance=true })
  record(5, "secondary", statusSide("FRZ"), { useEffectChance=true })
  record(6, "secondary", statusSide("PAR"), { useEffectChance=true })
  record(28, "primary", CrystalSwitching.forceSwitch, { accuracyChecked=true })
  record(31, "secondary", CrystalStatus.flinch, { useEffectChance=true })
  record(32, "primary", function(ctx)
    if ctx.move.id == "REST" then return CrystalStatus.rest(ctx) end
    local mon = ctx.user.mon
    if mon.hp >= mon.stats.hp then return {"But, it failed!"} end
    mon.hp = math.min(mon.stats.hp, mon.hp + math.max(1, math.floor(mon.stats.hp / 2)))
    ctx.drain()
    return {name(ctx,ctx.user) .. " regained health!"}
  end)
  record(33, "primary", function(ctx)
    local messages = ctx.inflict(ctx.target, "PSN", {
      toxic=true, moveType=ctx.move.type, source=ctx.move.id,
    })
    return #messages > 0 and messages or { "But, it failed!" }
  end, { accuracyChecked=true })
  record(36, "secondary", function(ctx)
    local choice
    repeat
      choice = math.floor(ctx.rng(0, 255) / 16) % 4
    until choice ~= 0
    local status = ({ "PAR", "FRZ", "BRN" })[choice]
    return ctx.inflict(ctx.target, status, {
      secondary=true, moveType=ctx.move.type, source=ctx.move.id,
    })
  end, { useEffectChance=true })
  record(42, "full", nil, { afterDamage=CrystalStatus.trapAfterDamage })
  record(46, "primary", CrystalStatus.startMist)
  record(47, "primary", CrystalStatus.startFocusEnergy)
  record(49, "primary", function(ctx)
    return confuseTarget(ctx, ctx.target, false)
  end, { accuracyChecked=true })
  record(66, "primary", function(ctx)
    local messages = ctx.inflict(ctx.target, "PSN", {
      moveType=ctx.move.type, source=ctx.move.id,
    })
    return #messages > 0 and messages or { "But, it failed!" }
  end, { accuracyChecked=true })
  record(67, "primary", function(ctx)
    local messages = ctx.inflict(ctx.target, "PAR", {
      moveType=ctx.move.type, source=ctx.move.id,
    })
    return #messages > 0 and messages or { "But, it failed!" }
  end, { accuracyChecked=true })
  record(76, "secondary", function(ctx)
    return confuseTarget(ctx, ctx.target, true)
  end, { useEffectChance=true })
  record(79, "primary", CrystalStatus.substitute)
  record(84, "primary", CrystalStatus.leechSeed, { accuracyChecked=true })
  record(86, "primary", CrystalStatus.disable, { accuracyChecked=true })

  -- Faint Attack and Vital Throw bypass ordinary accuracy, but Crystal still
  -- rejects a target hidden by Fly or Dig before reaching this callback.
  record(17, "full", nil, { accuracy=function() return true end })
  for code, stat in pairs({
    [68]="attack", [69]="defense", [70]="speed",
  }) do
    -- Lua 5.1 closes over the loop variable itself. Freeze the stat name per
    -- record rather than letting every callback inherit the final iteration.
    local statName = stat
    record(code, "secondary", function(ctx)
      return ctx.changeStage(ctx.target, statName, -1, false)
    end, { useEffectChance=true })
  end
  -- Crystal Haze resets the seven stat levels and recalculates both battlers;
  -- unlike the Generation I handler it does not cure status or erase screens.
  record(25, "primary", function(ctx)
    CrystalStats.reset(ctx.user)
    CrystalStats.reset(ctx.target)
    CrystalDamage.attachBattler(ctx.user)
    CrystalDamage.attachBattler(ctx.target)
    return { "All stat changes were eliminated!" }
  end)

  record(35, "primary", function(ctx)
    return startScreen(ctx, "lightScreen", " raised a LIGHT SCREEN!")
  end)

  record(57, "primary", function(ctx) -- Transform
    local native = MoveEffects.primary.TRANSFORM_EFFECT
    local messages = native(ctx.battle, ctx.user, ctx.target, ctx.move)
    CrystalDamage.transformBattler(ctx.user, ctx.target)
    return messages
  end)

  record(65, "primary", function(ctx)
    return startScreen(ctx, "reflect", " raised REFLECT!")
  end)

  local splitLabels = {
    specialAttack = "SPCL.ATK",
    specialDefense = "SPCL.DEF",
  }
  local function changeCrystalStage(ctx, target, stat, delta, fromEnemy)
    if not splitLabels[stat] then
      return MoveEffects.changeStage(ctx.battle, target, stat, delta, fromEnemy)
    end
    if fromEnemy and (target.substituteHP or target.mist) then
      return { "But, it failed!" }
    end
    local old, new, changed = CrystalStats.change(target, stat, delta)
    if not changed then return { "Nothing happened!" } end
    local direction = delta > 0 and "rose!" or "fell!"
    return { name(ctx, target) .. "'s " .. splitLabels[stat] .. " " .. direction }
  end

  for code, stat in pairs({ [71]="specialAttack", [72]="specialDefense" }) do
    local statName = stat
    record(code, "secondary", function(ctx)
      return changeCrystalStage(ctx, ctx.target, statName, -1, false)
    end, { useEffectChance=true })
  end

  local statRows = {
    [10]={"attack",1}, [11]={"defense",1}, [12]={"speed",1},
    [13]={"specialAttack",1}, [14]={"specialDefense",1},
    [15]={"accuracy",1}, [16]={"evasion",1},
    [18]={"attack",-1}, [19]={"defense",-1}, [20]={"speed",-1},
    [21]={"specialAttack",-1}, [22]={"specialDefense",-1},
    [23]={"accuracy",-1}, [24]={"evasion",-1},
    [50]={"attack",2}, [51]={"defense",2}, [52]={"speed",2},
    [53]={"specialAttack",2}, [54]={"specialDefense",2},
    [55]={"accuracy",2}, [56]={"evasion",2},
    [58]={"attack",-2}, [59]={"defense",-2}, [60]={"speed",-2},
    [61]={"specialAttack",-2}, [62]={"specialDefense",-2},
    [63]={"accuracy",-2}, [64]={"evasion",-2},
  }
  for code, row in pairs(statRows) do
    local rowDef = row
    record(code, "primary", function(ctx)
      local target = rowDef[2] > 0 and ctx.user or ctx.target
      local before = target.stages and (target.stages[rowDef[1]] or 0) or 0
      local messages = changeCrystalStage(
        ctx, target, rowDef[1], rowDef[2], rowDef[2] < 0)
      local after = target.stages and (target.stages[rowDef[1]] or 0) or before
      if ctx.move.id == "MINIMIZE" and after > before then
        target.minimized = true
      end
      return messages
    end, rowDef[2] < 0 and { accuracyChecked=true } or nil)
  end
  record(90, "primary", CrystalStatus.encore, { accuracyChecked=true })
  for code, stat in pairs({ [73]="accuracy", [74]="evasion" }) do
    local statName = stat
    record(code, "secondary", function(ctx)
      return ctx.changeStage(ctx.target, statName, -1, false)
    end, { useEffectChance=true })
  end
  record(91, "primary", function(ctx) -- Pain Split
    local hp = math.floor((ctx.user.mon.hp + ctx.target.mon.hp) / 2)
    ctx.user.mon.hp = math.min(ctx.user.mon.stats.hp, hp)
    ctx.target.mon.hp = math.min(ctx.target.mon.stats.hp, hp)
    ctx.drain()
    return { "The battlers shared their pain!" }
  end, { accuracyChecked=true })
  record(92, "secondary", function(ctx) -- Snore
    ctx.target.flinched = true
    return {}
  end, {
    useEffectChance=true,
    gate=function(ctx)
      if ctx.user.mon.status ~= "SLP" then return false, "But, it failed!" end
      return true
    end,
  })

  record(93, "primary", function(ctx) -- Conversion 2
    local last = ctx.target.lastMove
    local lastDef = last and ctx.data.moves[last]
    if not lastDef then return { "But, it failed!" } end
    local candidates = {}
    for _, typeId in ipairs({
      "NORMAL", "FIGHTING", "FLYING", "POISON", "GROUND", "ROCK",
      "BUG", "GHOST", "STEEL", "FIRE", "WATER", "GRASS", "ELECTRIC",
      "PSYCHIC_TYPE", "ICE", "DRAGON", "DARK",
    }) do
      if TypeChart.effectiveness(lastDef.type, { typeId }) <= 5
         and not isType(ctx.user, typeId) then
        candidates[#candidates + 1] = typeId
      end
    end
    if #candidates == 0 then return { "But, it failed!" } end
    local picked = candidates[rngRange(ctx, 1, #candidates)]
    ctx.user.curTypes = { picked }
    return { name(ctx, ctx.user) .. " became the " .. picked .. " type!" }
  end)

  record(94, "primary", function(ctx) -- Lock-On / Mind Reader
    ctx.user.lockedTarget, ctx.user.lockOnTurns = ctx.target, 2
    return { name(ctx, ctx.user) .. " took aim!" }
  end, { accuracyChecked=true })
  record(95, "primary", function(ctx) -- Sketch
    local last = ctx.target.lastMove
    local moveDef = last and ctx.data.moves[last]
    if not moveDef or last == "SKETCH" or last == "STRUGGLE" then
      return { "But, it failed!" }
    end
    ctx.moveInst.id = last
    ctx.moveInst.pp = moveDef.pp or 1
    return { name(ctx, ctx.user) .. " sketched " .. moveDef.name .. "!" }
  end, { accuracyChecked=true })

  record(96, "secondary", function(ctx) -- Defrost opponent
    if ctx.target.mon.status ~= "FRZ" then return {} end
    ctx.target.mon.status = nil
    return { name(ctx, ctx.target) .. " was defrosted!" }
  end)

  record(97, "primary", function(ctx) -- Sleep Talk
    if ctx.user.mon.status ~= "SLP" then return { "But, it failed!" } end
    local choices = {}
    for _, move in ipairs(ctx.user.mon.moves or {}) do
      if move.id ~= "SLEEP_TALK" and move.id ~= "REST" then
        choices[#choices + 1] = move.id
      end
    end
    if #choices == 0 then return { "But, it failed!" } end
    ctx.callMove(choices[rngRange(ctx, 1, #choices)])
    return {}
  end)
  record(98, "primary", function(ctx) -- Destiny Bond
    ctx.user.destinyBond = true
    return { name(ctx, ctx.user) .. " is trying to take its foe with it!" }
  end)
  record(99, "full", nil, SpecialDamage.record()) -- Reversal / Flail

  record(100, "primary", function(ctx) -- Spite
    local last = ctx.target.lastMove
    local slot
    for _, moveInst in ipairs(ctx.target.curMoves or {}) do
      if moveInst.id == last then slot = moveInst break end
    end
    if not slot or (slot.pp or 0) <= 0 then return { "But, it failed!" } end
    local loss = math.min(slot.pp, rngRange(ctx, 2, 5))
    slot.pp = slot.pp - loss
    return { last .. " lost " .. tostring(loss) .. " PP!" }
  end, { accuracyChecked=true })

  record(101, "full", nil) -- False Swipe floor is set by battle.damage

  record(104, "full", nil, MultiTurn.record()) -- Triple Kick

  record(105, "full", nil, {
    afterDamage=function(ctx, totalDealt)
      if ctx.rng(0, 255) >= (ctx.move.effectChance or 0) then return end
      snapshotLinkItems(ctx.battle)
      ctx.totalDealt = totalDealt
      CrystalItems.steal(ctx)
    end,
  })

  record(106, "primary", CrystalStatus.meanLook, { accuracyChecked=true })
  record(102, "primary", function(ctx) -- Heal Bell
    local save = ctx.battle.game and ctx.battle.game.save
    local party = ctx.user.isPlayer and save and save.party or ctx.battle.enemyParty
    for _, mon in ipairs(party or {}) do mon.status = nil end
    ctx.user.mon.status = nil
    return { "A bell chimed!" }
  end)
  record(107, "primary", CrystalStatus.nightmare, { accuracyChecked=true })
  record(108, "secondary", statusSide("BRN"), {
    useEffectChance=true,
    beforeAccuracy=thawUser,
  })

  record(109, "primary", function(ctx) -- Curse
    local ghost = false
    for _, typeId in ipairs(ctx.user.curTypes or {}) do
      if typeId == "GHOST" then ghost = true end
    end
    if ghost then
      local cost = math.floor(ctx.user.mon.stats.hp / 2)
      if ctx.user.mon.hp <= cost then return { "But, it failed!" } end
      ctx.damage(ctx.user, cost); ctx.target.cursed = true
      return { name(ctx, ctx.target) .. " was afflicted by a CURSE!" }
    end
    local messages = ctx.changeStage(ctx.user, "speed", -1, false)
    for _, stat in ipairs({ "attack", "defense" }) do
      for _, message in ipairs(ctx.changeStage(ctx.user, stat, 1, false)) do
        messages[#messages + 1] = message
      end
    end
    return messages
  end)
  local function protectLike(field, message)
    return function(ctx)
      local user, turn = ctx.user, ctx.battle.turnCount or 0
      if user.substituteHP then
        user.protectChain, user.protectLastTurn = nil, nil
        return { "But, it failed!" }
      end
      local consecutive = user.protectLastTurn == turn - 1
      user.protectChain = consecutive and ((user.protectChain or 1) + 1) or 1
      user.protectLastTurn = turn
      local consecutiveUses = math.max(0, user.protectChain - 1)
      if not Gen2Effects.protectSucceeds(consecutiveUses, function(n)
        return math.max(0, ctx.rng(0, n - 1))
      end) then
        user.protectChain = nil
        return { "But, it failed!" }
      end
      user[field] = true
      return { name(ctx, user) .. message }
    end
  end

  record(111, "primary", protectLike("protect", " protected itself!"))
  record(112, "primary", CrystalSwitching.spikes)
  record(113, "primary", function(ctx) -- Foresight
    ctx.target.foresight = true
    return { name(ctx, ctx.target) .. " was identified!" }
  end, { accuracyChecked=true })

  record(114, "primary", CrystalStatus.perishSong)
  record(115, "primary", function(ctx) ctx.battle.weather = "sandstorm"; ctx.battle.weatherTurns = 5
    return { "A sandstorm brewed!" } end)
  record(116, "primary", protectLike("endure", " braced itself!"))

  record(117, "full", nil, MultiTurn.record()) -- Rollout

  record(118, "primary", function(ctx) -- Swagger
    local messages = ctx.changeStage(ctx.target, "attack", 2, true)
    for _, message in ipairs(confuseTarget(ctx, ctx.target, false)) do
      messages[#messages + 1] = message
    end
    return messages
  end, { accuracyChecked=true })
  record(119, "full", nil, MultiTurn.record()) -- Fury Cutter

  record(120, "primary", CrystalStatus.attract, { accuracyChecked=true })
  record(121, "full", nil) -- Return

  record(122, "full", nil, SpecialDamage.record()) -- Present

  record(123, "full", nil) -- Frustration

  record(124, "primary", CrystalStatus.startSafeguard)
  record(125, "secondary", statusSide("BRN"), {
    useEffectChance=true,
    beforeAccuracy=thawUser,
  })
  record(126, "full", nil, {
    hitInvulnerable=function(ctx)
      return ctx.target.invulnerableMove == "DIG"
    end,
  }) -- Magnitude

  record(127, "full", nil, { perform=CrystalSwitching.batonPass }) -- Baton Pass

  record(128, "full", nil, { -- Pursuit
    onSwitchAttempt=function(ctx)
      ctx.battle.crystalSwitchingTarget = ctx.target
      ctx.battle:performMove(ctx.user, ctx.target, ctx.moveInst, false)
      ctx.battle.crystalSwitchingTarget = nil
      CrystalScheduler.afterAction(ctx.battle, ctx.user, ctx.target)
      return true
    end,
  })

  record(129, "full", nil, { -- Rapid Spin
    afterDamage=function(ctx)
      for _, message in ipairs(CrystalStatus.rapidSpin(ctx)) do ctx.say(message) end
    end,
  })

  for _, code in ipairs({ 132, 133, 134 }) do -- Morning Sun / Synthesis / Moonlight
    record(code, "primary", function(ctx)
      if ctx.user.mon.hp >= ctx.user.mon.stats.hp then return { "But, it failed!" } end
      local wants = ({ [132]=0, [133]=1, [134]=2 })[code]
      local fraction = Gen2Effects.timeBasedHealFraction(
        ctx.battle.weather, wants, ctx.battle.timeOfDay)
      local heal = math.max(1, math.floor(ctx.user.mon.stats.hp * fraction))
      ctx.user.mon.hp = math.min(ctx.user.mon.stats.hp, ctx.user.mon.hp + heal)
      ctx.drain()
      return { name(ctx, ctx.user) .. " regained health!" }
    end)
  end
  record(136, "primary", function(ctx) ctx.battle.weather = "rain"; ctx.battle.weatherTurns = 5
    return { "It started to rain!" } end)
  record(137, "primary", function(ctx) ctx.battle.weather = "sun"; ctx.battle.weatherTurns = 5
    return { "The sunlight got bright!" } end)
  record(135, "full", nil) -- Hidden Power

  record(138, "secondary", function(ctx)
    return ctx.changeStage(ctx.user, "defense", 1, false)
  end, { useEffectChance=true })
  record(139, "secondary", function(ctx)
    return ctx.changeStage(ctx.user, "attack", 1, false)
  end, { useEffectChance=true })
  record(140, "secondary", function(ctx)
    local messages = {}
    for _, stat in ipairs({
      "attack", "defense", "speed", "specialAttack", "specialDefense",
    }) do
      local changed = splitLabels[stat]
        and changeCrystalStage(ctx, ctx.user, stat, 1, false)
        or ctx.changeStage(ctx.user, stat, 1, false)
      for _, message in ipairs(changed) do messages[#messages + 1] = message end
    end
    return messages
  end, { useEffectChance=true })

  record(141, "secondary", function(ctx) -- Fake Out
    ctx.target.flinched = true
    return {}
  end, {
    gate=function(ctx)
      if ctx.user.crystalEnteredTurn ~= (ctx.battle.turnCount or 0) then
        return false, "But, it failed!"
      end
      return true
    end,
  })

  record(142, "primary", function(ctx) -- Belly Drum
    ctx.user.stages = ctx.user.stages or {}
    local attack = ctx.user.stages.attack or 0
    if attack >= 6 then return { "But, it failed!" } end
    -- Crystal performs its first sharp boost before checking HP.  The
    -- original low-HP bug leaves this +2 behind when the move then fails.
    ctx.user.stages.attack = math.min(6, attack + 2)
    local cost = math.floor(ctx.user.mon.stats.hp / 2)
    if ctx.user.mon.hp <= cost then return { "But, it failed!" } end
    ctx.damage(ctx.user, cost); ctx.user.stages.attack = 6
    return { name(ctx, ctx.user) .. " maximized ATTACK!" }
  end)
  record(143, "primary", function(ctx) -- Psych Up
    CrystalStats.copy(ctx.user, ctx.target)
    return { name(ctx, ctx.user) .. " copied the stat changes!" }
  end)
  record(144, "full", nil, SpecialDamage.record()) -- Mirror Coat

  record(146, "secondary", function(ctx) -- Twister
    ctx.target.flinched = true
    return {}
  end, {
    useEffectChance=true,
    hitInvulnerable=function(ctx)
      return ctx.target.invulnerableMove == "FLY"
    end,
  })
  record(147, "full", nil, { -- Earthquake
    hitInvulnerable=function(ctx)
      return ctx.target.invulnerableMove == "DIG"
    end,
  })
  record(148, "full", nil, SpecialDamage.record()) -- Future Sight
  record(149, "full", nil, { -- Gust
    hitInvulnerable=function(ctx)
      return ctx.target.invulnerableMove == "FLY"
    end,
  })
  record(150, "secondary", CrystalStatus.flinch, { -- Stomp
    useEffectChance=true,
  })
  record(152, "secondary", statusSide("PAR"), { -- Thunder
    useEffectChance=true,
    accuracy=function(ctx)
      if ctx.battle.weather == "rain" then return true end
      local old = ctx.move.accuracy
      if ctx.battle.weather == "sun" then
        ctx.move.accuracy = 128 * 100 / 255
      end
      local ok, result = pcall(ctx.accuracyRoll)
      ctx.move.accuracy = old
      if not ok then error(result, 0) end
      return result
    end,
  })
  record(154, "full", nil, SpecialDamage.record()) -- Beat Up
  record(156, "primary", function(ctx) -- Defense Curl
    local before = ctx.user.stages.defense or 0
    local messages = ctx.changeStage(ctx.user, "defense", 1, false)
    if (ctx.user.stages.defense or 0) > before then
      ctx.user.defenseCurl = true
    end
    return messages
  end)

  require("mods.CRYSTAL_251.battle.crystal_classic_effects").register(mod, record)

  -- Only neutral/unused bytes and damage-hook-owned effects remain empty.
  for code = 0, 0x9c do
    if not registered[code] then
      record(code, "full", nil)
    end
  end

  mod.hooks:wrap("battle.accuracy", function(next, ctx)
    return CrystalItems.withBrightPowder(next, ctx)
  end, 40)

  mod.hooks:wrap("battle.turn_order", function(next, a, aMove, b, bMove, ctx)
    if not ((a and a.crystal251Active) or (b and b.crystal251Active)) then
      return next(a, aMove, b, bMove, ctx)
    end
    return Gen2TurnOrder.firstMover(a, aMove, b, bMove,
      ctx and ctx.rng, ctx and ctx.invertTie)
  end, 40)

  mod.hooks:wrap("battle.accuracy", function(next, ctx)
    if ctx.target.protect then return false end
    if ctx.user.lockedTarget == ctx.target and (ctx.user.lockOnTurns or 0) > 0 then
      return true
    end
    local userAcc = ctx.user.stages and ctx.user.stages.accuracy or 0
    local targetEva = ctx.target.stages and ctx.target.stages.evasion or 0
    if ctx.target.foresight and targetEva >= userAcc then
      ctx.user.stages = ctx.user.stages or {}
      ctx.target.stages = ctx.target.stages or {}
      local oldAcc, oldEva = ctx.user.stages.accuracy, ctx.target.stages.evasion
      ctx.user.stages.accuracy, ctx.target.stages.evasion = 0, 0
      local ok, result = pcall(next, ctx)
      ctx.user.stages.accuracy, ctx.target.stages.evasion = oldAcc, oldEva
      if not ok then error(result, 0) end
      return result
    end
    return next(ctx)
  end, 60)

  mod.hooks:wrap("battle.damage", function(next, ctx)
    local move, user, target = ctx.move, ctx.user, ctx.target
    local token = CrystalDamage.prepareMove(move)
    local routed = token ~= nil
    local oldPower, oldType = move.power, move.type
    local oldTargetTypes = target.curTypes
    local hp, maxhp = user.mon.hp, user.mon.stats.hp
    if move.id == "RETURN" then
      move.power = math.max(1, Gen2Effects.happinessPower(user.mon.happiness or 70, false))
    elseif move.id == "FRUSTRATION" then
      move.power = math.max(1, Gen2Effects.happinessPower(user.mon.happiness or 70, true))
    elseif move.id == "FLAIL" or move.id == "REVERSAL" then
      local ratio = math.floor(48 * hp / math.max(1, maxhp))
      move.power = ratio <= 1 and 200 or ratio <= 4 and 150 or ratio <= 9 and 100
        or ratio <= 16 and 80 or ratio <= 32 and 40 or 20
    elseif move.id == "MAGNITUDE" then
      move.power = Gen2Effects.magnitudePower(function(n)
        return ctx.rng(0, n - 1)
      end)
    elseif move.id == "ROLLOUT" and not (ctx.opts and ctx.opts.crystalSequence) then
      move.power = Gen2Effects.rampedPower(oldPower, user.rolloutCount or 0,
        user.defenseCurl)
    elseif move.id == "FURY_CUTTER" and not (ctx.opts and ctx.opts.crystalSequence) then
      move.power = Gen2Effects.rampedPower(oldPower, user.furyCutterCount or 0,
        false)
    elseif move.id == "HIDDEN_POWER" then
      local d = user.mon.dvs or {}
      local types = { "FIGHTING", "FLYING", "POISON", "GROUND", "ROCK", "BUG",
        "GHOST", "STEEL", "FIRE", "WATER", "GRASS", "ELECTRIC",
        "PSYCHIC_TYPE", "ICE", "DRAGON", "DARK" }
      local index = math.floor((((d.attack or 0) % 4) * 4
        + (d.defense or 0) % 4) * 5 / 10) + 1
      move.type = types[index]
      local bits = math.floor((d.special or 0) / 8)
        + math.floor((d.speed or 0) / 8) * 2
        + math.floor((d.defense or 0) / 8) * 4
        + math.floor((d.attack or 0) / 8) * 8
      move.power = math.floor((bits * 5 + (d.special or 0) % 4) / 2) + 31
    end
    if target.foresight and (move.type == "NORMAL" or move.type == "FIGHTING") then
      local filtered = {}
      for _, typeId in ipairs(target.curTypes or {}) do
        if typeId ~= "GHOST" then filtered[#filtered + 1] = typeId end
      end
      target.curTypes = filtered
    end
    if not routed then
      if ctx.battle.weather == "rain" then
        if move.type == "WATER" then move.power = math.floor(move.power * 1.5)
        elseif move.type == "FIRE" then move.power = math.floor(move.power / 2) end
      elseif ctx.battle.weather == "sun" then
        if move.type == "FIRE" then move.power = math.floor(move.power * 1.5)
        elseif move.type == "WATER" then move.power = math.floor(move.power / 2) end
      end
    end

    local pursuitSwitching = move.id == "PURSUIT"
      and ctx.battle.crystalSwitchingTarget == target
    local doubleDamage = ((move.id == "GUST" or move.id == "TWISTER")
        and target.invulnerableMove == "FLY")
      or ((move.id == "EARTHQUAKE" or move.id == "MAGNITUDE")
        and target.invulnerableMove == "DIG")
      or (move.id == "STOMP" and target.minimized)
    local ok, damage, info = pcall(next, ctx)
    if ok and type(damage) == "number" then
      -- Crystal's Pursuit command doubles wCurDamage after the ordinary
      -- formula has finished. Doubling base power instead changes rounding.
      if doubleDamage then damage = math.min(65535, damage * 2) end
      if pursuitSwitching then damage = math.min(65535, damage * 2) end
      if (move.id == "FALSE_SWIPE" or target.endure)
         and damage >= target.mon.hp then
        damage = math.max(0, target.mon.hp - 1)
      end
    end
    if token then CrystalDamage.restoreMove(move, token)
    else move.power, move.type = oldPower, oldType end
    target.curTypes = oldTargetTypes
    if not ok then error(damage, 0) end
    return damage, info
  end, 60)

  mod.hooks:wrap("battle.run", function(next, ctx)
    return CrystalItems.run(next, ctx)
  end, 60)

  mod.hooks:wrap("battle.exp_award", function(next, ctx)
    return CrystalProgression.awardExp(next, ctx)
  end, 80)

  mod.events:on("battle.started", function(ev)
    local battle = ev.battle
    CrystalStatus.beginBattle(battle)
    CrystalItems.beginBattle(battle)
    snapshotLinkItems(battle)
    battle.crystalScreens = battle.crystalScreens or { player={}, enemy={} }
    for _, battler in ipairs({ battle.player, battle.enemy }) do
      if battler then
        battler.crystalEnteredTurn = (battle.turnCount or 0) + 1
        CrystalStats.ensure(battler)
        syncScreens(battle, battler)
      end
    end
  end)

  mod.events:on("battle.battler_switched", function(ev)
    local battle, battler, previous = ev.battle, ev.battler, ev.previous
    if not battler then return end
    battler.crystalEnteredTurn = (battle.turnCount or 0) + 1
    if previous and not battler.isPlayer then battle.participants = {} end
    if battle.markParticipant then battle:markParticipant() end
    CrystalStats.ensure(battler)
    CrystalStatus.onSwitch(battle, battler, previous, ev.batonPass)
    CrystalItems.beginBattle(battle)
    syncScreens(battle, battler)
    CrystalSwitching.applySpikes(battle, battler)
    if previous then
      previous.rageMove, previous.crystalRageMove = nil, nil
      previous.crystalRageCounter = nil
    end
  end)

  mod.events:on("battle.ended", function(ev)
    restoreLinkItems(ev and ev.battle)
  end)

  mod.events:on("battle.move_used", function(ev)
    local user, move = ev.user, ev.move
    if move.id ~= "FURY_CUTTER" then user.furyCutterCount = nil end
    if move.id ~= "ROLLOUT" and not user.forcedMove then user.rolloutCount = nil end
    if move.id ~= "PROTECT" and move.id ~= "DETECT" and move.id ~= "ENDURE" then
      user.protectChain, user.protectLastTurn = nil, nil
    end
    if user.destinyBond and move.id ~= "DESTINY_BOND" then
      user.destinyBond = nil
    end
  end)

  mod.events:on("battle.damage_dealt", function(ev)
    local crystalMove = CrystalDamage.moveFor(ev.move) or ev.move
    ev.target.crystalLastDamageTaken = {
      damage = ev.battle.lastDamage or ev.damage,
      from = ev.user,
      turn = ev.battle.turnCount or 0,
      category = crystalMove.category or TypeChart.category(crystalMove.type),
      moveId = crystalMove.id,
      power = crystalMove.power or 0,
      effect = crystalMove.effect,
    }
  end)

  mod.events:on("battle.fainted", function(ev)
    local battler, battle = ev.battler, ev.battle
    local last = battler and battler.crystalLastDamageTaken
    if battler and battler.destinyBond and last and last.from
       and last.turn == (battle.turnCount or 0) and last.from.mon.hp > 0 then
      battler.destinyBond = nil
      battle:applyDamage(last.from, last.from.mon.hp)
      battle:onFaint(last.from)
    end
  end)

  mod.events:on("battle.status_inflicted", function(ev)
    CrystalItems.onStatusInflicted(ev and ev.battle, ev and ev.target)
  end)
  mod.events:on("battle.confusion_inflicted", function(ev)
    CrystalItems.onConfusionInflicted(ev and ev.battle, ev and ev.target)
  end)

  mod.events:on("battle.turn_started", function(ev)
    CrystalScheduler.beginTurn(ev.battle)
    CrystalItems.beginTurn(ev.battle)
    CrystalStatus.beginTurn(ev.battle)
  end)
  mod.events:on("battle.turn_ended", function(ev)
    CrystalScheduler.onTurnEnded(ev)
  end)

end

return RuntimePatches.installers(Effects)
