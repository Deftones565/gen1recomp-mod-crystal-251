package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
local path = os.getenv("CRYSTAL_ROM") or "Pokemon - Crystal Version (UE) (V1.1) [C][!].gbc"
local file = io.open(path,"rb")
if not file then
  print("SKIP crystal 251 integration (set CRYSTAL_ROM to a supported ROM)")
  os.exit(0)
end
local raw=file:read("*a"); file:close()
love.data = {
  hash=function(kind, value)
    assert(kind == "sha1" and value == raw)
    return "verified-crystal-v11"
  end,
  encode=function(container, encoding, digest)
    assert(container == "string" and encoding == "hex"
      and digest == "verified-crystal-v11")
    return "f2f52230b536214ef7c9924f483392993e226cfb"
  end,
}
local Data=require("src.core.Data"); Data:load()
local function deepCopy(value)
  if type(value) ~= "table" then return value end
  local out = {}
  for key, child in pairs(value) do out[key] = deepCopy(child) end
  return out
end
local nativeGen1Moves = {}
for id, move in pairs(Data.moves) do
  if move.index and move.index <= 165 then nativeGen1Moves[id] = deepCopy(move) end
end
local sourcePrefix="assets/generated/"
local inner=T.fs.new(".")
local fs={root=inner.root}
function fs.read(path)
  if path=="mods/CRYSTAL_251/baseroms/crystal.gbc" then return raw end
  if path:sub(1,#sourcePrefix)==sourcePrefix then return nil end
  return inner.read(path)
end
function fs.write() return true end
function fs.createDirectory() return true end
function fs.load(path) return inner.load(path) end
function fs.getInfo(path)
  if path:sub(1,#sourcePrefix)==sourcePrefix then return nil end
  return inner.getInfo(path)
end
function fs.getDirectoryItems(path)
  if path=="mods" then return {"CRYSTAL_251","SHINY_INDICATORS"} end
  return inner.getDirectoryItems(path)
end
local run=T.sdk.loadMods({"mods/CRYSTAL_251","mods/SHINY_INDICATORS"},{data=Data,fs=fs})
T.eq(#run.errors,0,"mod and imported content load without registry errors")
for id, before in pairs(nativeGen1Moves) do
  local after = run.data.moves[id]
  T.eq(after.id, before.id, id .. " keeps its native id")
  T.eq(after.name, before.name, id .. " keeps its native name")
  T.eq(after.index, before.index, id .. " keeps its native index")
end
T.eq(run.data.moves.SKETCH.index, 166,
  "Crystal 251 begins registering moves at Generation II index 166")
T.eq(run.data.constants.dexSize,251,"Pokedex expands to 251")
T.eq(#run.data.constants.hmMoves,7,"Whirlpool and Waterfall join the HM rules")
local machineMoves=require("mods.CRYSTAL_251.catalog").tmItems
for _,def in pairs(run.data.items) do
  local machine=def.machine
  if machine and machine.kind=="TM" and machine.number>=1 and machine.number<=50 then
    T.eq(machine.move,machineMoves[machine.number],
      ("TM%02d teaches its Crystal move"):format(machine.number))
  elseif machine and machine.kind=="HM" and machine.number>=1 and machine.number<=7 then
    T.eq(machine.move,machineMoves[50+machine.number],
      ("HM%02d teaches its Crystal move"):format(machine.number))
  end
end
T.eq(run.data.items.TM_MEGA_PUNCH.machine.move,"DYNAMICPUNCH",
  "the existing Gen I TM01 item now teaches Crystal TM01 DynamicPunch")
T.eq(run.data.items.TM_RAZOR_WIND.machine.move,"HEADBUTT",
  "the existing Gen I TM02 item now teaches Crystal TM02 Headbutt")
T.eq(run.data.items.TM_SWORDS_DANCE.machine.move,"CURSE",
  "the existing Gen I TM03 item now teaches Crystal TM03 Curse")
local machopTmhm={}
for _,move in ipairs(run.data.pokemon.MACHOP.tmhm or {}) do machopTmhm[move]=true end
for _,move in ipairs({"DYNAMICPUNCH","HEADBUTT","CURSE"}) do
  T.check(machopTmhm[move],"Machop retains Crystal compatibility with "..move)
end
T.eq(run.data.pokemon.MAGIKARP.battleScaleBack,1,
  "the live battle registry keeps Crystal back sprites at native scale")

local ecology=run.loader.exports.CRYSTAL_251.ecology
T.eq(ecology.maps,58,"every Kanto and Crystal 251 wild map has a curated ecology")
T.eq(ecology.groups,60,"grass and Surf habitats are independently curated")
local obtainable={}
for species in pairs(ecology.direct) do obtainable[species]=true end
-- These retain their established gift, prize, static, trade, or legendary
-- source rather than being forced into an unrelated wild habitat.
for _,species in ipairs({"LICKITUNG","MR_MIME","LAPRAS","PORYGON","SNORLAX",
  "ARTICUNO","ZAPDOS","MOLTRES","MEWTWO","MEW","RAIKOU","ENTEI","SUICUNE",
  "CELEBI"}) do obtainable[species]=true end
for _,map in pairs(run.data.maps) do
  for _,object in ipairs(map.objects or {}) do
    if object.pokemon then obtainable[object.pokemon]=true end
  end
end
local fishing=run.data.field.fishing or {}
for _,rod in pairs(fishing) do
  if type(rod)=="table" then
    if rod.always then obtainable[rod.always.species]=true end
    for _,slot in ipairs(rod.pool or {}) do obtainable[slot.species]=true end
  end
end
for _,pool in pairs(run.data.field.superRod or {}) do
  for _,slot in ipairs(pool) do obtainable[slot.species]=true end
end
local changed=true
while changed do
  changed=false
  for id,mon in pairs(run.data.pokemon) do
    if obtainable[id] then
      for _,evo in ipairs(mon.evolutions or {}) do
        if not obtainable[evo.species] then
          obtainable[evo.species]=true; changed=true
        end
      end
    end
  end
end
local covered=0
local cache = assert(require("mods.CRYSTAL_251.lib.cache").readContent())
for _,species in ipairs(cache.species) do
  T.check(obtainable[species.id],species.id .. " has a wild, special, or evolution path")
  if obtainable[species.id] then covered=covered+1 end
end
T.eq(covered,251,"the acquisition graph covers all 251 species")

local ecologyRows=ecology.list()
T.eq(#ecologyRows,ecology.groups*4,
  "every habitat exports morning, day, night, and all-day documentation")
for _,row in ipairs(ecologyRows) do
  T.eq(#row.group.slots,10,row.mapId.."/"..row.terrain.."/"..row.period..
    " keeps the Generation I ten-slot probability table")
end
for _,species in ipairs({"IVYSAUR","VENUSAUR","BAYLEEF","MEGANIUM",
  "CHARMELEON","CHARIZARD","QUILAVA","TYPHLOSION","WARTORTLE",
  "BLASTOISE","CROCONAW","FERALIGATR"}) do
  T.check(not ecology.direct[species],species.." remains an evolution reward")
end
for _,species in ipairs({"BULBASAUR","CHIKORITA","CHARMANDER","CYNDAQUIL",
  "SQUIRTLE","TOTODILE"}) do
  T.check(ecology.direct[species],species.." has a rare themed wild source")
end
local function habitatHas(mapId,terrain,period,species)
  for _,row in ipairs(ecologyRows) do
    if row.mapId==mapId and row.terrain==terrain and row.period==period then
      for _,slot in ipairs(row.group.slots) do
        if slot.species==species then return true end
      end
    end
  end
  return false
end
T.check(habitatHas("POKEMON_TOWER_3F","grass","night","MISDREAVUS"),
  "Pokemon Tower gains a nocturnal ghost habitat")
T.check(habitatHas("POWER_PLANT","grass","day","ELEKID"),
  "Power Plant contains electric baby Pokemon")
T.check(habitatHas("SEAFOAM_ISLANDS_1F","grass","day","SWINUB"),
  "Seafoam contains cold-climate Pokemon")
T.check(habitatHas("POKEMON_MANSION_3F","grass","day","CYNDAQUIL"),
  "the fire starter is rare in the burned laboratory habitat")
T.check(habitatHas("VICTORY_ROAD_1F","grass","day","LARVITAR"),
  "Larvitar is reserved for a late rocky habitat")

local sanctuary=run.loader.exports.CRYSTAL_251.sanctuaries
local island=run.data.maps[sanctuary.island]
local cave=run.data.maps[sanctuary.cave]
T.check(island~=nil,"Navel Isle is a mod-owned overworld map")
T.check(cave~=nil,"Tidal Cave is a separate mod-owned cavern map")
T.eq(run.data.maps.CINNABAR_ISLAND.connections.south.map,sanctuary.island,
  "Cinnabar connects south to the new island")
T.eq(island.connections.north.map,"CINNABAR_ISLAND",
  "the island connection returns north to Cinnabar")
T.eq(island.warps[1].destMap,sanctuary.cave,"the badge-gated island entrance leads to Tidal Cave")
T.eq(cave.warps[1].destMap,sanctuary.island,"Tidal Cave exits back onto the island")
local WorldMap=require("src.world.Map")
T.check(island.index<run.data.field.indoorEncounters.firstIndoorMap,
  "Tidal Isle is classified as outdoor terrain rather than an all-tile cave")
local islandRuntime=WorldMap.new(island,run.data.tilesets[island.tileset])
T.check(islandRuntime:isGrassCell(18,8),"the island's visible tall grass is encounter terrain")
T.check(not islandRuntime:isGrassCell(8,12),"the island's ordinary ground is not encounter terrain")
local function reachable(def,startX,startY,targetX,targetY,surfing)
  local tileset=run.data.tilesets[def.tileset]
  local queue,head,seen={{startX,startY}},1,{[startX..","..startY]=true}
  while queue[head] do
    local at=queue[head]; head=head+1
    if at[1]==targetX and at[2]==targetY then return true end
    for _,d in ipairs({{1,0},{-1,0},{0,1},{0,-1}}) do
      local x,y=at[1]+d[1],at[2]+d[2]
      local key=x..","..y
      if not seen[key] and x>=0 and y>=0 and x<def.width*2 and y<def.height*2
          and WorldMap.defPassable(def,tileset,x,y,surfing) then
        seen[key]=true; queue[#queue+1]={x,y}
      end
    end
  end
  return false
end
T.check(reachable(island,14,0,island.warps[1].x,island.warps[1].y+1,true),
  "the Cinnabar surf connection has a traversable route to the cave cliff")
T.check(reachable(cave,cave.warps[1].x,cave.warps[1].y,10,4,false),
  "Tidal Cave has a walkable route from its exit to the tile below Lugia")
T.check(cave.tileset~="CAVERN","Tidal Cave isolates its pool collision from vanilla caves")
local caveWaterEnabled=false
for _,id in ipairs(run.data.field.waterTilesets or{}) do
  if id==cave.tileset then caveWaterEnabled=true end
end
T.check(caveWaterEnabled,"Tidal Cave's private tileset still permits Surf")
local function surfCanEscape(def,startX,startY)
  local tileset=run.data.tilesets[def.tileset]
  local queue,head,seen={{startX,startY}},1,{[startX..","..startY]=true}
  while queue[head] do
    local at=queue[head];head=head+1
    if WorldMap.defIsWalkableCell(def,tileset,at[1],at[2]) then return true end
    for _,d in ipairs({{1,0},{-1,0},{0,1},{0,-1}}) do
      local x,y=at[1]+d[1],at[2]+d[2]
      local key=x..","..y
      if not seen[key] and x>=0 and y>=0 and x<def.width*2 and y<def.height*2
          and WorldMap.defPassable(def,tileset,x,y,true) then
        seen[key]=true;queue[#queue+1]={x,y}
      end
    end
  end
  return false
end
for y=0,cave.height*2-1 do for x=0,cave.width*2-1 do
  if WorldMap.defIsWaterCell(cave,run.data.tilesets[cave.tileset],x,y) then
    T.check(surfCanEscape(cave,x,y),("Tidal Cave pool cell %d,%d can return to land"):format(x,y))
  end
end end
local lugia,hoOh,rumor
for _,object in ipairs(cave.objects or {}) do
  if object.pokemon=="LUGIA" then lugia=object end
end
for _,object in ipairs(run.data.maps.POKEMON_TOWER_7F.objects or {}) do
  if object.pokemon=="HO_OH" then hoOh=object end
end
for _,object in ipairs(run.data.maps.LAVENDER_TOWN.objects or {}) do
  if object.name=="CRYSTAL251_LAVENDER_SKYWATCHER" then rumor=object end
end
T.check(lugia and lugia.sprite=="CRYSTAL_251_SPRITE_LUGIA" and lugia.level==60,
  "Lugia uses its dedicated Crystal level-60 overworld sprite")
T.check(hoOh and hoOh.sprite=="CRYSTAL_251_SPRITE_HO_OH"
    and hoOh.level==60 and hoOh.hidden,
  "Ho-Oh uses its gated dedicated Crystal level-60 overworld sprite")
local tower=run.data.maps.POKEMON_TOWER_7F
local towerCells={}
for _,object in ipairs(tower.objects or {}) do
  local cell=object.x..","..object.y
  T.check(not towerCells[cell], (object.name or "tower object")
    .. " does not overlap " .. tostring(towerCells[cell]))
  towerCells[cell]=object.name
end
T.eq(hoOh and hoOh.x,11,"Ho-Oh uses the unoccupied summit column")
T.eq(hoOh and hoOh.y,3,"Ho-Oh remains at the Tower summit")
T.check(WorldMap.defIsWalkableCell(tower,run.data.tilesets[tower.tileset],11,4),
  "the player can stand below Ho-Oh and target it directly")
T.check(rumor~=nil,"Lavender gains an always-present Ho-Oh rumor NPC")

local tidalTrainers={}
for _,object in ipairs(island.objects or{}) do
  if object.trainerClass then tidalTrainers[#tidalTrainers+1]=object end
  T.check(object.sprite~="SPRITE_BOULDER","Tidal Isle no longer uses a boulder cave seal")
end
T.eq(#tidalTrainers,4,"Tidal Isle has two Swimmers and two land trainers")
for _,object in ipairs(tidalTrainers) do
  T.check(run.data.sprites[object.sprite]~=nil,object.name.." uses a registered overworld sprite")
  local water=WorldMap.defIsWaterCell(island,run.data.tilesets[island.tileset],object.x,object.y)
  if object.sprite=="SPRITE_SWIMMER" then
    T.check(water,object.name.." waits in the surf channel")
  else
    T.check(WorldMap.defIsWalkableCell(island,run.data.tilesets[island.tileset],object.x,object.y),
      object.name.." stands on passable island ground")
  end
end
local oceanOnly={TENTACOOL=true,CORSOLA=true,QWILFISH=true,MANTINE=true,
  CHINCHOU=true,REMORAID=true,DRATINI=true}
for _,row in ipairs(ecology.list()) do
  if row.mapId==sanctuary.island and row.terrain=="grass" then
    for _,slot in ipairs(row.group.slots) do
      T.check(not oceanOnly[slot.species],slot.species.." stays out of Tidal Isle grass")
    end
  end
end

local MapScripts=require("src.script.MapScripts")
local function fakeOverworld(mapId)
  local out={map={id=mapId,def=run.data.maps[mapId]},npcs={},entities={},npcPool={}}
  function out:replaceBlock(bx,by,block)
    self.map.def.blocks[by*self.map.def.width+bx+1]=block
  end
  return out
end
local gateGame={data=run.data,save={inventory={},flags={},objectToggles={},options={}}}
for index,badge in ipairs({"BOULDERBADGE","CASCADEBADGE","THUNDERBADGE",
  "RAINBOWBADGE","SOULBADGE","MARSHBADGE","VOLCANOBADGE","EARTHBADGE"}) do
  if index<8 then gateGame.save.inventory[badge]=true end
end
MapScripts.get(sanctuary.island).onEnter(gateGame,fakeOverworld(sanctuary.island))
local function islandBlock(bx,by) return island.blocks[by*island.width+bx+1] end
T.eq(islandBlock(sanctuary.caveDoor.bx,sanctuary.caveDoor.by),sanctuary.caveDoor.closed,
  "the cave cliff has no door before badge eight")
gateGame.save.inventory.EARTHBADGE=true
MapScripts.get(sanctuary.island).onEnter(gateGame,fakeOverworld(sanctuary.island))
T.eq(islandBlock(sanctuary.caveDoor.bx,sanctuary.caveDoor.by),sanctuary.caveDoor.open,
  "badge eight spawns the real cave door block")
run.loader.events:emit("game.ready",{game=gateGame})
for index=1,4 do
  local header=gateGame.data:trainerHeader("TidalIsle",index)
  T.check(header and header.range>0,"Tidal trainer "..index.." has a sight range")
  T.check(header and gateGame.data.text[header.battle] and gateGame.data.text[header.won]
      and gateGame.data.text[header.after],
    "Tidal trainer "..index.." has encounter, victory, and defeated dialogue")
end
MapScripts.get("POKEMON_TOWER_7F").onEnter(gateGame,fakeOverworld("POKEMON_TOWER_7F"))
T.eq(gateGame.save.objectToggles.POKEMON_TOWER_7F[sanctuary.hoOhObject],false,
  "eight badges alone do not reveal Ho-Oh")
gateGame.save.flags.EVENT_RESCUED_MR_FUJI=true
MapScripts.get("POKEMON_TOWER_7F").onEnter(gateGame,fakeOverworld("POKEMON_TOWER_7F"))
T.eq(gateGame.save.objectToggles.POKEMON_TOWER_7F[sanctuary.hoOhObject],true,
  "Ho-Oh appears only after badge eight and Mr. Fuji's rescue")
local rumorRows=MapScripts.talkScript("LAVENDER_TOWN",
  "TEXT_CRYSTAL251_LAVENDER_SKYWATCHER")
local rumorText=rumorRows and rumorRows[2] and rumorRows[2][2] or ""
T.check(rumorText:find("shadow",1,true) and not rumorText:find("HO%-OH"),
  "the Lavender dialogue hints at Ho-Oh without naming it")
local function hasStatic(rows,species,level,flag)
  for _,command in ipairs(rows or {}) do
    if command[1]=="static_battle" and command[2]==species
        and command[3]==level and command[4]==flag then return true end
  end
  return false
end
T.check(hasStatic(MapScripts.talkScript("POKEMON_TOWER_7F",
  "TEXT_CRYSTAL251_POKEMON_TOWER_HO_OH"),"HO_OH",60,sanctuary.hoOhFlag),
  "Ho-Oh uses the one-time Generation I static-battle command")
T.check(hasStatic(MapScripts.talkScript(sanctuary.cave,
  "TEXT_CRYSTAL251_TIDAL_CAVE_LUGIA"),"LUGIA",60,sanctuary.lugiaFlag),
  "Lugia uses the one-time Generation I static-battle command")

T.eq(ecology.period(),"combined","no time provider uses the all-day fallback")
run.loader.hooks:call("world.tod",function() return "NIGHT" end,"DAY",{})
T.eq(ecology.period(),"night","the final public time-provider value selects night")
local function secondSlot(encounter)
  return {species=encounter.grass.slots[2].species,
    level=encounter.grass.slots[2].level}
end
local nightRoll=run.loader.hooks:call("encounter.roll",secondSlot,
  run.data.encounters.ROUTE_1,{mapId="ROUTE_1",terrain="grass"})
T.eq(nightRoll.species,"HOOTHOOT","night ecology reaches nocturnal Route 1 species")
run.loader.modOptions.CRYSTAL_251={time_spawns="off"}
local combinedRoll=run.loader.hooks:call("encounter.roll",secondSlot,
  run.data.encounters.ROUTE_1,{mapId="ROUTE_1",terrain="grass"})
T.eq(combinedRoll.species,"RATTATA","TIME SPAWNS OFF restores the all-day table")
local function secondSurf(encounter)
  return {species=encounter.water.slots[2].species,
    level=encounter.water.slots[2].level}
end
local surfRoll=run.loader.hooks:call("encounter.roll",secondSurf,
  run.data.encounters.ROUTE_21,{mapId="ROUTE_21",terrain="water"})
T.eq(surfRoll.species,"MARILL","Surf ecology replaces water rather than grass slots")
run.loader.modOptions.CRYSTAL_251={time_spawns="auto"}

for id, trainer in pairs(run.data.trainers) do
  for _, party in ipairs(trainer.parties or {}) do
    for _, mon in ipairs(party) do
      T.check(run.data.pokemon[mon.species]~=nil,id .. " only references registered species")
    end
  end
end

local trainerAudit=run.loader.exports.CRYSTAL_251.trainerChanges
local auditedParties=0
for _,trainer in pairs(run.data.trainers) do auditedParties=auditedParties+#(trainer.parties or{}) end
T.eq(#trainerAudit.audit,auditedParties,"every trainer party record is explicitly audited")
T.check(trainerAudit.changed>0,"curated trainer audit installs Johto party members")
local forbidden={RAIKOU=true,ENTEI=true,SUICUNE=true,LUGIA=true,HO_OH=true,
  CELEBI=true,MEW=true}
for _,row in ipairs(trainerAudit.audit) do
  T.eq(#row.after,#row.before,row.id.." party size remains unchanged")
  local changedSlots=0
  for slot,after in ipairs(row.after) do
    T.eq(after.level,row.before[slot].level,row.id.." party levels remain unchanged")
    if after.species~=row.before[slot].species then
      changedSlots=changedSlots+1
      T.check(not forbidden[after.species],row.id.." never gains a legendary or mythical")
    end
  end
  T.check(changedSlots<=1,row.id.." has at most one curated Johto addition")
  if #row.after>1 then
    T.eq(row.after[#row.after].species,row.before[#row.before].species,
      row.id.." keeps its original final-slot ace")
  end
end
local birdFamilies={PIDGEY=true,PIDGEOTTO=true,PIDGEOT=true,SPEAROW=true,FEAROW=true,
  FARFETCHD=true,DODUO=true,DODRIO=true,HOOTHOOT=true,NOCTOWL=true,NATU=true,
  XATU=true,MURKROW=true,DELIBIRD=true,SKARMORY=true}
for _,party in ipairs(run.data.trainers.OPP_BIRD_KEEPER.parties) do
  for _,mon in ipairs(party) do T.check(birdFamilies[mon.species],
    "Bird Keepers use actual bird families: "..mon.species) end
end

T.eq(#run.data.field.trades,17,"seven Crystal-inspired trades append after ten native rows")
T.eq(run.data.field.trades[1].give,"NIDORINO","native trade row one is unchanged")
T.eq(run.data.field.trades[10].get,"NIDORAN_F","native trade row ten is unchanged")
local newTrades=run.loader.exports.CRYSTAL_251.trades
T.eq(#newTrades,7,"all seven new trade definitions are exported")
local tradeFlags={}
local RuntimeMap=require("src.world.Map")
for offset,row in ipairs(newTrades) do
  T.eq(row.index,10+offset,"new trade indices are stable and appended")
  T.check(not tradeFlags[row.flag],"new trade completion flags are unique")
  tradeFlags[row.flag]=true
  local map=run.data.maps[row.map]
  T.check(RuntimeMap.defIsWalkableCell(map,run.data.tilesets[map.tileset],row.x,row.y),
    row.map.." trade NPC stands on a walkable cell")
  local object
  for _,candidate in ipairs(map.objects or{}) do
    if candidate.text==row.text then object=candidate break end
  end
  T.check(object and object.x==row.x and object.y==row.y,
    row.map.." contains its new trade NPC")
  local script=MapScripts.talkScript(row.map,row.text)
  local command
  for _,entry in ipairs(script or{}) do if entry[1]=="trade" then command=entry end end
  T.check(command and command[2]==row.index and command[3]==row.flag,
    row.map.." trade NPC uses its record and completion flag")
end

local allBadges={}
for _, id in ipairs({"BOULDERBADGE","CASCADEBADGE","THUNDERBADGE","RAINBOWBADGE",
  "SOULBADGE","MARSHBADGE","VOLCANOBADGE","EARTHBADGE"}) do allBadges[id]=true end
local game={save={inventory=allBadges,flags={EVENT_BEAT_CHAMPION_RIVAL=true,
  EVENT_RESCUED_MR_FUJI=true},options={colors="redpp"}}}
run.loader.events:emit("game.ready",{game=game})
run.loader.modOptions.CRYSTAL_251={force_legendary=true,crystal_shinies=true}
run.loader.modOptions.shiny_indicators={colors=true,markers=true,animation=true,chime=true}
local titleItems=run.loader.hooks:call("ui.title_menu.items",
  function(_, rows) return rows end,game,{{label="EXIT GAME"}})
T.eq(titleItems[1].label,"REIMPORT CRYSTAL",
  "a valid import keeps an explicit reimport action on the title menu")
local rolled=run.loader.hooks:call("encounter.roll",function() return {
  species="PIDGEY",level=4} end,run.data.encounters.VIRIDIAN_FOREST,
  {mapId="VIRIDIAN_FOREST",terrain="grass",rng=function(a) return a end})
T.eq(rolled.species,"CELEBI","post-Champion forced test reaches the gated Celebi encounter")

local unown={dvs={attack=15,defense=15,speed=15,special=15}}
local ctx={species="UNOWN",side="front",kind="summary",mon=unown,trueColor=false}
local sprite=run.loader.hooks:call("pokemon.sprite",function(p) return p end,
  run.data.pokemon.UNOWN.spriteFront,ctx)
T.eq(unown.crystal251Form,"Z","Unown form is derived from the four Generation II DVs")
T.eq(sprite,"crystal_251/generated/unown/z_front.png","Unown Z selects its own imported picture")

local shinyMon={dvs={attack=10,defense=10,speed=10,special=10}}
local shinyDexCtx={species="CHIKORITA",side="front",kind="dex",mon=shinyMon,
  trueColor=false,data=run.data}
local shinyDex=run.loader.hooks:call("pokemon.sprite",function(p) return p end,
  run.data.pokemon.CHIKORITA.spriteFront,shinyDexCtx)
T.eq(shinyDex,"crystal_251/generated/shiny/dex/chikorita.png",
  "Shiny Indicators and Crystal 251 select Crystal's centered shiny Pokédex sprite")
T.eq(shinyDexCtx.trueColor,true,"Crystal's imported shiny colors bypass a second recolor")
local shinyBackCtx={species="CHIKORITA",side="back",kind="battle",mon=shinyMon,
  trueColor=false,data=run.data}
local shinyBack=run.loader.hooks:call("pokemon.sprite",function(p) return p end,
  run.data.pokemon.CHIKORITA.spriteBack,shinyBackCtx)
T.eq(shinyBack,"crystal_251/generated/shiny/back/chikorita.png",
  "Shiny Indicators and Crystal 251 select Crystal's native shiny battle back")

run.loader.modOptions.CRYSTAL_251.force_legendary=false
run.loader.modOptions.shiny_indicators.force_wild_shiny=true
run.loader.hooks:call("encounter.roll",function()
  return {species="CHIKORITA",level=5}
end,run.data.encounters.ROUTE_1,{mapId="ROUTE_1",terrain="grass"})
local firstFrameMon={species="CHIKORITA",level=5,hp=20,stats={hp=20},statExp={},
  dvs={attack=1,defense=1,speed=1,special=1}}
local firstFrameCtx={species="CHIKORITA",side="front",kind="battle",
  mon=firstFrameMon,trueColor=false,data=run.data}
local firstFramePath=run.loader.hooks:call("pokemon.sprite",function(p) return p end,
  run.data.pokemon.CHIKORITA.spriteFront,firstFrameCtx)
T.eq(firstFramePath,"crystal_251/generated/shiny/front/chikorita.png",
  "forced encounter uses Crystal's shiny sprite on its first rendered frame")
T.eq(firstFrameCtx.trueColor,true,"forced Crystal shiny remains true-color")

local damageMove={id="HIDDEN_POWER",power=1,type="NORMAL"}
local damageCtx={move=damageMove,rng=function(a) return a end,battle={weather=nil},
  user={mon={hp=50,stats={hp=50},dvs={attack=15,defense=15,speed=15,special=15}}},
  target={mon={hp=10,stats={hp=10}}}}
local dynamicDamage=run.loader.hooks:call("battle.damage",function(c)
  T.eq(c.move.type,"STEEL","Hidden Power derives its Generation II type from DVs")
  T.eq(c.move.power,70,"Hidden Power derives its Generation II power from DVs")
  return c.move.power,{typeMult=10,crit=false}
end,damageCtx)
T.eq(dynamicDamage,70,"dynamic move power reaches the damage pipeline")
T.eq(damageMove.type,"NORMAL","dynamic type changes do not leak into shared move data")
local protectHit=run.loader.hooks:call("battle.accuracy",function() return true end,
  {user={},target={protect=true}})
T.eq(protectHit,false,"Protect blocks an incoming accuracy check")

run.release()
T.finish("crystal 251 integration")
