package.path = "./?.lua;./?/init.lua;" .. package.path

local Modes = require("mods.CRYSTAL_251.battle.crystal_modes")

local checks, failures = 0, 0
local function fail(message)
  failures = failures + 1
  io.stderr:write("FAIL " .. message .. "\n")
end
local function ok(value, message)
  checks = checks + 1
  if not value then fail(message) end
end
local function eq(got, want, message)
  checks = checks + 1
  if got ~= want then
    fail(("%s (got %s, want %s)"):format(message, tostring(got), tostring(want)))
  end
end
local function seq(values)
  local index = 0
  return function(a, b)
    index = index + 1
    local value = values[index]
    if value == nil then value = a or 0 end
    if b ~= nil then
      if value < a then value = a elseif value > b then value = b end
    end
    return value
  end
end

-- Explicit policy separation.
do
  eq(Modes.modeOf({kind="wild"}), "wild", "wild mode detected")
  eq(Modes.modeOf({kind="trainer"}), "trainer", "trainer mode detected")
  eq(Modes.modeOf({kind="trainer",battleTower=true}), "battle_tower",
    "Battle Tower overrides trainer mode")
  eq(Modes.modeOf({kind="link",battleTower=true}), "link",
    "link mode has highest priority")
  ok(Modes.policyFor("wild").capture, "wild battles permit capture")
  ok(not Modes.policyFor("trainer").capture, "trainer battles block capture")
  ok(Modes.policyFor("link").run == "forfeit", "link RUN is a forfeit")
  ok(not Modes.policyFor("battle_tower").obedience,
    "Battle Tower disables obedience checks")
  ok(not Modes.policyFor("battle_tower").trainerItems,
    "Battle Tower disables trainer items")
end

-- Exact ten-seed Crystal link stream: output bytes 1..9, transform all ten,
-- then wrap to transformed seed 1.
do
  local rng, state = Modes.makeLinkRng({1,2,3,4,5,6,7,8,9,10})
  for i = 1, 9 do eq(rng(0,255), i, "link RNG output " .. i) end
  eq(state.count, 0, "ninth output wraps the link RNG cursor")
  eq(state.seeds[1], 6, "first seed advances by x5+1")
  eq(state.seeds[10], 51, "unused tenth seed still advances")
  eq(rng(0,255), 6, "next stream begins at transformed seed one")
  eq(state.count, 1, "cursor advances in the new stream")
end

-- One handshake integer expands to a deterministic shared ten-byte state.
do
  local a, as = Modes.makeLinkRng(77)
  local b, bs = Modes.makeLinkRng(77)
  for i = 1, 40 do eq(a(0,255), b(0,255), "derived streams agree call " .. i) end
  eq(as.count, bs.count, "derived link cursors agree")
  for i = 1, 10 do eq(as.seeds[i], bs.seeds[i], "derived seed agrees " .. i) end
end

local function mon(species, item)
  return {species=species,hp=100,status=nil,heldItem=item,happiness=70,
    moves={{id="TACKLE",pp=35}}}
end
local function battler(isPlayer, species, item)
  local m = mon(species,item)
  return {isPlayer=isPlayer,name=species,mon=m,curMoves=m.moves,
    curTypes={"NORMAL"},stages={specialAttack=1,specialDefense=-1}}
end
local function linkBattle(role)
  local player = battler(true, role=="guest" and "GUEST" or "HOST",
    role=="guest" and "LEFTOVERS" or "BERRY")
  local enemy = battler(false, role=="guest" and "HOST" or "GUEST",
    role=="guest" and "BERRY" or "LEFTOVERS")
  local playerParty = {player.mon}
  local enemyParty = {enemy.mon}
  local b = {kind="link",linkRole=role,player=player,enemy=enemy,
    playerParty=playerParty,enemyParty=enemyParty,weather="rain",
    crystalScreens={player={reflect=3},enemy={safeguard=2}},
    crystalSpikes={player=1,enemy=0},crystalFutureSight={player={turns=2,damage=44,
      moveId="FUTURE_SIGHT",category="special",source=player}}}
  local rng,state=Modes.makeLinkRng({11,12,13,14,15,16,17,18,19,20})
  b.rng,b.crystalLinkRngState=rng,state
  return b
end

-- Host-first serialization is perspective-independent and covers all Crystal
-- state omitted by the base link signature.
do
  local host = linkBattle("host")
  local guest = linkBattle("guest")
  -- Mirror the host-side field state from the guest perspective.
  guest.crystalScreens.player={safeguard=2}
  guest.crystalScreens.enemy={reflect=3}
  guest.crystalSpikes.player=0
  guest.crystalSpikes.enemy=1
  guest.crystalFutureSight={enemy={turns=2,damage=44,moveId="FUTURE_SIGHT",
    category="special",source=guest.enemy}}
  eq(Modes.linkSyncString(host), Modes.linkSyncString(guest),
    "link sync stream is canonical across perspectives")
  local before=Modes.linkSyncString(host)
  host.player.stages.specialAttack=2
  ok(Modes.linkSyncString(host)~=before,"split Special stage affects link hash")
  before=Modes.linkSyncString(host)
  host.player.mon.heldItem="MYSTERYBERRY"
  ok(Modes.linkSyncString(host)~=before,"held item affects link hash")
  before=Modes.linkSyncString(host)
  host.rng(0,255)
  ok(Modes.linkSyncString(host)~=before,"link RNG cursor affects link hash")
end

-- Hash messages fold Crystal state into the fatal active component and the
-- combined legacy value without changing the wire message type.
do
  local b=linkBattle("host")
  b.localHashes={[3]="legacy"}
  b.localParts={[3]={actives="active",volatile="volatile",bench="bench"}}
  local msg={type="hash",turn=3,value="legacy",
    parts={actives="active",volatile="volatile",bench="bench"}}
  Modes.attachCrystalHash(b,msg)
  ok(msg.value~="legacy" and msg.value:find("C251=",1,true),
    "combined link hash includes Crystal digest")
  eq(msg.value,b.localHashes[3],"local and wire combined hashes agree")
  eq(msg.parts.actives,b.localParts[3].actives,
    "local and wire active components agree")
  ok(msg.crystal251~=nil,"wire message exposes Crystal diagnostic digest")
end

-- Crystal wild flee lists and gating.
do
  local function wild(species, rolls)
    return {kind="wild",crystal251Active=true,rng=seq(rolls or {0}),
      player={cantEscape=false},enemy={mon={species=species,hp=10,status=nil}}}
  end
  ok(Modes.shouldWildFlee(wild("RAIKOU",{255})),"Raikou always flees")
  ok(Modes.shouldWildFlee(wild("ENTEI",{255})),"Entei always flees")
  ok(Modes.shouldWildFlee(wild("CUBONE",{0})),"often-flee species flees below half")
  ok(Modes.shouldWildFlee(wild("CUBONE",{128})),
    "often-flee species flees at Crystal's inclusive half threshold")
  ok(not Modes.shouldWildFlee(wild("CUBONE",{129})),
    "often-flee species stays above the half threshold")
  ok(Modes.shouldWildFlee(wild("MAGNEMITE",{25})),
    "sometimes-flee species flees below ten percent threshold")
  ok(not Modes.shouldWildFlee(wild("MAGNEMITE",{26})),
    "sometimes-flee species stays at threshold")
  ok(not Modes.shouldWildFlee(wild("PIDGEY",{0})),
    "unlisted wild species never flees")
  local trapped=wild("RAIKOU",{0}); trapped.enemy.crystalTrapTurns=2
  ok(not Modes.shouldWildFlee(trapped),"partial trapping blocks wild flee")
  local meanLook=wild("RAIKOU",{0}); meanLook.player.cantEscape=true
  ok(not Modes.shouldWildFlee(meanLook),"Mean Look blocks wild flee")
  local sleeping=wild("RAIKOU",{0}); sleeping.enemy.mon.status="SLP"
  ok(not Modes.shouldWildFlee(sleeping),"sleep blocks wild flee")
  local frozen=wild("RAIKOU",{0}); frozen.enemy.mon.status="FRZ"
  ok(not Modes.shouldWildFlee(frozen),"freeze blocks wild flee")
end

-- Trainer DVs, including the Rival2 bug and HP-DV derivation.
do
  local falkner=Modes.trainerDVs("OPP_BIRD_KEEPER")
  eq(falkner.attack,9,"Bird Keeper uses Crystal attack DV")
  eq(falkner.defense,8,"Bird Keeper uses Crystal defense DV")
  eq(falkner.speed,8,"Bird Keeper uses Crystal speed DV")
  eq(falkner.special,8,"Bird Keeper uses Crystal Special DV")
  eq(falkner.hp,8,"HP DV derives from low DV bits")
  eq(Modes.trainerDVs("OPP_RIVAL1").attack,13,"Rival1 has high Crystal DVs")
  eq(Modes.trainerDVs("OPP_RIVAL2").attack,9,
    "Rival2 preserves Crystal's lower-DV bug")
end

-- Battle Tower healing restores HP, status and PP while retaining held items.
do
  local m={hp=1,status="PSN",heldItem="BERRY",stats={hp=222},
    moves={{id="TACKLE",pp=1,ppUps=2}}}
  Modes.healBattleTowerParty({moves={TACKLE={pp=35}}},{m})
  eq(m.hp,222,"Battle Tower heals HP before the next match")
  eq(m.status,nil,"Battle Tower clears status between matches")
  eq(m.moves[1].pp,49,"Battle Tower restores PP with PP Ups")
  eq(m.heldItem,"BERRY","Battle Tower healing does not recreate held items")
end

-- Link extras preserve battle-relevant party bytes and reject unknown items
-- in strict negotiated links.
do
  local source={heldItem="LEFTOVERS",happiness=201,pokerus=7,caughtData=1234}
  local packed={crystal251=Modes.packLinkExtras(source)}
  local restored={}
  local data={items={LEFTOVERS={}}}
  local got,why=Modes.unpackLinkExtras(data,restored,packed,true)
  eq(why,nil,"known held item unpacks without error")
  eq(got.heldItem,"LEFTOVERS","held item crosses Crystal link")
  eq(got.happiness,201,"happiness crosses Crystal link")
  eq(got.pokerus,7,"Pokerus byte crosses Crystal link")
  eq(got.caughtData,1234,"caught data crosses Crystal link")
  local bad,reason=Modes.unpackLinkExtras(data,{},
    {crystal251={heldItem="FAKE_ITEM"}},true)
  eq(bad,nil,"strict link rejects unknown held item")
  eq(reason,"unknown held item","strict item rejection explains failure")
  local lenient=Modes.unpackLinkExtras(data,{},
    {crystal251={heldItem="FAKE_ITEM"}},false)
  eq(lenient.heldItem,nil,"legacy link drops unknown held item")
end

-- Link configuration installs Crystal RNG, fatal hash extension, and RUN
-- forfeiture without editing the base link implementation.
do
  local sent={}
  local net={send=function(self,msg) sent[#sent+1]=msg end}
  local b=linkBattle("host")
  b.net=net
  b.localHashes={[1]="h"}; b.localParts={[1]={actives="a"}}
  b.finish=function(self) self.finished=true return "done" end
  b.say=function(self,text) self.lastText=text end
  Modes.configureLinkBattle(b,net,{crystalRNs={1,2,3,4,5,6,7,8,9,10}})
  eq(b.crystalBattleMode,"link","configured battle is marked link")
  eq(b.rng(0,255),1,"configured link uses Crystal seed stream")
  net:send({type="hash",turn=1,value="h",parts={actives="a"}})
  ok(sent[1].value:find("C251=",1,true)~=nil,
    "configured net injects Crystal hash")
  b:tryRun()
  eq(b.result,"lose","local RUN forfeits the link match")
  eq(sent[#sent].type,"forfeit","RUN sends definite forfeit message")
  eq(sent[#sent].reason,"run","forfeit identifies RUN source")
  local wrapped=net.send
  eq(b:finish(),"done","wrapped finish preserves return value")
  ok(net.send~=wrapped,"finish restores the shared network sender")
  local originalSend = net.send
  local interrupted = {game=b.game, finish=function() end}
  Modes.configureLinkBattle(interrupted,net,{seed=1})
  ok(net.send~=originalSend,"next link battle installs a sender wrapper")
  require("mods.CRYSTAL_251.lib.runtime_patches").restore()
  eq(net.send,originalSend,"unload during a link battle restores the shared sender")
end

print(("%d/%d checks passed (Crystal battle modes and link sync)")
  :format(checks-failures,checks))
if failures>0 then os.exit(1) end
