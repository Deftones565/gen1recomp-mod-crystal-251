local CACHE = "crystal_251/content.json"

local function loadCache()
  if not (love and love.filesystem and love.filesystem.getInfo(CACHE, "file")) then return nil end
  local raw = love.filesystem.read(CACHE)
  if not raw then return nil end
  local content = require("mods.CRYSTAL_251.lib.json").decode(raw)
  local supported = { [10]=true, [12]=true, [13]=true }
  if type(content) ~= "table" or not supported[content.schema] then return nil end
  return content
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
    KINGS_ROCK={"KING'S ROCK",10000}, METAL_COAT={"METAL COAT",10000},
    DRAGON_SCALE={"DRAGON SCALE",10000}, SUN_STONE={"SUN STONE",10000},
    UP_GRADE={"UP-GRADE",10000}, LINKING_CORD={"LINKING CORD",15000},
  }
  for id, row in pairs(rows) do
    if not mod.content.items:get(id) then
      mod.content.items:register(id, { id=id, name=row[1], price=row[2],
        tossable=true, needsTarget=true, effect="CRYSTAL_EVOLUTION_ITEM" })
    end
  end
  for number, move in pairs({ [6]="WHIRLPOOL", [7]="WATERFALL" }) do
    local id = ("HM_%02d"):format(number)
    if not mod.content.items:get(id) then
      mod.content.items:register(id, { id=id, name=("HM%02d"):format(number), price=0,
        tossable=false, needsTarget=true, machine={ kind="HM", move=move, number=number } })
    end
  end
  -- The fourth floor is already Kanto's evolution-stone counter. Keeping
  -- the additions there makes every converted evolution obtainable without
  -- inventing a second shop UI or touching a map script.
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
  for _, cached in ipairs(cache.moves) do
    local row = copy(cached)
    local id = existingMoveByIndex[row.index] or row.id
    moveIdByIndex[row.index] = id
    row.id = id
    row.effectChance = nil
    row.crystalAnim = nil
    if mod.content.moves:get(id) then mod.content.moves:override(id, row)
    else mod.content.moves:register(id, row) end
  end

  local existingSpeciesByDex = {}
  for id, def in mod.content.pokemon:each() do if def.dex then existingSpeciesByDex[def.dex]=id end end
  for _, source in ipairs(cache.species) do
    local row = copy(source)
    local id, old = existingSpeciesByDex[row.dex] or row.id, existingSpeciesByDex[row.dex]
      and mod.content.pokemon:get(existingSpeciesByDex[row.dex]) or nil
    row.id = id
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
  local cache = loadCache()
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
      label=cache and "REIMPORT CRYSTAL" or "IMPORT CRYSTAL",
      onSelect=function() mod.ui.push(game, "Crystal251Import") end,
    })
    return items
  end, 100)
  if not cache then
    mod.log:warn("Crystal data is not imported; use IMPORT CRYSTAL on the title menu")
    return
  end

  registerContent(mod, cache)
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
  mod.events:on("game.ready", function(ev) game = ev and ev.game end)
  mod.exports.fingerprint = cache.fingerprint
  mod.exports.revision = cache.revision
  mod.exports.dexSize = 251
  mod.log:info("loaded %d Pokemon and %d moves from %s",
    #cache.species, #cache.moves, cache.revision)
end
