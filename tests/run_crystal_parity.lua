package.path = "./?.lua;./?/init.lua;" .. package.path

local suites = {
  "move_parity_edge_test.lua",
  "move_parity_test.lua",
  "crystal_exhaustive_parity_test.lua",
  "crystal_full_battle_test.lua",
  "crystal_integration_cleanup_test.lua",
  "crystal_presentation_test.lua",
  "crystal_gender_test.lua",
  "crystal_daycare_test.lua",
  "crystal_progression_test.lua",
  "crystal_modes_test.lua",
  "crystal_ai_test.lua",
  "crystal_actions_test.lua",
  "crystal_scheduler_test.lua",
  "crystal_held_items_test.lua",
  "crystal_held_item_management_test.lua",
  "crystal_item_progression_test.lua",
  "crystal_damage_test.lua",
  "crystal_stats_test.lua",
  "crystal_switching_test.lua",
  "crystal_status_test.lua",
  "crystal_command_interpreter_test.lua",
  "crystal_multi_turn_test.lua",
  "crystal_special_damage_test.lua",
}

local lua = os.getenv("LUAJIT_BIN") or "luajit"
local root = "mods/CRYSTAL_251/tests/"
local passed = 0

local function success(a, b, c)
  if type(a) == "number" then return a == 0 end
  if a == true and b == "exit" then return c == 0 end
  return a == true
end

for _, suite in ipairs(suites) do
  io.write(("[%d/%d] %s\n"):format(passed + 1, #suites, suite))
  local a, b, c = os.execute(("%q %q"):format(lua, root .. suite))
  if not success(a, b, c) then
    io.stderr:write("FAIL Crystal parity suite: " .. suite .. "\n")
    os.exit(1)
  end
  passed = passed + 1
end

print(("%d/%d Crystal parity suites passed"):format(passed, #suites))
