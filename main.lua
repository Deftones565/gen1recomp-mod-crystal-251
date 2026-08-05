local CACHE = "crystal_251/content.json"

-- These Generation II moves share an effect byte with a Generation I move,
-- but Crystal stores a per-move effect chance.  Old content caches already
-- contain the Gen I alias, so rewrite only the new move ids at registration
-- time instead of requiring the player to import the ROM again.
local GEN2_EFFECT_OVERRIDES = {
  FAINT_ATTACK = "CRYSTAL_EFFECT_11",
  VITAL_THROW = "CRYSTAL_EFFECT_11",
  POWDER_SNOW = "CRYSTAL_EFFECT_05",
  SWEET_KISS = "CRYSTAL_EFFECT_31",
  SLUDGE_BOMB = "CRYSTAL_EFFECT_02",
  ZAP_CANNON = "CRYSTAL_EFFECT_06",
  ICY_WIND = "CRYSTAL_EFFECT_46",
  SPARK = "CRYSTAL_EFFECT_06",
  DYNAMICPUNCH = "CRYSTAL_EFFECT_4C",
  DRAGONBREATH = "CRYSTAL_EFFECT_06",
  IRON_TAIL = "CRYSTAL_EFFECT_45",
  CRUNCH = "CRYSTAL_EFFECT_48",
  SHADOW_BALL = "CRYSTAL_EFFECT_48",
  ROCK_SMASH = "CRYSTAL_EFFECT_45",
}

-- Generation I move ids whose native handlers do not express Crystal's
-- command family or secondary state. These records are patched only in the
-- merged CRYSTAL_251 data view; the engine source and base data stay untouched.
local KANTO_EFFECT_OVERRIDES = {
  GROWTH = "CRYSTAL_EFFECT_0D",
  HAZE = "CRYSTAL_EFFECT_19",
  PSYCHIC_M = "CRYSTAL_EFFECT_48",
  LIGHT_SCREEN = "CRYSTAL_EFFECT_23",
  TRANSFORM = "CRYSTAL_EFFECT_39",
  REFLECT = "CRYSTAL_EFFECT_41",
  AMNESIA = "CRYSTAL_EFFECT_36",
  TRI_ATTACK = "CRYSTAL_EFFECT_24",
  MINIMIZE = "CRYSTAL_EFFECT_10",
  GUST = "CRYSTAL_EFFECT_95",
  STOMP = "CRYSTAL_EFFECT_96",
  THUNDER = "CRYSTAL_EFFECT_98",
  EARTHQUAKE = "CRYSTAL_EFFECT_93",
  DEFENSE_CURL = "CRYSTAL_EFFECT_9C",
}

local function loadCache()
  if not (love and love.filesystem and love.filesystem.getInfo(CACHE, "file")) then
    return nil, false
  end
  local raw = love.filesystem.read(CACHE)
  if not raw then return nil, true end
  local content = require("mods.CRYSTAL_251.lib.json").decode(raw)
  local supported = { [22]=true }
  if type(content) ~= "table" or not supported[content.schema] then
    return nil, true
  end
  local Gender = require("mods.CRYSTAL_251.battle.crystal_gender")
  local Daycare = require("mods.CRYSTAL_251.daycare")
  if not Gender.cacheHasRatios(content) or not Daycare.cacheHasData(content) then
    return nil, true
  end
  return content, false
end

local function isShiny(mon)
  local d = mon and mon.dvs
  if not d then return false end
  local attack = { [2]=true,[3]=true,[6]=true,[7]=true,[10]=true,[11]=true,[14]=true,[15]=true }
  return d.defense == 10 and d.speed == 10 and d.special == 10 and attack[d.attack] == true
end

local function unownLetter(mon)
  local d = mon and mon.dvs
  if not d then return "A" end
  local function middle(dv) return (dv or 0) % 8 - (dv or 0) % 2 end
  local value = middle(d.attack) * 32 + middle(d.defense) * 8
    + middle(d.speed) * 2 + math.floor(middle(d.special) / 2)
  local index = math.max(1, math.min(26, math.floor(value / 10) + 1))
  local letter = string.char(64 + index)
  -- A mod-owned field is intentionally serialized with the monster, keeping
  -- its Crystal form stable in party, boxes, trades, and Hall of Fame.
  mon.crystal251Form = letter
  return letter
end

local function copy(value)
  if type(value) ~= "table" then return value end
  local out = {}
  for key, child in pairs(value) do out[key] = copy(child) end
  return out
end

local function installItems(mod)
  mod.content.item_effects:register("CRYSTAL_EVOLUTION_ITEM", {
    needsTarget=true, field=true,
    use=function(ctx)
      local target, itemId = ctx and ctx.target, ctx and ctx.itemId
      for _, evo in ipairs((ctx and ctx.speciesDef and ctx.speciesDef.evolutions) or {}) do
        if evo.method=="ITEM" and evo.item==itemId then
          return "consumed",nil,{evolveTo=evo.species}
        end
      end
      return "failed",{"It won't have\nany effect."}
    end,
  })
  local rows = {
    HEAVY_BALL={"HEAVY BALL",0}, LEVEL_BALL={"LEVEL BALL",0},
    LURE_BALL={"LURE BALL",0}, FAST_BALL={"FAST BALL",0},
    FRIEND_BALL={"FRIEND BALL",0}, MOON_BALL={"MOON BALL",0},
    LOVE_BALL={"LOVE BALL",0}, PARK_BALL={"PARK BALL",0},
    EXP_SHARE={"EXP.SHARE",3000}, LUCKY_EGG={"LUCKY EGG",200},
    BRIGHTPOWDER={"BRIGHTPOWDER",10}, LUCKY_PUNCH={"LUCKY PUNCH",10},
    METAL_POWDER={"METAL POWDER",10}, QUICK_CLAW={"QUICK CLAW",100},
    PSNCUREBERRY={"PSNCUREBERRY",10}, SOFT_SAND={"SOFT SAND",100},
    SHARP_BEAK={"SHARP BEAK",100}, PRZCUREBERRY={"PRZCUREBERRY",10},
    BURNT_BERRY={"BURNT BERRY",10}, ICE_BERRY={"ICE BERRY",10},
    POISON_BARB={"POISON BARB",100}, KINGS_ROCK={"KING'S ROCK",100},
    BITTER_BERRY={"BITTER BERRY",10}, MINT_BERRY={"MINT BERRY",10},
    SILVERPOWDER={"SILVERPOWDER",100}, AMULET_COIN={"AMULET COIN",100},
    CLEANSE_TAG={"CLEANSE TAG",200}, MYSTIC_WATER={"MYSTIC WATER",100},
    TWISTEDSPOON={"TWISTEDSPOON",100}, BLACKBELT_I={"BLACKBELT",100},
    BLACKGLASSES={"BLACKGLASSES",100}, PINK_BOW={"PINK BOW",100},
    STICK={"STICK",200}, SMOKE_BALL={"SMOKE BALL",200},
    NEVERMELTICE={"NEVERMELTICE",100}, MAGNET={"MAGNET",100},
    MIRACLEBERRY={"MIRACLEBERRY",10}, SPELL_TAG={"SPELL TAG",100},
    MIRACLE_SEED={"MIRACLE SEED",100}, THICK_CLUB={"THICK CLUB",500},
    FOCUS_BAND={"FOCUS BAND",200}, HARD_STONE={"HARD STONE",100},
    CHARCOAL={"CHARCOAL",9800}, BERRY_JUICE={"BERRY JUICE",100},
    SCOPE_LENS={"SCOPE LENS",200}, METAL_COAT={"METAL COAT",100},
    DRAGON_FANG={"DRAGON FANG",100}, LEFTOVERS={"LEFTOVERS",200},
    MYSTERYBERRY={"MYSTERYBERRY",10}, DRAGON_SCALE={"DRAGON SCALE",2100},
    BERSERK_GENE={"BERSERK GENE",200}, LIGHT_BALL={"LIGHT BALL",100},
    POLKADOT_BOW={"POLKADOT BOW",100}, BERRY={"BERRY",10},
    GOLD_BERRY={"GOLD BERRY",10}, SUN_STONE={"SUN STONE",2100},
    UP_GRADE={"UP-GRADE",2100}, LINKING_CORD={"LINKING CORD",15000},
    FLOWER_MAIL={"FLOWER MAIL",50,true}, SURF_MAIL={"SURF MAIL",50,true},
    LITEBLUEMAIL={"LITEBLUEMAIL",50,true}, PORTRAITMAIL={"PORTRAITMAIL",50,true},
    LOVELY_MAIL={"LOVELY MAIL",50,true}, EON_MAIL={"EON MAIL",50,true},
    MORPH_MAIL={"MORPH MAIL",50,true}, BLUESKY_MAIL={"BLUESKY MAIL",50,true},
    MUSIC_MAIL={"MUSIC MAIL",50,true}, MIRAGE_MAIL={"MIRAGE MAIL",50,true},
  }
  local evolution = {
    KINGS_ROCK=true, METAL_COAT=true, DRAGON_SCALE=true,
    SUN_STONE=true, UP_GRADE=true, LINKING_CORD=true,
  }
  for id, row in pairs(rows) do
    if not mod.content.items:get(id) then
      local def = { id=id, name=row[1], price=row[2], tossable=true }
      if row[3] then def.isMail = true end
      if evolution[id] then
        def.needsTarget = true
        def.effect = "CRYSTAL_EVOLUTION_ITEM"
      end
      mod.content.items:register(id, def)
    end
  end
  local balls = { "HEAVY_BALL", "LEVEL_BALL", "LURE_BALL", "FAST_BALL",
    "FRIEND_BALL", "MOON_BALL", "LOVE_BALL", "PARK_BALL" }
  for _, id in ipairs(balls) do
    if not mod.content.balls:get(id) then
      mod.content.balls:register(id, { randMax=255, tossAnim="ULTRATOSS_ANIM" })
    end
  end
  for number, move in pairs({ [6]="WHIRLPOOL", [7]="WATERFALL" }) do
    local id = ("HM_%02d"):format(number)
    if not mod.content.items:get(id) then
      mod.content.items:register(id, { id=id, name=("HM%02d"):format(number), price=0,
        tossable=false, needsTarget=true, machine={ kind="HM", move=move, number=number } })
    end
  end
  mod.content.text_pointers:patch("CeladonMart4F", {
    TEXT_CELADONMART4F_CLERK={
      label="CeladonMart4FClerkText",
      mart={ "POKE_DOLL", "FIRE_STONE", "THUNDER_STONE", "WATER_STONE",
        "LEAF_STONE", "SUN_STONE", "KINGS_ROCK", "METAL_COAT",
        "DRAGON_SCALE", "UP_GRADE", "LINKING_CORD" },
    },
  })
end

local function installItemBridge()
  local ItemEffects = require("src.inventory.ItemEffects")
  if ItemEffects._crystal251BridgeInstalled then return end
  ItemEffects._crystal251BridgeInstalled = true
  local extras = { KINGS_ROCK=true, METAL_COAT=true, DRAGON_SCALE=true,
    SUN_STONE=true, UP_GRADE=true, LINKING_CORD=true }
  local oldStone, oldNeeds, oldUse = ItemEffects.isStone, ItemEffects.needsTarget, ItemEffects.use
  ItemEffects.isStone = function(id) return extras[id] or oldStone(id) end
  ItemEffects.needsTarget = function(id, def) return extras[id] or oldNeeds(id, def) end
  ItemEffects.use = function(data, save, itemId, target, battle, moveIndex, ow)
    if target and target.isEgg then
      return "failed", { "It won't have\nany effect." }
    end
    if not extras[itemId] then return oldUse(data, save, itemId, target, battle, moveIndex, ow) end
    if battle or not target then return "failed", { "It won't have\nany effect." } end
    for _, evo in ipairs((data.pokemon[target.species] or {}).evolutions or {}) do
      if evo.method == "ITEM" and evo.item == itemId then
        return "consumed", nil, { evolveTo=evo.species }
      end
    end
    return "failed", { "It won't have\nany effect." }
  end
end

local function installTypes(mod)
  local chart = require("mods.CRYSTAL_251.type_chart")
  for id, row in pairs(chart.types) do mod.content.type_chart:register(id, row) end
  for id, multiplier in pairs(chart.rows) do
    if mod.content.type_chart:get(id) then
      mod.content.type_chart:override(id, { multiplier=multiplier })
    else
      mod.content.type_chart:register(id, { multiplier=multiplier })
    end
  end
  for id, multiplier in pairs(chart.corrections) do
    if mod.content.type_chart:get(id) then
      mod.content.type_chart:override(id, { multiplier=multiplier })
    else
      mod.content.type_chart:register(id, { multiplier=multiplier })
    end
  end
end

local function registerContent(mod, cache)
  require("mods.CRYSTAL_251.effects").install(mod)
  require("mods.CRYSTAL_251.battle.crystal_presentation").register(mod, cache)
  installTypes(mod)
  installItems(mod)
  mod.content.constants:patch("dexSize", 251)
  mod.content.constants:override("hmMoves",
    { "CUT", "FLY", "SURF", "STRENGTH", "FLASH", "WHIRLPOOL", "WATERFALL" })
  mod.content.link_fields:register("crystal251_form", {
    rev=1,
    pack=function(mon) return mon.crystal251Form end,
    unpack=function(mon, value) mon.crystal251Form=value end,
  })
  mod.content.link_fields:register("crystal251_legendary", {
    rev=1,
    pack=function(mon) return mon.crystal251Legendary end,
    unpack=function(mon, value) mon.crystal251Legendary=value end,
  })
  local comparisons = {
    CRYSTAL_STAT_GT=function(a,b) return a>b end,
    CRYSTAL_STAT_LT=function(a,b) return a<b end,
    CRYSTAL_STAT_EQ=function(a,b) return a==b end,
  }
  for methodId, compare in pairs(comparisons) do
    mod.content.evolution_methods:register(methodId, {
    check=function(_, mon, evo, trigger)
      if trigger.kind ~= "levelup" or mon.level < (evo.level or 20) then return false end
      return compare(mon.stats.attack, mon.stats.defense)
    end,
    describe=function(evo) return "Level " .. tostring(evo.level or 20) end,
    })
  end

  local existingMoveByIndex = {}
  for id, def in mod.content.moves:each() do if def.index then existingMoveByIndex[def.index]=id end end
  local moveIdByIndex = {}
  local crystalMoves = {}
  for _, cached in ipairs(cache.moves) do
    local existingId = existingMoveByIndex[cached.index]
    local crystalId = existingId or cached.id
    local crystalRow = copy(cached)
    crystalRow.id = crystalId
    crystalRow.effect = GEN2_EFFECT_OVERRIDES[crystalId] or crystalRow.effect
    crystalMoves[crystalId] = crystalRow
    if cached.index < 166 then
      -- Keep the registered move definition native by default. The complete
      -- Crystal row remains mod-owned for damage routing; a small set of
      -- split-stat/screen moves is patched immediately after this loop.
      moveIdByIndex[cached.index] = assert(existingId,
        ("missing native Generation I move at index %d"):format(cached.index))
    else
      local row = copy(cached)
      local id = existingId or row.id
      moveIdByIndex[row.index] = id
      row.id = id
      row.effect = GEN2_EFFECT_OVERRIDES[id] or row.effect
      if mod.content.moves:get(id) then mod.content.moves:override(id, row)
      else mod.content.moves:register(id, row) end
    end
  end

  for id, effect in pairs(KANTO_EFFECT_OVERRIDES) do
    local crystal = assert(crystalMoves[id], "missing Crystal move record for " .. id)
    crystal.effect = effect
    mod.content.moves:patch(id, {
      effect = effect,
      effectChance = crystal.effectChance,
    })
  end

  local CrystalProgression = require("mods.CRYSTAL_251.battle.crystal_progression")
  local CrystalGender = require("mods.CRYSTAL_251.battle.crystal_gender")
  local CrystalSummary = require("mods.CRYSTAL_251.battle.crystal_summary")
  local existingSpeciesByDex = {}
  local crystalHeldItems = {}
  local crystalBaseStats = {}
  for id, def in mod.content.pokemon:each() do if def.dex then existingSpeciesByDex[def.dex]=id end end
  for _, source in ipairs(cache.species) do
    local row = copy(source)
    local id, old = existingSpeciesByDex[row.dex] or row.id, existingSpeciesByDex[row.dex]
      and mod.content.pokemon:get(existingSpeciesByDex[row.dex]) or nil
    row.id = id
    crystalHeldItems[id] = row.crystalHeldItems
    crystalBaseStats[id] = {
      hp = row.baseStats.hp, attack = row.baseStats.attack,
      defense = row.baseStats.defense, speed = row.baseStats.speed,
      specialAttack = row.crystalSpecialAttack or row.baseStats.special,
      specialDefense = row.crystalSpecialDefense or row.baseStats.special,
    }
    row.crystalHeldItems = nil
    row.frontAnimation = nil
    if old then
      -- Crystal's Time Capsule deliberately restores the original Kanto base
      -- Special. Johto has no official Gen I value and keeps the imported
      -- stronger-special policy recorded in the cache.
      row.baseStats.special = old.baseStats.special
      row.dexEntry, row.cry = old.dexEntry, old.cry
    elseif row.dex >= 152 then
      local dexEntry = assert(row.pokedex,
        ("Crystal import is missing Pokédex data for %s"):format(row.id))

      local page1 = (dexEntry.pages and dexEntry.pages[1]) or {}
      local page2 = (dexEntry.pages and dexEntry.pages[2]) or {}
      local description

      if #page1 > 0 or #page2 > 0 then
        description = table.concat(page1, "\n")
        if #page2 > 0 then
          if description ~= "" then description = description .. "\n\n" end
          description = description .. table.concat(page2, "\n")
        end
      else
        description = dexEntry.text or ""
      end

      local textId = "CRYSTAL_251_DEX_" .. row.id
      mod.content.text:register(textId, description)

      row.dexEntry = {
        kind = dexEntry.category or "?",
        heightFt = assert(dexEntry.height and dexEntry.height.feet),
        heightIn = assert(dexEntry.height and dexEntry.height.inches),
        weight = assert(dexEntry.weight and dexEntry.weight.raw),
        text = textId,
      }
    end
    CrystalGender.setRatio(id, source.crystalGenderRatio)
    row.crystalGenderRatio = source.crystalGenderRatio
    row.pokedex = nil
    row.shinySpriteFront, row.shinySpriteBack = nil, nil
    row.spriteDex, row.shinySpriteDex = nil, nil
    row.paletteColors = nil
    row.crystalSpecialAttack, row.crystalSpecialDefense = nil, nil
    if mod.content.pokemon:get(id) then mod.content.pokemon:override(id, row)
    else mod.content.pokemon:register(id, row) end
    local paletteColors = copy(source.paletteColors)
    -- The Pokédex palette zone also recolors its white background. Crystal's
    -- 15-bit white expands to 248,248,248, producing a visible gray rectangle.
    -- Normalize color zero to display white; sprite transparency is unchanged.
    paletteColors[1] = { 255, 255, 255 }
    mod.content.palettes:register("CRYSTAL_251_" .. id, paletteColors)
    mod.content.icons:register(id, source.icon)
  end
  CrystalSummary.configure(crystalBaseStats)
  local SpecialDamage = require("mods.CRYSTAL_251.battle.special_damage")
  local MultiTurn = require("mods.CRYSTAL_251.battle.multi_turn")
  local CrystalStatus = require("mods.CRYSTAL_251.battle.crystal_status")
  local CrystalSwitching = require("mods.CRYSTAL_251.battle.crystal_switching")
  local CrystalItems = require("mods.CRYSTAL_251.battle.crystal_items")
  local CrystalScheduler = require("mods.CRYSTAL_251.battle.crystal_scheduler")
  local CrystalActions = require("mods.CRYSTAL_251.battle.crystal_actions")
  local CrystalAI = require("mods.CRYSTAL_251.battle.crystal_ai")
  SpecialDamage.patchMoves(mod, crystalMoves)
  MultiTurn.patchMoves(mod, crystalMoves)
  CrystalStatus.patchMoves(mod, crystalMoves)
  CrystalSwitching.patchMoves(mod, crystalMoves)

  local MoveScripts = require("mods.CRYSTAL_251.battle.move_scripts")
  local CommandInterpreter = require("mods.CRYSTAL_251.battle.command_interpreter")
  local crystalMoveScripts = MoveScripts.build(crystalMoves)
  local crystalInterpreter = CommandInterpreter.new()
  local scriptsOk, scriptsErr = MoveScripts.validate(
    crystalMoveScripts, crystalInterpreter, 251)
  assert(scriptsOk, scriptsErr)

  mod.exports.crystalHeldItems = crystalHeldItems
  mod.exports.crystalBaseStats = crystalBaseStats
  mod.exports.crystalMoves = crystalMoves
  mod.exports.crystalMoveScripts = crystalMoveScripts
  mod.exports.crystalCommandInterpreter = crystalInterpreter
  mod.exports.crystalSpecialDamage = SpecialDamage
  mod.exports.crystalMultiTurn = MultiTurn
  mod.exports.crystalStatus = CrystalStatus
  mod.exports.crystalSwitching = CrystalSwitching
  mod.exports.crystalItems = CrystalItems
  mod.exports.crystalScheduler = CrystalScheduler
  mod.exports.crystalActions = CrystalActions
  mod.exports.crystalAI = CrystalAI
  SpecialDamage.configure({
    moves = crystalMoves,
    scripts = crystalMoveScripts,
    interpreter = crystalInterpreter,
  })
  MultiTurn.configure({
    moves = crystalMoves,
    scripts = crystalMoveScripts,
    interpreter = crystalInterpreter,
  })
  require("mods.CRYSTAL_251.battle.crystal_damage").install(mod, {
    baseStats = crystalBaseStats,
    moves = crystalMoves,
    scripts = crystalMoveScripts,
    interpreter = crystalInterpreter,
  })
  local bridge = require("mods.CRYSTAL_251.runtime_bridge")
  bridge.setHeldItems(crystalHeldItems)
  bridge.install()
  local dramatic = mod.find("DRAMATIC_SHAPE") or mod.find("dramatic_shape")
  CrystalGender.installDramatic(dramatic and dramatic.exports)
  local presentation = require("mods.CRYSTAL_251.battle.crystal_presentation")
  presentation.configure(cache)
  presentation.installRuntime()
  mod.exports.crystalRuntime = bridge
  mod.exports.crystalPresentation = presentation
  mod.exports.crystalProgression = CrystalProgression
  mod.exports.crystalGender = CrystalGender
  mod.exports.crystalSummary = CrystalSummary
  mod.exports.rollWildHeldItem = bridge.rollWildHeldItem

  local overworld = assert(cache.overworldSprites,
    "Crystal import is missing legendary overworld sprites")
  mod.content.sprites:register("CRYSTAL_251_SPRITE_LUGIA", {
    image=assert(overworld.lugia), frames=2, walker=false,
    -- Crystal assigns PAL_NPC_BLUE to Lugia. This existing Gen I assignment
    -- lets every color pipeline apply its corresponding blue OBJ palette.
    paletteSource="ROM:SpriteSheetPointerTable[15]",
  })
  mod.content.sprites:register("CRYSTAL_251_SPRITE_HO_OH", {
    image=assert(overworld.hoOh), frames=2, walker=false,
    -- Crystal assigns PAL_NPC_RED to Ho-Oh; Gen I's bird is in the matching
    -- orange/red OBJ group and supplies only the palette, never the artwork.
    paletteSource="ROM:SpriteSheetPointerTable[8]",
  })
  local sanctuaries = require("mods.CRYSTAL_251.sanctuaries").install(mod)
  local ecology = require("mods.CRYSTAL_251.ecology").install(mod, cache)
  local trades = require("mods.CRYSTAL_251.trades").install(mod)
  local trainerChanges = require("mods.CRYSTAL_251.trainers").install(mod)
  mod.exports.ecology = ecology
  mod.exports.sanctuaries = sanctuaries
  mod.exports.trainerChanges = trainerChanges
  mod.exports.trades = trades
end

return function(mod)
  local cache, staleCache = loadCache()
  local game
  mod.options:define({
    { key="crystal_shinies", label="CRYSTAL SHINIES", type="toggle", default=true },
    { key="time_spawns", label="TIME SPAWNS", type="choice", default="auto",
      choices={ { "AUTO", "auto" }, { "OFF", "off" } } },
    { key="legendary_ko_removes", label="KO REMOVES LEGEND", type="toggle", default=false },
    { key="force_legendary", label="TEST LEGENDARY", type="toggle", default=false },
  })
  mod.content.screens:register("Crystal251Import", {
    new=function(game) return require("mods.CRYSTAL_251.import_screen").new(game, mod) end,
  })
  mod.hooks:wrap("ui.title_menu.items", function(next, game, items)
    items = next(game, items)
    mod.ui.insertBefore(items, "EXIT GAME", {
      label=(cache or staleCache) and "REIMPORT CRYSTAL" or "IMPORT CRYSTAL",
      onSelect=function() mod.ui.push(game, "Crystal251Import") end,
    })
    return items
  end, 100)
  if not cache then
    if staleCache then
      mod.log:warn("Crystal cache is outdated; use REIMPORT CRYSTAL on the title menu")
    else
      mod.log:warn("Crystal data is not imported; use IMPORT CRYSTAL on the title menu")
    end
    return
  end

  registerContent(mod, cache)
  local daycare = require("mods.CRYSTAL_251.daycare").install(
    mod, cache.eggAssets, cache.daycareIconAssets)
  mod.exports.crystalDaycare = daycare
  installItemBridge()
  require("mods.CRYSTAL_251.legendaries").install(mod)
  local shinyPaths, dexPaths = {}, {}
  for _, row in ipairs(cache.species) do
    shinyPaths[row.spriteFront] = row.shinySpriteFront
    shinyPaths[row.spriteBack] = row.shinySpriteBack
    shinyPaths[row.spriteDex] = row.shinySpriteDex
    dexPaths[row.spriteFront] = row.spriteDex
  end
  local unownForms = {}
  for _, row in ipairs(cache.unownForms or {}) do
    unownForms[row.letter] = row
    shinyPaths[row.front] = row.shinyFront
    shinyPaths[row.back] = row.shinyBack
    shinyPaths[row.dex] = row.shinyDex
    dexPaths[row.front] = row.dex
  end
  mod.hooks:wrap("pokemon.sprite", function(next, path, ctx)
    local result = next(path, ctx)
    if ctx and ctx.species == "UNOWN" then
      local letter = ctx.mon and (ctx.mon.crystal251Form or unownLetter(ctx.mon)) or "A"
      local form = unownForms[letter] or unownForms.A
      if form then
        result = ctx.side == "back" and form.back
          or (ctx.kind == "dex" and form.dex or form.front)
      end
    elseif ctx and ctx.kind == "dex" and ctx.side == "front" and dexPaths[result] then
      result = dexPaths[result]
    end
    local color = game and game.save and game.save.options and game.save.options.colors
    if mod.options:get("crystal_shinies") and (color == "gbc" or color == "redpp")
        and ctx and isShiny(ctx.mon) and shinyPaths[result] then
      ctx.trueColor = true
      return shinyPaths[result]
    end
    return result
  -- Run outside Shiny Indicators (100): its temporary force option finalizes
  -- DVs after calling next(), and this outer selector must see those DVs on
  -- the first frame to choose Crystal's imported shiny asset.
  end, 120)
  mod.events:on("game.ready", function(ev)
    game = (ev and ev.game) or require("src.core.Game")
    local dramatic = mod.find("DRAMATIC_SHAPE") or mod.find("dramatic_shape")
    require("mods.CRYSTAL_251.battle.crystal_gender")
      .installDramatic(dramatic and dramatic.exports)
  end)
  mod.exports.fingerprint = cache.fingerprint
  mod.exports.revision = cache.revision
  mod.exports.dexSize = 251
  mod.log:info("loaded %d Pokemon and %d moves from %s",
    #cache.species, #cache.moves, cache.revision)
end
