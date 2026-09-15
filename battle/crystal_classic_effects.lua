-- Crystal command bodies for the Kanto move families. These are mod-owned
-- records: assigning a Crystal id must never erase a move's non-damage work.
local Gen2 = require("mods.CRYSTAL_251.battle.gen2.Effects")
local Classic = {}
local function name(who) return (who.isPlayer and "" or "Enemy ") .. who.name end
local function failed(ctx) ctx.say("But, it failed!") end
local function known(user, id)
  for _, move in ipairs(user.curMoves or user.mon.moves or {}) do
    if move.id == id then return true end
  end
end
local function drain(ctx)
  local mon = ctx.user.mon
  mon.hp = math.min(mon.stats.hp, mon.hp + math.max(1, math.floor(ctx.totalDealt / 2)))
  ctx.drain()
  ctx.say("Sucked health from\n" .. name(ctx.target) .. "!")
end

function Classic.register(mod, record)
  record(3, "full", nil, {afterDamage=drain})
  record(8, "full", nil, {afterDamage=drain, gate=function(ctx)
    return ctx.target.mon.status == "SLP", "But, it failed!"
  end})
  record(7, "full", nil, {explode=true,
    onMiss=function(ctx) ctx.battle:selfDestruct(ctx.user) end,
    afterDamage=function(ctx) ctx.battle:selfDestruct(ctx.user) end})
  record(48, "full", nil, {afterDamage=function(ctx)
    local mon = ctx.user.mon
    mon.hp = math.max(0, mon.hp - Gen2.recoilDamage(ctx.totalDealt))
    ctx.drain()
    ctx.say(name(ctx.user) .. "'s\nhit with recoil!")
  end})
  record(80, "full", nil, {afterDamage=function(ctx)
    ctx.user.mustRecharge = true
  end})
  record(34, "full", nil, {afterDamage=function(ctx)
    if ctx.user.isPlayer then
      ctx.battle.payDay = (ctx.battle.payDay or 0) + 2 * ctx.user.mon.level
    end
    ctx.say("Coins scattered\neverywhere!")
  end})
  record(45, "full", nil, {onMiss=function(ctx, reason)
    if reason == "immune" then return end
    local damage = ctx.computeDamage({rng=ctx.rng}) or 0
    local crash = math.max(1, math.floor(math.min(damage, ctx.target.mon.hp) / 8))
    ctx.user.mon.hp = math.max(0, ctx.user.mon.hp - crash)
    ctx.drain()
    ctx.say(name(ctx.user) .. " kept going\nand crashed!")
    if ctx.user.mon.hp <= 0 then ctx.battle:onFaint(ctx.user) end
  end})
  record(9, "full", nil, {callsMove=function(ctx)
    local last = ctx.target.lastMove
    if not last or not ctx.data.moves[last] or known(ctx.user, last)
        or last == "STRUGGLE" then failed(ctx); return nil end
    return last
  end})
  record(83, "full", nil, {callsMove=function(ctx)
    local pick = Gen2.metronomePick(ctx.data.constants.moveOrder,
      ctx.user.curMoves or ctx.user.mon.moves, function(n) return ctx.rng(0,n-1) end)
    if not pick then failed(ctx) end
    return pick
  end})
  record(85, "primary", function() return {"But nothing happened!"} end)
  record(30, "primary", function(ctx)
    local choices = {}
    for _, move in ipairs(ctx.user.curMoves or ctx.user.mon.moves or {}) do
      local def = ctx.data.moves[move.id]
      local same = false
      for _, current in ipairs(ctx.user.curTypes or {}) do
        if def and def.type == current then same = true end
      end
      if def and def.id ~= "CURSE" and not same then choices[#choices+1] = def.type end
    end
    if #choices == 0 then return {"But, it failed!"} end
    ctx.user.curTypes = {choices[ctx.rng(1,#choices)]}
    return {name(ctx.user) .. " changed its type!"}
  end)
  record(82, "primary", function(ctx)
    local last = ctx.target.lastMove
    local def = last and ctx.data.moves[last]
    if ctx.user.transformed or ctx.target.substituteHP or not def
        or last == "STRUGGLE" or last == "MIMIC" or last == "SKETCH"
        or known(ctx.user,last) then return {"But, it failed!"} end
    -- Keep party-owned moves unchanged; switching restores the original slots.
    local moves = {}
    for i, move in ipairs(ctx.user.curMoves or ctx.user.mon.moves) do
      moves[i] = {}
      for k,v in pairs(move) do moves[i][k]=v end
      if move == ctx.moveInst or move.id == "MIMIC" then
        moves[i] = {id=last,pp=def.pp or 5}
      end
    end
    ctx.user.curMoves = moves
    return {name(ctx.user) .. " learned\n" .. (def.name or last) .. "!"}
  end)
  record(153, "primary", function(ctx)
    local battle, user, target = ctx.battle, ctx.user, ctx.target
    local blocked = {forceshiny=true,force_shiny=true,trap=true,celebi=true,suicune=true,
      BATTLETYPE_FORCESHINY=true,BATTLETYPE_TRAP=true,BATTLETYPE_CELEBI=true,BATTLETYPE_SUICUNE=true}
    if battle.kind ~= "wild" or user.cantEscape or user.cantEscapeFrom
        or user.crystalTrapTurns or blocked[battle.crystalBattleType or battle.battleType] then
      return {"But, it failed!"}
    end
    local level, foe = user.mon.level, target.mon.level
    if user.isPlayer and level < foe and ctx.rng(0,level+foe) < math.floor(foe/4) then
      return {"But, it failed!"}
    end
    battle.result, battle.afterQueue = "run", "finish"
    return {name(user) .. " fled from battle!"}
  end)
  for _, byte in ipairs({39,75,145,151,155}) do
    local extra = {charge={anim="XSTATITEM_ANIM",enemyAnim="XSTATITEM_DUPLICATE_ANIM"}}
    if byte == 155 then extra.charge = {invulnerable=true,anim="TELEPORT"} end
    if byte == 75 then
      extra.run = function(ctx)
        if ctx.rng(0,255) < (ctx.move.effectChance or 0) then ctx.target.flinched=true end
        return {}
      end
      extra.kind = "secondary"
    end
    record(byte, extra.kind or "full", nil, extra)
  end
  mod.hooks:wrap("battle.charge_required", function(next, ctx)
    if not ctx.battle.crystal251Active then return next(ctx) end
    if ctx.move.id == "SOLARBEAM" and ctx.battle.weather == "sun" then return false end
    if ctx.move.id == "SKULL_BASH" then
      local messages = require("src.battle.MoveEffects").changeStage(
        ctx.battle,ctx.user,"defense",1,false)
      for _, message in ipairs(messages) do ctx.battle:sayNext(message) end
    end
    return next(ctx)
  end,40)
end
return Classic
