local Cache = require("mods.CRYSTAL_251.lib.cache")

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

local function cacheSupported(content)
  -- Schema 24 remains readable through the legacy per-asset cache fallback;
  -- schema 25 stores the same public content in one compressed asset bundle.
  local supported = { [24]=true, [25]=true }
  if type(content) ~= "table" or not supported[content.schema] then return false end
  local Gender = require("mods.CRYSTAL_251.battle.crystal_gender")
  local Daycare = require("mods.CRYSTAL_251.daycare")
  if not (Gender.cacheHasRatios(content) and Daycare.cacheHasData(content)) then
    return false, "Crystal cache metadata is incomplete"
  end
  return Cache.assetsComplete(content)
end

local function loadCache(mod)
  Cache.bind(mod)
  Cache.installAssetBridge()

  -- Prefer the selected playthrough's durable cache. Crucially, distinguish a
  -- genuinely missing cache from a storage/binding failure: an I/O or identity
  -- error must never be interpreted as permission to re-extract the ROM.
  local stored, state, code, message = Cache.readContentStatus()
  local context = Cache.context and Cache.context() or nil
  local playthrough = context and context.playthroughId or "none"
  local version = context and context.gameVersion or "unknown"

  local supported, supportReason = cacheSupported(stored)
  if supported then
    mod.log:info("Crystal cache: state=valid game=%s playthrough=%s",
      tostring(version), tostring(playthrough))
    return stored, false
  end

  local stale = stored ~= nil
  if stale then
    mod.log:warn("Crystal cache: state=stale game=%s playthrough=%s (%s); rebuilding from required ROM",
      tostring(version), tostring(playthrough), tostring(supportReason or "invalid cache"))
  elseif state == "error" then
    mod.log:error("Crystal cache: state=error code=%s game=%s playthrough=%s: %s",
      tostring(code), tostring(version), tostring(playthrough), tostring(message))
    return nil, false
  elseif state == "unbound" then
    -- No durable playthrough is selected yet (first install / empty slot).
    -- Early ROM extraction is required so Crystal's registries can still be
    -- populated before they freeze; it will be persisted once gameplay owns a
    -- real playthrough.
    mod.log:info("Crystal cache: state=unbound code=%s; bootstrapping from required ROM",
      tostring(code))
  else
    mod.log:info("Crystal cache: state=missing game=%s playthrough=%s; bootstrapping from required ROM",
      tostring(version), tostring(playthrough))
  end

  local imported = Cache.importPackaged()
  if cacheSupported(imported) then return imported, stale end
  return nil, stale
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
    LOVE_BALL={"LOVE BALL",0},
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
    UP_GRADE={"UP-GRADE",2100},
    FLOWER_MAIL={"FLOWER MAIL",50,true}, SURF_MAIL={"SURF MAIL",50,true},
    LITEBLUEMAIL={"LITEBLUEMAIL",50,true}, PORTRAITMAIL={"PORTRAITMAIL",50,true},
    LOVELY_MAIL={"LOVELY MAIL",50,true}, EON_MAIL={"EON MAIL",50,true},
    MORPH_MAIL={"MORPH MAIL",50,true}, BLUESKY_MAIL={"BLUESKY MAIL",50,true},
    MUSIC_MAIL={"MUSIC MAIL",50,true}, MIRAGE_MAIL={"MIRAGE MAIL",50,true},
  }
  local evolution = {
    KINGS_ROCK=true, METAL_COAT=true, DRAGON_SCALE=true,
    SUN_STONE=true, UP_GRADE=true,
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
    "FRIEND_BALL", "MOON_BALL", "LOVE_BALL" }
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
  -- Gen1Recomp's machine item ids are named after the Gen I move they taught
  -- (TM_MEGA_PUNCH is the item displayed as TM01, for example). Crystal's
  -- per-species tmhm bitfield is numbered against Crystal's own machine list,
  -- so leaving the item records untouched makes TM01 ask for MEGA_PUNCH while
  -- the Pokemon record correctly advertises DYNAMICPUNCH. Remap by machine
  -- number while preserving every existing item id/story reward/save entry.
  require("mods.CRYSTAL_251.lib.crystal_machines").patchItems(mod)
  mod.content.text_pointers:patch("CeladonMart4F", {
    TEXT_CELADONMART4F_CLERK={
      label="CeladonMart4FClerkText",
      mart={ "POKE_DOLL", "FIRE_STONE", "THUNDER_STONE", "WATER_STONE",
        "LEAF_STONE", "SUN_STONE", "KINGS_ROCK", "METAL_COAT",
        "DRAGON_SCALE", "UP_GRADE" },
    },
  })
end

local function installItemBridge()
  local ItemEffects = require("src.inventory.ItemEffects")
  if ItemEffects._crystal251BridgeInstalled then return end
  ItemEffects._crystal251BridgeInstalled = true
  local extras = { KINGS_ROCK=true, METAL_COAT=true, DRAGON_SCALE=true,
    SUN_STONE=true, UP_GRADE=true }
  local behaviors = require("mods.CRYSTAL_251.item_behaviors")
  local oldStone, oldNeeds, oldHeals, oldUse = ItemEffects.isStone,
    ItemEffects.needsTarget, ItemEffects.healsHP, ItemEffects.use
  ItemEffects.isStone = function(id) return extras[id] or oldStone(id) end
  ItemEffects.needsTarget = function(id, def)
    return extras[id] or behaviors.needsTarget(id) or oldNeeds(id, def)
  end
  ItemEffects.healsHP = function(id)
    return behaviors.healsHP(id) or oldHeals(id)
  end
  ItemEffects.use = function(data, save, itemId, target, battle, moveIndex, ow)
    if target and target.isEgg then
      return "failed", { "It won't have\nany effect." }
    end
    local result, messages, extra = behaviors.use(
      data, itemId, target, battle, moveIndex)
    if result then return result, messages, extra end
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
  local Registry = require("mods.CRYSTAL_251.lib.registry")
  for id, row in pairs(chart.types) do
    Registry.upsert(mod.content.type_chart, id, row)
  end
  for id, multiplier in pairs(chart.rows) do
    Registry.upsert(mod.content.type_chart, id, { multiplier=multiplier })
  end
  for id, multiplier in pairs(chart.corrections) do
    Registry.upsert(mod.content.type_chart, id, { multiplier=multiplier })
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
  local CrystalEvolutions = require("mods.CRYSTAL_251.lib.evolutions")
  local existingSpeciesByDex = {}
  local crystalHeldItems = {}
  local crystalBaseStats = {}
  for id, def in mod.content.pokemon:each() do if def.dex then existingSpeciesByDex[def.dex]=id end end
  for _, source in ipairs(cache.species) do
    local row = copy(source)
    local id, old = existingSpeciesByDex[row.dex] or row.id, existingSpeciesByDex[row.dex]
      and mod.content.pokemon:get(existingSpeciesByDex[row.dex]) or nil
    row.id = id
    row.evolutions = CrystalEvolutions.normalize(id, row.evolutions)
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
    row.paletteColors, row.shinyPaletteColors = nil, nil
    row.crystalSpecialAttack, row.crystalSpecialDefense = nil, nil
    if mod.content.pokemon:get(id) then mod.content.pokemon:override(id, row)
    else mod.content.pokemon:register(id, row) end
    local paletteColors = copy(source.paletteColors)
    -- The Pokédex palette zone also recolors its white background. Crystal's
    -- 15-bit white expands to 248,248,248, producing a visible gray rectangle.
    -- Normalize color zero to display white; sprite transparency is unchanged.
    paletteColors[1] = { 255, 255, 255 }
    mod.content.palettes:register("CRYSTAL_251_" .. id, paletteColors)
    require("mods.CRYSTAL_251.lib.registry")
      .upsert(mod.content.icons, id, source.icon)
  end
  CrystalSummary.configure(crystalBaseStats)
  CrystalGender.installCompatibility(mod)
  CrystalSummary.installCompatibility(mod)
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
  local machineProgression = require("mods.CRYSTAL_251.machine_progression").install(mod)
  local itemProgression = require("mods.CRYSTAL_251.item_progression").install(mod)
  local itemBehaviors = require("mods.CRYSTAL_251.item_behaviors").install(mod)
  local heldItemManagement = require("mods.CRYSTAL_251.held_item_management").install(mod)
  local trainerChanges = require("mods.CRYSTAL_251.trainers").install(mod)
  mod.exports.ecology = ecology
  mod.exports.sanctuaries = sanctuaries
  mod.exports.trainerChanges = trainerChanges
  mod.exports.trades = trades
  mod.exports.machineProgression = machineProgression
  mod.exports.itemProgression = itemProgression
  mod.exports.itemBehaviors = itemBehaviors
  mod.exports.heldItemManagement = heldItemManagement
end

return function(mod)
  local cache, staleCache = loadCache(mod)
  local game
  mod.options:define({
    { key="crystal_shinies", label="CRYSTAL SHINIES", type="toggle", default=true },
    { key="time_spawns", label="TIME SPAWNS", type="choice", default="auto",
      choices={ { "AUTO", "auto" }, { "OFF", "off" } } },
    { key="legendary_ko_removes", label="KO REMOVES LEGEND", type="toggle", default=false },
    { key="force_legendary", label="TEST LEGENDARY", type="toggle", default=false },
  })
  local ImportScreen = require("mods.CRYSTAL_251.import_screen")
  ImportScreen.mod = mod
  mod.content.screens:register("Crystal251Import", {
    new=function(game, options) return ImportScreen.new(game, mod, options) end,
  })

  -- The engine exposes the same OptionsMenu from the title screen and from
  -- the in-game START menu. Only expose ROM reimport after a real playthrough
  -- has entered the overworld. At the title screen the stack contains the
  -- title/options states but not game.overworld; in-game menus leave the
  -- overworld underneath them on the state stack.
  local function inLoadedPlaythrough(g)
    local stack = g and g.stack
    local states = stack and stack.states
    local overworld = g and g.overworld
    if not (overworld and type(states) == "table") then return false end
    for _, state in ipairs(states) do
      if state == overworld then return true end
    end
    return false
  end

  -- Deliberately no ui.title_menu.items hook: Crystal ROM management must not
  -- appear on the game's title/start screen. The launcher owns first import;
  -- this in-game Options row is only a reimport/update helper.
  mod.hooks:wrap("ui.options.rows", function(next, game, rows)
    local out = next(game, rows)
    if type(out) ~= "table" or not inLoadedPlaythrough(game) then return out end
    out[#out + 1] = {
      id = "CRYSTAL_251:crystalRom",
      label = "CRYSTAL ROM",
      value = function()
        if cache then return "READY" end
        return staleCache and "UPDATE" or "IMPORT"
      end,
      activate = function(g)
        if inLoadedPlaythrough(g) then
          mod.ui.push(g, "Crystal251Import")
        end
      end,
    }
    return out
  end, 100)
  if not cache then
    -- required_imports should make the ROM available before this entry chunk
    -- runs. A late splash-screen extraction cannot repair this boot because the
    -- content registries are already being finalized, so never start one here.
    -- The manual CRYSTAL ROM screen remains as a validation/reimport helper and
    -- asks for a restart; the next boot performs the real early extraction.
    if staleCache then
      mod.log:warn("Crystal cache is outdated and the required Crystal ROM could not "
        .. "be imported during early mod load; replace/reselect the ROM in Imported Files and restart")
    else
      mod.log:warn("Crystal data is unavailable even though this mod requires a Crystal ROM; "
        .. "select a supported ROM in Imported Files and restart")
    end
    return
  end

  -- A required Crystal ROM can provide the overhaul immediately on a first
  -- launch, before any playthrough exists. Once the real overworld is active,
  -- commit that in-memory extraction to this playthrough's mod.storage in
  -- small batches. The next cold start can then restore the cache before the
  -- content registries freeze instead of extracting the ROM again.
  local importScreen, persistLogged = nil, false
  local function screenIsOnStack(g, screen)
    local states = g and g.stack and g.stack.states
    if type(states) ~= "table" or not screen then return false end
    for _, state in ipairs(states) do
      if state == screen then return true end
    end
    return false
  end

  mod.hooks:wrap("input.step", function(next, liveGame, dt)
    local result = next(liveGame, dt)
    if Cache.hasPendingPersist and Cache.hasPendingPersist() then
      -- Automatic work is never advanced invisibly.  First put the registered
      -- opaque importer on the live stack; its update method owns every cache
      -- write on subsequent frames and displays the corresponding progress.
      if importScreen and not screenIsOnStack(liveGame, importScreen) then
        importScreen = nil
      end
      if not importScreen and inLoadedPlaythrough(liveGame) then
        importScreen = mod.ui.push(liveGame, "Crystal251Import", {
          automatic = true,
        })
      end
    elseif importScreen and not persistLogged then
      persistLogged = true
      mod.log:info("Crystal ROM extraction cached for this playthrough")
    end
    return result
  end, 5)

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
  end)
  mod.exports.fingerprint = cache.fingerprint
  mod.exports.revision = cache.revision
  mod.exports.dexSize = 251
  mod.log:info("loaded %d Pokemon and %d moves from %s",
    #cache.species, #cache.moves, cache.revision)
end
