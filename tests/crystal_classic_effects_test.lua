package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local f=assert(io.open(assert(os.getenv('CRYSTAL_ROM'),'set CRYSTAL_ROM'),'rb'))
local raw=f:read('*a'); f:close()
local run=require('mods.CRYSTAL_251.tests._real_rom_mod').load(T,raw)
local data=run.data
local Pokemon=require('src.pokemon.Pokemon')
local Battle=require('src.battle.BattleState')
local function fresh(id)
  local mon=Pokemon.new(data,'MEW',50,function() return 15 end)
  mon.moves={{id=id,pp=20}}
  local save=require('src.core.SaveData').newGame(); save.party={mon}
  local game={save=save,data=data,stack={push=function() end},input={wasPressed=function() return true end}}
  local b=Battle.newWild(game,'SNORLAX',50)
  b.phase='menu'; b.rng=function(a,z) return a end
  b.accuracyRoll=function() return true end
  for _,who in ipairs({b.player,b.enemy}) do who.mon.hp=1000; who.mon.stats.hp=1000; who.shownHP=1000 end
  return b
end
local function use(b,id)
  local mv=b.player.curMoves[1]
  if mv.id~=id then mv={id=id,pp=20} end
  b:performMove(b.player,b.enemy,mv)
end
-- Every imported effect must do work or explicitly belong to the damage hook.
local neutral={CRYSTAL_EFFECT_00=true,CRYSTAL_EFFECT_65=true,CRYSTAL_EFFECT_79=true,
 CRYSTAL_EFFECT_7B=true,CRYSTAL_EFFECT_87=true}
for id,move in pairs(data.moves) do
  if type(move)=='table' and move.index and move.index<=251 then
    local effect=data.move_effects[move.effect]
    local active=neutral[move.effect] or effect and effect.charge
    for _,v in pairs(effect or {}) do if type(v)=='function' then active=true end end
    T.check(active,id..' has an implemented Crystal effect')
  end
end
for _,id in ipairs({'ABSORB','MEGA_DRAIN','GIGA_DRAIN','DREAM_EATER'}) do
  local b=fresh(id); b.player.mon.hp=500; b.enemy.mon.status='SLP'
  use(b,id)
  T.check(b.enemy.mon.hp<1000,id..' deals damage')
  T.eq(b.player.mon.hp,500+math.max(1,math.floor((1000-b.enemy.mon.hp)/2)),id..' drains half the damage')
end
local b=fresh('DREAM_EATER'); use(b,'DREAM_EATER')
T.eq(b.enemy.mon.hp,1000,'Dream Eater fails against an awake target')
for _,id in ipairs({'SELFDESTRUCT','EXPLOSION'}) do
  b=fresh(id); use(b,id); T.eq(b.player.mon.hp,0,id..' faints its user')
  b=fresh(id); b.accuracyRoll=function() return false end; use(b,id)
  T.eq(b.player.mon.hp,0,id..' also faints its user on a miss')
end
b=fresh('TAKE_DOWN');use(b,'TAKE_DOWN')
T.eq(1000-b.player.mon.hp,math.max(1,math.floor((1000-b.enemy.mon.hp)/4)),'recoil uses Crystal quarter damage')
b=fresh('HYPER_BEAM'); b.enemy.mon.hp=1;use(b,'HYPER_BEAM')
T.eq(b.player.mustRecharge,true,'Hyper Beam requires recharge even after a knockout')
b=fresh('PAY_DAY');use(b,'PAY_DAY')
T.eq(b.payDay,100,'Pay Day scatters twice user level')
for _,id in ipairs({'RECOVER','SOFTBOILED','MILK_DRINK'}) do
  b=fresh(id);b.player.mon.hp=200;use(b,id)
  T.eq(b.player.mon.hp,700,id..' heals half maximum HP')
end
b=fresh('REST');b.player.mon.hp=200;use(b,'REST')
T.eq(b.player.mon.hp,1000,'Rest still heals fully')
T.eq(b.player.mon.status,'SLP','Rest applies sleep')
for _,id in ipairs({'DIG','FLY','RAZOR_WIND','SKY_ATTACK','SKULL_BASH','SOLARBEAM'}) do
  b=fresh(id);use(b,id)
  T.eq(b.enemy.mon.hp,1000,id..' charges without immediate damage')
  T.check(b.player.charging,id..' records its pending move')
  if id=='DIG' or id=='FLY' then T.eq(b.player.invulnerableMove,id,id..' supplies Crystal invulnerability identity') end
  if id=='SKULL_BASH' then T.eq(b.player.stages.defense,1,'Skull Bash raises defense during charge') end
  use(b,id)
  T.check(b.enemy.mon.hp<1000,id..' releases damage on the second use')
  T.eq(b.player.invulnerableMove,nil,id..' clears invulnerability after release')
end
b=fresh('SOLARBEAM');b.weather='sun';use(b,'SOLARBEAM')
T.check(b.enemy.mon.hp<1000 and not b.player.charging,'sun removes SolarBeam charge')
b=fresh('MIMIC');b.enemy.lastMove='TACKLE';use(b,'MIMIC')
T.eq(b.player.curMoves[1].id,'TACKLE','Mimic copies the last used move')
T.eq(b.player.mon.moves[1].id,'MIMIC','Mimic preserves the party move')
b=fresh('CONVERSION'); b.player.curMoves[2]={id='THUNDERBOLT',pp=10};use(b,'CONVERSION')
T.eq(b.player.curTypes[1],'NORMAL','Conversion may use its own Normal type')
b=fresh('TELEPORT');use(b,'TELEPORT')
T.eq(b.result,'run','Teleport ends a wild battle')
b=fresh('TELEPORT');b.kind='trainer';use(b,'TELEPORT')
T.eq(b.result,nil,'Teleport cannot escape trainer battles')
b=fresh('TELEPORT');b.crystalBattleType='trap';use(b,'TELEPORT')
T.eq(b.result,nil,'Teleport respects a forced trap battle')
b=fresh('JUMP_KICK');b.player.mon.hp=1;b.accuracyRoll=function() return false end
local fainted
b.onFaint=function(_,who) fainted=who end
use(b,'JUMP_KICK')
T.eq(b.player.mon.hp,0,'Jump Kick crash can knock out the user')
T.eq(fainted,b.player,'Jump Kick crash enters the faint pipeline')
run.release()
T.finish('Crystal original move family backport')
