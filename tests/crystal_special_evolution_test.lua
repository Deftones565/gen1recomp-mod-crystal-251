package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local f=assert(io.open(assert(os.getenv('CRYSTAL_ROM')),'rb'));local raw=f:read('*a');f:close()
local run=require('mods.CRYSTAL_251.tests._real_rom_mod').load(T,raw)
local data=run.data
local mockImage=love.image
love.image=nil -- use the engine's headless evolution flow, not the movie stub
local Pokemon=require('src.pokemon.Pokemon')
local Evolution=require('src.pokemon.Evolution')
local Clock=require('mods.CRYSTAL_251.core.gen2.Clock')
local Policy=require('mods.CRYSTAL_251.lib.evolutions')
local g={data=data,save=require('src.core.SaveData').newGame()}
g.stack={states={},push=function(self,s) self.states[#self.states+1]=s end,
 pop=function(self) return table.remove(self.states) end,top=function(self) return self.states[#self.states] end}
local function mon(id,level,happiness)
 local m=Pokemon.new(data,id,level or 20,function() return 15 end)
 m.happiness=happiness or 220;m.moves={};g.save.party={m};return m
end
local function pending(m) return Evolution.pendingFor(g,m,{kind='levelup'}) end
-- Advance presentation callbacks, keeping the real Bag, level-up and evolution code.
local function drain()
 local n=0
 while g.stack:top() do
  n=n+1;assert(n<100,'presentation callback loop')
  local s=g.stack:pop();if s.onDone then s.onDone() end
 end
end
local Screens=require('src.ui.Screens')
local originalPush=Screens.push
Screens.push=function(game,id,opts,...)
 if id=='PartyMenu' then return opts.onSwitch(game.save.party[1]) end
 return originalPush(game,id,opts,...)
end
local function use(m,item)
 g.save.inventory[item]=2
 local bag=require('src.ui.BagMenu').new(g);g.stack:push(bag)
 bag.onChoose({value=item})
 local menu=g.stack:pop();menu.items[1].onSelect()
 drain()
end
for id,target in pairs({PICHU='PIKACHU',CLEFFA='CLEFAIRY',IGGLYBUFF='JIGGLYPUFF',
 TOGEPI='TOGETIC',GOLBAT='CROBAT',CHANSEY='BLISSEY'}) do
 for _,hour in ipairs({0,4,10,18,23}) do
  Clock.setTime(g.save,hour,0)
  local m=mon(id,20,219)
  T.eq(pending(m),nil,id..' 219 friendship is insufficient')
  m.happiness=220;T.eq(pending(m),target,id..' 220 friendship qualifies at '..hour)
  m.heldItem='EVERSTONE';T.eq(pending(m),nil,id..' Everstone prevents evolution')
  m.heldItem=nil
  for _,kind in ipairs({'manual','walk','item','trade'}) do
   T.eq(Evolution.pendingFor(g,m,{kind=kind}),nil,id..' needs level-up, not '..kind)
  end
 end
 local m=mon(id,20,219)
 use(m,'RARE_CANDY')
 T.eq(m.level,21,id..' Bag Rare Candy gains a level')
 T.check(m.happiness>=220,id..' Rare Candy raises friendship before evolution')
 T.eq(m.species,target,id..' Bag Rare Candy actually evolves')
 T.eq(g.save.inventory.RARE_CANDY,1,id..' consumes one candy')
 T.eq(g.save.pokedex.owned[target],true,target..' added to dex')
end
for _,row in ipairs({{0,0,'UMBREON'},{3,59,'UMBREON'},{4,0,'ESPEON'},
 {9,59,'ESPEON'},{10,0,'ESPEON'},{17,59,'ESPEON'},{18,0,'UMBREON'},{23,59,'UMBREON'}}) do
 Clock.setTime(g.save,row[1],row[2]);local m=mon('EEVEE',20,219)
 T.eq(pending(m),nil,'Eevee requires friendship at every clock boundary')
 m.happiness=220;T.eq(pending(m),row[3],'RTC boundary '..row[1]..':'..row[2])
 m.happiness=219;use(m,'RARE_CANDY')
 T.eq(m.species,row[3],'actual Candy evolution at clock boundary')
 local m=mon('EEVEE');local done=false
 T.eq(Evolution.checkParty(g,nil,{}),0,'no after-battle evolution without a level gained')
 T.eq(m.species,'EEVEE','high friendship alone does not evolve')
 T.eq(Evolution.checkParty(g,function() done=true end,{[m]=true}),1,'after-battle sweep queues Eevee')
 drain();T.eq(m.species,row[3],'after-battle sweep applies correct time evolution')
 T.check(done,'after-battle callback completes')
end
for period,target in pairs({MORN='ESPEON',DAY='ESPEON',NITE='UMBREON',NITE_F='UMBREON'}) do
 g.overworld={timeOfDay=function() return period end}
 T.eq(pending(mon('EEVEE')),target,'active world '..period)
end
g.overworld=nil
-- Real battle awards must return deferred steps, raise friendship when those
-- steps commit, and mark the Pokemon for the after-battle evolution sweep.
for _,hour in ipairs({12,22}) do
 local m=mon('EEVEE',20,219);Clock.setTime(g.save,hour,0)
 local Growth=require('src.pokemon.Growth')
 m.exp=Growth.expForLevel(data.pokemon.EEVEE.growthRate,21,data.growth_rates)-1
 love.image=mockImage
 local b=require('src.battle.BattleState').newWild(g,'CATERPIE',2)
 love.image=nil
 b.crystal251Active=true;b.queue={};b.nextInsert=0
 b:awardExp()
 T.eq(m.level,20,'battle level waits for its queued commit')
 T.eq(m.happiness,219,'friendship waits for level commit')
 local n=0
 while #b.queue>0 do
  n=n+1;assert(n<100,'battle queue loop')
  local row=table.remove(b.queue,1);b.nextInsert=0
  if row.fn then row.fn() end
 end
 drain()
 T.eq(m.level,21,'battle experience commits the new level')
 T.check(m.happiness>=220,'battle level crosses friendship threshold')
 T.check(b.leveledUp[m],'battle tracks Pokemon that gained levels')
 Evolution.checkParty(g,nil,b.leveledUp);drain()
 T.eq(m.species,hour==12 and 'ESPEON' or 'UMBREON','battle-earned friendship evolution')
end
for _,row in ipairs({{101,100,'HITMONLEE'},{99,100,'HITMONCHAN'},{100,100,'HITMONTOP'}}) do
 local m=mon('TYROGUE',19);m.stats.attack=row[1];m.stats.defense=row[2]
 T.eq(pending(m),nil,'Tyrogue cannot evolve below 20')
 m.level=20;T.eq(pending(m),row[3],'Tyrogue current stats select '..row[3])
 m.heldItem='EVERSTONE';T.eq(pending(m),nil,'Everstone blocks '..row[3]);m.heldItem=nil
 Evolution.checkParty(g,nil,{[m]=true});drain()
 T.eq(m.species,row[3],'after-battle evolution applies '..row[3])
end
for _,row in ipairs({{15,0,'HITMONLEE'},{0,15,'HITMONCHAN'},{15,15,'HITMONTOP'}}) do
 local m=mon('TYROGUE',19);m.dvs.attack=row[1];m.dvs.defense=row[2]
 use(m,'RARE_CANDY')
 T.eq(m.species,row[3],'Tyrogue Candy compares recalculated level 20 stats')
end
for id,rule in pairs(Policy.levelTrades) do
 local m=mon(id,rule.level-1)
 T.eq(pending(m),nil,id..' below substitute trade level')
 m.level=rule.level;T.eq(pending(m),rule.species,id..' correct substitute trade level')
 m.heldItem='EVERSTONE';T.eq(pending(m),nil,id..' Everstone blocks substitute trade evolution')
 m.heldItem=nil;m.level=rule.level-1;use(m,'RARE_CANDY')
 T.eq(m.species,rule.species,id..' Candy reaches substitute trade evolution')
end
-- Gen II permits deliberate item evolution even while Everstone is held.
for id,def in pairs(data.pokemon) do
 for _,evo in ipairs(def.evolutions or {}) do
  if evo.method=='ITEM' then
   local m=mon(id);m.heldItem='EVERSTONE'
   T.eq(Evolution.pendingFor(g,m,{kind='item',item='POTION'}),nil,id..' rejects wrong evolution item')
   use(m,evo.item)
   T.eq(m.species,evo.species,id..' actual Bag '..evo.item..' -> '..evo.species)
   T.eq(g.save.inventory[evo.item],1,evo.item..' consumed once')
  end
 end
end
local m=mon('BULBASAUR',16);m.heldItem='EVERSTONE'
T.eq(pending(m),nil,'Everstone also blocks ordinary level evolution')
m.heldItem=nil;T.eq(pending(m),'IVYSAUR','removing Everstone restores evolution')
Screens.push=originalPush
run.release();T.finish('Crystal friendship, clock and special evolution integration')
