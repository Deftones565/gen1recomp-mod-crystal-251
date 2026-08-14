local LZ = require("mods.CRYSTAL_251.lib.lz")
local Catalog = require("mods.CRYSTAL_251.catalog")
local DaycareIcons = require("mods.CRYSTAL_251.daycare_icons")
local Evolutions = require("mods.CRYSTAL_251.lib.evolutions")

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

function Reader:s16(offset)
  local value = self:u16(offset)
  return value >= 0x8000 and value - 0x10000 or value
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

local function copyRestingFrame(raw, width, height)
  local out = {}
  for index = 1, width * height * 16 do out[index] = raw[index] end
  return out
end

local function bitSet(value, bit)
  return math.floor(value / 2 ^ bit) % 2 == 1
end

local function parsePicAnimationScript(reader, bank, address)
  local offset = reader:banked(bank, address)
  local entries = {}
  for _ = 1, 256 do
    local command = reader:u8(offset)
    if command == 0xff then break end
    entries[#entries + 1] = { command, reader:u8(offset + 1) }
    offset = offset + 2
  end
  local out, pc, repeatCount = {}, 1, 0
  for _ = 1, 1024 do
    local row = entries[pc]
    if not row then break end
    pc = pc + 1
    if row[1] == 0xfe then
      repeatCount = row[2]
    elseif row[1] == 0xfd then
      if repeatCount > 0 then
        repeatCount = repeatCount - 1
        if repeatCount > 0 then pc = row[2] + 1 end
      end
    else
      out[#out + 1] = { frame = row[1], duration = row[2] == 0 and 256 or row[2] }
    end
  end
  return out
end

local function animationFrame(reader, front, width, height, tableIndex, frame,
    framesTable, framesBank, bitmasksTable, bitmasksBank)
  if frame == 0 then return copyRestingFrame(front, width, height) end
  local speciesFrameAddress = reader:u16(framesTable + (tableIndex - 1) * 2)
  local speciesFrameTable = reader:banked(framesBank, speciesFrameAddress)
  local frameAddress = reader:u16(speciesFrameTable + (frame - 1) * 2)
  local record = reader:banked(framesBank, frameAddress)
  local bitmaskIndex = reader:u8(record)
  record = record + 1

  local bitmaskAddress = reader:u16(bitmasksTable + (tableIndex - 1) * 2)
  local bitmaskBase = reader:banked(bitmasksBank, bitmaskAddress)
  local bitmaskSize = ({ [5]=4, [6]=5, [7]=7 })[height]
  assert(bitmaskSize, "unsupported Crystal animation size")
  local bitmask = bitmaskBase + bitmaskIndex * bitmaskSize
  local out = copyRestingFrame(front, width, height)
  local bit = 0
  for column = 0, height - 1 do
    for row = 0, height - 1 do
      local byte = reader:u8(bitmask + math.floor(bit / 8))
      if bitSet(byte, bit % 8) then
        local sourceTile = reader:u8(record)
        record = record + 1
        local targetTile = column * height + row
        for index = 1, 16 do
          out[targetTile * 16 + index] = assert(front[sourceTile * 16 + index])
        end
      end
      bit = bit + 1
    end
  end
  return out
end

local function extractFrontAnimation(reader, args)
  local pointer = reader:u16(args.animationPointers
    + (args.tableIndex - 1) * 2)
  local sequence = parsePicAnimationScript(reader, args.animationBank, pointer)
  if #sequence == 0 then return nil end
  local unique, frames = {}, {}
  for _, row in ipairs(sequence) do
    local paths = unique[row.frame]
    if not paths then
      local base = "crystal_251/generated/animations/front/" .. args.stem
        .. "_" .. tostring(row.frame)
      paths = { normal=base .. ".png", shiny=base .. "_shiny.png" }
      local raw = animationFrame(reader, args.front, args.width, args.height,
        args.tableIndex, row.frame, args.framesPointers, args.framesBank,
        args.bitmasksPointers, args.bitmasksBank)
      args.writePicture(paths.normal, raw, args.width, args.height,
        args.normalPalette, "columns")
      args.writePicture(paths.shiny, raw, args.width, args.height,
        args.shinyPalette, "columns")
      unique[row.frame] = paths
    end
    frames[#frames + 1] = {
      path=paths.normal, shinyPath=paths.shiny, duration=row.duration,
    }
  end
  return { frames=frames, source="Pokemon Crystal normal front animation" }
end

local function validCryHeader(reader, bank, address)
  if bank < 1 or bank > 0x7f or address < 0x4000 or address >= 0x8000 then
    return false
  end
  local offset = reader:banked(bank, address)
  if offset < 0 or offset + 8 >= #reader.raw then return false end
  local first = reader:u8(offset)
  local count = math.floor(first / 0x40) + 1
  if count < 1 or count > 3 then return false end
  local seen = {}
  for index = 0, count - 1 do
    local descriptor = reader:u8(offset + index * 3)
    local channel = descriptor % 16 + 1
    local target = reader:u16(offset + index * 3 + 1)
    if not ({ [5]=true, [6]=true, [8]=true })[channel]
        or seen[channel] or target < 0x4000 or target >= 0x8000 then
      return false
    end
    seen[channel] = true
  end
  return true
end

local function findCryPointers(reader)
  local rows = 69
  for offset = 0, #reader.raw - rows * 3 do
    local bank = reader:u8(offset)
    local address = reader:u16(offset + 1)
    if validCryHeader(reader, bank, address) then
      local valid = true
      for index = 1, rows - 1 do
        local row = offset + index * 3
        if not validCryHeader(reader, reader:u8(row), reader:u16(row + 1)) then
          valid = false
          break
        end
      end
      if valid then return offset end
    end
  end
  error("could not locate Crystal cry pointer table")
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
      evo = { method = "ITEM", item = assert(Catalog.itemByByte[item],
          ("unknown Crystal evolution item 0x%02x"):format(item)),
        species = speciesIds[target] }
    elseif method == 3 then
      local held, target = reader:u8(pos), reader:u8(pos + 1); pos = pos + 2
      local levelRule = held == 0xff
        and Evolutions.levelTrades[speciesIds[dex]] or nil
      if levelRule then
        assert(speciesIds[target] == levelRule.species,
          "Crystal trade evolution target does not match the standalone policy")
        evo = { method = "LEVEL", level = levelRule.level,
          species = speciesIds[target] }
      else
        assert(held ~= 0xff,
          "Crystal trade evolution has no standalone evolution policy")
        evo = { method = "ITEM", item = assert(Catalog.itemByByte[held],
            ("unknown Crystal held evolution item 0x%02x"):format(held)),
          species = speciesIds[target] }
      end
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

local function eggMovesFor(reader, pointerTable, bank, dex, moveIds)
  local address = reader:u16(pointerTable + (dex - 1) * 2)
  local pos = reader:banked(bank, address)
  local out = {}
  while true do
    local move = reader:u8(pos); pos = pos + 1
    if move == 0xff then break end
    local id = moveIds[move]
    if id then out[#out + 1] = id end
  end
  return out
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
  local eggMovePointersAt = at("eggMovePointers")
  local eggMoveBank = assert(addresses.eggMovePointers).bank
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
    local front
    if opts.writePicture then
      local tableOffset, picIndex = picsAt, dex
      if dex == 201 then tableOffset, picIndex = unownPicsAt, 1 end
      local ok, extractedFront, back = pcall(unpackPicture, reader, tableOffset, picIndex)
      if not ok then error(("Crystal picture %03d (%s): %s"):format(dex, speciesIds[dex], extractedFront)) end
      front = extractedFront
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
      crystalGenderRatio = reader:u8(offset + 13),
      crystalHatchCycles = reader:u8(offset + 15),
      crystalEggGroups = {
        math.floor(reader:u8(offset + 23) / 16), reader:u8(offset + 23) % 16,
      },
      crystalEggMoves = eggMovesFor(reader, eggMovePointersAt,
        eggMoveBank, dex, moveIds),
      crystalMenuIcon = assert(DaycareIcons.BY_DEX[dex]),
      crystalHeldItems = {
        common = Catalog.itemByByte[reader:u8(offset + 11)],
        rare = Catalog.itemByByte[reader:u8(offset + 12)],
      },
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
      shinyPaletteColors = shiny,
      icon = ({ GRASS="GRASS", WATER="WATER", BUG="BUG", FLYING="BIRD",
        ROCK="QUADRUPED", GROUND="QUADRUPED", DRAGON="SNAKE" })
        [Catalog.typeByByte[reader:u8(offset + 7)]] or "MON",
    }
    if opts.writePicture and front and dex ~= 201 then
      pokemon[dex].frontAnimation = extractFrontAnimation(reader, {
        animationPointers=at("animationPointers"),
        animationBank=addresses.animationPointers.bank,
        framesPointers=at("framesPointers"),
        framesBank=dex < 152 and addresses.kantoFrames.bank
          or addresses.johtoFrames.bank,
        bitmasksPointers=at("bitmasksPointers"),
        bitmasksBank=addresses.bitmasksPointers.bank,
        tableIndex=dex, stem=speciesIds[dex]:lower(), front=front,
        width=width, height=height, normalPalette=normal,
        shinyPalette=shiny, writePicture=opts.writePicture,
      })
    end
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
      row.frontAnimation = extractFrontAnimation(reader, {
        animationPointers=at("unownAnimationPointers"),
        animationBank=addresses.unownAnimationPointers.bank,
        framesPointers=at("unownFramesPointers"),
        framesBank=addresses.unownFramesPointers.bank,
        bitmasksPointers=at("unownBitmasksPointers"),
        bitmasksBank=addresses.unownBitmasksPointers.bank,
        tableIndex=form, stem="unown_" .. letter:lower(), front=front,
        width=5, height=5, normalPalette=nil, shinyPalette=shiny,
        writePicture=opts.writePicture,
      })
      unownForms[#unownForms + 1] = row
    end
  end


  local eggAssets = {
    front = "crystal_251/generated/egg/front.png",
    icon = "crystal_251/generated/egg/icon.png",
  }
  if opts.writePicture then
    -- EggPic is the same transposed, compressed animated-front format as
    -- species front pictures. Only the first 5x5 tile frame is the resting
    -- stats-screen image; pictureImage deliberately ignores the later frames.
    local eggFront = LZ.decompress(reader.raw, at("eggPic") + 1)
    opts.writePicture(eggAssets.front, eggFront, 5, 5, nil, "columns", "egg")

    -- Crystal's EggIcon is a normal two-frame 16x32 sheet. Gen1Recomp's
    -- party icon animation can ask for frames 0, 1, 2 or 3 based on the
    -- hidden hatchling species, so repeat the two real frames once. This
    -- keeps every possible source rect inside the imported image without
    -- inventing any art or exposing the hidden species icon.
    local icon = reader:bytes(at("eggIcon"), 8 * 16)
    local fourFrames = {}
    for copyIndex = 0, 1 do
      for i = 1, #icon do fourFrames[copyIndex * #icon + i] = icon[i] end
    end
    opts.writePicture(eggAssets.icon, fourFrames, 2, 8, nil, "rows", "egg_icon")
  end

  local iconTable = at("iconPointers")
  local iconBank = assert(addresses.iconPointers).bank
  local daycareIconAssets = {}
  for iconIndex = 1, DaycareIcons.MAX_INDEX do
    local path = ("crystal_251/generated/daycare_icons/%02d.png"):format(iconIndex)
    daycareIconAssets[iconIndex] = path
    if opts.writePicture then
      local twoFrames = unpackOverworldIcon(reader, iconTable, iconIndex, iconBank)
      local sheet = {}
      -- SpriteRenderer expects stand-down/up/left followed by walk-down/up/left.
      -- Crystal menu icons are directionless, so repeat frame 1 for the three
      -- standing poses and frame 2 for the three walking poses. NPC movement
      -- then uses the ROM's real second animation frame while each boarder walks.
      for copyIndex = 1, 3 do
        for i = 1, 4 * 16 do sheet[#sheet + 1] = twoFrames[i] end
      end
      for copyIndex = 1, 3 do
        for i = 4 * 16 + 1, 8 * 16 do sheet[#sheet + 1] = twoFrames[i] end
      end
      opts.writePicture(path, sheet, 2, 12, nil, "rows", "daycare_icon")
    end
  end

  local overworldSprites = {
    lugia = "crystal_251/generated/overworld/lugia.png",
    hoOh = "crystal_251/generated/overworld/ho_oh.png",
  }
  if opts.writePicture then
    -- Keep the sanctuary paths stable while the Day Care uses the complete
    -- icon set above.
    opts.writePicture(overworldSprites.hoOh,
      unpackOverworldIcon(reader, iconTable, 33, iconBank), 2, 4,
      nil, "rows", "overworld")
    opts.writePicture(overworldSprites.lugia,
      unpackOverworldIcon(reader, iconTable, 34, iconBank), 2, 4,
      nil, "rows", "overworld")
  end

  local cries = {}
  local cryPointers = at("cryPointers")
  local cryData = at("pokemonCries")
  for dex = 1, 251 do
    local row = cryData + (dex - 1) * 6
    local cryIndex = reader:u16(row)
    assert(cryIndex >= 0 and cryIndex < 69,
      "invalid Crystal cry index for " .. speciesIds[dex])
    local pointer = cryPointers + cryIndex * 3
    local path = "crystal_251/generated/cries/"
      .. speciesIds[dex]:lower() .. ".wav"
    local definition = {
      path=path,
      header={ bank=reader:u8(pointer), address=reader:u16(pointer + 1), engine=1 },
      pitch=reader:s16(row + 2), length=reader:u16(row + 4), index=cryIndex,
    }
    definition.chip = require("mods.CRYSTAL_251.lib.crystal_cry")
      .chip(raw, definition)
    cries[dex] = definition
    if opts.writeCry then opts.writeCry(path, definition) end
  end

  return {
    schema = 24, revision = revision.id, species = pokemon, moves = moves,
    cries = cries,
    unownForms = unownForms, overworldSprites = overworldSprites,
    daycareIconAssets = daycareIconAssets, eggAssets = eggAssets,
    fingerprint = revision.id .. ":251:251:v21",
  }
end

Extractor._test = {
  Reader=Reader,
  parsePicAnimationScript=parsePicAnimationScript,
  animationFrame=animationFrame,
  validCryHeader=validCryHeader,
  findCryPointers=findCryPointers,
}

return Extractor
