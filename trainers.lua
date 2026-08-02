local Data = require("mods.CRYSTAL_251.trainer_data")

local Trainers = {}

local function copy(value)
  if type(value)~="table" then return value end
  local out={}; for k,v in pairs(value) do out[k]=copy(v) end; return out
end

local function partyReferences(mod)
  local refs = {}
  for mapId, map in mod.content.maps:each() do
    for _, object in ipairs(map.objects or {}) do
      if object.trainerClass and object.trainerParty then
        local key=object.trainerClass..":"..object.trainerParty
        refs[key]=refs[key] or {}
        refs[key][#refs[key]+1]=mapId
      end
    end
  end
  for _, maps in pairs(refs) do table.sort(maps) end
  return refs
end

local function eligible(pool, level)
  local normal, preview = {}, {}
  for _, row in ipairs(pool or {}) do
    if row.min <= level then normal[#normal+1]=row
    elseif row.min <= level+4 then preview[#preview+1]=row end
  end
  return #normal>0 and normal or preview
end

local function choose(pool, level, seed, used)
  local choices=eligible(pool,level)
  if #choices==0 then return nil end
  for offset=0,#choices-1 do
    local row=choices[(seed+offset-1)%#choices+1]
    if not used[row.id] then return row end
  end
  return choices[(seed-1)%#choices+1]
end

local function localJohtoPool(mod, maps, level)
  local found={}
  for _, mapId in ipairs(maps or {}) do
    local enc=mod.content.encounters:get(mapId)
    for _, terrain in ipairs({"grass","water"}) do
      for _, slot in ipairs((enc and enc[terrain] and enc[terrain].slots) or {}) do
        local def=mod.content.pokemon:get(slot.species)
        if def and (def.dex or 0)>=152 and (slot.level or level)<=level+4 then
          found[slot.species]=math.min(found[slot.species] or 99,slot.level or 1)
        end
      end
    end
  end
  local pool={}
  for id,min in pairs(found) do pool[#pool+1]={id=id,min=min} end
  table.sort(pool,function(a,b) return a.id<b.id end)
  return pool
end

function Trainers.install(mod)
  local refs=partyReferences(mod)
  local audit, changed = {}, 0
  for id, trainer in mod.content.trainers:each() do
    local parties=copy(trainer.parties)
    local modified=false
    for pi,party in ipairs(parties) do
      local before=copy(party)
      local boss=Data.bosses[id]
      local maps=refs[id..":"..pi] or {}
      local theme
      if #maps==1 then theme=Data.gymThemes[maps[1]] end
      theme=theme or Data.classThemes[id]
      local reviewed=Data.reviewedUnchanged[id]==true
      local maxLevel,used=0,{}
      for _,row in ipairs(party) do maxLevel=math.max(maxLevel,row.level);used[row.species]=true end

      if boss and party[boss.slot] and boss.slot<#party then
        used[party[boss.slot].species]=nil
        party[boss.slot].species=boss.species
        used[boss.species]=true
        modified=true;changed=changed+1
        theme={name="BOSS SIGNATURE",pool={{id=boss.species,min=1}}}
      elseif not reviewed and #party>0 then
        local pool=theme and theme.pool or localJohtoPool(mod,maps,maxLevel)
        local target=1
        -- Preserve the final slot as the party's familiar ace whenever there
        -- is another slot available.
        if #party>2 then target=1+(pi-1)%(#party-1) end
        local selected=choose(pool,party[target].level,pi+(trainer.index or 0),used)
        if selected and selected.id~=party[target].species then
          party[target].species=selected.id
          modified=true;changed=changed+1
        end
      end

      audit[#audit+1]={ id=id,party=pi,maps=maps,theme=theme and theme.name or
        (reviewed and "REVIEWED CANONICAL" or "LOCAL GENERALIST"),
        before=before,after=copy(party),preview=(function()
          if not theme then return false end
          for _,row in ipairs(theme.pool or {}) do
            for _,mon in ipairs(party) do if mon.species==row.id and row.min>mon.level then return true end end
          end
          return false
        end)() }
    end
    if modified then mod.content.trainers:patch(id,{parties=parties}) end
  end
  table.sort(audit,function(a,b) return a.id==b.id and a.party<b.party or a.id<b.id end)
  return {changed=changed,audit=audit,classThemes=Data.classThemes,
    gymThemes=Data.gymThemes,reviewedUnchanged=Data.reviewedUnchanged}
end

return Trainers
