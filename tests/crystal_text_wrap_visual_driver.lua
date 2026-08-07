-- Visual regression sweep for CRYSTAL_251 battle-text soft wrapping.
--
-- Run from the Gen1Recomp repository root:
--   rm -rf /tmp/crystal251-wrap-visual
--   POKEPORT_DRIVER=mods/CRYSTAL_251/tests/crystal_text_wrap_visual_driver.lua \
--   SHOT_DIR=/tmp/crystal251-wrap-visual POKEPORT_SPEED=20 love .
--
-- The driver exhaustively audits every 1-251 move name against every 1-251
-- Pokemon name on both sides for move-use text, plus Crystal's generated
-- status/effect/residual/switch/trap/item messages. Every candidate that
-- needs a soft wrap is written to wrap-audit.tsv. Screenshots are generated
-- once per distinct wrap geometry, so visual coverage stays manageable.
-- Set WRAP_VIS_LIMIT=0 to capture every distinct geometry (default 200).

return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Font = require("src.render.Font")
  local Wrap = require("mods.CRYSTAL_251.battle.crystal_text_wrap")

  local dir = os.getenv("SHOT_DIR") or "/tmp/crystal251-wrap-visual"
  local limit = tonumber(os.getenv("WRAP_VIS_LIMIT") or "200") or 200
  limit = math.max(0, math.floor(limit))

  local function shellQuote(value)
    return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
  end
  assert(os.execute("mkdir -p " .. shellQuote(dir)), "could not create SHOT_DIR")

  local function glyphCount(text)
    local spans = Font.split and Font.split(text or "") or nil
    return spans and #spans or #(text or "")
  end

  local function fit(text, cols)
    text = tostring(text or ""):gsub("[\n\v]", " ")
    local spans = Font.split and Font.split(text) or nil
    if not spans or #spans <= cols then return text end
    local cut = spans[cols] and spans[cols].to or cols
    return text:sub(1, cut - 1) .. "."
  end

  local function splitWrapped(text)
    local lines, controls = {}, {}
    local pos, control = 1, "start"
    while true do
      local marker = text:find("[\n\v]", pos)
      lines[#lines + 1] = marker and text:sub(pos, marker - 1) or text:sub(pos)
      controls[#controls + 1] = control
      if not marker then break end
      control = text:sub(marker, marker) == "\v" and "cont" or "line"
      pos = marker + 1
    end
    return lines, controls
  end

  local function printable(text)
    return tostring(text or ""):gsub("\v", "\\v"):gsub("\n", "\\n")
      :gsub("\t", " ")
  end

  local function tsv(text)
    return printable(text):gsub("\r", " "):gsub("\t", " ")
  end

  -- The generated Gen I tables are keyed by stable string ids, and not every
  -- record carries a numeric index. The first visual tester incorrectly
  -- discarded those records, which turned a real 151-species runtime into
  -- only 124 collected names. For a text-layout sweep we only need the id and
  -- display name, so collect every named record and deduplicate by stable id.
  local function collectNamed(tableValue)
    local rows, seen = {}, {}
    for key, def in pairs(tableValue or {}) do
      if type(def) == "table" then
        local id = tostring(def.id or key)
        local name = def.name or def.displayName
        if type(name) == "string" and name ~= "" and not seen[id] then
          seen[id] = true
          rows[#rows + 1] = {
            index = tonumber(def.index),
            id = id,
            name = name,
          }
        end
      end
    end
    table.sort(rows, function(a, b)
      if a.index and b.index and a.index ~= b.index then return a.index < b.index end
      if a.index and not b.index then return true end
      if b.index and not a.index then return false end
      return a.id < b.id
    end)
    return rows
  end

  -- The visual audit only needs display names. A normal headless boot may
  -- legitimately have only Red's 151 species / 165 moves when the user's
  -- Crystal ROM cache has not been imported yet. Do not make the visual
  -- regression suite depend on that cache: complete the two name tables with
  -- Crystal's canonical ROM strings (pret/pokecrystal data/*/names.asm).
  local CRYSTAL_SPECIES_152_251 = {
    "CHIKORITA", "BAYLEEF", "MEGANIUM", "CYNDAQUIL", "QUILAVA", "TYPHLOSION", "TOTODILE",
    "CROCONAW", "FERALIGATR", "SENTRET", "FURRET", "HOOTHOOT", "NOCTOWL", "LEDYBA", "LEDIAN",
    "SPINARAK", "ARIADOS", "CROBAT", "CHINCHOU", "LANTURN", "PICHU", "CLEFFA", "IGGLYBUFF",
    "TOGEPI", "TOGETIC", "NATU", "XATU", "MAREEP", "FLAAFFY", "AMPHAROS", "BELLOSSOM",
    "MARILL", "AZUMARILL", "SUDOWOODO", "POLITOED", "HOPPIP", "SKIPLOOM", "JUMPLUFF", "AIPOM",
    "SUNKERN", "SUNFLORA", "YANMA", "WOOPER", "QUAGSIRE", "ESPEON", "UMBREON", "MURKROW",
    "SLOWKING", "MISDREAVUS", "UNOWN", "WOBBUFFET", "GIRAFARIG", "PINECO", "FORRETRESS",
    "DUNSPARCE", "GLIGAR", "STEELIX", "SNUBBULL", "GRANBULL", "QWILFISH", "SCIZOR", "SHUCKLE",
    "HERACROSS", "SNEASEL", "TEDDIURSA", "URSARING", "SLUGMA", "MAGCARGO", "SWINUB",
    "PILOSWINE", "CORSOLA", "REMORAID", "OCTILLERY", "DELIBIRD", "MANTINE", "SKARMORY",
    "HOUNDOUR", "HOUNDOOM", "KINGDRA", "PHANPY", "DONPHAN", "PORYGON2", "STANTLER", "SMEARGLE",
    "TYROGUE", "HITMONTOP", "SMOOCHUM", "ELEKID", "MAGBY", "MILTANK", "BLISSEY", "RAIKOU",
    "ENTEI", "SUICUNE", "LARVITAR", "PUPITAR", "TYRANITAR", "LUGIA", "HO-OH", "CELEBI"
  }

  local CRYSTAL_MOVES_166_251 = {
    "SKETCH", "TRIPLE KICK", "THIEF", "SPIDER WEB", "MIND READER", "NIGHTMARE", "FLAME WHEEL",
    "SNORE", "CURSE", "FLAIL", "CONVERSION2", "AEROBLAST", "COTTON SPORE", "REVERSAL", "SPITE",
    "POWDER SNOW", "PROTECT", "MACH PUNCH", "SCARY FACE", "FAINT ATTACK", "SWEET KISS",
    "BELLY DRUM", "SLUDGE BOMB", "MUD-SLAP", "OCTAZOOKA", "SPIKES", "ZAP CANNON", "FORESIGHT",
    "DESTINY BOND", "PERISH SONG", "ICY WIND", "DETECT", "BONE RUSH", "LOCK-ON", "OUTRAGE",
    "SANDSTORM", "GIGA DRAIN", "ENDURE", "CHARM", "ROLLOUT", "FALSE SWIPE", "SWAGGER",
    "MILK DRINK", "SPARK", "FURY CUTTER", "STEEL WING", "MEAN LOOK", "ATTRACT", "SLEEP TALK",
    "HEAL BELL", "RETURN", "PRESENT", "FRUSTRATION", "SAFEGUARD", "PAIN SPLIT", "SACRED FIRE",
    "MAGNITUDE", "DYNAMICPUNCH", "MEGAHORN", "DRAGONBREATH", "BATON PASS", "ENCORE", "PURSUIT",
    "RAPID SPIN", "SWEET SCENT", "IRON TAIL", "METAL CLAW", "VITAL THROW", "MORNING SUN",
    "SYNTHESIS", "MOONLIGHT", "HIDDEN POWER", "CROSS CHOP", "TWISTER", "RAIN DANCE",
    "SUNNY DAY", "CRUNCH", "MIRROR COAT", "PSYCH UP", "EXTREMESPEED", "ANCIENTPOWER",
    "SHADOW BALL", "FUTURE SIGHT", "ROCK SMASH", "WHIRLPOOL", "BEAT UP"
  }

  local function idFromDisplay(name)
    local overrides = {
      ["NIDORAN♀"] = "NIDORAN_F", ["NIDORAN♂"] = "NIDORAN_M",
      ["FARFETCH'D"] = "FARFETCHD", ["MR.MIME"] = "MR_MIME",
      ["HO-OH"] = "HO_OH",
    }
    if overrides[name] then return overrides[name] end
    return tostring(name):upper():gsub("[^%w]+", "_"):gsub("^_+", ""):gsub("_+$", "")
  end

  local function completeCanonical(rows, names)
    local seenId, seenName = {}, {}
    for _, row in ipairs(rows) do
      seenId[row.id] = true
      seenName[row.name] = true
    end
    local usedFallback = false
    for _, name in ipairs(names) do
      local id = idFromDisplay(name)
      if not seenId[id] and not seenName[name] then
        rows[#rows + 1] = { id = id, name = name }
        seenId[id], seenName[name] = true, true
        usedFallback = true
      end
    end
    return usedFallback
  end

  local species = collectNamed(game.data and game.data.pokemon)
  local moves = collectNamed(game.data and game.data.moves)
  local runtimeSpeciesCount, runtimeMoveCount = #species, #moves
  local speciesFallback = completeCanonical(species, CRYSTAL_SPECIES_152_251)
  local movesFallback = completeCanonical(moves, CRYSTAL_MOVES_166_251)

  -- Do not abort a visual run before it can produce diagnostics. The normal
  -- Red-data boot is expected to reach exactly 251/251 after the canonical
  -- additions; if a future engine changes the generated table shape, record
  -- the discrepancy and still render every name we could collect.
  if #species ~= 251 then
    print(("[wrap-visual] WARNING: expected 251 Pokemon names, got %d "
      .. "(runtime supplied %d)"):format(#species, runtimeSpeciesCount))
  end
  if #moves ~= 251 then
    print(("[wrap-visual] WARNING: expected 251 move names, got %d "
      .. "(runtime supplied %d)"):format(#moves, runtimeMoveCount))
  end

  local report = assert(io.open(dir .. "/wrap-audit.tsv", "w"))
  report:write("category\tsource\traw\twrapped\tline_glyphs\n")

  local candidates, wrappedCount = 0, 0
  local visuals, seenGeometry = {}, {}

  local function geometry(category, wrapped)
    local lines, controls = splitWrapped(wrapped)
    local lengths = {}
    for i, line in ipairs(lines) do
      lengths[#lengths + 1] = tostring(glyphCount(line))
        .. (controls[i] == "cont" and "c" or "")
    end
    local shapes = {}
    for _, line in ipairs(lines) do
      shapes[#shapes + 1] = line:gsub("[^ ]", "X")
    end
    return category .. "|" .. table.concat(lengths, ",")
      .. "|" .. table.concat(shapes, "/")
  end

  local function add(category, source, raw, forceVisual)
    candidates = candidates + 1
    local wrapped = Wrap.wrap(raw, 18)
    if wrapped == raw then return end
    wrappedCount = wrappedCount + 1
    local lines = splitWrapped(wrapped)
    local lens = {}
    for _, line in ipairs(lines) do lens[#lens + 1] = glyphCount(line) end
    report:write(tsv(category), "\t", tsv(source), "\t", tsv(raw), "\t",
      tsv(wrapped), "\t", table.concat(lens, ","), "\n")

    local key = geometry(category, wrapped)
    if forceVisual or not seenGeometry[key] then
      if not seenGeometry[key] then seenGeometry[key] = true end
      if limit == 0 or #visuals < limit or forceVisual then
        visuals[#visuals + 1] = {
          category = category,
          source = source,
          raw = raw,
          wrapped = wrapped,
          lines = lines,
          forced = forceVisual and true or false,
        }
      end
    end
  end

  -- Always put the four reported regressions at the front of the visual set.
  add("reported/paralysis", "synthetic Pokemon", "Pokemon is fully paralyzed!", true)
  add("reported/encore", "synthetic Pokemon", "Pokemon got an ENCORE!", true)
  add("reported/rage", "DUNSPARCE", "DUNSPARCE's RAGE is building!", true)
  add("reported/burn", "synthetic Enemy Pokemon",
    "Enemy Pokemon\nis hurt by its burn!", true)

  local nameTemplates = {
    { "status/woke", function(n) return n .. " woke up!" end },
    { "status/asleep", function(n) return n .. " is fast asleep!" end },
    { "status/frozen", function(n) return n .. " is frozen solid!" end },
    { "status/flinch", function(n) return n .. " flinched!" end },
    { "status/disable-ended", function(n) return n .. " is disabled no more!" end },
    { "status/confusion-ended", function(n) return n .. " snapped out of confusion!" end },
    { "status/confused", function(n) return n .. " is confused!" end },
    { "status/paralysis", function(n) return n .. " is fully paralyzed!" end },
    { "residual/poison", function(n) return n .. "\nis hurt by poison!" end },
    { "residual/burn", function(n) return n .. "\nis hurt by its burn!" end },
    { "residual/leech-seed", function(n) return "LEECH SEED\nsapped " .. n .. "!" end },
    { "residual/nightmare", function(n) return n .. "\nis locked in a\nNIGHTMARE!" end },
    { "residual/curse", function(n) return n .. "\nis afflicted by\nthe CURSE!" end },
    { "status/confusion-inflict", function(n) return n .. " became confused!" end },
    { "status/substitute-existing", function(n) return n .. " already has a SUBSTITUTE!" end },
    { "status/substitute-made", function(n) return n .. " made a SUBSTITUTE!" end },
    { "status/rest", function(n) return n .. " went to sleep and became healthy!" end },
    { "status/leech-seed", function(n) return n .. " was seeded!" end },
    { "status/safeguard", function(n) return n .. " is protected by SAFEGUARD!" end },
    { "status/mist", function(n) return n .. " became shrouded in mist!" end },
    { "status/focus-energy", function(n) return n .. " is getting pumped!" end },
    { "status/mean-look", function(n) return n .. " can't escape now!" end },
    { "status/nightmare", function(n) return n .. " began having a NIGHTMARE!" end },
    { "status/attract", function(n) return n .. " fell in love!" end },
    { "status/rapid-spin", function(n) return n .. " blew away trapping effects!" end },
    { "status/perish", function(n) return n .. "'s perish count fell to 3!" end },
    { "status/defrost", function(n) return n .. " was defrosted!" end },
    { "status/encore-ended", function(n) return n .. "'s ENCORE ended!" end },
    { "weather/sandstorm-hit", function(n) return n .. " is buffeted by the sandstorm!" end },
    { "switch/roar", function(n) return n .. " was blown away!" end },
    { "switch/whirlwind", function(n) return n .. " ran away scared!" end },
    { "switch/dragged", function(n) return n .. " was dragged out!" end },
    { "switch/baton-pass", function(n) return n .. " was passed the battle!" end },
    { "special/recovered", function(n) return n .. " regained health!" end },
    { "special/future-sight", function(n) return n .. " foresaw an attack!" end },
    { "special/bide-store", function(n) return n .. " is storing energy!" end },
    { "special/bide-release", function(n) return n .. " unleashed energy!" end },
    { "special/miss", function(n) return n .. "'s attack missed!" end },
    { "item/focus-band", function(n) return n .. " hung on with FOCUS BAND!" end },
    { "item/berserk-gene", function(n) return n .. "'s BERSERK GENE activated!" end },
    { "obedience/sleep", function(n) return n .. " ignored orders...sleeping!" end },
    { "obedience/ignored", function(n) return n .. " ignored orders!" end },
    { "obedience/nap", function(n) return n .. " began to nap!" end },
    { "obedience/no", function(n) return n .. " won't obey!" end },
    { "obedience/loaf", function(n) return n .. " is loafing around!" end },
    { "obedience/turned", function(n) return n .. " turned away!" end },
  }

  for _, mon in ipairs(species) do
    local names = { mon.name, "Enemy " .. mon.name }
    for _, display in ipairs(names) do
      for _, row in ipairs(nameTemplates) do
        add(row[1], mon.id .. "/" .. display, row[2](display))
      end
    end
  end

  -- Every move against every species on both sides. This is intentionally
  -- exhaustive: move names with spaces can choose a different word boundary
  -- even when their character count matches another move.
  for _, mon in ipairs(species) do
    for _, move in ipairs(moves) do
      add("move/use-player", mon.id .. "/" .. move.id,
        mon.name .. "\nused " .. move.name .. "!")
      add("move/use-enemy", mon.id .. "/" .. move.id,
        "Enemy " .. mon.name .. "\nused " .. move.name .. "!")
    end
  end

  -- Move-name-bearing Crystal status/trap text.
  for _, move in ipairs(moves) do
    add("move/disabled-now", move.id, move.name .. " is disabled!")
    add("move/disabled-set", move.id, move.name .. " was disabled!")
  end
  local trapMoves = { "BIND", "WRAP", "FIRE_SPIN", "CLAMP", "WHIRLPOOL" }
  local byMove = {}
  for _, move in ipairs(moves) do byMove[move.id] = move.name end
  for _, mon in ipairs(species) do
    for _, moveId in ipairs(trapMoves) do
      local moveName = byMove[moveId] or moveId
      for _, display in ipairs({ mon.name, "Enemy " .. mon.name }) do
        add("trap/damage", mon.id .. "/" .. moveId,
          display .. "'s\nhurt by\n" .. moveName .. "!")
        add("trap/released", mon.id .. "/" .. moveId,
          display .. "\nwas released from\n" .. moveName .. "!")
      end
    end
  end

  -- A few dynamic non-name strings that can still cross the boundary.
  for _, text in ipairs({
    "SPIKES scattered all around!",
    "Both Pokemon will faint in 3 turns!",
    "Too weak to make a SUBSTITUTE!",
    "It hurt itself in its confusion!",
    "The future attack struck Enemy WOBBUFFET!",
    "But no PP is left for the move!",
    "It's not very effective...",
  }) do
    add("fixed", text, text)
  end

  report:close()

  -- Forced examples must remain first; sort only the automatically-selected
  -- geometry representatives that follow them.
  local forced = {}
  local automatic = {}
  for _, case in ipairs(visuals) do
    if case.forced then forced[#forced + 1] = case else automatic[#automatic + 1] = case end
  end
  table.sort(automatic, function(a, b)
    if a.category ~= b.category then return a.category < b.category end
    return a.source < b.source
  end)
  visuals = forced
  for _, case in ipairs(automatic) do visuals[#visuals + 1] = case end

  local summary = assert(io.open(dir .. "/summary.txt", "w"))
  summary:write(("Candidates audited: %d\nWrapping combinations: %d\nVisual geometries: %d\n")
    :format(candidates, wrappedCount, #visuals))
  summary:write("Classic width: 18 glyph cells\n")
  summary:write(("Names audited: %d Pokemon / %d moves "
    .. "(runtime supplied %d / %d)\n")
    :format(#species, #moves, runtimeSpeciesCount, runtimeMoveCount))
  summary:write(("Name source: %s Pokemon / %s moves\n"):format(
    speciesFallback and "runtime + canonical Crystal fallback" or "runtime Crystal data",
    movesFallback and "runtime + canonical Crystal fallback" or "runtime Crystal data"))
  summary:write("Full combination list: wrap-audit.tsv\n")
  summary:close()

  local Viewer = { isOpaque=true, letterboxWhite=true }
  Viewer.__index = Viewer
  function Viewer:update() end
  function Viewer:draw()
    love.graphics.clear(1, 1, 1, 1)
    love.graphics.setColor(0, 0, 0, 1)
    local case = self.case
    Font.draw(("WRAP %03d/%03d"):format(self.index or 0, self.total or 0), 8, 8)
    Font.draw(fit(case and case.category or "", 18), 8, 24)
    Font.draw(fit(case and case.source or "", 18), 8, 40)
    Font.draw("18-COL BOUNDARY", 8, 64)
    -- Interior text area is x=8..151 (18 8px cells). The guide marks the
    -- first pixel outside it; any glyph crossing this line is a visual fail.
    love.graphics.setColor(0.65, 0.65, 0.65, 1)
    love.graphics.line(152, 80, 152, 143)
    love.graphics.setColor(0, 0, 0, 1)
    Font.drawBox(0, 12, 20, 6)
    local lines = case and case.window or { "", "" }
    for row = 1, math.min(2, #lines) do
      Font.draw(lines[row], 8, row == 1 and 112 or 128)
    end
  end

  while game.stack:top() do game.stack:pop() end
  local viewer = setmetatable({}, Viewer)
  game.stack:push(viewer)
  U.wait(2)

  local shotCount = 0
  local function safeName(value)
    value = tostring(value or "case"):lower():gsub("[^%w]+", "-"):gsub("^-", ""):gsub("-$", "")
    if #value > 42 then value = value:sub(1, 42) end
    return value ~= "" and value or "case"
  end

  -- Render every rolling two-line window. Three-line messages therefore get
  -- two captures, matching what the real battle box displays before/after its
  -- automatic scroll.
  for index, case in ipairs(visuals) do
    local lines = case.lines
    local windows = math.max(1, #lines - 1)
    for window = 1, windows do
      local first = #lines == 1 and 1 or window
      case.window = { lines[first] or "", lines[first + 1] or "" }
      viewer.case = case
      viewer.index = index
      viewer.total = #visuals
      U.wait(1)
      shotCount = shotCount + 1
      local filename = ("%04d-%s-%s-w%d.png"):format(shotCount,
        safeName(case.category), safeName(case.source), window)
      U.shot(game, dir .. "/" .. filename)
    end
  end

  print(("[driver] PASS Crystal text-wrap visual audit: %d candidates, %d wrapping, %d screenshots under %s")
    :format(candidates, wrappedCount, shotCount, dir))
end
