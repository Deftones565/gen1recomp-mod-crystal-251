package.path = './?.lua;./?/init.lua;' .. package.path
local T = require('tests.modkit')
local file = assert(io.open(assert(os.getenv('CRYSTAL_ROM'), 'set CRYSTAL_ROM'), 'rb'))
local raw = file:read('*a'); file:close()
local run = require('mods.CRYSTAL_251.tests._real_rom_mod').load(T, raw)
T.eq(#run.errors, 0, 'real ROM boots the complete mod')
local Runtime = require('src.mods.Runtime')
local Game = require('src.core.Game')
local Pokemon = require('src.pokemon.Pokemon')
local Clock = require('mods.CRYSTAL_251.core.gen2.Clock')
local Daycare = require('mods.CRYSTAL_251.daycare')
local Roamers = require('mods.CRYSTAL_251.core.gen2.Roamers')
local ItemEffects = require('src.inventory.ItemEffects')
local Follower = require('src.world.PikachuFollower')
local save = require('src.core.SaveData').newGame()
local mon = Pokemon.new(run.data, 'EEVEE', 20, function() return 15 end)
mon.happiness = 70
save.party = {mon}
Game.save, Game.data = save, run.data
Game.overworld = {map={id='ROUTE_10'},timeOfDay=function()
  return Runtime.call('world.tod', function(tod) return tod end, 'DAY', {})
end}
Game.stack = {states={},push=function(self,s) self.states[#self.states+1]=s end}
for _, hour in ipairs({8,12,22}) do
  Clock.setTime(save,hour,0)
  T.eq(Game.overworld:timeOfDay(), Clock.daytime(hour), 'RTC reaches the Kanto overworld')
  local rows = Runtime.call('ui.start_menu.items', function(_,r) return r end, Game,{})
  T.check(rows[#rows].label:find(('TIME %02d:'):format(hour),1,true), 'START clock uses the shared RTC')
end
mon.happiness=220
local methods = run.data.evolution_methods
T.check(methods.EVOLVE_HAPPINESS_NITE.check(Game,mon,{}, {kind='levelup'}), 'Umbreon evolves at night without trigger time')
T.check(not methods.EVOLVE_HAPPINESS_MORNDAY.check(Game,mon,{}, {kind='levelup'}), 'Espeon cannot evolve at night')
Clock.setTime(save,12,0)
T.check(methods.EVOLVE_HAPPINESS_MORNDAY.check(Game,mon,{}, {kind='levelup'}), 'Espeon evolves in daytime')
mon.heldItem='EVERSTONE'
T.check(not methods.EVOLVE_HAPPINESS_MORNDAY.check(Game,mon,{}, {kind='levelup'}), 'Everstone blocks friendship evolution')
mon.heldItem=nil
mon.happiness=70
save.daycare={crystal251=true,slots={},stepCounter=0}
for i=1,511 do Daycare.stepState(save,run.data,function(a) return a end) end
T.eq(mon.happiness,70,'walking does not award friendship before step 512')
Daycare.stepState(save,run.data,function(a) return a end)
T.eq(mon.happiness,71,'shared Day Care counter awards exactly one point at step 512')
Runtime.emit('world.stepped',{})
T.eq(mon.happiness,71,'world observer does not duplicate the Day Care award')
local egg={species='TOGEPI',isEgg=true,eggCycles=1,happiness=1,hp=1}
save.party[2]=egg; save.daycare.stepCounter=127
T.eq(Daycare.stepState(save,run.data,function(a) return a end),egg,'hatch phase returns the actual egg')
T.eq(mon.happiness,71,'hatch return does not award friendship')
save.party[2]=nil
mon.happiness=70
local result=ItemEffects.use(run.data,save,'PROTEIN',mon)
T.eq(result,'consumed','vitamin follows actual item handler')
T.eq(mon.happiness,75,'successful vitamin raises friendship')
local old=mon.happiness
ItemEffects.use(run.data,save,'PROTEIN',nil)
T.eq(mon.happiness,old,'failed item does not raise friendship')
local machine=run.data.items.TM_MEGA_PUNCH
mon=Pokemon.new(run.data,'MEW',20,function() return 15 end)
mon.moves={}; mon.happiness=70; save.party={mon}
local result,move=ItemEffects.use(run.data,save,'TM_MEGA_PUNCH',mon)
T.eq(result,'learn','retained Kanto TM has a compatible recipient')
T.eq(mon.happiness,70,'opening the teaching prompt does not award friendship')
mon.moves={{id=move,pp=10}}
Follower.modifyHappiness(save,'USEDTMHM',mon)
T.eq(mon.happiness,71,'successful TM callback awards friendship')
Follower.modifyHappiness(save,'USEDTMHM',mon)
T.eq(mon.happiness,71,'duplicate teaching notification cannot award twice')
local battle={crystal251Active=true,kind='trainer',oppClass='OPP_BROCK',game=Game,
  player={isPlayer=true,mon=mon},enemy={mon={level=50}}}
Runtime.emit('battle.started',{battle=battle,kind='trainer'})
T.eq(mon.happiness,74,'Gym battle awards party friendship')
Runtime.emit('battle.started',{battle=battle,kind='trainer'})
T.eq(mon.happiness,74,'Gym battle award is once per battle')
Runtime.emit('battle.fainted',{battle=battle,battler=battle.player})
T.eq(mon.happiness,69,'fainting to a foe 30 levels higher applies the larger loss')
battle.kind='link'
Runtime.emit('battle.fainted',{battle=battle,battler=battle.player})
T.eq(mon.happiness,69,'link fainting preserves friendship')
mon.hp=1; mon.status='PSN'; save.poisonSteps=3
-- Headless tests do not enter a rendered map. Bind the same Game upvalue
-- that Overworld:enter initializes, leaving the poison implementation intact.
local function bindGame(fn, seen)
  seen=seen or {}; if seen[fn] then return end; seen[fn]=true
  for i=1,100 do
    local key,value=debug.getupvalue(fn,i); if not key then break end
    if key=='Game' then debug.setupvalue(fn,i,Game)
    elseif type(value)=='function' then bindGame(value,seen) end
  end
end
local poison=require('src.world.OverworldController').applyFieldPoison
bindGame(poison)
poison(Game.overworld)
T.eq(mon.hp,0,'actual field poison faints the recipient')
T.eq(mon.happiness,64,'field poison faint applies Crystal friendship loss')
for _, row in ipairs(Roamers.MAPS) do
  T.check(run.data.maps[row.map] ~= nil,row.map .. ' roaming node exists in Kanto')
  T.check(run.data.encounters[row.map] and run.data.encounters[row.map].grass,row.map .. ' supports grass encounters')
end
local Progression=require('mods.CRYSTAL_251.battle.crystal_progression')
local captured=Pokemon.new(run.data,'EEVEE',20,function() return 15 end)
Progression.prepareCaughtMon({enemy={mon=captured},game=Game,lastBall='POKE_BALL'})
T.eq(captured.caughtData.mapId,'ROUTE_10','capture stores the Kanto origin for friendship')
local Happiness=require('mods.CRYSTAL_251.core.gen2.Happiness')
T.eq(Happiness.levelUpEvent(captured,'ROUTE_10'),'GAINLEVELATHOME','origin map selects Crystal home bonus')
T.eq(Happiness.levelUpEvent(captured,'ROUTE_11'),'GAINLEVEL','another map uses ordinary level friendship')
local state={roamers={{species='RAIKOU',level=40,map='ROUTE_42',hp=37,dvs={attack=9}},
 {hp=0},{species='SUICUNE',level=40,map='ROUTE_38',hp=42}}}
Roamers.init(state)
T.eq(state.roamers[1].map,'ROUTE_10','old Johto save migrates onto Kanto routes')
T.eq(state.roamers[1].hp,37,'migration preserves roamer damage')
T.eq(state.roamers[1].dvs.attack,9,'migration preserves DVs')
T.eq(state.roamers[2].species,nil,'migration does not revive caught roamers')
local index,slot=Roamers.checkEncounter(state,'ROUTE_10',false,function(n) return n==4 and 2 or 1 end)
T.eq(index,1,'migrated roamer can be encountered naturally')
T.eq(slot,state.roamers[1],'encounter keeps persistent state')
T.eq(Roamers.checkEncounter(state,'ROUTE_10',true,function() return 1 end),nil,'roamers do not appear while surfing')
-- Exercise the production legendary adapter with real Kanto event shapes.
Runtime.emit('game.ready',{game=Game})
local function natural(a,b) return b==32 and 1 or b end
local function encounter() return Runtime.call('encounter.roll',function() return {species='PIDGEY',level=3} end,
  {},{mapId='VIRIDIAN_FOREST',terrain='grass',rng=natural}) end
T.check(encounter().species ~= 'CELEBI','Celebi remains gated before champion')
save.flags.EVENT_BEAT_CHAMPION_RIVAL=true
T.eq(encounter().species,'CELEBI','Celebi is available after champion on a natural successful roll')
run.release()
T.finish('Crystal ROM-backed service integration')
