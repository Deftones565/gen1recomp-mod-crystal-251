package.path = "./?.lua;./?/init.lua;" .. package.path

local Progression = require("mods.CRYSTAL_251.machine_progression")

local checks, passed = 0, 0
local function check(value, message)
  checks = checks + 1
  if not value then error(message, 0) end
  passed = passed + 1
end
local function eq(actual, expected, message)
  check(actual == expected, ("%s: expected %s, got %s")
    :format(message, tostring(expected), tostring(actual)))
end

local maps = {
  ROCKET_HIDEOUT_B4F={ objects={ {index=1}, {index=4}, {index=9} } },
  SEAFOAM_ISLANDS_B4F={ objects={ {index=1}, {index=2}, {index=3} } },
}
local scripts, screens = {}, {}
local previousNewCalls = 0
screens.MoveLearnMenu = {
  new=function(...)
    previousNewCalls = previousNewCalls + 1
    local menu = require("src.ui.MoveLearnMenu").new(...)
    menu.compatMarker = "preserved"
    return menu
  end,
}
local mapRegistry = {}
function mapRegistry:get(id) return maps[id] end
function mapRegistry:patch(id, partial)
  local append = partial.objects and partial.objects.__append or {}
  maps[id].objects = maps[id].objects or {}
  for _, row in ipairs(append) do maps[id].objects[#maps[id].objects + 1] = row end
end
local scriptRegistry = {}
function scriptRegistry:register(id, def) scripts[id] = def end
local screenRegistry = {}
function screenRegistry:get(id) return screens[id] end
function screenRegistry:register(id, def)
  assert(screens[id] == nil, id .. " already registered")
  screens[id] = def
end
function screenRegistry:override(id, def) screens[id] = def end

local result = Progression.install({ content={ maps=mapRegistry,
  map_scripts=scriptRegistry, screens=screenRegistry } })

local lance = maps.ROCKET_HIDEOUT_B4F.objects[#maps.ROCKET_HIDEOUT_B4F.objects]
eq(lance.index, 10, "Lance receives the next stable Rocket Hideout object index")
eq(lance.sprite, "SPRITE_LANCE", "HM06 is represented by Lance")
eq(lance.text, Progression.LANCE_TEXT, "Lance uses the mod-owned gift script")
eq(result.hm06.method, "gift", "HM06 acquisition remains a gift")

local lanceScript = scripts.ROCKET_HIDEOUT_B4F.talk[Progression.LANCE_TEXT]
local sawGiovanniGate, sawHM06, sawRewardFlag = false, false, false
for _, command in ipairs(lanceScript) do
  if command[1] == "check_flag"
      and command[2] == "EVENT_BEAT_ROCKET_HIDEOUT_GIOVANNI" then
    sawGiovanniGate = true
  elseif command[1] == "give_item" and command[2] == "HM_06" then
    sawHM06 = true
  elseif command[1] == "set_flag" and command[2] == Progression.HM06_FLAG then
    sawRewardFlag = true
  end
end
check(sawGiovanniGate, "Lance gates HM06 on the Rocket Hideout victory")
check(sawHM06, "Lance's normal dialogue gives HM06")
check(sawRewardFlag, "Lance records the one-time HM06 reward")

local waterfall = maps.SEAFOAM_ISLANDS_B4F.objects[#maps.SEAFOAM_ISLANDS_B4F.objects]
eq(waterfall.index, 4, "HM07 receives the next stable Seafoam object index")
eq(waterfall.item, "HM_07", "Seafoam item ball contains HM07")
eq(waterfall.sprite, "SPRITE_POKE_BALL", "HM07 uses normal item-ball pickup")
eq(result.hm07.method, "item_ball", "HM07 acquisition remains an ice-cave pickup")

local pushed = {}
local game = {
  input={ wasPressed=function(_, key) return key == "a" end },
  data={
    constants={ hmMoves={ "CUT", "FLY", "SURF", "STRENGTH", "FLASH",
      "WHIRLPOOL", "WATERFALL" } },
    pokemon={ TEST={ name="TEST" } },
    moves={ WATERFALL={name="WATERFALL",pp=15},
      TACKLE={name="TACKLE",pp=35}, HEADBUTT={name="HEADBUTT",pp=15} },
  },
  stack={
    push=function(_, value) pushed[#pushed + 1] = value end,
    pop=function() end,
  },
}
local mon={ species="TEST", nickname="TEST", moves={
  {id="WATERFALL",pp=15}, {id="TACKLE",pp=35},
  {id="TACKLE",pp=35}, {id="TACKLE",pp=35},
} }
local menu = screens.MoveLearnMenu.new(game, mon, "HEADBUTT", function() end)
eq(previousNewCalls, 1, "Crystal composes with an existing move-info screen")
eq(menu.compatMarker, "preserved", "existing screen behavior survives decoration")
menu.selecting, menu.index = true, 1
menu:update(0)
eq(mon.moves[1].id, "WATERFALL", "Crystal HM07 cannot be forgotten")
eq(#pushed, 1, "forgetting HM07 displays the HM refusal message")

pushed = {}
menu = screens.MoveLearnMenu.new(game, mon, "HEADBUTT", function() end)
menu.selecting, menu.index = true, 2
menu:update(0)
eq(mon.moves[2].id, "HEADBUTT", "ordinary moves remain replaceable")

print(("%d/%d checks passed (Crystal machine progression)"):format(passed, checks))
