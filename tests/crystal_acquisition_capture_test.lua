package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local f=assert(io.open(assert(os.getenv('CRYSTAL_ROM')),'rb'));local raw=f:read('*a');f:close()
local run,cache=require('mods.CRYSTAL_251.tests._real_rom_mod').load(T,raw)
local data=run.data
local Pokemon=require('src.pokemon.Pokemon')
local Battle=require('src.battle.BattleState')
local Runtime=require('src.mods.Runtime')
local Evolution=require('src.pokemon.Evolution')
local Items=require('src.inventory.ItemEffects')
local P=require('mods.CRYSTAL_251.battle.crystal_progression')
local Native=require('src.battle.gen2.Catching')
local Clock=require('mods.CRYSTAL_251.core.gen2.Clock')
local Stats=require('src.pokemon.Stats')
for _,source in ipairs(cache.species) do
 local def=data.pokemon[source.id]
 T.eq(def.baseStats.special,source.crystalSpecialAttack,source.id..' compatibility alias is SpAtk')
 local m=Pokemon.new(data,source.id,50,function() return 15 end)
 local stats=Stats.calc(def,50,m.dvs,m.statExp)
 T.eq(stats.specialAttack,source.crystalSpecialAttack+20,source.id..' recalculated SpAtk')
 T.eq(stats.specialDefense,source.crystalSpecialDefense+20,source.id..' recalculated SpDef')
 T.eq(m.stats.special,stats.specialAttack,source.id..' new Pokemon alias')
 m.stats.special=999
 require('mods.CRYSTAL_251.battle.crystal_summary').enrich(m)
 T.eq(m.stats.special,stats.specialAttack,source.id..' old save alias migrated')
end
local function game()
 local g={data=data,save=require('src.core.SaveData').newGame(),input={wasPressed=function() return true end}}
 g.save.party={Pokemon.new(data,'MEW',50,function() return 15 end)}
 g.stack={states={},push=function(self,s) self.states[#self.states+1]=s end,
  pop=function(self) return table.remove(self.states) end,top=function(self) return self.states[#self.states] end}
 g.overworld={map={id='ROUTE_1',def=data.maps.ROUTE_1},afterBattle=function() end}
 return g
end
local function battle(g,species)
 local b=Battle.newWild(g,species or 'CATERPIE',40)
 b.rng=function(a) return a end;b.queue={};b.nextInsert=0
 b.offerNickname=function() end
 -- Headless renderer: run gameplay queue callbacks while skipping UI/animation.
 b.buildScreen=function() return {} end
 g.save.pokedex.owned[b.enemy.mon.species]=true
 return b
end
local function drain(b)
 local n=0
 while #b.queue>0 do
  n=n+1;assert(n<5000,'queue loop')
  local row=table.remove(b.queue,1);b.nextInsert=0
  if row.fn then row.fn() end
 end
end
local g=game()
-- Every evolution row must win actual first-match dispatch under a reachable trigger.
local itemSources={}
for _,map in pairs(data.maps) do
 for _,object in ipairs(map.objects or {}) do if object.item then itemSources[object.item]=true end end
end
for _,rows in pairs(data.text_pointers) do
 for _,entry in pairs(rows) do
  if type(entry)=='table' then for _,id in ipairs(entry.mart or {}) do itemSources[id]=true end end
 end
end
local evolutionCount=0
for id,def in pairs(data.pokemon) do
 for _,evo in ipairs(def.evolutions or {}) do
  local mon=Pokemon.new(data,id,evo.level or 40,function() return 15 end)
  mon.happiness=255;mon.heldItem=nil
  local trigger={kind=evo.method=='ITEM' and 'item' or 'levelup',item=evo.item}
  if evo.method=='CRYSTAL_STAT_GT' then mon.stats.attack=101;mon.stats.defense=100
  elseif evo.method=='CRYSTAL_STAT_LT' then mon.stats.attack=99;mon.stats.defense=100
  elseif evo.method=='CRYSTAL_STAT_EQ' then mon.stats.attack=100;mon.stats.defense=100 end
  Clock.setTime(g.save,evo.method=='EVOLVE_HAPPINESS_NITE' and 22 or 12,0)
  T.eq(Evolution.pendingFor(g,mon,trigger),evo.species,id..' -> '..evo.species..' is selectable')
  T.check(data.pokemon[evo.species],evo.species..' destination exists')
  if evo.item then
   T.check(data.items[evo.item],evo.item..' exists')
   T.check(itemSources[evo.item],evo.item..' has a real Kanto shop or pickup')
   local result,_,extra=Items.use(data,g.save,evo.item,mon)
   T.eq(result,'consumed',id..' evolution item is usable')
   T.eq(extra and extra.evolveTo,evo.species,id..' item handler chooses correct evolution')
  end
  evolutionCount=evolutionCount+1
 end
end
T.check(evolutionCount>100,'all imported evolution branches visited')
-- Compare the Kanto adapter against the LOCAL Gen II engine, including precision edges.
for ball in pairs(P.BALLS) do
 for _,maxHP in ipairs({1,85,86,100,200,341,342,500}) do
  for _,hp in ipairs({1,math.max(1,math.floor(maxHP/2)),maxHP}) do
   for _,status in ipairs({'','SLP','FRZ','PSN','BRN','PAR'}) do
    local b=battle(g,'MAGNEMITE');local mon=b.enemy.mon
    mon.hp=hp;mon.stats.hp=maxHP;mon.status=status~='' and status or nil
    local opts=P.catchOptions(b,ball,mon,b.enemy.def)
    local expected=Native.rate(opts)
    T.eq(P.finalCatchRate(b,ball,mon,b.enemy.def),expected,ball..' matches local Gen II rate')
    for _,roll in ipairs({0,math.max(0,expected-1),expected,255}) do
     b.rng=function() return roll end;opts.random=function() return roll end
     T.eq(P.catchAttempt(b,ball,mon,b.enemy.def),Native.vanillaAttempt(opts),ball..' matches local Gen II roll')
    end
   end
  end
 end
end
-- The real Bag consumes each ball and the real throw queue stores its catch.
for ball in pairs(P.BALLS) do
 if ball~='SAFARI_BALL' then
  local g=game();local b=battle(g)
  g.save.inventory[ball]=2
  T.check(data.items[ball] and data.balls[ball],ball..' has item and ball records')
  T.eq(Items.use(data,g.save,ball,nil,b),'ball',ball..' reaches the ball branch')
  local list=require('src.ui.BagMenu').new(g,{battle=b});g.stack:push(list)
  list.onChoose({value=ball})
  T.eq(g.save.inventory[ball],1,ball..' is consumed once by Bag')
  drain(b)
  T.eq(b.result,'caught',ball..' actual throw succeeds')
  T.eq(g.save.party[2],b.enemy.mon,ball..' stores the caught Pokemon')
  T.eq(b.enemy.mon.caughtData.ball,ball,ball..' caught metadata survives')
  if ball=='FRIEND_BALL' then T.eq(b.enemy.mon.happiness,200,'Friend Ball friendship survives storage') end
end
end
-- Safari uses its own counter/menu but must reach the same Gen II capture seam.
do
 local g=game();local b=battle(g);b.safari={balls=3};b.safariCatchRate=120
 b:safariAction('ball');drain(b)
 T.eq(b.safari.balls,2,'Safari consumes exactly one Safari Ball')
 T.eq(b.result,'caught','Safari action reaches the Gen II catch path')
 T.eq(g.save.party[2].caughtData.ball,'SAFARI_BALL','Safari capture stores ball metadata')
end
-- Full party sends the captured Pokemon to a real box rather than losing it.
do
 local g=game()
 for i=2,6 do g.save.party[i]=Pokemon.new(data,'MEW',20,function() return 15 end) end
 local b=battle(g);b:throwBall('MASTER_BALL');drain(b)
 T.eq(#g.save.party,6,'full-party capture does not overfill party')
 T.eq(b.result,'caught','full-party capture succeeds')
 local found=false
 local function contains(t)
  if type(t)~='table' then return end
  for _,v in pairs(t) do if v==b.enemy.mon then found=true elseif type(v)=='table' then contains(v) end end
 end
 contains(g.save.boxes)
 T.check(found,'caught Pokemon is actually stored in a box')
end
-- Trainer captures remain blocked even with a guaranteed ball.
do
 local g=game();local b=battle(g);b.kind='trainer';b.enemyAction=function() return {id='SPLASH',pp=40} end
 b:throwBall('MASTER_BALL');drain(b)
 T.check(b.result~='caught' and #g.save.party==1,'Master Ball cannot steal trainer Pokemon')
end
-- A connected map route is necessary even when the encounter's own gate passes.
local reachable={PALLET_TOWN=true};local pending={'PALLET_TOWN'};local cursor=1
while pending[cursor] do
 local id=pending[cursor];cursor=cursor+1;local map=data.maps[id]
 local function visit(dest)
  if data.maps[dest] and not reachable[dest] then reachable[dest]=true;pending[#pending+1]=dest end
 end
 for _,edge in pairs(map.connections or {}) do if type(edge)=='table' then visit(edge.map) end end
 for _,warp in ipairs(map.warps or {}) do visit(warp.destMap) end
end
-- Actual static encounter scripts for all six stationary legendaries.
local Scripts=require('src.script.MapScripts');require('data.scripts.init')
local statics={ARTICUNO=true,ZAPDOS=true,MOLTRES=true,MEWTWO=true,LUGIA=true,HO_OH=true}
local found={}
for mapId,map in pairs(data.maps) do
 for _,object in ipairs(map.objects or {}) do
  local rows=object.text and Scripts.talkScript(mapId,object.text)
  for _,row in ipairs(type(rows)=="table" and rows or {}) do
   if row[1]=='static_battle' and statics[row[2]] then
    found[row[2]]=mapId
    T.check(reachable[mapId],row[2].." map connects to the Kanto world")
    local g=game();g.overworld.map={id=mapId,def=map}
    local ctx={game=g,save=g.save,overworld=g.overworld,runner={yield=function() end,resume=function() end}}
    require('src.script.Commands').start_battle(ctx,'wild',row[2],row[3])
    local b=g.stack:top()
    T.eq(b.enemy.mon.species,row[2],row[2]..' script starts its battle')
    T.check(b.crystal251Active and not b.noCatch,row[2]..' is a catchable Crystal battle')
    Runtime.emit('game.ready',{game=g});b:enter()
    b.rng=function(a) return a end;b.offerNickname=function() end
    g.save.pokedex.owned[row[2]]=true
    b:throwBall('MASTER_BALL');drain(b)
    T.eq(b.result,'caught',row[2]..' actual encounter can be caught')
    T.eq(g.save.party[2].species,row[2],row[2]..' capture is kept')
   end
  end
 end
end
for id in pairs(statics) do T.check(found[id],id..' has an actual map encounter script') end
-- Exercise naturally selected roaming/mythical encounters and battle.started wiring.
local R=require('mods.CRYSTAL_251.core.gen2.Roamers')
for _,row in ipairs({{'RAIKOU','ROUTE_10',2},{'ENTEI','ROUTE_7',3},{'SUICUNE','ROUTE_14',4},
 {'MEW','CERULEAN_CAVE_B1F'},{'CELEBI','VIRIDIAN_FOREST'}}) do
 local g=game();g.save.inventory.SECRET_KEY=1;g.save.flags.EVENT_BEAT_CHAMPION_RIVAL=true
 for _,badge in ipairs({'BOULDERBADGE','CASCADEBADGE','THUNDERBADGE','RAINBOWBADGE','SOULBADGE','MARSHBADGE','VOLCANOBADGE','EARTHBADGE'}) do g.save.inventory[badge]=1 end
 g.overworld.map={id=row[2],def=data.maps[row[2]]}
 T.check(reachable[row[2]],row[1]..' encounter map connects to Kanto')
 Runtime.emit('game.ready',{game=g})
 local rolled=Runtime.call('encounter.roll',function() return {species='PIDGEY',level=3} end,{},
  {mapId=row[2],terrain='grass',rng=function(a,z) return z==4 and (row[3] or 1) or 1 end})
 T.eq(rolled.species,row[1],row[1]..' is naturally selectable at its location')
 local b=battle(g,rolled.species)
 b:enter()
 T.eq(b.enemy.mon.crystal251Legendary,row[1]:lower(),row[1]..' starts with persistent legendary state')
 T.check(b.enemy.mon.hp>0 and not b.noCatch,row[1]..' is alive and catchable')
 for _,dv in pairs(b.enemy.mon.dvs) do T.check(dv>=0 and dv<=15,row[1]..' has valid DVs') end
 b:throwBall('MASTER_BALL');drain(b)
 T.eq(b.result,'caught',row[1]..' can be caught during its real battle')
 T.eq(g.save.party[2].species,row[1],row[1]..' capture is kept')
 Runtime.emit('battle.ended',{battle=b,result='caught'})
end
print('Evolution branches exercised: '..evolutionCount)
run.release();T.finish('Crystal evolution, legendary and real capture paths')
