local Effects = {}

-- Effects not already provided by the Gen I engine are registered under a
-- stable Crystal byte id. The first implementation tier preserves safe
-- damage/status behavior; stateful Gen II effects carry their state on the
-- battlers/battle so saves and replays never depend on a global singleton.
function Effects.install(mod)
  local MoveEffects = require("src.battle.MoveEffects")
  local function name(ctx, battler)
    return battler.isPlayer and battler.name or ("Enemy " .. battler.name)
  end
  local function record(code, kind, run)
    local id = ("CRYSTAL_EFFECT_%02X"):format(code)
    mod.content.move_effects:register(id, { kind = kind or "full", run = run })
  end
  local statRows = {
    [10]={"attack",1}, [11]={"defense",1}, [12]={"speed",1},
    [13]={"special",1}, [14]={"special",1}, [15]={"accuracy",1}, [16]={"evasion",1},
    [18]={"attack",-1}, [19]={"defense",-1}, [20]={"speed",-1},
    [21]={"special",-1}, [22]={"special",-1}, [23]={"accuracy",-1}, [24]={"evasion",-1},
    [50]={"attack",2}, [51]={"defense",2}, [52]={"speed",2},
    [53]={"special",2}, [54]={"special",2}, [55]={"accuracy",2}, [56]={"evasion",2},
    [58]={"attack",-2}, [59]={"defense",-2}, [60]={"speed",-2},
    [61]={"special",-2}, [62]={"special",-2}, [63]={"accuracy",-2}, [64]={"evasion",-2},
  }
  for code, row in pairs(statRows) do
    record(code, "primary", function(ctx)
      local target = row[2] > 0 and ctx.user or ctx.target
      return MoveEffects.changeStage(ctx.battle, target, row[1], row[2], row[2] < 0)
    end)
  end
  record(90, "primary", function(ctx) -- Encore
    local last = ctx.target.lastMove
    if not last then return { "But, it failed!" } end
    ctx.target.encoreMove, ctx.target.encoreTurns = last, ctx.battle.rng(3, 6)
    return { name(ctx, ctx.target) .. " got an ENCORE!" }
  end)
  record(36, "secondary", function(ctx) -- Tri Attack
    if ctx.rng(1, 5) ~= 1 then return {} end
    local status = ({ "BRN", "FRZ", "PAR" })[ctx.rng(1, 3)]
    return ctx.inflict(ctx.target, status, { secondary=true,
      moveType=ctx.move.type, source=ctx.move.id })
  end)
  for code, stat in pairs({ [73]="accuracy", [74]="evasion" }) do
    record(code, "secondary", function(ctx)
      if ctx.rng(0, 255) >= 77 then return {} end
      return ctx.changeStage(ctx.target, stat, -1, false)
    end)
  end
  record(91, "primary", function(ctx) -- Pain Split
    local hp = math.floor((ctx.user.mon.hp + ctx.target.mon.hp) / 2)
    ctx.user.mon.hp = math.min(ctx.user.mon.stats.hp, hp)
    ctx.target.mon.hp = math.min(ctx.target.mon.stats.hp, hp)
    ctx.drain()
    return { "The battlers shared their pain!" }
  end)
  record(94, "primary", function(ctx) -- Lock-On / Mind Reader
    ctx.user.lockedTarget, ctx.user.lockOnTurns = ctx.target, 2
    return { name(ctx, ctx.user) .. " took aim!" }
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
    ctx.callMove(choices[ctx.rng(1, #choices)])
    return {}
  end)
  record(98, "primary", function(ctx) -- Destiny Bond
    ctx.user.destinyBond = true
    return { name(ctx, ctx.user) .. " is trying to take its foe with it!" }
  end)
  record(106, "primary", function(ctx) -- Mean Look
    ctx.target.cantEscape = true
    return { name(ctx, ctx.target) .. " can't escape now!" }
  end)
  record(102, "primary", function(ctx) -- Heal Bell
    local save = ctx.battle.game and ctx.battle.game.save
    local party = ctx.user.isPlayer and save and save.party or ctx.battle.enemyParty
    for _, mon in ipairs(party or {}) do mon.status = nil end
    ctx.user.mon.status = nil
    return { "A bell chimed!" }
  end)
  record(107, "primary", function(ctx) -- Nightmare
    if ctx.target.mon.status ~= "SLP" then return { "But, it failed!" } end
    ctx.target.nightmare = true
    return { name(ctx, ctx.target) .. " began having a NIGHTMARE!" }
  end)
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
  record(111, "primary", function(ctx) -- Protect
    ctx.user.protect = true
    return { name(ctx, ctx.user) .. " protected itself!" }
  end)
  record(112, "primary", function(ctx) -- Spikes
    local side = ctx.user.isPlayer and "enemySpikes" or "playerSpikes"
    ctx.battle[side] = true
    return { "SPIKES scattered all around!" }
  end)
  record(114, "primary", function(ctx) -- Perish Song
    ctx.user.perishTurns, ctx.target.perishTurns = 3, 3
    return { "Both Pokemon will faint in 3 turns!" }
  end)
  record(115, "primary", function(ctx) ctx.battle.weather = "sandstorm"; ctx.battle.weatherTurns = 5
    return { "A sandstorm brewed!" } end)
  record(116, "primary", function(ctx) -- Endure
    ctx.user.endure = true
    return { name(ctx, ctx.user) .. " braced itself!" }
  end)
  record(118, "primary", function(ctx) -- Swagger
    local messages = ctx.changeStage(ctx.target, "attack", 2, true)
    ctx.target.confusedTurns = ctx.target.confusedTurns or ctx.rng(2, 5)
    messages[#messages + 1] = name(ctx, ctx.target) .. " became confused!"
    return messages
  end)
  record(120, "primary", function(ctx) -- Attract
    ctx.target.infatuatedWith = ctx.user
    return { name(ctx, ctx.target) .. " fell in love!" }
  end)
  record(124, "primary", function(ctx) ctx.user.safeguardTurns = 5
    return { name(ctx, ctx.user) .. " is protected by SAFEGUARD!" } end)
  for _, code in ipairs({ 132, 133, 134 }) do -- Morning Sun / Synthesis / Moonlight
    record(code, "primary", function(ctx)
      if ctx.user.mon.hp >= ctx.user.mon.stats.hp then return { "But, it failed!" } end
      local numerator, denominator = 1, 2
      if ctx.battle.weather == "sun" then numerator, denominator = 2, 3
      elseif ctx.battle.weather then numerator, denominator = 1, 4 end
      local heal = math.max(1, math.floor(ctx.user.mon.stats.hp * numerator / denominator))
      ctx.user.mon.hp = math.min(ctx.user.mon.stats.hp, ctx.user.mon.hp + heal)
      ctx.drain()
      return { name(ctx, ctx.user) .. " regained health!" }
    end)
  end
  record(136, "primary", function(ctx) ctx.battle.weather = "rain"; ctx.battle.weatherTurns = 5
    return { "It started to rain!" } end)
  record(137, "primary", function(ctx) ctx.battle.weather = "sun"; ctx.battle.weatherTurns = 5
    return { "The sunlight got bright!" } end)
  record(142, "primary", function(ctx) -- Belly Drum
    local cost = math.floor(ctx.user.mon.stats.hp / 2)
    if ctx.user.mon.hp <= cost then return { "But, it failed!" } end
    ctx.damage(ctx.user, cost); ctx.user.stages.attack = 6
    return { name(ctx, ctx.user) .. " maximized ATTACK!" }
  end)
  record(143, "primary", function(ctx) -- Psych Up
    for stat, value in pairs(ctx.target.stages or {}) do ctx.user.stages[stat] = value end
    return { name(ctx, ctx.user) .. " copied the stat changes!" }
  end)
  record(156, "primary", function(ctx) -- Defense Curl
    return ctx.changeStage(ctx.user, "defense", 1, false)
  end)

  mod.hooks:wrap("battle.accuracy", function(next, ctx)
    if ctx.target.protect then return false end
    if ctx.user.lockedTarget == ctx.target and (ctx.user.lockOnTurns or 0) > 0 then
      return true
    end
    return next(ctx)
  end, 60)

  mod.hooks:wrap("battle.damage", function(next, ctx)
    local move, user, target = ctx.move, ctx.user, ctx.target
    local oldPower, oldType = move.power, move.type
    local hp, maxhp = user.mon.hp, user.mon.stats.hp
    if move.id == "RETURN" then
      move.power = math.max(1, math.floor((user.mon.happiness or 70) * 10 / 25))
    elseif move.id == "FRUSTRATION" then
      move.power = math.max(1, math.floor((255 - (user.mon.happiness or 70)) * 10 / 25))
    elseif move.id == "FLAIL" or move.id == "REVERSAL" then
      local ratio = math.floor(48 * hp / math.max(1, maxhp))
      move.power = ratio <= 1 and 200 or ratio <= 4 and 150 or ratio <= 9 and 100
        or ratio <= 16 and 80 or ratio <= 32 and 40 or 20
    elseif move.id == "MAGNITUDE" then
      local roll = ctx.rng(1, 100)
      move.power = roll <= 5 and 10 or roll <= 15 and 30 or roll <= 35 and 50
        or roll <= 65 and 70 or roll <= 85 and 90 or roll <= 95 and 110 or 150
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
    if ctx.battle.weather == "rain" then
      if move.type == "WATER" then move.power = math.floor(move.power * 1.5)
      elseif move.type == "FIRE" then move.power = math.floor(move.power / 2) end
    elseif ctx.battle.weather == "sun" then
      if move.type == "FIRE" then move.power = math.floor(move.power * 1.5)
      elseif move.type == "WATER" then move.power = math.floor(move.power / 2) end
    end
    local damage, info = next(ctx)
    if (move.id == "FALSE_SWIPE" or target.endure) and damage >= target.mon.hp then
      damage = math.max(0, target.mon.hp - 1)
    end
    move.power, move.type = oldPower, oldType
    return damage, info
  end, 60)

  mod.events:on("battle.turn_started", function(ev)
    local battle = ev.battle
    for _, battler in ipairs({ battle.player, battle.enemy }) do
      battler.protect, battler.endure = nil, nil
    end
  end)
  mod.events:on("battle.turn_ended", function(ev)
    local battle = ev.battle
    for _, battler in ipairs({ battle.player, battle.enemy }) do
      if battler.lockOnTurns then battler.lockOnTurns = battler.lockOnTurns - 1 end
      if battler.encoreTurns then battler.encoreTurns = battler.encoreTurns - 1 end
      if battler.safeguardTurns then battler.safeguardTurns = battler.safeguardTurns - 1 end
      local residual = battler.cursed
        or (battler.nightmare and battler.mon.status == "SLP")
      if battler.mon.hp > 0 and residual then
        battle:applyDamage(battler,
          math.max(1, math.floor(battler.mon.stats.hp / 4)))
      end
      if battler.perishTurns then
        battler.perishTurns = battler.perishTurns - 1
        if battler.perishTurns <= 0 and battler.mon.hp > 0 then
          battle:applyDamage(battler, battler.mon.hp)
        end
      end
      if battler.mon.hp <= 0 then battle:onFaint(battler) end
    end
    if battle.weatherTurns then
      battle.weatherTurns = battle.weatherTurns - 1
      if battle.weather == "sandstorm" then
        for _, battler in ipairs({ battle.player, battle.enemy }) do
          local immune = false
          for _, typeId in ipairs(battler.curTypes or {}) do
            if typeId == "ROCK" or typeId == "GROUND" or typeId == "STEEL" then
              immune = true
            end
          end
          if not immune and battler.mon.hp > 0 then
            battle:applyDamage(battler,
              math.max(1, math.floor(battler.mon.stats.hp / 8)))
            if battler.mon.hp <= 0 then battle:onFaint(battler) end
          end
        end
      end
      if battle.weatherTurns <= 0 then battle.weather, battle.weatherTurns = nil, nil end
    end
  end)
  for code = 0, 158 do
    local id = ("CRYSTAL_EFFECT_%02X"):format(code)
    if not mod.content.move_effects:get(id) then record(code, "full", nil) end
  end
end

return Effects
