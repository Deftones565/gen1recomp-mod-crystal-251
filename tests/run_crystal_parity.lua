package.path = "./?.lua;./?/init.lua;" .. package.path

local suites = {
  "crystal_acquisition_capture_test.lua",
  "crystal_actions_test.lua",
  "crystal_ai_test.lua",
  "crystal_all_items_audit_test.lua",
  "crystal_auto_import_test.lua",
  "crystal_backport_integration_test.lua",
  "crystal_classic_effects_test.lua",
  "crystal_command_interpreter_test.lua",
  "crystal_cry_test.lua",
  "crystal_damage_test.lua",
  "crystal_daycare_test.lua",
  "crystal_exhaustive_parity_test.lua",
  "crystal_exp_share_test.lua",
  "crystal_fast_import_test.lua",
  "crystal_full_battle_test.lua",
  "crystal_gen3_ui_compat_test.lua",
  "crystal_gender_test.lua",
  "crystal_held_item_management_test.lua",
  "crystal_held_items_test.lua",
  "crystal_import_visibility_test.lua",
  "crystal_integration_cleanup_test.lua",
  "crystal_item_behaviors_test.lua",
  "crystal_item_progression_test.lua",
  "crystal_machine_full_audit_test.lua",
  "crystal_machine_progression_test.lua",
  "crystal_modes_test.lua",
  "crystal_move_animation_runtime_test.lua",
  "crystal_multi_turn_test.lua",
  "crystal_patch_coverage_test.lua",
  "crystal_presentation_test.lua",
  "crystal_progression_test.lua",
  "crystal_registry_compat_test.lua",
  "crystal_runtime_lifecycle_test.lua",
  "crystal_scheduler_test.lua",
  "crystal_secondary_effect_audit_test.lua",
  "crystal_special_damage_test.lua",
  "crystal_special_evolution_test.lua",
  "crystal_stats_test.lua",
  "crystal_status_test.lua",
  "crystal_summary_test.lua",
  "crystal_switching_test.lua",
  "crystal_text_wrap_test.lua",
  "crystal_tmhm_items_test.lua",
  "crystal_trades_yellow_test.lua",
  "crystal_type_effectiveness_audit_test.lua",
  "extractor_test.lua",
  "import_screen_test.lua",
  "integration_test.lua",
  "lz_test.lua",
  "move_parity_edge_test.lua",
  "move_parity_test.lua",
  "visual_sprite_test.lua",
}

local lua = os.getenv("LUAJIT_BIN") or "luajit"
local root = "mods/CRYSTAL_251/tests/"
local passed, failures = 0, {}
local rom = os.getenv("CRYSTAL_ROM")
  or "Pokemon - Crystal Version (UE) (V1.1) [C][!].gbc"
local romFile = io.open(rom, "rb")
if not romFile then
  io.stderr:write("Crystal verification requires a supported ROM. Set CRYSTAL_ROM; ROM skips are not a passing run.\n")
  os.exit(1)
end
romFile:close()
local function quote(value) return "'" .. value:gsub("'", "'\"'\"'") .. "'" end
local function success(a,b,c)
  if type(a)=="number" then return a==0 end
  return a==true and (b~="exit" or c==0)
end
for index,suite in ipairs(suites) do
  io.write(("[%d/%d] %s\n"):format(index,#suites,suite)); io.flush()
  local log=os.tmpname()
  local a,b,c=os.execute(quote(lua).." "..quote(root..suite).." >"..quote(log).." 2>&1")
  local f=assert(io.open(log,"rb")); local output=f:read("*a"); f:close(); os.remove(log)
  io.write(output)
  if not success(a,b,c) or output:find("SKIP",1,true) then
    failures[#failures+1]=suite
  else passed=passed+1 end
end
print(("%d/%d required Crystal suites passed"):format(passed,#suites))
print("Not included: two optional STADIUM2_IMPORTER integration suites and interactive visual drivers.")
if #failures>0 then
  io.stderr:write("Failed or skipped required suites: "..table.concat(failures,", ").."\n")
  os.exit(1)
end
