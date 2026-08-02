local Legendaries = {}

local BADGES = {
  "BOULDERBADGE", "CASCADEBADGE", "THUNDERBADGE", "RAINBOWBADGE",
  "SOULBADGE", "MARSHBADGE", "VOLCANOBADGE", "EARTHBADGE",
}

local PROFILES = {
  { id="raikou", species="RAIKOU", level=40, roaming=true, secretKey=true },
  { id="entei", species="ENTEI", level=40, roaming=true, secretKey=true },
  { id="suicune", species="SUICUNE", level=40, roaming=true, secretKey=true },
  { id="mew", species="MEW", level=50, map="CERULEAN_CAVE_B1F", badges=8 },
  { id="celebi", species="CELEBI", level=30, map="VIRIDIAN_FOREST",
    flag="EVENT_BEAT_CHAMPION_RIVAL" },
}

local function badgeCount(save)
  local count, inventory = 0, (save and save.inventory) or {}
  for _, id in ipairs(BADGES) do if inventory[id] then count = count + 1 end end
  return count
end

local function randomDVs(rng)
  rng = rng or math.random
  local d = { attack=rng(0,15), defense=rng(0,15),
    speed=rng(0,15), special=rng(0,15) }
  d.hp = (d.attack%2)*8 + (d.defense%2)*4 + (d.speed%2)*2 + d.special%2
  return d
end

local function statsFor(def, level, dvs)
  local out = {}
  for _, key in ipairs({ "hp", "attack", "defense", "speed", "special" }) do
    local value = math.floor(((def.baseStats[key] + (dvs[key] or 0))*2)*level/100)
    out[key] = value + (key == "hp" and level + 10 or 5)
  end
  return out
end

function Legendaries.install(mod)
  local game, pending, active = nil, nil, nil
  local routePool, maps = {}, {}

  local function stateTable()
    local states = mod.save:get("crystalLegendaries")
    if type(states) ~= "table" then states = { version=1 } end
    for _, profile in ipairs(PROFILES) do
      local state = states[profile.id]
      if type(state) ~= "table" then
        state = { status="available", dvs=randomDVs() }
        states[profile.id] = state
      end
    end
    mod.save:set("crystalLegendaries", states)
    return states
  end

  local function unlocked(profile)
    local save = game and game.save
    if not save then return false end
    if profile.badges and badgeCount(save) < profile.badges then return false end
    if profile.secretKey and not (save.inventory and save.inventory.SECRET_KEY) then return false end
    if profile.flag and not (save.flags and save.flags[profile.flag]) then return false end
    return true
  end

  local function choose(pool, exclude, rng)
    if #pool == 0 then return nil end
    rng = rng or math.random
    local candidates = {}
    for _, id in ipairs(pool) do if id ~= exclude then candidates[#candidates+1]=id end end
    if #candidates == 0 then candidates = pool end
    return candidates[rng(1,#candidates)]
  end

  local function neighbours(mapId)
    local allowed, out = {}, {}
    for _, id in ipairs(routePool) do allowed[id]=true end
    for _, connection in pairs((maps[mapId] and maps[mapId].connections) or {}) do
      if connection and allowed[connection.map] then out[#out+1]=connection.map end
    end
    return out
  end

  local function relocate(state, playerMap, rng)
    local connected = neighbours(state.mapId)
    local pool = #connected > 0 and connected or routePool
    state.mapId = choose(pool, playerMap, rng)
  end

  local function ensureRoamers(states, rng)
    for _, profile in ipairs(PROFILES) do
      if profile.roaming then
        local state = states[profile.id]
        state.dvs = state.dvs or randomDVs(rng)
        if state.status == "available" and not state.mapId then
          state.mapId = choose(routePool, nil, rng)
        end
      end
    end
  end

  local function buildWorld()
    routePool, maps = {}, {}
    for id, def in mod.content.maps:each() do maps[id]=def end
    for id, encounter in mod.content.encounters:each() do
      if id:match("^ROUTE_%d+$") and encounter.grass and #(encounter.grass.slots or {})>0 then
        routePool[#routePool+1]=id
      end
    end
    table.sort(routePool)
  end

  local function applyBattle(battle, profile, state)
    local mon, def = battle.enemy.mon, battle.enemy.def
    mon.level, mon.dvs = profile.level, state.dvs
    mon.statExp = { hp=0, attack=0, defense=0, speed=0, special=0 }
    mon.stats = statsFor(def, profile.level, state.dvs)
    mon.hp = math.max(1, math.min(state.hp or mon.stats.hp, mon.stats.hp))
    mon.status = state.statusCondition
    battle.enemy.curStats, battle.enemy.shownHP = mon.stats, mon.hp
    battle.enemy.shownStatus = mon.status
    mon.crystal251Legendary = profile.id
    active = { battle=battle, profile=profile, state=state, fainted=false }
  end

  mod.events:on("game.ready", function(ev)
    game = ev and ev.game or game
    buildWorld()
    local states=stateTable(); ensureRoamers(states); mod.save:set("crystalLegendaries",states)
  end)

  mod.events:on("map.entered", function(ev)
    local states=stateTable(); ensureRoamers(states)
    for _, profile in ipairs(PROFILES) do
      local state=states[profile.id]
      if profile.roaming and state.status=="available" and unlocked(profile) then
        relocate(state, ev and ev.mapId)
      end
    end
    mod.save:set("crystalLegendaries",states)
  end)

  mod.hooks:wrap("encounter.roll", function(next, encDef, ctx)
    pending=nil
    local ordinary=next(encDef,ctx)
    if not ordinary or not game then return ordinary end
    local states=stateTable(); ensureRoamers(states,ctx.rng)
    local candidates={}
    for _, profile in ipairs(PROFILES) do
      local state=states[profile.id]
      local location = profile.roaming and state.mapId or profile.map
      local delegated = profile.id=="mew" and mod.find("roaming_events")~=nil
      if not delegated and state.status=="available" and unlocked(profile) and location==ctx.mapId
          and (not profile.roaming or ctx.terrain=="grass") then
        candidates[#candidates+1]={profile=profile,state=state}
      end
    end
    local force = mod.options:get("force_legendary") == true
    if #candidates==0 or (not force and ctx.rng(1,32)~=1) then return ordinary end
    local selected=candidates[ctx.rng(1,#candidates)]
    pending={ profile=selected.profile, state=selected.state, mapId=ctx.mapId }
    return { species=selected.profile.species, level=selected.profile.level }
  end, 70)

  mod.events:on("battle.started", function(ev)
    if pending and ev.kind=="wild" and ev.species==pending.profile.species then
      applyBattle(ev.battle,pending.profile,pending.state)
    end
    pending=nil
  end)

  mod.hooks:wrap("battle.enemy_action", function(next,battle)
    if active and active.battle==battle and active.profile.roaming
        and battle.enemy and battle.enemy.mon.hp>0 then
      return { id="TELEPORT", pp=20 }
    end
    return next(battle)
  end, 70)

  mod.events:on("battle.fainted", function(ev)
    if active and active.battle==ev.battle and ev.battler==ev.battle.enemy then
      active.fainted=true
    end
  end)

  mod.events:on("pokemon.caught", function(ev)
    if active and active.battle==ev.battle then
      active.state.status="caught"
      active.state.hp, active.state.statusCondition = nil, nil
      ev.mon.crystal251Legendary=active.profile.id
      mod.save:set("crystalLegendaries",stateTable())
    end
  end)

  mod.events:on("battle.ended", function(ev)
    if not active or active.battle~=ev.battle then return end
    local state, profile = active.state, active.profile
    if state.status~="caught" then
      local mon=ev.battle.enemy and ev.battle.enemy.mon
      state.hp, state.statusCondition = mon and mon.hp, mon and mon.status
      if active.fainted and mod.options:get("legendary_ko_removes") then
        state.status="defeated"
      elseif profile.roaming then
        if active.fainted then state.hp,state.statusCondition=nil,nil end
        relocate(state,nil)
      else
        state.hp,state.statusCondition=nil,nil
      end
    end
    mod.save:set("crystalLegendaries",stateTable())
    active=nil
  end)

  return { profiles=PROFILES }
end

return Legendaries
