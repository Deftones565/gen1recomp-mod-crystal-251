local Roamers = require("mods.CRYSTAL_251.core.gen2.Roamers")
local Legendaries = {}
local BADGES={"BOULDERBADGE","CASCADEBADGE","THUNDERBADGE","RAINBOWBADGE","SOULBADGE","MARSHBADGE","VOLCANOBADGE","EARTHBADGE"}
local PROFILES={
 {id="raikou",species="RAIKOU",level=40,roaming=true,secretKey=true},
 {id="entei",species="ENTEI",level=40,roaming=true,secretKey=true},
 {id="suicune",species="SUICUNE",level=40,roaming=true,secretKey=true},
 {id="mew",species="MEW",level=50,map="CERULEAN_CAVE_B1F",badges=8},
 {id="celebi",species="CELEBI",level=30,map="VIRIDIAN_FOREST",flag="EVENT_BEAT_CHAMPION_RIVAL"},
}
local function badgeCount(save) local n=0 for _,id in ipairs(BADGES) do if save.inventory and save.inventory[id] then n=n+1 end end return n end
local function dvs(rng) rng=rng or math.random local d={attack=rng(0,15),defense=rng(0,15),speed=rng(0,15),special=rng(0,15)} d.hp=(d.attack%2)*8+(d.defense%2)*4+(d.speed%2)*2+d.special%2 return d end
local function stats(def,level,d) local out={} for _,k in ipairs({"hp","attack","defense","speed","special"}) do out[k]=math.floor(((def.baseStats[k]+(d[k] or 0))*2)*level/100)+(k=="hp" and level+10 or 5) end return out end
function Legendaries.install(mod)
 local game,pending,active=nil,nil,nil
 local function state() local s=mod.save:get("crystalLegendaries") if type(s)~="table" then s={version=2} end Roamers.init(s) mod.save:set("crystalLegendaries",s) return s end
 local function open(p) local save=game and game.save if not save then return false end if p.badges and badgeCount(save)<p.badges then return false end if p.flag and not (save.flags and save.flags[p.flag]) then return false end return not p.secretKey or (save.inventory and save.inventory.SECRET_KEY) end
 local function rng(ctx) return function(a,b) local low,high = b and a or 1,b or a; return ctx and ctx.rng and ctx.rng(low,high) or math.random(low,high) end end
 local function apply(b,p,slot) local mon,def=b.enemy.mon,b.enemy.def mon.level,mon.dvs=p.level,slot.dvs or dvs() slot.dvs=mon.dvs mon.statExp={hp=0,attack=0,defense=0,speed=0,special=0} mon.stats=stats(def,p.level,mon.dvs) if (slot.hp or 0)==0 then slot.hp=math.min(255,mon.stats.hp) end mon.hp=math.max(1,math.min(slot.hp,mon.stats.hp)) b.enemy.curStats,b.enemy.shownHP=mon.stats,mon.hp b.enemy.shownStatus=nil mon.crystal251Legendary=p.id active={battle=b,profile=p,index=pending.index,slot=slot,mapId=pending.mapId,fainted=false} end
 mod.events:on("game.ready",function(ev) game=ev and ev.game or game state() end)
 mod.events:on("map.entered",function(ev) local s=state() Roamers.update(s,ev and ev.mapId,rng(ev)) mod.save:set("crystalLegendaries",s) end)
 mod.hooks:wrap("encounter.roll",function(next,def,ctx)
  pending=nil if not game or not ctx or ctx.terrain~="grass" then return next(def,ctx) end
  local s=state(); local i,slot=Roamers.checkEncounter(s,ctx.mapId,false,rng(ctx)); local p
  for _,x in ipairs(PROFILES) do if slot and x.species==slot.species then p=x end end
  if p and open(p) then pending={index=i,profile=p,slot=slot,mapId=ctx.mapId} mod.save:set("crystalLegendaries",s) return {species=slot.species,level=slot.level} end
  local ordinary=next(def,ctx)
  if not ordinary then return ordinary end
  -- Preserve the mod's custom stationary/event encounters. Roamers have
  -- already had first refusal above, matching ChooseWildEncounter.
  for _,x in ipairs(PROFILES) do
    if not x.roaming and x.map==ctx.mapId and open(x) then
      local old=s[x.id] or {dvs=dvs(rng(ctx)),status="available"}; s[x.id]=old
      if old.status=="available" and (mod.options:get("force_legendary") or rng(ctx)(32)==1) then
        pending={profile=x,slot=old,mapId=ctx.mapId}
        mod.save:set("crystalLegendaries",s)
        return {species=x.species,level=x.level}
      end
    end
  end
  return ordinary
 end,70)
 mod.events:on("battle.started",function(ev) if pending and ev.kind=="wild" and ev.species==pending.profile.species then apply(ev.battle,pending.profile,pending.slot) end pending=nil end)
 mod.hooks:wrap("battle.enemy_action",function(next,b) if active and active.battle==b and active.profile.roaming and b.enemy.mon.hp>0 then return {id="TELEPORT",pp=20} end return next(b) end,70)
 mod.events:on("battle.fainted",function(ev) if active and active.battle==ev.battle and ev.battler==ev.battle.enemy then active.fainted=true end end)
 mod.events:on("pokemon.caught",function(ev) if active and active.battle==ev.battle then local s=state() if active.profile.roaming then Roamers.endBattle(s,active.index,"caught",0,active.mapId,rng(ev)) else active.slot.status="caught" end mod.save:set("crystalLegendaries",s) ev.mon.crystal251Legendary=active.profile.id end end)
 mod.events:on("battle.ended",function(ev)
  if not active or active.battle~=ev.battle then
   if ev.battle and ((ev.battle.battleKind and ev.battle:battleKind()=="wild") or ev.battle.kind=="wild") then local s=state(); Roamers.afterWildBattle(s,ev.mapId or (game and game.overworld and game.overworld.map and game.overworld.map.id),rng(ev)); mod.save:set("crystalLegendaries",s) end
   return
  end
  local s=state(); local m=ev.battle.enemy and ev.battle.enemy.mon
  if active.profile.roaming then Roamers.endBattle(s,active.index,active.fainted and "win" or "flee",m and m.hp,active.mapId,rng(ev)) elseif active.fainted then active.slot.status="defeated" end
  mod.save:set("crystalLegendaries",s); active=nil
 end)
 return {profiles=PROFILES,roamers=Roamers}
end
return Legendaries
