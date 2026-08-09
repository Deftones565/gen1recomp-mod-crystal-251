package.path = "./?.lua;./?/init.lua;" .. package.path

local P = require("mods.CRYSTAL_251.battle.crystal_progression")

local checks, failures = 0, 0
local function check(value, message)
  checks = checks + 1
  if not value then
    failures = failures + 1
    io.stderr:write("FAIL " .. message .. "\n")
  end
end
local function eq(got, want, message)
  check(got == want, ("%s (got %s, want %s)")
    :format(message, tostring(got), tostring(want)))
end

local function mon(name, hp, item)
  return { species=name, nickname=name, hp=hp == nil and 100 or hp,
    heldItem=item }
end

local function award(party, alive, opts)
  opts = opts or {}
  local calls, delegated = {}, 0
  local battle = {
    crystal251Active = opts.active ~= false,
    kind = opts.kind or "wild",
    linkRole = opts.linkRole,
    battleTower = opts.battleTower,
    inBattleTowerBattle = opts.inBattleTowerBattle,
    crystalBattleTower = opts.crystalBattleTower,
    game = { save = { party = party } },
    player = { mon = opts.activeMon or party[1] },
  }
  local ok, err = pcall(P.awardExp, function(ctx)
    delegated = delegated + 1
    return ctx and "delegated"
  end, {
    battle=battle,
    participants=opts.reportedParticipants or #(alive or {}),
    alive=alive,
    applyShare=function(target, split, announce)
      calls[#calls + 1] = { mon=target, split=split, announce=announce,
        context=target._crystal251ExpContext }
      if opts.throwOn == #calls then error("apply failure") end
    end,
  })
  return calls, delegated, ok, err
end

local lead, finisher, holder = mon("LEAD"), mon("FINISHER"),
  mon("HOLDER", 100, "EXP_SHARE")

local calls, delegated = award({lead}, {lead}, {active=false})
eq(delegated, 1, "non-Crystal battles delegate to the normal award path")
eq(#calls, 0, "non-Crystal battles do not run the Crystal distributor")

calls = award({lead, finisher}, {lead, finisher})
eq(#calls, 2, "ordinary experience pays every living participant")
eq(calls[1].split, 2, "ordinary experience divides by living participants")
eq(calls[2].split, 2, "every participant uses the same divisor")

calls = award({lead, holder}, {lead})
eq(#calls, 2, "a benched holder creates participant and holder passes")
eq(calls[1].mon, lead, "the participant receives the first half")
eq(calls[1].split, 2, "a sole participant receives half the reward")
eq(calls[2].mon, holder, "the benched holder receives the second half")
eq(calls[2].split, 2, "a sole holder receives the whole holder half")
eq(calls[2].announce, "expShare", "the holder pass is identified for messaging")

lead.heldItem = "EXP_SHARE"
calls = award({lead}, {lead})
eq(#calls, 2, "a participating holder receives both Crystal passes")
eq(calls[1].mon, lead, "the holder first receives its participant half")
eq(calls[2].mon, lead, "the holder then receives its holder half")
eq(calls[1].split, 2, "solo holder participant half is halved")
eq(calls[2].split, 2, "solo holder item half is halved")
lead.heldItem = nil

holder.heldItem = "EXP_SHARE"
calls = award({lead, finisher, holder}, {lead, finisher})
eq(#calls, 3, "switch training pays two participants plus the holder")
eq(calls[1].split, 4, "switch participants divide the participant half")
eq(calls[2].split, 4, "the finisher gets the same participant share")
eq(calls[3].split, 2, "the switched-out holder also gets the holder half")

local holder2 = mon("HOLDER2", 100, "EXP_SHARE")
holder.heldItem = "EXP_SHARE"
calls = award({lead, holder, holder2}, {lead, holder})
eq(#calls, 4, "a participating holder and bench holder use both passes")
eq(calls[1].split, 4, "two participants split the participant half")
eq(calls[2].mon, holder, "participating holder appears in participant pass")
eq(calls[3].split, 4, "two holders split the holder half")
eq(calls[4].split, 4, "both holders use the same holder divisor")

holder.hp = 0
calls = award({lead, holder}, {lead})
eq(#calls, 1, "a fainted sole holder does not activate EXP.SHARE")
eq(calls[1].split, 1, "fainted holder does not halve participant experience")
holder.hp = 100

finisher.hp = 0
calls = award({lead, finisher}, {lead, finisher}, {reportedParticipants=2})
eq(#calls, 1, "a stale fainted participant is not paid")
eq(calls[1].split, 1, "a stale fainted participant does not dilute experience")
finisher.hp = 100

lead.hp = 0
calls = award({lead, holder}, {}, {activeMon=lead, reportedParticipants=1})
eq(#calls, 1, "a healthy holder is paid when all participants fainted")
eq(calls[1].mon, holder, "only the healthy holder receives double-KO experience")
eq(calls[1].split, 2, "double-KO holder receives the holder half")
lead.hp = 100

calls = award({lead, lead, holder, holder}, {lead, lead})
eq(#calls, 2, "duplicate party/context references cannot duplicate awards")
eq(calls[1].split, 2, "deduplicated participant receives half")
eq(calls[2].split, 2, "deduplicated holder receives half")

local outsider = mon("OUTSIDER")
calls = award({lead}, {outsider})
eq(#calls, 1, "a non-party participant is ignored and active fallback is used")
eq(calls[1].mon, lead, "healthy active party mon is the participant fallback")

for _, opts in ipairs({
  {kind="link"}, {linkRole="host"}, {battleTower=true},
  {inBattleTowerBattle=true}, {crystalBattleTower=true},
}) do
  calls, delegated = award({lead, holder}, {lead}, opts)
  eq(#calls, 0, "link and Battle Tower modes award no experience")
  eq(delegated, 0, "no-exp modes do not fall through to Gen I awards")
end

lead._crystal251ExpContext = "outer"
calls = award({lead}, {lead})
eq(calls[1].context, true, "Crystal experience context is active during apply")
eq(lead._crystal251ExpContext, "outer", "existing experience context is restored")
lead._crystal251ExpContext = nil

local _, _, succeeded, err = award({lead}, {lead}, {throwOn=1})
check(not succeeded and tostring(err):find("apply failure", 1, true),
  "apply errors propagate to the caller")
eq(lead._crystal251ExpContext, nil, "experience context is restored after an error")

-- Exercise the real Crystal Experience.apply bridge, including the two-pass
-- rounding behavior. With odd base values, two halves intentionally need not
-- add back to the unsplit reward.
P.installRuntime()
local Experience = require("src.battle.Experience")
local Stats = require("src.pokemon.Stats")
local expData = {
  constants={levelCap=100},
  pokemon={TEST={name="TEST",growthRate="MEDIUM_FAST",learnset={},
    baseStats={hp=50,attack=50,defense=50,speed=50,special=50}}},
}
local defeated = {baseExp=101,
  baseStats={hp=41,attack=45,defense=47,speed=49,special=51}}
local function battleMon(item)
  local target = mon("TEST", 30, item)
  target.level, target.exp = 10, 1000
  target.dvs = {hp=8,attack=8,defense=8,speed=8,special=8}
  target.statExp = {hp=0,attack=0,defense=0,speed=0,special=0}
  target.stats = Stats.calc(expData.pokemon.TEST, target.level,
    target.dvs, target.statExp)
  return target
end
local function realAward(party, alive, battleOpts)
  local gained = {}
  local battle = {crystal251Active=true,kind="wild",
    game={save={party=party}},player={mon=alive[1]}}
  for key, value in pairs(battleOpts or {}) do battle[key] = value end
  P.awardExp(function() error("must not delegate") end, {
    battle=battle,participants=#alive,alive=alive,
    applyShare=function(target, split, announce)
      local levels, amount = Experience.apply(expData, target, defeated, 10,
        false, split, target.traded)
      gained[#gained + 1] = {mon=target,amount=amount,levels=levels,
        announce=announce}
    end,
  })
  return gained
end

local dual = battleMon("EXP_SHARE")
local before = dual.exp
local real = realAward({dual}, {dual})
eq(#real, 2, "real participating holder is applied twice")
eq(real[1].amount, 71, "participant half floors before level scaling")
eq(real[2].amount, 71, "holder half uses the same Crystal rounding")
eq(dual.exp - before, 142, "two rounded halves produce the exact total")
eq(dual.statExp.attack, 44, "odd stat experience is halved independently per pass")

local luckyLead, benchShare = battleMon("LUCKY_EGG"), battleMon("EXP_SHARE")
real = realAward({luckyLead, benchShare}, {luckyLead})
eq(real[1].amount, 106, "Lucky Egg boosts the participant half by 1.5x")
eq(real[2].amount, 71, "EXP.SHARE holder receives an unboosted holder half")

local tradedShare = battleMon("EXP_SHARE")
tradedShare.traded = true
real = realAward({tradedShare}, {tradedShare})
eq(real[1].amount, 106, "traded boost applies to the participant half")
eq(real[2].amount, 106, "traded boost also applies to the holder half")

local capped = battleMon("EXP_SHARE")
capped.level, capped.exp = 100, 1000000
capped.stats = Stats.calc(expData.pokemon.TEST, 100, capped.dvs, capped.statExp)
real = realAward({capped}, {capped})
eq(#real, 2, "a level-100 holder still runs both announcement passes")
eq(capped.level, 100, "EXP.SHARE never raises a Pokemon above the level cap")
eq(#real[1].levels + #real[2].levels, 0,
  "a capped holder creates no level-up sequence")

if failures > 0 then
  error(("%d/%d EXP.SHARE checks failed"):format(failures, checks))
end
print(("%d/%d checks passed (Crystal EXP.SHARE edge cases)"):format(checks, checks))
