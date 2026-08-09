package.path = "./?.lua;./?/init.lua;" .. package.path

local B = require("mods.CRYSTAL_251.item_behaviors")

local checks, failures = 0, 0
local function eq(got, want, label)
  checks = checks + 1
  if got ~= want then
    failures = failures + 1
    io.stderr:write(("FAIL %s (got %s, want %s)\n")
      :format(label, tostring(got), tostring(want)))
  end
end
local function ok(value, label) eq(not not value, true, label) end

local data = {
  pokemon={ PIKACHU={name="PIKACHU"} },
  moves={
    TACKLE={name="TACKLE",pp=35},
    SKETCH={name="SKETCH",pp=1},
  },
}
local function mon()
  return { species="PIKACHU", hp=50, status=nil, stats={hp=100},
    moves={{id="TACKLE",pp=20,ppUps=0},{id="SKETCH",pp=0,ppUps=0}} }
end

for item, amount in pairs({ BERRY=10, BERRY_JUICE=20, GOLD_BERRY=30 }) do
  local target = mon()
  local result, _, extra = B.use(data, item, target)
  eq(result, "consumed", item .. " is consumed after healing")
  eq(target.hp, 50 + amount, item .. " restores its Crystal HP amount")
  eq(extra.healedFrom, 50, item .. " reports the old HP for the UI")

  target.hp = target.stats.hp
  result = B.use(data, item, target)
  eq(result, "failed", item .. " is rejected at full HP")
  target.hp = 0
  result = B.use(data, item, target)
  eq(result, "failed", item .. " cannot revive a fainted Pokemon")
end

local statusCases = {
  PSNCUREBERRY="PSN", PRZCUREBERRY="PAR", BURNT_BERRY="FRZ",
  ICE_BERRY="BRN", MINT_BERRY="SLP",
}
for item, status in pairs(statusCases) do
  local target = mon()
  target.status = status
  local battler = {mon=target, sleepTurns=4, toxicCounter=3, nightmare=true}
  local result = B.use(data, item, target, {player=battler})
  eq(result, "consumed", item .. " cures its matching status")
  eq(target.status, nil, item .. " clears the major status")
  eq(battler.sleepTurns, nil, item .. " clears battle sleep state")

  target.status = status == "PSN" and "PAR" or "PSN"
  result = B.use(data, item, target, {player=battler})
  eq(result, "failed", item .. " rejects the wrong status")
end

do
  local target = mon()
  target.status = "PSN"
  local battler = {mon=target, confusedTurns=3, toxicCounter=4}
  local result = B.use(data, "MIRACLEBERRY", target, {player=battler})
  eq(result, "consumed", "MiracleBerry cures combined ailments")
  eq(target.status, nil, "MiracleBerry clears major status")
  eq(battler.confusedTurns, nil, "MiracleBerry clears confusion")
  eq(battler.toxicCounter, nil, "MiracleBerry clears Toxic escalation")

  battler.confusedTurns = 2
  result = B.use(data, "MIRACLEBERRY", target, {player=battler})
  eq(result, "consumed", "MiracleBerry can cure confusion alone")
end

do
  local target = mon()
  local battler = {mon=target, confusedTurns=2}
  local result = B.use(data, "BITTER_BERRY", target, {player=battler})
  eq(result, "consumed", "Bitter Berry cures confusion")
  eq(battler.confusedTurns, nil, "Bitter Berry clears confusion turns")
  result = B.use(data, "BITTER_BERRY", target, {player=battler})
  eq(result, "failed", "Bitter Berry is rejected without confusion")
end

do
  local target = mon()
  local result = B.use(data, "MYSTERYBERRY", target, nil, 1)
  eq(result, "consumed", "MysteryBerry restores selected move PP")
  eq(target.moves[1].pp, 25, "MysteryBerry restores five PP")
  target.moves[1].pp = 34
  result = B.use(data, "MYSTERYBERRY", target, nil, 1)
  eq(result, "consumed", "MysteryBerry can top off a move")
  eq(target.moves[1].pp, 35, "MysteryBerry caps PP at the maximum")
  result = B.use(data, "MYSTERYBERRY", target, nil, 1)
  eq(result, "failed", "MysteryBerry is rejected on full PP")
  result = B.use(data, "MYSTERYBERRY", target, nil, 2)
  eq(result, "consumed", "MysteryBerry works on one-PP moves")
  eq(target.moves[2].pp, 1, "MysteryBerry respects a one-PP maximum")
  result = B.use(data, "MYSTERYBERRY", target, nil, nil)
  eq(result, "failed", "MysteryBerry requires a selected move")
end

for _, item in ipairs({"BERRY","PSNCUREBERRY","BITTER_BERRY","MYSTERYBERRY"}) do
  local result = B.use(data, item, nil)
  eq(result, "failed", item .. " rejects a missing target")
  result = B.use(data, item, {isEgg=true})
  eq(result, "failed", item .. " rejects an Egg")
end

do
  local source = {grass={rate=30,slots={{species="PIDGEY",level=3}}}}
  local seen
  local function capture(def) seen=def return "rolled" end
  local save = {party={{heldItem="CLEANSE_TAG"}}}
  eq(B.cleanseEncounter(capture, source, {save=save}), "rolled",
    "Cleanse Tag continues the encounter chain")
  eq(seen.grass.rate, 15, "Cleanse Tag halves the encounter rate")
  eq(source.grass.rate, 30, "Cleanse Tag does not mutate the source encounter")
  ok(seen.grass.slots == source.grass.slots,
    "Cleanse Tag preserves the encounter slots")

  save.party[1].heldItem = nil
  save.party[2] = {heldItem="CLEANSE_TAG"}
  B.cleanseEncounter(capture, source, {save=save})
  eq(seen.grass.rate, 15, "Cleanse Tag works from any party slot")
  save.party[2].heldItem = nil
  B.cleanseEncounter(capture, source, {save=save})
  ok(seen == source, "encounter rate is unchanged without Cleanse Tag")
end

if failures > 0 then
  io.stderr:write(("%d/%d checks failed (Crystal item behaviors)\n")
    :format(failures, checks))
  os.exit(1)
end
print(("%d/%d checks passed (Crystal item behaviors)"):format(checks, checks))
