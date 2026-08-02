local LZ = require("mods.CRYSTAL_251.lib.lz")
local Catalog = require("mods.CRYSTAL_251.catalog")

local Extractor = {}

local function romOffset(pointer)
  return pointer.bank * 0x4000 + pointer.address % 0x4000
end

local Reader = {}
Reader.__index = Reader

function Reader.new(raw)
  return setmetatable({ raw = raw }, Reader)
end

function Reader:u8(offset)
  assert(offset >= 0 and offset < #self.raw, "Crystal ROM read outside file")
  return self.raw:byte(offset + 1)
end

function Reader:u16(offset)
  return self:u8(offset) + self:u8(offset + 1) * 256
end

function Reader:banked(bank, address)
  return bank * 0x4000 + address % 0x4000
end

function Reader:bytes(offset, count)
  local out = {}
  for i = 0, count - 1 do out[i + 1] = self:u8(offset + i) end
  return out
end

local function textByte(value)
  if value >= 0x80 and value <= 0x99 then
    return string.char(string.byte("A") + value - 0x80)
  elseif value >= 0xa0 and value <= 0xb9 then
    return string.char(string.byte("a") + value - 0xa0)
  elseif value >= 0xf6 and value <= 0xff then
    return string.char(string.byte("0") + value - 0xf6)
  end
  return ({ [0x7f]=" ", [0xe0]="'", [0xe3]="-", [0xe8]=".",
    [0xea]="E", [0xef]=" M", [0xf5]=" F" })[value] or ""
end

local function fixedName(reader, offset, count)
  local out = {}
  for i = 0, count - 1 do
    local value = reader:u8(offset + i)
    if value == 0x50 then break end
    out[#out + 1] = textByte(value)
  end
  return table.concat(out):gsub("%s+$", "")
end

local function terminatedName(reader, offset)
  local out = {}
  while true do
    local value = reader:u8(offset)
    offset = offset + 1
    if value == 0x50 then break end
    out[#out + 1] = textByte(value)
  end
  return table.concat(out), offset
end

local dexCharacters = {
  [0x24]="POKé", [0x4a]="PKMN", [0x54]="POKé", [0x56]="……",
  [0x70]="PO", [0x71]="KE", [0x72]="“", [0x73]="”", [0x75]="…",
  [0x7f]=" ", [0xc0]="Ä", [0xc1]="Ö", [0xc2]="Ü", [0xc3]="ä",
  [0xc4]="ö", [0xc5]="ü", [0xd0]="'d", [0xd1]="'l", [0xd2]="'m",
  [0xd3]="'r", [0xd4]="'s", [0xd5]="'t", [0xd6]="'v", [0xdf]="←",
  [0xe0]="'", [0xe1]="PK", [0xe2]="MN", [0xe3]="-", [0xe6]="?",
  [0xe7]="!", [0xe8]=".", [0xe9]="&", [0xea]="é", [0xeb]="→",
  [0xec]="▷", [0xed]="▶", [0xee]="▼", [0xef]="♂", [0xf0]="$",
  [0xf1]="×", [0xf2]=".", [0xf3]="/", [0xf4]=",", [0xf5]="♀",
}

local function dexTextByte(value)
  if value >= 0x80 and value <= 0x99 then
    return string.char(string.byte("A") + value - 0x80)
  elseif value >= 0xa0 and value <= 0xb9 then
    return string.char(string.byte("a") + value - 0xa0)
  elseif value >= 0xf6 and value <= 0xff then
    return string.char(string.byte("0") + value - 0xf6)
  end
  return dexCharacters[value] or ("<%02X>"):format(value)
end

local function dexString(reader, offset)
  local lines, out = {}, {}
  while true do
    local value = reader:u8(offset)
    offset = offset + 1
    if value == 0x50 then break end
    if value == 0x4e or value == 0x4f or value == 0x51 or value == 0x55 then
      lines[#lines + 1] = table.concat(out):gsub("%s+$", "")
      out = {}
    else
      out[#out + 1] = dexTextByte(value)
    end
  end
  lines[#lines + 1] = table.concat(out):gsub("%s+$", "")
  return lines, offset
end

local function parsePokedexData(reader, pointerTable, addresses, dex)
  local address = reader:u16(pointerTable + (dex - 1) * 2)
  local bankIndex = math.floor((dex - 1) / 64) + 1
  local bank = assert(addresses["pokedexEntries" .. bankIndex]).bank
  local pos = reader:banked(bank, address)
  local categoryBytes = {}
  while true do
    local value = reader:u8(pos)
    pos = pos + 1
    if value == 0x50 then break end
    categoryBytes[#categoryBytes + 1] = dexTextByte(value)
  end
  local heightRaw, weightRaw = reader:u16(pos), reader:u16(pos + 2)
  pos = pos + 4
  local page1; page1, pos = dexString(reader, pos)
  local page2; page2, pos = dexString(reader, pos)
  local feet, inches = math.floor(heightRaw / 100), heightRaw % 100
  local totalInches = feet * 12 + inches
  local pageText = { table.concat(page1, " "), table.concat(page2, " ") }
  return {
    category = table.concat(categoryBytes):gsub("%s+$", ""),
    height = {
      raw = heightRaw, feet = feet, inches = inches, totalInches = totalInches,
      centimeters = math.floor(totalInches * 25.4 + 0.5) / 10,
    },
    weight = {
      raw = weightRaw, pounds = weightRaw / 10,
      kilograms = math.floor(weightRaw * 0.45359237 + 0.5) / 10,
    },
    pages = { page1, page2 }, pageText = pageText,
    text = table.concat(pageText, "\n\n"),
  }
end

local function normalizeId(name)
  local id = name:upper():gsub("[^A-Z0-9]+", "_"):gsub("^_+", ""):gsub("_+$", "")
  return id
end

local function rgb15(lo, hi)
  local value = lo + hi * 256
  local r = value % 32
  local g = math.floor(value / 32) % 32
  local b = math.floor(value / 1024) % 32
  return { math.floor(r * 255 / 31 + 0.5), math.floor(g * 255 / 31 + 0.5),
    math.floor(b * 255 / 31 + 0.5) }
end

local function paletteAt(reader, base, dex, shiny)
  local offset = base + dex * 8 + (shiny and 4 or 0)
  return { { 248, 248, 248 }, rgb15(reader:u8(offset), reader:u8(offset + 1)),
    rgb15(reader:u8(offset + 2), reader:u8(offset + 3)), { 0, 0, 0 } }
end

local function unpackPicture(reader, tableOffset, index)
  local row = tableOffset + (index - 1) * 6
  -- dba_pic stores the bank first, biased by PICS_FIX ($36), followed by
  -- the little-endian address. FixPicBank reverses this in Crystal.
  local frontBank, frontAddress = reader:u8(row) + 0x36, reader:u16(row + 1)
  local backBank, backAddress = reader:u8(row + 3) + 0x36, reader:u16(row + 4)
  local frontOffset = reader:banked(frontBank, frontAddress)
  local backOffset = reader:banked(backBank, backAddress)
  local front = LZ.decompress(reader.raw, frontOffset + 1)
  local back = LZ.decompress(reader.raw, backOffset + 1)
  return front, back
end

-- Crystal's SPRITE_LUGIA and SPRITE_HO_OH are not ordinary bird sheets.
-- GetMonSprite maps each one to a species-specific menu icon, and
-- LoadOverworldMonIcon loads all eight 2bpp tiles (two 16x16 frames). The
-- icon pointer table and graphics share a ROM bank in both retail revisions.
local function unpackOverworldIcon(reader, pointerTable, iconIndex, bank)
  local address = reader:u16(pointerTable + iconIndex * 2)
  return reader:bytes(reader:banked(bank, address), 8 * 16)
end

local function parseEvolutionData(reader, pointerTable, speciesIds, moveIds, dex)
  local address = reader:u16(pointerTable + (dex - 1) * 2)
  local pos = reader:banked(0x10, address)
  local evolutions = {}
  while true do
    local method = reader:u8(pos); pos = pos + 1
    if method == 0 then break end
    local evo
    if method == 1 then
      local level, target = reader:u8(pos), reader:u8(pos + 1); pos = pos + 2
      evo = { method = "LEVEL", level = level, species = speciesIds[target] }
    elseif method == 2 then
      local item, target = reader:u8(pos), reader:u8(pos + 1); pos = pos + 2
      evo = { method = "ITEM", item = Catalog.itemByByte[item] or "LINKING_CORD",
        species = speciesIds[target] }
    elseif method == 3 then
      local held, target = reader:u8(pos), reader:u8(pos + 1); pos = pos + 2
      evo = { method = "ITEM", item = held == 0xff and "LINKING_CORD"
        or Catalog.itemByByte[held] or "LINKING_CORD", species = speciesIds[target] }
    elseif method == 4 then
      local time, target = reader:u8(pos), reader:u8(pos + 1); pos = pos + 2
      local levels = { [172]=15, [173]=15, [174]=15, [175]=20, [42]=35, [113]=35 }
      evo = { method = "LEVEL", level = levels[dex] or 35, species = speciesIds[target] }
      if dex == 133 then
        evo.method = "ITEM"
        -- Crystal's happiness branches encode time-of-day, but a timeless
        -- Gen I save has no clock. Preserve the two results deterministically:
        -- Espeon uses Sun Stone and Umbreon uses Moon Stone.
        evo.item = speciesIds[target] == "UMBREON" and "MOON_STONE" or "SUN_STONE"
        evo.level = nil
      end
    elseif method == 5 then
      local level, compare, target = reader:u8(pos), reader:u8(pos + 1), reader:u8(pos + 2)
      pos = pos + 3
      local methods = { [1]="CRYSTAL_STAT_GT", [2]="CRYSTAL_STAT_LT", [3]="CRYSTAL_STAT_EQ" }
      evo = { method = assert(methods[compare]), level = level, species = speciesIds[target] }
    else
      error(("unknown Crystal evolution method %d for dex %d"):format(method, dex))
    end
    evolutions[#evolutions + 1] = evo
  end
  local learnset = {}
  while true do
    local level = reader:u8(pos); pos = pos + 1
    if level == 0 then break end
    local move = reader:u8(pos); pos = pos + 1
    if moveIds[move] then learnset[#learnset + 1] = { level = level, move = moveIds[move] } end
  end
  return evolutions, learnset
end

local function tmhmFor(reader, offset, moveIds)
  local out = {}
  for bit = 0, 59 do
    local value = reader:u8(offset + math.floor(bit / 8))
    if math.floor(value / 2 ^ (bit % 8)) % 2 == 1 then
      local id = moveIds[Catalog.tmItems[bit + 1]] or Catalog.tmItems[bit + 1]
      if id then out[#out + 1] = id end
    end
  end
  return out
end

local function categories(typeId, power)
  if power == 0 then return "status" end
  return ({ NORMAL=true, FIGHTING=true, FLYING=true, POISON=true, GROUND=true,
    ROCK=true, BUG=true, GHOST=true, STEEL=true })[typeId] and "physical" or "special"
end

function Extractor.extract(raw, revision, opts)
  assert(type(raw) == "string" and #raw == 2 * 1024 * 1024,
    "Pokemon Crystal ROM must be exactly 2 MiB")
  opts = opts or {}
  local reader, addresses = Reader.new(raw), revision.addresses
  local at = function(name) return romOffset(assert(addresses[name], name)) end

  local speciesIds, speciesNames = {}, {}
  local namesAt = at("pokemonNames")
  for dex = 1, 251 do
    local display = Catalog.displayOverrides[dex] or fixedName(reader, namesAt + (dex - 1) * 10, 10)
    speciesNames[dex] = display
    speciesIds[dex] = Catalog.idOverrides[dex] or normalizeId(display)
  end

  local moveIds, moveNames, moveNameAt = {}, {}, at("moveNames")
  for index = 1, 251 do
    local display; display, moveNameAt = terminatedName(reader, moveNameAt)
    local id = normalizeId(display)
    if index == 94 then id = "PSYCHIC_M" end
    moveNames[index], moveIds[index] = display, id
    moveIds[id] = id
  end

  local moves, movesAt = {}, at("moves")
  local highCrit = { KARATE_CHOP=true, RAZOR_WIND=true, RAZOR_LEAF=true,
    CRABHAMMER=true, SLASH=true, AEROBLAST=true, CROSS_CHOP=true }
  local priority = { QUICK_ATTACK=1, MACH_PUNCH=1, EXTREMESPEED=1,
    PROTECT=3, DETECT=3, ENDURE=3, VITAL_THROW=-1, WHIRLWIND=-1,
    ROAR=-1, COUNTER=-1, MIRROR_COAT=-1 }
  for index = 1, 251 do
    local offset = movesAt + (index - 1) * 7
    local typeId = assert(Catalog.typeByByte[reader:u8(offset + 3)], "unknown move type")
    local power = reader:u8(offset + 2)
    local id = moveIds[index]
    moves[index] = {
      id = id, name = moveNames[index], index = index,
      effect = Catalog.effectId(reader:u8(offset + 1)), power = power, type = typeId,
      accuracy = math.floor(reader:u8(offset + 4) * 100 / 255 + 0.5),
      pp = reader:u8(offset + 5), effectChance = reader:u8(offset + 6),
      crystalAnim = reader:u8(offset), category = categories(typeId, power),
      priority = priority[id], highCrit = highCrit[id] or nil,
    }
  end

  local pokemon, baseAt, unownForms = {}, at("baseData"), {}
  local palettesAt, picsAt = at("pokemonPalettes"), at("pokemonPicPointers")
  local unownPicsAt = at("unownPicPointers")
  local pokedexPointersAt = at("pokedexEntryPointers")
  for dex = 1, 251 do
    local offset = baseAt + (dex - 1) * 32
    local size = reader:u8(offset + 17)
    local width, height = math.floor(size / 16), size % 16
    local normal = paletteAt(reader, palettesAt, dex, false)
    local shiny = paletteAt(reader, palettesAt, dex, true)
    local stem = speciesIds[dex]:lower()
    local frontPath = "crystal_251/generated/front/" .. stem .. ".png"
    local backPath = "crystal_251/generated/back/" .. stem .. ".png"
    local shinyFront = "crystal_251/generated/shiny/front/" .. stem .. ".png"
    local shinyBack = "crystal_251/generated/shiny/back/" .. stem .. ".png"
    local dexPath = "crystal_251/generated/dex/" .. stem .. ".png"
    local shinyDex = "crystal_251/generated/shiny/dex/" .. stem .. ".png"
    if opts.writePicture then
      local tableOffset, picIndex = picsAt, dex
      if dex == 201 then tableOffset, picIndex = unownPicsAt, 1 end
      local ok, front, back = pcall(unpackPicture, reader, tableOffset, picIndex)
      if not ok then error(("Crystal picture %03d (%s): %s"):format(dex, speciesIds[dex], front)) end
      -- pokemon_animation_graphics transposes every front frame before the
      -- ROM compressor sees it, so the decompressed resting frame is also
      -- column-major (see pret/pokecrystal's transpose_tiles).
      opts.writePicture(frontPath, front, width, height, nil, "columns")
      -- Crystal's back.2bpp assets are assembled with rgbgfx --columns.
      -- Keep that storage detail explicit so the image writer can restore
      -- ordinary row-major tile order before producing the PNG.
      opts.writePicture(backPath, back, 6, 6, nil, "columns")
      opts.writePicture(shinyFront, front, width, height, shiny, "columns")
      opts.writePicture(shinyBack, back, 6, 6, shiny, "columns")
      opts.writePicture(dexPath, front, width, height, nil, "columns", "dex")
      opts.writePicture(shinyDex, front, width, height, shiny, "columns", "dex")
    end
    local evolutions, learnset = parseEvolutionData(reader,
      at("evosAttacksPointers"), speciesIds, moveIds, dex)
    local pokedex = dex >= 152
      and parsePokedexData(reader, pokedexPointersAt, addresses, dex) or nil
    local level1 = {}
    for _, row in ipairs(learnset) do if row.level == 1 then level1[#level1 + 1] = row.move end end
    pokemon[dex] = {
      id = speciesIds[dex], name = speciesNames[dex], dex = dex, index = dex,
      baseStats = { hp=reader:u8(offset + 1), attack=reader:u8(offset + 2),
        defense=reader:u8(offset + 3), speed=reader:u8(offset + 4),
        special=math.max(reader:u8(offset + 5), reader:u8(offset + 6)) },
      crystalSpecialAttack = reader:u8(offset + 5),
      crystalSpecialDefense = reader:u8(offset + 6),
      types = { assert(Catalog.typeByByte[reader:u8(offset + 7)]) },
      catchRate = reader:u8(offset + 9), baseExp = reader:u8(offset + 10),
      growthRate = assert(Catalog.growthByByte[reader:u8(offset + 22)]),
      pokedex = pokedex,
      level1Moves = level1, learnset = learnset, evolutions = evolutions,
      tmhm = tmhmFor(reader, offset + 24, moveIds), frontSize = math.max(width, height),
      -- Generation I back pictures are 32x32 and the battle renderer doubles
      -- them. Crystal back pictures are already full-size 48x48 artwork, so
      -- drawing them at the Gen I default would produce a 96x96 overrun.
      battleScaleBack = 1,
      spriteFront = frontPath, spriteBack = backPath,
      shinySpriteFront = shinyFront, shinySpriteBack = shinyBack,
      spriteDex = dexPath, shinySpriteDex = shinyDex,
      palette = "CRYSTAL_251_" .. speciesIds[dex], paletteColors = normal,
      icon = ({ GRASS="GRASS", WATER="WATER", BUG="BUG", FLYING="BIRD",
        ROCK="QUADRUPED", GROUND="QUADRUPED", DRAGON="SNAKE" })
        [Catalog.typeByByte[reader:u8(offset + 7)]] or "MON",
    }
    if reader:u8(offset + 8) ~= reader:u8(offset + 7) then
      pokemon[dex].types[2] = assert(Catalog.typeByByte[reader:u8(offset + 8)])
    end
    if opts.progress then opts.progress(dex, 251) end
  end

  if opts.writePicture then
    local shiny = paletteAt(reader, palettesAt, 201, true)
    for form = 1, 26 do
      local letter = string.char(64 + form)
      local front, back = unpackPicture(reader, unownPicsAt, form)
      local base = "crystal_251/generated/unown/" .. letter:lower()
      local row = { letter=letter, front=base .. "_front.png", back=base .. "_back.png",
        shinyFront=base .. "_shiny_front.png", shinyBack=base .. "_shiny_back.png",
        dex=base .. "_dex.png", shinyDex=base .. "_shiny_dex.png" }
      opts.writePicture(row.front, front, 5, 5, nil, "columns")
      opts.writePicture(row.back, back, 6, 6, nil, "columns")
      opts.writePicture(row.shinyFront, front, 5, 5, shiny, "columns")
      opts.writePicture(row.shinyBack, back, 6, 6, shiny, "columns")
      opts.writePicture(row.dex, front, 5, 5, nil, "columns", "dex")
      opts.writePicture(row.shinyDex, front, 5, 5, shiny, "columns", "dex")
      unownForms[#unownForms + 1] = row
    end
  end


  local iconTable = at("iconPointers")
  local iconBank = assert(addresses.iconPointers).bank
  local overworldSprites = {
    lugia = "crystal_251/generated/overworld/lugia.png",
    hoOh = "crystal_251/generated/overworld/ho_oh.png",
  }
  if opts.writePicture then
    -- ICON_HO_OH = 33 and ICON_LUGIA = 34 in pret/pokecrystal. The assets
    -- are row-major 16x32 sheets: two 16x16 animation frames stacked.
    opts.writePicture(overworldSprites.hoOh,
      unpackOverworldIcon(reader, iconTable, 33, iconBank), 2, 4,
      nil, "rows", "overworld")
    opts.writePicture(overworldSprites.lugia,
      unpackOverworldIcon(reader, iconTable, 34, iconBank), 2, 4,
      nil, "rows", "overworld")
  end

  return {
    schema = 13, revision = revision.id, species = pokemon, moves = moves,
    unownForms = unownForms, overworldSprites = overworldSprites,
    fingerprint = revision.id .. ":251:251:v11",
  }
end

return Extractor
