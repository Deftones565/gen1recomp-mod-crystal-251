package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")

local path = os.getenv("CRYSTAL_ROM")
  or "Pokemon - Crystal Version (UE) (V1.1) [C][!].gbc"
local file = io.open(path, "rb")
if not file then
  print("SKIP Crystal move animation runtime (set CRYSTAL_ROM to a supported ROM)")
  os.exit(0)
end
local raw = file:read("*a")
file:close()

local run, cache = require("mods.CRYSTAL_251.tests._real_rom_mod").load(T, raw)
local Data = run.data

local checks, failures = 0, 0
local function check(value, message)
  checks = checks + 1
  if not value then
    failures = failures + 1
    io.stderr:write("FAIL " .. message .. "\n")
  end
  return value
end

check(#run.errors == 0, "CRYSTAL_251 loads without errors")

local data = run.data
local animData = data and data.battle_anims
check(type(animData) == "table", "merged battle animation data exists")
check(type(animData and animData.moveAnims) == "table", "merged move animation table exists")
check(type(animData and animData.subanims) == "table", "merged subanimation table exists")
check(type(animData and animData.frameBlocks) == "table", "merged frame-block table exists")
check(type(animData and animData.baseCoords) == "table", "merged base-coordinate table exists")
check(type(animData and animData.tilesheets) == "table", "merged animation tilesheet table exists")

local AnimPlayer = require("src.battle.AnimPlayer")
local BattleState = require("src.battle.BattleState")
local Pokemon = require("src.pokemon.Pokemon")
local SaveData = require("src.core.SaveData")

local moves = { "TACKLE", "WRAP", "SHADOW_BALL", "SANDSTORM" }

local function inspectDefinition(id)
  local definition = animData and animData.moveAnims and animData.moveAnims[id]
  if not check(type(definition) == "table", id .. " has a merged move animation") then return end
  if not check(type(definition.seq) == "table", id .. " animation has a sequence") then return end
  check(#definition.seq > 0, id .. " animation sequence is not empty")
  for rowIndex, row in ipairs(definition.seq) do
    if not row.effect then
      local sub = animData.subanims[row.subanim]
      if check(type(sub) == "table",
          id .. " row " .. rowIndex .. " references subanimation " .. tostring(row.subanim)) then
        check(type(animData.tilesheets[row.tileset]) == "table",
          id .. " row " .. rowIndex .. " references tilesheet " .. tostring(row.tileset))
        for blockIndex, entry in ipairs(sub.blocks or {}) do
          check(type(animData.frameBlocks[entry.block]) == "table",
            id .. " subanimation block " .. blockIndex .. " references frame block "
              .. tostring(entry.block))
          check(type(animData.baseCoords[entry.coord]) == "table",
            id .. " subanimation block " .. blockIndex .. " references coordinate "
              .. tostring(entry.coord))
        end
      end
    end
  end
  local player = AnimPlayer.new(animData)
  local started, err = pcall(player.start, player, id, true)
  if check(started, id .. " AnimPlayer start succeeds" .. (err and ": " .. tostring(err) or "")) then
    check(#player.steps > 0, id .. " AnimPlayer compiles visible timed steps")
  end
end

for _, id in ipairs(moves) do inspectDefinition(id) end

local function makeGame(moveId)
  local save = SaveData.newGame()
  save.options = save.options or {}
  save.options.animations = true
  save.party = { Pokemon.new(data, "MEW", 50, function() return 15 end) }
  save.party[1].moves = { { id = moveId, pp = data.moves[moveId].pp or 20 } }
  local stack = { states = {} }
  function stack:push(state) self.states[#self.states + 1] = state end
  function stack:pop() return table.remove(self.states) end
  function stack:top() return self.states[#self.states] end
  return {
    data = data,
    save = save,
    stack = stack,
    input = { wasPressed = function() return false end },
  }
end

local function inspectQueue(id)
  local game = makeGame(id)
  local battle = BattleState.newWild(game, "MEW", 50)
  battle.queue = {}
  battle.nextInsert = 0
  battle.rng = function(a) return a or 0 end
  battle.player.mon.hp = 1000
  battle.player.mon.stats.hp = 1000
  battle.enemy.mon.hp = 1000
  battle.enemy.mon.stats.hp = 1000
  battle:performMove(battle.player, battle.enemy,
    { id = id, pp = data.moves[id].pp or 20 }, false)
  check(battle:animationsOn(), id .. " runtime has battle animations enabled")
  local row
  for _, queued in ipairs(battle.queue) do
    if queued.anim == id then row = queued break end
  end
  check(row ~= nil, id .. " performMove queues its move animation row")
  check(battle.animPlayer ~= nil, id .. " battle constructed an AnimPlayer")
  if battle.animPlayer then
    local started, err = pcall(battle.animPlayer.start, battle.animPlayer, id, true)
    if check(started, id .. " live battle AnimPlayer starts" .. (err and ": " .. tostring(err) or "")) then
      check(#battle.animPlayer.steps > 0, id .. " live battle animation has drawable steps")
    end
  end
end

for _, id in ipairs(moves) do inspectQueue(id) end

if failures > 0 then
  io.stderr:write(("%d/%d checks failed (Crystal move animation runtime)\n")
    :format(failures, checks))
  os.exit(1)
end

print(("%d/%d checks passed (Crystal move animation runtime)"):format(checks, checks))
