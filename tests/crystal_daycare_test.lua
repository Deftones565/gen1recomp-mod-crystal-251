package.path = "./?.lua;./?/init.lua;" .. package.path

_G.love = { math={ random=function(a) return a end } }

package.loaded["src.pokemon.Growth"] = {
  expForLevel=function(_, level) return level * 100 end,
  levelForExp=function(_, exp, cap)
    return math.min(cap or 100, math.max(1, math.floor((exp or 0) / 100)))
  end,
}
package.loaded["src.pokemon.Stats"] = {
  calc=function(_, level, dvs)
    return { hp=level + 20, attack=(dvs.attack or 0) + level,
      defense=(dvs.defense or 0) + level, speed=(dvs.speed or 0) + level,
      special=(dvs.special or 0) + level }
  end,
}
package.loaded["src.render.TextBox"] = {
  new=function(game, text, onDone, opts)
    return { game=game, text=text, onDone=onDone, opts=opts }
  end,
}
local dexScreensOpened = 0
package.loaded["src.ui.DexEntryMenu"] = {
  new=function(game, species)
    dexScreensOpened = dexScreensOpened + 1
    return {
      game=game, species=species,
      update=function(self) self.game.stack:pop() end,
    }
  end,
}
package.loaded["src.core.Sound"] = {
  playCry=function() end, play=function() end,
}

package.loaded["src.pokemon.Pokemon"] = {
  movesAtLevel=function(def, level)
    local ids = {}
    local function add(id)
      for _, known in ipairs(ids) do if known == id then return end end
      ids[#ids + 1] = id
    end
    for _, id in ipairs(def.level1Moves or {}) do add(id) end
    for _, row in ipairs(def.learnset or {}) do if row.level <= level then add(row.move) end end
    while #ids > 4 do table.remove(ids, 1) end
    return ids
  end,
  learnMovesFromDayCare=function(_, mon, _, from, to)
    mon.learnedFrom, mon.learnedTo = from, to
  end,
}

local Gender = require("mods.CRYSTAL_251.battle.crystal_gender")
Gender.resetForTests()
local Daycare = require("mods.CRYSTAL_251.daycare")

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

local function def(groups, opts)
  opts = opts or {}
  return {
    name=opts.name or "MON", crystalEggGroups=groups,
    crystalHatchCycles=opts.cycles or 20,
    crystalEggMoves=opts.eggMoves or {}, tmhm=opts.tmhm or {},
    level1Moves=opts.level1 or { "TACKLE" }, learnset=opts.learnset or {},
    evolutions=opts.evolutions or {}, growthRate="MEDIUM_FAST",
    baseStats={ hp=50, attack=50, defense=50, speed=50, special=50 },
  }
end

local data = {
  pokemon={
    A=def({1,1}), B=def({1,2}), C=def({3,3}),
    DITTO=def({13,13}), GENDERLESS=def({10,10}),
    STERILE=def({15,15}),
    PICHU=def({5,6}, { cycles=10, eggMoves={"EGG_MOVE"}, tmhm={"TM_MOVE"},
      learnset={ {level=1,move="TACKLE"}, {level=10,move="SHARED"} },
      evolutions={ {method="LEVEL",level=5,species="PIKACHU"} } }),
    PIKACHU=def({5,6}, { evolutions={ {method="ITEM",species="RAICHU"} } }),
    RAICHU=def({5,6}),
    NIDORAN_F=def({1,5}), NIDORAN_M=def({1,5}),
  },
  moves={
    TACKLE={pp=35}, EGG_MOVE={pp=5}, SHARED={pp=10},
    TM_MOVE={pp=15}, NO_MOVE={pp=20},
  },
  items={ FLOWER_MAIL={isMail=true} },
  growth_rates={},
}

for _, species in ipairs({"A","B","C","PICHU","PIKACHU","RAICHU","NIDORAN_F","NIDORAN_M"}) do
  Gender.setRatio(species, 127)
end
Gender.setRatio("DITTO", 255)
Gender.setRatio("GENDERLESS", 255)
Gender.setRatio("STERILE", 127)

local function mon(species, gender, ot, defense, special, moves)
  local attack, speed = 15, 15
  if gender == "F" then attack, speed = 0, 0 end
  return { species=species, level=20, exp=2000, hp=40, otId=ot,
    dvs={attack=attack,defense=defense or 1,speed=speed,special=special or 2},
    statExp={hp=0,attack=0,defense=0,speed=0,special=0},
    stats={hp=40}, moves=moves or {} }
end

local femaleA = mon("A", "F", 1, 1, 2)
local maleAOther = mon("A", "M", 2, 2, 3)
local maleASame = mon("A", "M", 1, 2, 3)
local maleB = mon("B", "M", 2, 3, 4)
local maleBSame = mon("B", "M", 1, 3, 4)

eq(Daycare.compatibility(data, femaleA, maleAOther), 254,
  "same species and different OT is the highest tier")
eq(Daycare.compatibility(data, femaleA, maleASame), 177,
  "same species and same OT is the second tier")
eq(Daycare.compatibility(data, femaleA, maleB), 128,
  "different species and different OT is the third tier")
eq(Daycare.compatibility(data, femaleA, maleBSame), 51,
  "different species and same OT is the lowest breeding tier")
eq(Daycare.compatibility(data, femaleA, mon("B", "F", 2, 3, 4)), 0,
  "same-gender pair is incompatible")
eq(Daycare.compatibility(data, femaleA, mon("C", "M", 2, 3, 4)), 0,
  "unshared egg groups are incompatible")
eq(Daycare.compatibility(data, mon("STERILE", "F", 1), maleAOther), 0,
  "No Eggs group is incompatible")
eq(Daycare.compatibility(data, mon("DITTO", nil, 1, 4, 5),
  mon("GENDERLESS", nil, 2, 2, 3)), 128,
  "Ditto breeds with a genderless non-Ditto")
eq(Daycare.compatibility(data, mon("DITTO", nil, 1), mon("DITTO", nil, 2)), 0,
  "two Ditto cannot breed")
eq(Daycare.compatibility(data, femaleA, mon("B", "M", 2, 1, 10)), 255,
  "matching Defense and low Special DV bits trigger the family block")

eq(Daycare.eggChance(254), 80, "very compatible chance is 80/256")
eq(Daycare.eggChance(177), 40, "compatible chance is 40/256")
eq(Daycare.eggChance(128), 30, "different-species chance is 30/256")
eq(Daycare.eggChance(51), 10, "low compatibility chance is 10/256")
eq(Daycare.eggChance(255), 0, "DV-blocked pair never produces an egg")

-- Child species is reduced through two pre-evolutions and inherits Crystal's
-- explicit egg moves, shared level-up moves, and compatible TM/HM moves.
local mother = mon("RAICHU", "F", 1, 1, 2,
  { {id="SHARED",pp=10}, {id="NO_MOVE",pp=20} })
local father = mon("RAICHU", "M", 2, 9, 13,
  { {id="EGG_MOVE",pp=5}, {id="SHARED",pp=10}, {id="TM_MOVE",pp=15}, {id="NO_MOVE",pp=20} })
local rolls = { 255, 255 }
local at = 0
local egg = Daycare.makeEgg(data, mother, father, function(low, high)
  at = at + 1
  return math.max(low, math.min(high, rolls[at] or low))
end, {id=77,name="RED"})
eq(egg.species, "PICHU", "egg species is reduced through two pre-evolutions")
eq(egg.level, 5, "Crystal eggs are level 5")
eq(egg.hp, 0, "an unhatched egg has zero current HP")
eq(egg.eggCycles, 10, "egg starts with the species hatch-cycle count")
eq(egg.happiness, 10, "unhatched Egg stores its hatch cycles in happiness")
eq(egg.nickname, "EGG", "party displays the unhatched mon as EGG")
eq(egg.dvs.defense, mother.dvs.defense,
  "male child inherits Defense DV from the opposite-gender parent")
eq(egg.dvs.special % 8, mother.dvs.special % 8,
  "male child inherits the low three Special DV bits")
local eggMoveSet = {}
eq(#egg.moves, 0, "unhatched egg exposes no usable moves")
for _, move in ipairs(egg.eggMoves) do eggMoveSet[move.id] = true end
ok(eggMoveSet.EGG_MOVE, "explicit egg move is inherited")
ok(eggMoveSet.SHARED, "move known by both parents and in level-up list is inherited")
ok(eggMoveSet.TM_MOVE, "compatible TM/HM move is inherited")
eq(eggMoveSet.NO_MOVE, nil, "ordinary non-heritable move is rejected")

-- GetHeritableMoves makes Ditto the move donor only opposite a female
-- non-Ditto parent. A male or genderless non-Ditto supplies its own moves.
local femaleParent = mon("PICHU", "F", 1, 4, 5,
  { {id="NO_MOVE",pp=20} })
local dittoEggMove = mon("DITTO", nil, 2, 6, 7,
  { {id="EGG_MOVE",pp=5} })
local femaleDittoEgg = Daycare.makeEgg(data, femaleParent, dittoEggMove,
  function(low) return low end, {id=77,name="RED"})
local femaleDittoMoves = {}
for _, move in ipairs(femaleDittoEgg.eggMoves) do femaleDittoMoves[move.id]=true end
ok(femaleDittoMoves.EGG_MOVE,
  "Ditto supplies egg moves when paired with a female non-Ditto")

local maleParent = mon("PICHU", "M", 1, 4, 5,
  { {id="EGG_MOVE",pp=5} })
local dittoNoMove = mon("DITTO", nil, 2, 6, 7,
  { {id="NO_MOVE",pp=20} })
local maleDittoEgg = Daycare.makeEgg(data, maleParent, dittoNoMove,
  function(low) return low end, {id=77,name="RED"})
local maleDittoMoves = {}
for _, move in ipairs(maleDittoEgg.eggMoves) do maleDittoMoves[move.id]=true end
ok(maleDittoMoves.EGG_MOVE,
  "male non-Ditto supplies egg moves when paired with Ditto")
eq(maleDittoMoves.NO_MOVE, nil,
  "Ditto's ordinary move is not inherited from a male pairing")

local cache={eggAssets={front="egg/front.png",icon="egg/icon.png"},
  daycareIconAssets={},species={}}
for i=1,38 do cache.daycareIconAssets[i]="daycare/icon_"..i..".png" end
for i=1,251 do cache.species[i]={crystalHatchCycles=20,
  crystalEggGroups={1,1},crystalEggMoves={},crystalMenuIcon=8} end
cache.species[25].crystalMenuIcon=4
ok(Daycare.cacheHasData(cache), "complete breeding cache is accepted")
cache.species[25].crystalEggGroups=nil
eq(Daycare.cacheHasData(cache), false, "cache missing egg groups is rejected")
cache.species[25].crystalEggGroups={1,1}
cache.eggAssets.icon=nil
eq(Daycare.cacheHasData(cache), false, "cache missing ROM-derived Egg icon is rejected")
cache.eggAssets.icon="egg/icon.png"
cache.daycareIconAssets[4]=nil
eq(Daycare.cacheHasData(cache), false,
  "cache missing an animated Day Care icon is rejected")
cache.daycareIconAssets[4]="daycare/icon_4.png"
cache.species[25].crystalMenuIcon=nil
eq(Daycare.cacheHasData(cache), false,
  "cache missing a species menu-icon identity is rejected")
cache.species[25].crystalMenuIcon=4

local dialogueFemale=mon("A","F",1,1,2); dialogueFemale.nickname="ALPHA"
local dialogueMale=mon("A","M",1,2,3); dialogueMale.nickname="BETA"
local dialogueState={slots={{mon=dialogueFemale},{mon=dialogueMale}}}
local dialogue=Daycare.compatibilityDialogue(data,dialogueState)
ok(dialogue:find("ALPHA",1,true)~=nil and dialogue:find("BETA",1,true)~=nil,
  "boarder dialogue names both deposited Pokemon")
ok(dialogue:find("get along",1,true)~=nil,
  "boarder dialogue describes the pair's compatibility")
local sterileState={slots={{mon=mon("A","F",1)},{mon=mon("A","F",2)}}}
ok(Daycare.compatibilityDialogue(data,sterileState):find("won't breed",1,true)~=nil,
  "incompatible boarders explicitly say they will not breed")

-- Old one-slot saves migrate without losing deferred Gen I step experience.
local oldMon=mon("A","F",1); oldMon.exp=1000
local migratedSave={party={},daycare={mon=oldMon,steps=45,depositLevel=20}}
local migrated=Daycare.normalize(migratedSave,data)
eq(migrated.slots[1].mon.exp,1045,"old deferred Day Care EXP migrates once")
eq(migrated.mon,nil,"Crystal state no longer exposes the Gen I single-mon field")

-- A specific attendant owns a specific slot; the lady does not silently use
-- the man's empty slot.
local ladyFemale=mon("A","F",4)
local ladySave={party={ladyFemale,mon("B","M",5),mon("C","M",6)},
  money=5000,player={id=4,name="RED"}}
local ladySlot=Daycare.depositInto(ladySave,data,2,ladyFemale,function(a)return a end)
eq(ladySlot,2,"lady deposits directly into slot 2")
eq(ladySave.daycare.slots[1],nil,"lady leaves the man's slot untouched")
ok(ladySave.daycare.slots[2] and ladySave.daycare.slots[2].mon==ladyFemale,
  "lady owns the second boarded Pokemon")

-- Deposit rules and two independent slots.
local save={party={femaleA,maleB,mon("C","M",3)},money=5000,player={id=1,name="RED"}}
local function breedingLow(low, high)
  if low == 0 and high == 255 then return 150 end
  return low
end
local slot1=Daycare.deposit(save,data,femaleA,breedingLow)
local slot2=Daycare.deposit(save,data,maleB,breedingLow)
eq(slot1,1,"first deposited mon uses the man slot")
eq(slot2,2,"second deposited mon uses the lady slot")
eq(#save.party,1,"both deposited mons leave the party")
eq(Daycare.slotCount(save.daycare),2,"Crystal Day Care holds two mons")

-- Both boarders gain one EXP per completed step, and a zero counter performs
-- the compatibility-dependent egg roll instead of refreshing every move.
save.daycare.compatibility=254
save.daycare.stepsToEgg=1
local before1=save.daycare.slots[1].mon.exp
local before2=save.daycare.slots[2].mon.exp
Daycare.stepState(save,data,function(low,high) return low end)
eq(save.daycare.slots[1].mon.exp,before1+1,"first boarder gains one EXP per step")
eq(save.daycare.slots[2].mon.exp,before2+1,"second boarder gains one EXP per step")
eq(save.daycare.eggReady,true,"successful compatibility roll makes the egg available")

local taken=Daycare.takeEgg(save,data,breedingLow)
ok(taken and taken.isEgg,"available egg can be added to the party")
eq(save.daycare.eggReady,false,"taking the egg clears the ready flag")
ok(save.daycare.stepsToEgg~=nil,"same pair begins producing another egg")

-- Hatch counters advance every 256 steps at the $80 offset and stop on the
-- first egg that becomes ready, matching DoEggStep's party order.
taken.eggCycles=1
save.daycare.stepCounter=0x7f
local hatchExp1=save.daycare.slots[1] and save.daycare.slots[1].mon.exp
local hatchExp2=save.daycare.slots[2] and save.daycare.slots[2].mon.exp
local ready=Daycare.stepState(save,data,function(a)return a end)
eq(ready,taken,"first ready egg is returned for hatching")
if hatchExp1 then eq(save.daycare.slots[1].mon.exp,hatchExp1,
  "hatch event returns before first boarder gains EXP") end
if hatchExp2 then eq(save.daycare.slots[2].mon.exp,hatchExp2,
  "hatch event returns before second boarder gains EXP") end
eq(taken.eggCycles,0,"hatch counter reaches zero at the $80 step")
eq(taken.happiness,0,"Egg happiness byte follows the remaining hatch cycles")

-- Hatching reveals the inherited moves that were hidden while the mon was
-- still an Egg. A species not previously owned shows its Pokédex entry after
-- the hatch announcement and resumes at the nickname prompt when dismissed.
local function testStack()
  local stack={items={}}
  function stack:push(state) self.items[#self.items + 1]=state end
  function stack:pop() return table.remove(self.items) end
  function stack:top() return self.items[#self.items] end
  return stack
end
local function finishText(stack)
  local box=stack:pop()
  ok(box and box.onDone,"test advances a callback-backed hatch text box")
  box.onDone()
  return box
end
local hatchGame={data=data,save=save,stack=testStack()}
local beforeDexScreens=dexScreensOpened
Daycare.hatch(hatchGame,taken)
eq(taken.isEgg,nil,"hatching clears the Egg marker")
eq(taken.eggMoves,nil,"hatching consumes the hidden inherited move list")
ok(#taken.moves>0,"hatching exposes the inherited moves")
eq(taken.happiness,120,"hatched Pokemon starts with Crystal hatch happiness")
ok(save.pokedex.seen[taken.species],"hatching marks the species seen")
ok(save.pokedex.owned[taken.species],"hatching marks the species owned")
eq(hatchGame.stack:top().text,"Huh?","hatching starts with the surprise text")
finishText(hatchGame.stack)
ok(hatchGame.stack:top().text:find("hatched into",1,true)~=nil,
  "hatch announcement follows the surprise text")
finishText(hatchGame.stack)
local dexScreen=hatchGame.stack:top()
eq(dexScreensOpened,beforeDexScreens+1,
  "first-owned hatch opens one Pokédex entry")
eq(dexScreen.species,taken.species,
  "first-owned hatch opens the new species entry")
dexScreen:update(0)
local nicknamePrompt=hatchGame.stack:top()
ok(nicknamePrompt.text:find("nickname",1,true)~=nil,
  "dismissing the Pokédex entry resumes at the nickname prompt")

-- A repeat hatch already owned in the Pokédex skips the entry page and goes
-- directly from the hatch announcement to the nickname prompt.
local repeatEgg=Daycare.makeEgg(data,femaleA,maleAOther,
  function(low) return low end,{id=1,name="RED"})
hatchGame.stack=testStack()
beforeDexScreens=dexScreensOpened
Daycare.hatch(hatchGame,repeatEgg)
finishText(hatchGame.stack)
finishText(hatchGame.stack)
eq(dexScreensOpened,beforeDexScreens,
  "repeat hatch does not reopen an already-owned Pokédex entry")
ok(hatchGame.stack:top().text:find("nickname",1,true)~=nil,
  "repeat hatch proceeds directly to the nickname prompt")

-- Retrieval price is 100 plus 100 per gained level; withdrawal heals,
-- recalculates, and applies Day Care move learning only at retrieval.
local boarder=save.daycare.slots[1]
boarder.depositLevel=20
boarder.mon.exp=2400
local level,grown,fee=Daycare.levelAndFee(data,boarder)
eq(level,24,"retrieval derives current level from accumulated EXP")
eq(grown,4,"retrieval reports levels gained since deposit")
eq(fee,500,"retrieval costs 100 plus 100 per gained level")
local money=save.money
local returned,why,paid=Daycare.withdraw(save,data,1,breedingLow)
eq(why,nil,"boarder can be withdrawn with room and money")
eq(paid,500,"withdrawal charges the computed fee")
eq(save.money,money-500,"withdrawal deducts money")
eq(returned.level,24,"withdrawn mon receives its gained levels")
eq(returned.hp,returned.stats.hp,"withdrawn mon returns fully healed")
eq(returned.learnedFrom,20,"Day Care move learning begins at deposit level")
eq(returned.learnedTo,24,"Day Care move learning ends at retrieval level")

-- Egg restrictions and last-healthy protection.
local eggOnly={species="A",isEgg=true,hp=0}
local badSave={party={eggOnly,mon("A","M",1)},money=0,player={id=1}}
local _,whyEgg=Daycare.deposit(badSave,data,eggOnly,function(a)return a end)
eq(whyEgg,"egg","an Egg cannot be deposited")
local mailMon=mon("A","F",1); mailMon.heldItem="FLOWER_MAIL"
badSave.party={mailMon,mon("A","M",1)}
local _,whyMail=Daycare.deposit(badSave,data,mailMon,function(a)return a end)
eq(whyMail,"mail","a mon holding Mail cannot be deposited")
local fainted=mon("A","F",1); fainted.hp=0
local healthy=mon("A","M",1); healthy.hp=10
badSave.party={fainted,healthy}
local _,whyHealthy=Daycare.deposit(badSave,data,healthy,function(a)return a end)
eq(whyHealthy,"last_healthy","last healthy party mon cannot be deposited")
badSave.party={fainted,mon("A","M",1)}
badSave.party[2].hp=0
local _,whyNoHealthy=Daycare.deposit(badSave,data,fainted,function(a)return a end)
eq(whyNoHealthy,"last_healthy",
  "a fainted mon cannot be deposited when no other usable mon remains")

-- The waiting-Egg state moves the gentleman outside without touching any
-- unrelated object toggle.
local toggleSave={party={},daycare={crystal251=true,slots={},stepCounter=0,
  compatibility=0,eggReady=false},objectToggles={DAYCARE={OTHER_NPC=false}}}
Daycare.syncNPCFlags(toggleSave,data)
eq(toggleSave.objectToggles.DAYCARE.DAYCARE_GENTLEMAN,true,
  "inside man is visible when no Egg is waiting")
eq(toggleSave.objectToggles.DAYCARE.CRYSTAL251_DAYCARE_LADY,true,
  "appended lady remains visible")
eq(toggleSave.objectToggles.DAYCARE.CRYSTAL251_DAYCARE_MON_1,false,
  "first boarder object is hidden when slot 1 is empty")
eq(toggleSave.objectToggles.DAYCARE.CRYSTAL251_DAYCARE_MON_2,false,
  "second boarder object is hidden when slot 2 is empty")
eq(toggleSave.objectToggles.ROUTE_5.CRYSTAL251_DAYCARE_MAN_OUTSIDE,false,
  "outside man is hidden when no Egg is waiting")
eq(toggleSave.objectToggles.DAYCARE.OTHER_NPC,false,
  "Day Care synchronization preserves unrelated object toggles")
toggleSave.daycare.eggReady=true
Daycare.syncNPCFlags(toggleSave,data)
eq(toggleSave.objectToggles.DAYCARE.DAYCARE_GENTLEMAN,false,
  "inside man hides while an Egg is waiting")
eq(toggleSave.objectToggles.ROUTE_5.CRYSTAL251_DAYCARE_MAN_OUTSIDE,true,
  "outside man appears while an Egg is waiting")

-- Installation is deferred until game.ready, whose event has no required
-- payload. The live Game singleton must still be captured and its completed
-- steps must run the Crystal Day Care before the vanilla step pipeline.
local runtimeBoarder=mon("A","F",1); runtimeBoarder.exp=2000
local runtimeGame={data=data,save={party={mon("C","M",9)},money=0,
  player={id=9,name="RED"},daycare={crystal251=true,
    slots={{mon=runtimeBoarder,depositLevel=20}},stepCounter=0,
    compatibility=0,eggReady=false}},stack={push=function() end}}
local vanillaSteps=0
package.loaded["src.core.Game"]=runtimeGame
package.loaded["src.world.OverworldController"]={
  onStepComplete=function() vanillaSteps=vanillaSteps+1 end,
}
package.loaded["src.ui.PartyMenu"]={
  draw=function() end, entryY=function(i) return (i-1)*16 end,
}
package.loaded["src.ui.SummaryMenu"]={
  new=function(game, m) return {game=game,mon=m} end,
  update=function() end, draw=function() end,
  sgbPalettes=function() return "vanilla" end,
}
local healedEgg={isEgg=true,hp=0,status=nil}
package.loaded["src.pokemon.Pokemon"].heal=function(m) m.hp=999 end
local readyListener
local registeredScripts={}
local registeredSprites={}
local mapPatches={}
local fakeMaps={
  DAYCARE={objects={{index=1,name="DAYCARE_GENTLEMAN"}}},
  ROUTE_5={objects={{index=1,name="ROUTE5_NATIVE_1"},
                    {index=2,name="ROUTE5_NATIVE_2"}}},
}
local fakeMod={
  content={
    maps={
      get=function(_,id) return fakeMaps[id] end,
      patch=function(_,id,value)
        mapPatches[id]=value
        for _,obj in ipairs(value.objects.__append or {}) do
          fakeMaps[id].objects[#fakeMaps[id].objects+1]=obj
        end
      end,
    },
    map_scripts={register=function(_,id,value) registeredScripts[id]=value end},
    sprites={register=function(_,id,value) registeredSprites[id]=value end},
  },
  hooks={wrap=function() end},
  events={on=function(_,name,fn) if name=="game.ready" then readyListener=fn end end},
}
Daycare.resetForTests()
local testIconAssets={}
for i=1,38 do testIconAssets[i]="daycare/icon_"..i..".png" end
Daycare.install(fakeMod,{front="egg/front.png",icon="egg/icon.png"},testIconAssets)
ok(mapPatches.DAYCARE and mapPatches.DAYCARE.objects.__append,
  "lady is added with the map-list append wrapper")
ok(mapPatches.ROUTE_5 and mapPatches.ROUTE_5.objects.__append,
  "outside man is added with the map-list append wrapper")
eq(#fakeMaps.DAYCARE.objects,4,
  "appending the lady and two boarders preserves the native Day Care man")
eq(#fakeMaps.ROUTE_5.objects,3,"appending the outside man preserves Route 5 NPCs")
local ladyObject=fakeMaps.DAYCARE.objects[2]
eq(ladyObject.index,2,"lady index follows all existing Day Care objects")
eq(ladyObject.x,5,"lady uses Crystal's interior X coordinate")
eq(ladyObject.y,3,"lady uses Crystal's interior Y coordinate")
eq(ladyObject.sprite,"SPRITE_GRANNY","lady uses the existing granny sprite")
local mon1Object=fakeMaps.DAYCARE.objects[3]
local mon2Object=fakeMaps.DAYCARE.objects[4]
eq(mon1Object.index,3,"first boarder index follows the appended lady")
eq(mon2Object.index,4,"second boarder index follows the first boarder")
eq(mon1Object.x,3,"first boarder starts on the open lower floor")
eq(mon1Object.y,5,"first boarder starts on the open lower floor")
eq(mon2Object.x,4,"second boarder starts beside the first on open floor")
eq(mon2Object.y,5,"second boarder starts beside the first on open floor")
eq(mon1Object.movement,"WALK","first boarder wanders around the house")
eq(mon2Object.movement,"WALK","second boarder wanders around the house")
eq(mon1Object.hidden,true,"first boarder starts hidden until slot 1 is occupied")
eq(mon2Object.hidden,true,"second boarder starts hidden until slot 2 is occupied")
local pikachuSprite=registeredSprites.CRYSTAL_251_DAYCARE_ICON_04
ok(pikachuSprite~=nil,"Pikachu's Crystal menu icon is registered as an NPC sprite")
eq(pikachuSprite.frames,6,"Day Care icon sheets expose all six NPC poses")
eq(pikachuSprite.walker,true,"Day Care icon sprites animate while walking")
local outsideObject=fakeMaps.ROUTE_5.objects[3]
eq(outsideObject.index,3,"outside man index follows all existing Route 5 objects")
eq(outsideObject.x,12,"outside man stands beside the Kanto Day Care door")
eq(outsideObject.y,22,"outside man stands below the Kanto Day Care door")
eq(outsideObject.hidden,true,"outside man starts hidden until an Egg is ready")
ok(registeredScripts.DAYCARE
    and registeredScripts.DAYCARE.talk.TEXT_DAYCARE_GENTLEMAN,
  "existing gentleman receives the Crystal slot-1 script")
ok(registeredScripts.DAYCARE
    and registeredScripts.DAYCARE.talk.TEXT_CRYSTAL251_DAYCARE_LADY,
  "appended lady receives the Crystal slot-2 script")
ok(registeredScripts.DAYCARE
    and registeredScripts.DAYCARE.talk.TEXT_CRYSTAL251_DAYCARE_MON_1,
  "first boarder receives the compatibility-check interaction")
ok(registeredScripts.DAYCARE
    and registeredScripts.DAYCARE.talk.TEXT_CRYSTAL251_DAYCARE_MON_2,
  "second boarder receives the compatibility-check interaction")
ok(registeredScripts.ROUTE_5
    and registeredScripts.ROUTE_5.talk.TEXT_CRYSTAL251_DAYCARE_MAN_OUTSIDE,
  "appended outside man receives the Egg-pickup script")
ok(readyListener,"Day Care registers its game.ready lifecycle hook")
readyListener()
local installedStepBridge=package.loaded["src.world.OverworldController"].onStepComplete
-- Simulate the module-local state reset that accompanies a loader rollback or
-- hot reload. The shared overworld class survives and must keep exactly one
-- Crystal bridge instead of accumulating another wrapper frame.
Daycare.resetForTests()
readyListener()
eq(package.loaded["src.world.OverworldController"].onStepComplete,
  installedStepBridge,"Day Care hot reload reuses its overworld step bridge")
local beforeRuntime=runtimeBoarder.exp
package.loaded["src.world.OverworldController"].onStepComplete({})
eq(runtimeBoarder.exp,beforeRuntime+1,
  "reload-safe step bridge advances the boarder exactly once")
eq(vanillaSteps,1,"ordinary Day Care steps continue into the vanilla pipeline")
package.loaded["src.pokemon.Pokemon"].heal(healedEgg)
eq(healedEgg.hp,0,"Pokemon Center healing leaves an Egg at zero HP")

if failures > 0 then
  io.stderr:write(("%d/%d Crystal daycare checks failed\n"):format(failures, checks))
  os.exit(1)
end
print(("%d/%d checks passed (Crystal Day Care and breeding)\n"):format(checks, checks))
