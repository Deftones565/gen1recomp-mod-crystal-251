-- Pokemon Crystal's two-slot Day Care and breeding system, adapted to the
-- Kanto Day Care building without collapsing Crystal's separate attendants.
-- The existing gentleman owns slot 1, an appended lady owns slot 2, and an
-- appended Route 5 gentleman handles waiting Eggs outside. The persistent
-- state intentionally lives in save.daycare so old Gen I saves migrate in place.

local Daycare = {}
local DaycareIcons = require("mods.CRYSTAL_251.daycare_icons")

local MAX_PARTY = 6
local MAX_LEVEL = 100
local EGG_LEVEL = 5
local HATCH_HAPPINESS = 120

local INSIDE_MAN_NAME = "DAYCARE_GENTLEMAN"
local LADY_NAME = "CRYSTAL251_DAYCARE_LADY"
local OUTSIDE_MAN_NAME = "CRYSTAL251_DAYCARE_MAN_OUTSIDE"
local LADY_TEXT = "TEXT_CRYSTAL251_DAYCARE_LADY"
local OUTSIDE_MAN_TEXT = "TEXT_CRYSTAL251_DAYCARE_MAN_OUTSIDE"
local MON1_NAME = "CRYSTAL251_DAYCARE_MON_1"
local MON2_NAME = "CRYSTAL251_DAYCARE_MON_2"
local MON1_TEXT = "TEXT_CRYSTAL251_DAYCARE_MON_1"
local MON2_TEXT = "TEXT_CRYSTAL251_DAYCARE_MON_2"

local eggAssets
local daycareIconAssets
local gameRef

local function copy(value)
  if type(value) ~= "table" then return value end
  local out = {}
  for key, child in pairs(value) do out[key] = copy(child) end
  return out
end

function Daycare.configureAssets(assets, iconAssets)
  assert(type(assets) == "table" and type(assets.front) == "string"
      and type(assets.icon) == "string",
    "Crystal import is missing ROM-derived Egg graphics")
  assert(type(iconAssets) == "table"
      and #iconAssets == DaycareIcons.MAX_INDEX,
    "Crystal import is missing animated Day Care icon graphics")
  for index = 1, DaycareIcons.MAX_INDEX do
    assert(type(iconAssets[index]) == "string" and iconAssets[index] ~= "",
      "Crystal import is missing Day Care icon " .. index)
  end
  eggAssets = { front=assets.front, icon=assets.icon }
  daycareIconAssets = copy(iconAssets)
end

local function clampDV(value)
  value = math.floor(tonumber(value) or 0)
  return math.max(0, math.min(15, value))
end

local function randomDVs(rng)
  rng = rng or function(a, b) return love.math.random(a, b) end
  -- Crystal generates the packed Attack/Defense and Speed/Special bytes with
  -- two RNG calls, then reads the nibbles as the four DVs.
  local attackDefense = rng(0, 255)
  local speedSpecial = rng(0, 255)
  local dvs = {
    attack = math.floor(attackDefense / 16), defense = attackDefense % 16,
    speed = math.floor(speedSpecial / 16), special = speedSpecial % 16,
  }
  dvs.hp = (dvs.attack % 2) * 8 + (dvs.defense % 2) * 4
    + (dvs.speed % 2) * 2 + (dvs.special % 2)
  return dvs
end

local function initialEggCounter(rng)
  rng = rng or function(a, b) return love.math.random(a, b) end
  -- DayCare_InitBreeding repeatedly draws a raw byte until it is at least
  -- 150. This is uniform over 150..255, but the rejected draws still consume
  -- RNG and therefore matter to the generated species and DVs that follow.
  local value
  repeat value = rng(0, 255) until value >= 150
  return value
end

local function recomputeHPDV(dvs)
  dvs.hp = (clampDV(dvs.attack) % 2) * 8
    + (clampDV(dvs.defense) % 2) * 4
    + (clampDV(dvs.speed) % 2) * 2
    + (clampDV(dvs.special) % 2)
end

local function nameOf(data, mon)
  local def = mon and data and data.pokemon and data.pokemon[mon.species]
  return mon and (mon.nickname or (def and def.name) or mon.species) or "POKéMON"
end

local function slotCount(dc)
  local count = 0
  for i = 1, 2 do if dc.slots[i] and dc.slots[i].mon then count = count + 1 end end
  return count
end
Daycare.slotCount = slotCount

local function firstOpenSlot(dc)
  for i = 1, 2 do if not (dc.slots[i] and dc.slots[i].mon) then return i end end
end

local function ownerId(mon)
  -- Every native party mon belongs to the current player unless a trade/link
  -- explicitly stamped an OT id.  Treating two absent ids as equal preserves
  -- Crystal's same-OT compatibility tier for old Gen I saves.
  return mon and mon.otId or 0
end

local function groupsOf(data, mon)
  local def = mon and data and data.pokemon and data.pokemon[mon.species]
  local groups = def and def.crystalEggGroups
  if type(groups) ~= "table" then return nil end
  return { tonumber(groups[1]), tonumber(groups[2]) }
end

local function sharesGroup(a, b)
  for _, ga in ipairs(a or {}) do
    for _, gb in ipairs(b or {}) do
      if ga == gb then return true end
    end
  end
  return false
end

-- CheckBreedmonCompatibility.  The byte is kept exact because both the
-- outside-man dialogue and the egg-production probabilities use it.
function Daycare.compatibility(data, mon1, mon2)
  if not (mon1 and mon2) then return 0, "missing" end
  local groups1, groups2 = groupsOf(data, mon1), groupsOf(data, mon2)
  if not (groups1 and groups2) then return 0, "missing_data" end
  if (groups1[1] == 15 and groups1[2] == 15)
      or (groups2[1] == 15 and groups2[2] == 15) then
    return 0, "no_eggs_group"
  end

  local ditto1, ditto2 = mon1.species == "DITTO", mon2.species == "DITTO"
  if ditto1 and ditto2 then return 0, "two_ditto" end
  if not ditto1 and not ditto2 and not sharesGroup(groups1, groups2) then
    return 0, "different_groups"
  end

  local Gender = require("mods.CRYSTAL_251.battle.crystal_gender")
  local gender1, gender2 = Gender.forMon(mon1), Gender.forMon(mon2)
  if not ditto1 and not ditto2 then
    if gender1 == nil or gender2 == nil then return 0, "genderless" end
    if gender1 == gender2 then return 0, "same_gender" end
  end

  local dvs1, dvs2 = mon1.dvs or {}, mon2.dvs or {}
  if clampDV(dvs1.defense) == clampDV(dvs2.defense)
      and clampDV(dvs1.special) % 8 == clampDV(dvs2.special) % 8 then
    return 255, "related_dvs"
  end

  local sameSpecies = mon1.species == mon2.species
  local differentOT = ownerId(mon1) ~= ownerId(mon2)
  if sameSpecies then return differentOT and 254 or 177, "compatible" end
  return differentOT and 128 or 51, "compatible"
end

function Daycare.compatibilityText(value)
  if value == 254 then return "The two seem to\nget along very\nwell!" end
  if value == 177 then return "The two seem to\nget along." end
  if value == 128 then return "The two seem to\ncare for each\nother." end
  if value == 51 then return "The two don't\nseem to like each\nother much." end
  return "The two prefer to\nplay with other\nPOKéMON than each\nother."
end

function Daycare.compatibilityDialogue(data, dc)
  local slot1, slot2 = dc and dc.slots and dc.slots[1], dc and dc.slots and dc.slots[2]
  local mon1, mon2 = slot1 and slot1.mon, slot2 and slot2.mon
  if not (mon1 and mon2) then
    local lone = mon1 or mon2
    return lone and ((nameOf(data, lone) .. " is waiting\nfor a partner."))
      or "No POKéMON are\nbeing raised."
  end

  local value = Daycare.compatibility(data, mon1, mon2)
  dc.compatibility = value
  local names = ("%s and\n%s"):format(nameOf(data, mon1), nameOf(data, mon2))
  local verdict
  if value == 254 then
    verdict = "They like each\nother a lot!"
  elseif value == 177 then
    verdict = "They get along\nwell."
  elseif value == 128 then
    verdict = "They seem to like\neach other."
  elseif value == 51 then
    verdict = "They don't like\neach other much."
  else
    verdict = "They won't breed."
  end
  return names .. "\f" .. verdict
end

function Daycare.eggChance(value)
  if value >= 230 and value < 255 then return 80 end
  if value >= 170 and value < 255 then return 40 end
  if value >= 110 and value < 255 then return 30 end
  if value > 0 and value < 255 then return 10 end
  return 0
end

local function movesSet(mon)
  local out = {}
  for _, move in ipairs((mon and mon.moves) or {}) do out[move.id] = true end
  return out
end

local function listSet(rows, key)
  local out = {}
  for _, row in ipairs(rows or {}) do out[type(row) == "table" and row[key] or row] = true end
  return out
end

local function pushMove(data, list, id)
  if not id then return end
  for _, move in ipairs(list) do if move.id == id then return end end
  local def = data.moves and data.moves[id]
  local pp = def and def.pp or 0
  local entry = { id=id, pp=pp, maxPp=pp }
  if #list < 4 then
    list[#list + 1] = entry
  else
    table.remove(list, 1)
    list[#list + 1] = entry
  end
end

local function reverseEvolutions(data)
  local reverse = {}
  local speciesList = {}
  for species, def in pairs(data.pokemon or {}) do
    speciesList[#speciesList + 1] = { id=species, dex=def.dex or 9999 }
  end
  table.sort(speciesList, function(a, b)
    if a.dex ~= b.dex then return a.dex < b.dex end
    return a.id < b.id
  end)
  for _, entry in ipairs(speciesList) do
    local species, def = entry.id, data.pokemon[entry.id]
    for _, evo in ipairs(def.evolutions or {}) do
      local evolved = evo.into or evo.species
      if evolved and reverse[evolved] == nil then reverse[evolved] = species end
    end
  end
  return reverse
end

function Daycare.baseEggSpecies(data, mon1, mon2, rng)
  local Gender = require("mods.CRYSTAL_251.battle.crystal_gender")
  local source
  if mon1.species == "DITTO" then source = mon2
  elseif mon2.species == "DITTO" then source = mon1
  elseif Gender.forMon(mon1) == "F" then source = mon1
  else source = mon2 end

  local species = source.species
  local reverse = reverseEvolutions(data)
  species = reverse[species] or species
  species = reverse[species] or species
  if species == "NIDORAN_F"
      and (rng or love.math.random)(0, 255) >= 128 then
    species = "NIDORAN_M"
  end
  return species, source
end

local function inheritedParent(mon1, mon2, egg)
  if mon1.species == "DITTO" then return mon1 end
  if mon2.species == "DITTO" then return mon2 end
  local Gender = require("mods.CRYSTAL_251.battle.crystal_gender")
  -- Eggs do not display a gender, but Crystal still derives the hidden
  -- hatchling gender from its species and DVs when choosing the DV donor.
  local childGender = Gender.forSpeciesDVs(egg.species, egg.dvs)
  local g1, g2 = Gender.forMon(mon1), Gender.forMon(mon2)
  if childGender == "M" then
    return g1 == "F" and mon1 or mon2
  elseif childGender == "F" then
    return g1 == "M" and mon1 or mon2
  end
end

local function moveDonor(mon1, mon2)
  local Gender = require("mods.CRYSTAL_251.battle.crystal_gender")
  -- GetHeritableMoves treats the male as the move donor. With Ditto, Ditto
  -- fills that role only when the non-Ditto parent is female; a male or
  -- genderless non-Ditto supplies its own moves instead.
  if mon1.species == "DITTO" then
    return Gender.forMon(mon2) == "F" and mon1 or mon2,
           Gender.forMon(mon2) == "F" and mon2 or mon1
  end
  if mon2.species == "DITTO" then
    return Gender.forMon(mon1) == "F" and mon2 or mon1,
           Gender.forMon(mon1) == "F" and mon1 or mon2
  end
  if Gender.forMon(mon1) == "F" then return mon2, mon1 end
  return mon1, mon2
end

function Daycare.makeEgg(data, mon1, mon2, rng, player)
  rng = rng or function(a, b) return love.math.random(a, b) end
  local species = Daycare.baseEggSpecies(data, mon1, mon2, rng)
  local def = assert(data.pokemon[species], "missing egg species " .. tostring(species))
  local dvs = randomDVs(rng)
  local egg = {
    species=species, level=EGG_LEVEL, exp=0, dvs=dvs,
    statExp={ hp=0, attack=0, defense=0, speed=0, special=0 },
    status=nil, moves={}, nickname="EGG", isEgg=true,
    eggCycles=assert(tonumber(def.eggSteps or def.crystalHatchCycles),
      "missing Crystal hatch cycles for " .. species),
    -- Crystal stores the remaining hatch cycles in the happiness byte while
    -- the party member is still an Egg, then sets real happiness on hatch.
    happiness=assert(tonumber(def.eggSteps or def.crystalHatchCycles)),
    otId=player and player.id or nil,
    ot=player and player.name or nil,
  }

  -- Inherit Defense DV and the low three Special-DV bits from Ditto, or from
  -- the parent opposite the egg's generated gender.
  local inherited = inheritedParent(mon1, mon2, egg)
  if inherited and inherited.dvs then
    egg.dvs.defense = clampDV(inherited.dvs.defense)
    egg.dvs.special = math.floor(egg.dvs.special / 8) * 8
      + clampDV(inherited.dvs.special) % 8
    recomputeHPDV(egg.dvs)
  end

  -- Keep inherited moves hidden until hatching.  An Egg is a party member,
  -- but Crystal does not let it expose or use its future moves (especially
  -- field HMs) before it hatches.
  local inheritedMoves = {}
  local Pokemon = require("src.pokemon.Pokemon")
  for _, id in ipairs(Pokemon.movesAtLevel(def, EGG_LEVEL)) do
    pushMove(data, inheritedMoves, id)
  end

  local donor, other = moveDonor(mon1, mon2)
  local otherMoves = movesSet(other)
  local levelMoves = listSet(def.levelMoves or def.learnset, "move")
  local eggMoves = listSet(def.eggMoves or def.crystalEggMoves)
  local tmhm = listSet(def.tmhm)
  for _, move in ipairs((donor and donor.moves) or {}) do
    local id = move.id
    if eggMoves[id] or tmhm[id] or (levelMoves[id] and otherMoves[id]) then
      pushMove(data, inheritedMoves, id)
    end
  end
  egg.eggMoves = inheritedMoves

  local Growth = require("src.pokemon.Growth")
  local Stats = require("src.pokemon.Stats")
  egg.exp = Growth.expForLevel(def.growthRate, EGG_LEVEL, data.growth_rates)
  egg.stats = Stats.calc(def, EGG_LEVEL, egg.dvs, egg.statExp)
  egg.hp = 0
  return egg
end

local function freshState()
  return {
    crystal251=true, slots={}, stepCounter=0,
    compatibility=0, stepsToEgg=nil, eggReady=false, egg=nil,
  }
end

function Daycare.normalize(save, data)
  if not save then return nil end
  local old = save.daycare
  if old and old.crystal251 and type(old.slots) == "table" then return old end
  local dc = freshState()
  if old and old.mon then
    local mon = old.mon
    mon.exp = (mon.exp or 0) + math.max(0, math.floor(old.steps or 0))
    dc.slots[1] = { mon=mon, depositLevel=old.depositLevel or mon.level or 1 }
  end
  save.daycare = dc
  return dc
end

local function setObjectToggle(save, mapId, name, visible)
  save.objectToggles = save.objectToggles or {}
  save.objectToggles[mapId] = save.objectToggles[mapId] or {}
  save.objectToggles[mapId][name] = visible
end

-- Crystal moves the Day Care Man outside while an Egg is waiting. These
-- persisted toggles also make a save/load on either map reconstruct the same
-- object arrangement before the player can interact.
function Daycare.syncNPCFlags(save, data)
  local dc = Daycare.normalize(save, data)
  local waiting = dc and dc.eggReady == true
  setObjectToggle(save, "DAYCARE", INSIDE_MAN_NAME, not waiting)
  setObjectToggle(save, "DAYCARE", LADY_NAME, true)
  setObjectToggle(save, "DAYCARE", MON1_NAME,
    dc and dc.slots[1] and dc.slots[1].mon ~= nil or false)
  setObjectToggle(save, "DAYCARE", MON2_NAME,
    dc and dc.slots[2] and dc.slots[2].mon ~= nil or false)
  setObjectToggle(save, "ROUTE_5", OUTSIDE_MAN_NAME, waiting)
  return waiting
end

local function npcByName(overworld, name)
  for _, npc in ipairs((overworld and overworld.npcs) or {}) do
    if npc.def and npc.def.name == name then return npc end
  end
end

local function skinBoarder(game, overworld, objectName, mon)
  local npc = npcByName(overworld, objectName)
  if not (npc and mon) then return end
  local def = game.data.pokemon and game.data.pokemon[mon.species]
  local spriteId = DaycareIcons.spriteId(def and def.crystalMenuIcon)
  if npc.def.sprite == spriteId and npc.crystal251BoarderSpecies == mon.species then
    return
  end
  local spriteDef = assert(game.data.sprites and game.data.sprites[spriteId],
    "missing Day Care sprite " .. spriteId)
  npc.def.sprite = spriteId
  npc.sprite = require("src.render.SpriteRenderer").new(spriteDef, npc.id)
  npc.crystal251BoarderSpecies = mon.species
end

function Daycare.syncNPCs(game, overworld)
  if not (game and game.save) then return false end
  local waiting = Daycare.syncNPCFlags(game.save, game.data)
  if not (overworld and overworld.map) then return waiting end
  local Commands = require("src.script.Commands")
  local ctx = { game=game, save=game.save, overworld=overworld }
  if waiting then
    Commands.hide_object(ctx, "DAYCARE", INSIDE_MAN_NAME)
    Commands.show_object(ctx, "ROUTE_5", OUTSIDE_MAN_NAME)
  else
    Commands.show_object(ctx, "DAYCARE", INSIDE_MAN_NAME)
    Commands.hide_object(ctx, "ROUTE_5", OUTSIDE_MAN_NAME)
  end
  Commands.show_object(ctx, "DAYCARE", LADY_NAME)

  local dc = Daycare.normalize(game.save, game.data)
  for slotIndex, objectName in ipairs({ MON1_NAME, MON2_NAME }) do
    local slot = dc.slots[slotIndex]
    if slot and slot.mon then
      Commands.show_object(ctx, "DAYCARE", objectName)
      if overworld.map.id == "DAYCARE" then
        skinBoarder(game, overworld, objectName, slot.mon)
      end
    else
      Commands.hide_object(ctx, "DAYCARE", objectName)
    end
  end
  return waiting
end

local function compatiblePair(dc)
  return dc.slots[1] and dc.slots[1].mon, dc.slots[2] and dc.slots[2].mon
end

function Daycare.refresh(data, dc, rng, player)
  local mon1, mon2 = compatiblePair(dc)
  if not (mon1 and mon2) then
    dc.compatibility, dc.stepsToEgg = 0, nil
    if not dc.eggReady then dc.egg = nil end
    return 0
  end
  local value = Daycare.compatibility(data, mon1, mon2)
  dc.compatibility = value
  if not dc.eggReady then
    if value ~= 0 and value ~= 255 then
      dc.stepsToEgg = initialEggCounter(rng)
      dc.egg = Daycare.makeEgg(data, mon1, mon2, rng, player)
    else
      dc.egg, dc.stepsToEgg = nil, nil
    end
  end
  return value
end

function Daycare.depositInto(save, data, slotIndex, mon, rng)
  local dc = Daycare.normalize(save, data)
  slotIndex = math.floor(tonumber(slotIndex) or 0)
  if slotIndex < 1 or slotIndex > 2 then return nil, "bad_slot" end
  if dc.slots[slotIndex] and dc.slots[slotIndex].mon then return nil, "full" end
  if not mon then return nil, "missing" end
  if mon.isEgg then return nil, "egg" end
  if mon.heldItem and data.items and data.items[mon.heldItem]
      and data.items[mon.heldItem].isMail then return nil, "mail" end
  if #(save.party or {}) < 2 then return nil, "last_mon" end
  local otherHealthy = false
  local partyIndex
  for i, partyMon in ipairs(save.party or {}) do
    if partyMon == mon then
      partyIndex = i
    elseif not partyMon.isEgg and (partyMon.hp or 0) > 0 then
      otherHealthy = true
    end
  end
  -- CheckCurPartyMonFainted requires at least one other usable party member,
  -- even when the selected deposit itself is fainted.
  if not otherHealthy then return nil, "last_healthy" end
  if not partyIndex then return nil, "not_party" end
  table.remove(save.party, partyIndex)
  dc.slots[slotIndex] = { mon=mon, depositLevel=mon.level or 1 }
  Daycare.refresh(data, dc, rng, save.player)
  return slotIndex
end

-- Compatibility wrapper retained for tests and callers that do not address a
-- specific Crystal attendant. The first empty slot remains the default.
function Daycare.deposit(save, data, mon, rng)
  local dc = Daycare.normalize(save, data)
  local slot = firstOpenSlot(dc)
  if not slot then return nil, "full" end
  return Daycare.depositInto(save, data, slot, mon, rng)
end

function Daycare.levelAndFee(data, slot)
  local mon = assert(slot and slot.mon)
  local def = assert(data.pokemon[mon.species])
  local Growth = require("src.pokemon.Growth")
  local level = Growth.levelForExp(def.growthRate, mon.exp or 0, MAX_LEVEL,
    data.growth_rates)
  local grown = math.max(0, level - (slot.depositLevel or mon.level or level))
  return level, grown, 100 + grown * 100
end

function Daycare.withdraw(save, data, slotIndex, rng)
  local dc = Daycare.normalize(save, data)
  local slot = dc.slots[slotIndex]
  if not (slot and slot.mon) then return nil, "empty" end
  if #(save.party or {}) >= MAX_PARTY then return nil, "party_full" end
  local mon = slot.mon
  local level, _, fee = Daycare.levelAndFee(data, slot)
  if (save.money or 0) < fee then return nil, "money", fee end
  save.money = (save.money or 0) - fee
  local def = assert(data.pokemon[mon.species])
  local oldLevel = slot.depositLevel or mon.level or level
  mon.level = level
  local Pokemon = require("src.pokemon.Pokemon")
  Pokemon.learnMovesFromDayCare(data, mon, def, oldLevel, level)
  local Stats = require("src.pokemon.Stats")
  mon.stats = Stats.calc(def, level, mon.dvs, mon.statExp)
  mon.hp, mon.status = mon.stats.hp, nil
  save.party[#save.party + 1] = mon
  dc.slots[slotIndex] = nil
  Daycare.refresh(data, dc, rng, save.player)
  return mon, nil, fee
end

function Daycare.takeEgg(save, data, rng)
  local dc = Daycare.normalize(save, data)
  if not (dc.eggReady and dc.egg) then return nil, "no_egg" end
  if #(save.party or {}) >= MAX_PARTY then return nil, "party_full" end
  local egg = dc.egg
  save.party[#save.party + 1] = egg
  dc.eggReady, dc.egg, dc.stepsToEgg = false, nil, nil
  Daycare.refresh(data, dc, rng, save.player)
  return egg
end

local function addDaycareExp(data, slot)
  local mon = slot and slot.mon
  local def = mon and data.pokemon and data.pokemon[mon.species]
  if not def then return end
  local Growth = require("src.pokemon.Growth")
  local cap = Growth.expForLevel(def.growthRate, MAX_LEVEL, data.growth_rates)
  mon.exp = math.min(cap, (mon.exp or 0) + 1)
end

function Daycare.stepState(save, data, rng)
  local dc = Daycare.normalize(save, data)

  -- CountStep checks party Eggs at the $80 phase before DayCareStep. When an
  -- Egg reaches zero, Crystal returns a hatch event immediately: boarder EXP,
  -- egg production, field poison and wild encounters do not run on that step.
  dc.stepCounter = ((dc.stepCounter or 0) + 1) % 256
  if dc.stepCounter == 0x80 then
    for _, mon in ipairs(save.party or {}) do
      if mon.isEgg then
        mon.eggCycles = math.max(0, math.floor(mon.eggCycles or 0) - 1)
        mon.happiness = mon.eggCycles
        if mon.eggCycles == 0 then return mon end
      end
    end
  end

  for i = 1, 2 do addDaycareExp(data, dc.slots[i]) end

  if not dc.eggReady and dc.stepsToEgg ~= nil
      and dc.compatibility ~= 0 and dc.compatibility ~= 255 then
    dc.stepsToEgg = (math.floor(dc.stepsToEgg) - 1) % 256
    if dc.stepsToEgg == 0 then
      local chance = Daycare.eggChance(dc.compatibility)
      -- DayCareStep first resets wStepsToEgg with one random byte, then uses
      -- a second random byte for the compatibility roll.
      local nextCounter = (rng or love.math.random)(0, 255)
      if (rng or love.math.random)(0, 255) < chance then
        dc.eggReady = true
        dc.stepsToEgg = nil
      else
        dc.stepsToEgg = nextCounter
      end
    end
  end
end

function Daycare.hatch(game, egg)
  if not (game and egg and egg.isEgg) then return false end
  local def = assert(game.data.pokemon[egg.species])
  local Stats = require("src.pokemon.Stats")
  egg.isEgg, egg.eggCycles = nil, nil
  egg.moves, egg.eggMoves = egg.eggMoves or {}, nil
  egg.nickname = nil
  egg.happiness = HATCH_HAPPINESS
  egg.otId = game.save.player and game.save.player.id or egg.otId
  egg.ot = game.save.player and game.save.player.name or egg.ot
  egg.status = nil
  egg.stats = Stats.calc(def, egg.level, egg.dvs, egg.statExp)
  egg.hp = egg.stats.hp
  game.save.pokedex = game.save.pokedex or { seen={}, owned={} }
  game.save.pokedex.seen = game.save.pokedex.seen or {}
  game.save.pokedex.owned = game.save.pokedex.owned or {}
  -- A hatch counts as obtaining the species. Remember whether it was already
  -- owned before setting the bit so a first hatch can open its Pokédex page.
  local newlyOwned = game.save.pokedex.owned[egg.species] ~= true
  game.save.pokedex.seen[egg.species] = true
  game.save.pokedex.owned[egg.species] = true

  local TextBox = require("src.render.TextBox")
  local name = def.name or egg.species
  local function askNickname()
    game.stack:push(TextBox.new(game,
      ("Give a nickname to\n%s?"):format(name), nil, {
        choice=function(yes)
          if not yes then return end
          local NamingScreen = require("src.ui.NamingScreen")
          game.stack:push(NamingScreen.new(game, {
            title=(name .. "'s NAME?"), default=name, maxLen=10,
            onDone=function(nickname) egg.nickname=nickname end,
          }))
        end,
      }))
  end

  local function showDexThenAskNickname()
    if not newlyOwned then
      askNickname()
      return
    end

    -- DexEntryMenu has no completion callback: wrap only this instance's
    -- update method and continue the hatch flow after the player dismisses it.
    -- The underlying screen still owns all rendering, input and cry behavior.
    local DexEntryMenu = require("src.ui.DexEntryMenu")
    local entry = DexEntryMenu.new(game, egg.species)
    local update = assert(entry.update, "DexEntryMenu has no update method")
    local continued = false
    entry.update = function(self, dt)
      local wasTop = game.stack:top() == self
      update(self, dt)
      if wasTop and not continued and game.stack:top() ~= self then
        continued = true
        askNickname()
      end
    end
    game.stack:push(entry)
  end

  game.stack:push(TextBox.new(game, "Huh?", function()
    require("src.core.Sound").playCry(game.data, egg.species)
    game.stack:push(TextBox.new(game,
      ("EGG hatched into\n%s!"):format(name), showDexThenAskNickname))
  end))
  return true
end

function Daycare.step(game, overworld, rng)
  if not (game and game.save and game.data) then return false end
  local dc = Daycare.normalize(game.save, game.data)
  local wasWaiting = dc.eggReady == true
  local ready = Daycare.stepState(game.save, game.data, rng)
  dc = Daycare.normalize(game.save, game.data)
  if wasWaiting ~= (dc.eggReady == true) then
    Daycare.syncNPCs(game, overworld)
  end
  if not ready then return false end
  Daycare.hatch(game, ready)
  return true
end

local ERROR_TEXT = {
  full="I'm already raising\na POKéMON.", egg="Sorry, I can't\naccept an EGG.",
  mail="Please remove the\nMAIL first.", last_mon="You only have one\nPOKéMON with you.",
  last_healthy="That is your last\nhealthy POKéMON.", party_full="You have no room\nfor another POKéMON.",
  money="You don't have\nenough money.",
  not_party="That one isn't in\nyour party.", bad_slot="That won't work.",
}

local function appendDaycareObjects(mod)
  local inside = assert(mod.content.maps:get("DAYCARE"), "missing DAYCARE map")
  local route = assert(mod.content.maps:get("ROUTE_5"), "missing ROUTE_5 map")
  local firstInsideIndex = #(inside.objects or {}) + 1
  local ladyIndex = firstInsideIndex
  local mon1Index, mon2Index = firstInsideIndex + 1, firstInsideIndex + 2
  local outsideIndex = #(route.objects or {}) + 1

  -- Lists replace by default in the mod API. __append is mandatory here: all
  -- three interior additions join the existing object table without deleting
  -- the native gentleman or any object appended by an earlier mod.
  mod.content.maps:patch("DAYCARE", { objects={ __append={
    {
      index=ladyIndex, x=5, y=3, sprite="SPRITE_GRANNY",
      movement="STAY", range="LEFT", text=LADY_TEXT, name=LADY_NAME,
    },
    {
      index=mon1Index, x=3, y=5, sprite=DaycareIcons.spriteId(8),
      movement="WALK", range="ANY_DIR", text=MON1_TEXT, name=MON1_NAME,
      hidden=true,
    },
    {
      index=mon2Index, x=4, y=5, sprite=DaycareIcons.spriteId(8),
      movement="WALK", range="ANY_DIR", text=MON2_TEXT, name=MON2_NAME,
      hidden=true,
    },
  } } })
  mod.content.maps:patch("ROUTE_5", { objects={ __append={ {
    index=outsideIndex, x=12, y=22, sprite="SPRITE_GENTLEMAN",
    movement="STAY", range="LEFT", text=OUTSIDE_MAN_TEXT,
    name=OUTSIDE_MAN_NAME, hidden=true,
  } } } })
  return ladyIndex, outsideIndex, mon1Index, mon2Index
end

local function installDaycareNPCs(mod)
  for iconIndex = 1, DaycareIcons.MAX_INDEX do
    mod.content.sprites:register(DaycareIcons.spriteId(iconIndex), {
      image=assert(daycareIconAssets and daycareIconAssets[iconIndex]),
      frames=6, walker=true,
    })
  end
  appendDaycareObjects(mod)

  local function keeperTalk(slotIndex, role)
    return function(game, overworld, npc, done)
      local TextBox = require("src.render.TextBox")
      local PartyMenu = require("src.ui.PartyMenu")
      local function text(value, cb, opts)
        game.stack:push(TextBox.new(game, value, cb, opts))
      end
      local function finish(value)
        if value then text(value, done) else done() end
      end
      local function random(a, b) return love.math.random(a, b) end
      local dc = Daycare.normalize(game.save, game.data)
      if npc and npc.facePlayer and overworld then npc:facePlayer(overworld.player) end

      -- Crystal blocks the lady's normal service while her husband is outside
      -- with an Egg, directing the player to him instead.
      if role == "lady" and dc.eggReady then
        finish("Gramps was looking\nfor you.")
        return
      end

      local slot = dc.slots[slotIndex]
      if not (slot and slot.mon) then
        local intro = role == "man"
          and "I'm the DAY-CARE\nMAN.\fWant me to raise\na POKéMON?"
          or "I'm the DAY-CARE\nLADY.\fWant me to raise\na POKéMON?"
        text(intro, nil, { choice=function(yes)
          if not yes then finish("Oh, fine then.\nCome again.") return end
          text("What should I\nraise?", function()
            game.stack:push(PartyMenu.new(game, {
              pickOnly=true,
              onCancel=function() finish("Oh, fine then.\nCome again.") end,
              onSwitch=function(mon)
                local deposited, why = Daycare.depositInto(
                  game.save, game.data, slotIndex, mon, random)
                if not deposited then
                  finish(ERROR_TEXT[why] or "That won't work.")
                  return
                end
                Daycare.syncNPCs(game, overworld)
                local name = nameOf(game.data, mon)
                require("src.core.Sound").playCry(game.data, mon.species)
                finish(("I'll raise your\n%s.\fCome back later."):format(name))
              end,
            }))
          end)
        end })
        return
      end

      local level, grown, fee = Daycare.levelAndFee(game.data, slot)
      local name = nameOf(game.data, slot.mon)
      local intro = grown > 0
        and ("Your %s has\ngrown by %d level%s!\fWant it back for\n¥%d?")
          :format(name, grown, grown == 1 and "" or "s", fee)
        or ("Back already?\fWant %s back\nfor ¥%d?"):format(name, fee)
      text(intro, nil, { choice=function(yes)
        if not yes then finish("Oh, fine then.\nCome again.") return end
        local returned, why = Daycare.withdraw(
          game.save, game.data, slotIndex, random)
        if not returned then
          finish(ERROR_TEXT[why] or "That won't work.")
          return
        end
        Daycare.syncNPCs(game, overworld)
        require("src.core.Sound").playCry(game.data, returned.species)
        finish(("Here's your\n%s!\fCome again."):format(name))
      end })
    end
  end

  local function daycareMonTalk(slotIndex)
    return function(game, overworld, npc, done)
      local dc = Daycare.normalize(game.save, game.data)
      local slot = dc.slots[slotIndex]
      if npc and npc.facePlayer and overworld then npc:facePlayer(overworld.player) end
      if slot and slot.mon then
        require("src.core.Sound").playCry(game.data, slot.mon.species)
      end
      game.stack:push(require("src.render.TextBox").new(game,
        Daycare.compatibilityDialogue(game.data, dc), done))
    end
  end

  local function outsideManTalk(game, overworld, npc, done)
    local TextBox = require("src.render.TextBox")
    local function text(value, cb, opts)
      game.stack:push(TextBox.new(game, value, cb, opts))
    end
    local function finish(value)
      if value then text(value, done) else done() end
    end
    local function random(a, b) return love.math.random(a, b) end
    local dc = Daycare.normalize(game.save, game.data)
    if npc and npc.facePlayer and overworld then npc:facePlayer(overworld.player) end

    if not (dc.eggReady and dc.egg) then
      Daycare.syncNPCs(game, overworld)
      finish("Not yet...")
      return
    end

    text("We found an EGG!\fDo you want it?", nil, { choice=function(yes)
      if not yes then finish("I'll keep it.\nThanks!") return end
      local egg, why = Daycare.takeEgg(game.save, game.data, random)
      if not egg then finish(ERROR_TEXT[why] or "That won't work.") return end
      require("src.core.Sound").play(game.data, "Get_Item1")
      text("You received the\nEGG!\fTake good care of\nthe EGG!", function()
        local direct = { "left", "left", "up" }
        local around = { "down", "left", "left", "up", "up" }
        -- Route34 uses the longer route when the player is standing directly
        -- left of Gramps and facing right, so he never walks through Red.
        local path = overworld and overworld.player
          and overworld.player.facing == "right" and around or direct
        local at = 0
        local function home()
          at = at + 1
          if not (overworld and npc and overworld.scriptMove and path[at]) then
            Daycare.syncNPCs(game, overworld)
            done()
            return
          end
          overworld:scriptMove(npc, path[at], 1, home)
        end
        home()
      end)
    end })
  end

  mod.content.map_scripts:register("DAYCARE", {
    onEnter=function(game, overworld) Daycare.syncNPCs(game, overworld) end,
    talk={
      TEXT_DAYCARE_GENTLEMAN=keeperTalk(1, "man"),
      [LADY_TEXT]=keeperTalk(2, "lady"),
      [MON1_TEXT]=daycareMonTalk(1),
      [MON2_TEXT]=daycareMonTalk(2),
    },
  })
  mod.content.map_scripts:register("ROUTE_5", {
    onEnter=function(game, overworld) Daycare.syncNPCs(game, overworld) end,
    talk={ [OUTSIDE_MAN_TEXT]=outsideManTalk },
  })
end

local function installEggVisuals()
  local Pokemon = require("src.pokemon.Pokemon")
  if not Pokemon._crystal251EggHeal then
    Pokemon._crystal251EggHeal = true
    local originalHeal = Pokemon.heal
    Pokemon.heal = function(mon, ...)
      if mon and mon.isEgg then
        -- HealParty leaves Eggs at zero HP; otherwise a Pokemon Center would
        -- turn the hidden hatchling into a usable battler before it hatches.
        mon.hp, mon.status = 0, nil
        return
      end
      return originalHeal(mon, ...)
    end
  end

  local PartyMenu = require("src.ui.PartyMenu")
  if not PartyMenu._crystal251EggVisuals then
    PartyMenu._crystal251EggVisuals = true
    local originalPartyDraw = PartyMenu.draw
    PartyMenu.draw = function(self)
      local result = originalPartyDraw(self)
      local party = self.party or self.game.save.party
      for i, mon in ipairs(party or {}) do
        if mon.isEgg then
          local y = PartyMenu.entryY(i)
          -- Crystal's Egg row has its icon and EGG name, but no level,
          -- status, HP bar, or HP digits.
          love.graphics.setColor(1, 1, 1, 1)
          love.graphics.rectangle("fill", 104, y, 56, 8)
          love.graphics.rectangle("fill", 40, y + 8, 120, 8)
          if self.tmhm then
            love.graphics.setColor(0, 0, 0, 1)
            require("src.render.Font").draw("NOT ABLE", 88, y + 8)
          end
        end
      end
      love.graphics.setColor(1, 1, 1, 1)
      return result
    end
  end

  local SummaryMenu = require("src.ui.SummaryMenu")
  if not SummaryMenu._crystal251EggVisuals then
    SummaryMenu._crystal251EggVisuals = true
    local originalNew = SummaryMenu.new
    local originalUpdate = SummaryMenu.update
    local originalDraw = SummaryMenu.draw
    local originalSgbPalettes = SummaryMenu.sgbPalettes

    SummaryMenu.sgbPalettes = function(self, game)
      if self.mon and self.mon.isEgg then
        -- Do not tint the Egg with the hidden hatchling species palette.
        return require("src.render.PaletteFX").wholeNamed(game.data, "MEWMON")
      end
      return originalSgbPalettes(self, game)
    end

    SummaryMenu.new = function(game, mon)
      if not (mon and mon.isEgg) then return originalNew(game, mon) end
      -- Preserve existing SummaryMenu wrappers while suppressing the hidden
      -- hatchling species cry for an unhatched Egg.
      local Sound = require("src.core.Sound")
      local playCry = Sound.playCry
      Sound.playCry = function() end
      local ok, menu = pcall(originalNew, game, mon)
      Sound.playCry = playCry
      if not ok then error(menu, 0) end
      menu.crystal251EggSummary = true
      return menu
    end

    SummaryMenu.update = function(self, dt)
      if not (self.mon and self.mon.isEgg) then return originalUpdate(self, dt) end
      local input = self.game.input
      if input:wasPressed("a") or input:wasPressed("b") then
        self.game.stack:pop()
      end
    end

    local function eggMessage(cycles)
      cycles = math.max(0, math.floor(tonumber(cycles) or 0))
      if cycles <= 5 then
        return { "It's making sounds", "inside!", "It's going to", "hatch soon!" }
      elseif cycles <= 10 then
        return { "It moves around", "inside sometimes.",
                 "It must be close", "to hatching." }
      elseif cycles <= 40 then
        return { "Wonder what's", "inside?", "It needs more time", "though." }
      end
      return { "It looks like this", "EGG will take a", "long time to hatch" }
    end

    SummaryMenu.draw = function(self)
      if not (self.mon and self.mon.isEgg) then return originalDraw(self) end
      local Font = require("src.render.Font")
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.rectangle("fill", 0, 0, 160, 144)
      if self.sprite then
        love.graphics.draw(self.sprite, 8,
          math.max(0, 56 - self.sprite:getHeight()))
      end
      Font.drawBox(0, 8, 20, 10)
      love.graphics.setColor(0, 0, 0, 1)
      Font.draw("EGG", 72, 8)
      for i, line in ipairs(eggMessage(self.mon.eggCycles)) do
        Font.draw(line, 8, 72 + (i - 1) * 16)
      end
      love.graphics.setColor(1, 1, 1, 1)
    end
  end
end

function Daycare.install(mod, assets, iconAssets)
  Daycare.configureAssets(assets, iconAssets)
  installDaycareNPCs(mod)
  installEggVisuals()
  mod.hooks:wrap("pokemon.sprite", function(next, path, ctx)
    if ctx and ctx.mon and ctx.mon.isEgg then
      ctx.trueColor = true
      return assert(eggAssets and eggAssets.front)
    end
    return next(path, ctx)
  end, 130)
  mod.hooks:wrap("pokemon.icon", function(next, path, ctx)
    if ctx and ctx.mon and ctx.mon.isEgg then return assert(eggAssets and eggAssets.icon) end
    return next(path, ctx)
  end, 130)

  mod.events:on("game.ready", function(ev)
    -- game.ready does not promise a payload. Resolve the live singleton here,
    -- after Game has finished wiring its save, data, stack, and overworld.
    gameRef = (ev and ev.game) or require("src.core.Game")
    if gameRef and gameRef.save then
      Daycare.normalize(gameRef.save, gameRef.data)
      local overworld = gameRef.overworld
      Daycare.syncNPCs(gameRef, overworld and overworld.map and overworld or nil)
    end

    local OverworldState = require("src.world.OverworldController")
    local bridge = OverworldState._crystal251DaycareStepBridge
    if not bridge then
      bridge = { original=OverworldState.onStepComplete }
      OverworldState._crystal251DaycareStepBridge = bridge
      OverworldState.onStepComplete = function(self, ...)
        -- Keep one engine-facing wrapper for the lifetime of the process.
        -- Loader rollback/hot reload can recreate this module, but it must not
        -- add another onStepComplete frame: enough stale frames eventually
        -- stack-overflow on a warp step, most visibly at the Celadon and
        -- Rocket Hideout elevator entrances.
        local step = bridge.step
        if step and step(self) then return end
        return bridge.original(self, ...)
      end
    end
    -- Rebind the one bridge to this module generation. This preserves the
    -- complete Crystal CountStep ordering without retaining a stale Daycare
    -- table or nesting another overworld wrapper after a reload.
    bridge.step = function(overworld)
      if gameRef and gameRef.save then Daycare.normalize(gameRef.save, gameRef.data) end
      -- Crystal's CountStep returns a hatch event before poison, encounters,
      -- and the rest of the completed-step pipeline. Preserve that ordering.
      return Daycare.step(gameRef, overworld)
    end
  end)
  return Daycare
end

function Daycare.cacheHasData(cache)
  local assets = cache and cache.eggAssets
  if type(assets) ~= "table" or type(assets.front) ~= "string"
      or type(assets.icon) ~= "string" then return false end
  local iconAssets = cache and cache.daycareIconAssets
  if type(iconAssets) ~= "table" or #iconAssets ~= DaycareIcons.MAX_INDEX then
    return false
  end
  for index = 1, DaycareIcons.MAX_INDEX do
    if type(iconAssets[index]) ~= "string" or iconAssets[index] == "" then
      return false
    end
  end
  local species = cache and cache.species
  if type(species) ~= "table" or #species < 251 then return false end
  for _, row in ipairs(species) do
    local cycles = row and tonumber(row.crystalHatchCycles)
    local groups = row and row.crystalEggGroups
    local icon = row and tonumber(row.crystalMenuIcon)
    if cycles == nil or cycles % 1 ~= 0 or cycles < 1 or cycles > 255
        or type(groups) ~= "table" or tonumber(groups[1]) == nil
        or tonumber(groups[2]) == nil or type(row.crystalEggMoves) ~= "table"
        or icon == nil or icon % 1 ~= 0 or icon < 1
        or icon > DaycareIcons.MAX_INDEX then
      return false
    end
  end
  return true
end

function Daycare.resetForTests()
  gameRef, eggAssets, daycareIconAssets = nil, nil, nil
end

return Daycare
