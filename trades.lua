-- Seven Pokemon Crystal NPC trades adapted to coherent Kanto locations.
-- They append after each game's native table, so Red/Blue/Yellow trade rows
-- and their completion flags are never replaced.

local Trades = {}

local NATIVE_LOCATIONS = {
  "ROUTE 11 GATE 2F", "ROUTE 2 TRADE HOUSE", "IN-GAME TRADE",
  "CINNABAR LAB", "VERMILION TRADE HOUSE", "ROUTE 18 GATE 2F",
  "CERULEAN TRADE HOUSE", "CINNABAR LAB", "CINNABAR LAB",
  "UNDERGROUND PATH ROUTE 5",
}

local ROWS = {
  {map="CELADON_MART_5F",index=5,x=10,y=5,sprite="SPRITE_BRUNO",
    text="TEXT_CRYSTAL251_TRADE_MIKE",give="ABRA",get="MACHOP",nickname="MUSCLE",
    flag="MOD_CRYSTAL251_TRADED_ABRA_FOR_MACHOP",dialogset=1,
    after="Your new MACHOP\nwill make you\vstrong!"},
  {map="CERULEAN_TRADE_HOUSE",index=3,x=6,y=4,sprite="SPRITE_YOUNGSTER",
    text="TEXT_CRYSTAL251_TRADE_KYLE",give="BELLSPROUT",get="ONIX",nickname="ROCKY",
    flag="MOD_CRYSTAL251_TRADED_BELLSPROUT_FOR_ONIX",dialogset=1,
    after="ROCKY likes a\nTRAINER who keeps\vmoving!",
    -- Yellow replaces Cerulean's trade house with Melanie's house. Patching
    -- the absent id creates a partial map record (objects but no warps), and
    -- Gen 1's elevator floor scan then crashes on that malformed record.
    -- Keep Kyle in Cerulean on a walkable edge cell that does not obstruct the
    -- Pokemon Center's entrance, counter, link desk, or central aisle.
    fallback={map="CERULEAN_POKECENTER",index=6,x=12,y=3}},
  {map="VERMILION_TRADE_HOUSE",index=2,x=6,y=4,sprite="SPRITE_SAILOR",
    text="TEXT_CRYSTAL251_TRADE_TIM",give="KRABBY",get="VOLTORB",nickname="VOLTY",
    flag="MOD_CRYSTAL251_TRADED_KRABBY_FOR_VOLTORB",dialogset=3,
    after="VOLTY is quick as\nlightning on a\vstormy sea!"},
  {map="FUCHSIA_MEETING_ROOM",index=4,x=8,y=4,sprite="SPRITE_BEAUTY",
    text="TEXT_CRYSTAL251_TRADE_EMY",give="DRAGONAIR",get="DODRIO",nickname="DORIS",
    flag="MOD_CRYSTAL251_TRADED_DRAGONAIR_FOR_DODRIO",dialogset=3,
    after="DORIS can cross\nthree paths at\vonce!"},
  {map="PEWTER_POKECENTER",index=5,x=9,y=3,sprite="SPRITE_GENTLEMAN",
    text="TEXT_CRYSTAL251_TRADE_CHRIS",give="HAUNTER",get="XATU",nickname="PAUL",
    flag="MOD_CRYSTAL251_TRADED_HAUNTER_FOR_XATU",dialogset=2,
    after="That HAUNTER\nevolved! What a\vdiscovery!"},
  {map="ROUTE_14",index=11,x=13,y=24,sprite="SPRITE_COOLTRAINER_F",
    text="TEXT_CRYSTAL251_TRADE_KIM",give="CHANSEY",get="AERODACTYL",nickname="AEROY",
    flag="MOD_CRYSTAL251_TRADED_CHANSEY_FOR_AERODACTYL",dialogset=3,
    after="AEROY was born to\nsoar over this\vroute!"},
  {map="ROCK_TUNNEL_POKECENTER",index=5,x=9,y=3,sprite="SPRITE_SCIENTIST",
    text="TEXT_CRYSTAL251_TRADE_FOREST",give="DUGTRIO",get="MAGNETON",nickname="MAGGIE",
    flag="MOD_CRYSTAL251_TRADED_DUGTRIO_FOR_MAGNETON",dialogset=1,
    after="MAGGIE reacts to\nthe nearby POWER\vPLANT!"},
}

local function copy(value)
  if type(value)~="table" then return value end
  local out={};for k,v in pairs(value) do out[k]=copy(v) end;return out
end

function Trades.install(mod)
  local tableRows=copy(mod.content.field:get("trades") or {})
  local locations=copy(mod.content.field:get("tradeLocations") or NATIVE_LOCATIONS)
  local installed={}
  for offset,definition in ipairs(ROWS) do
    local row=copy(definition)
    if not mod.content.maps:get(row.map) and row.fallback then
      for key,value in pairs(row.fallback) do row[key]=value end
    end
    row.fallback=nil
    assert(mod.content.maps:get(row.map),
      "Crystal 251 trade map is unavailable: "..tostring(row.map))
    local tradeIndex=#tableRows+1
    local afterId="CRYSTAL251_TRADE_AFTER_"..offset
    mod.content.text:register(afterId,row.after)
    tableRows[tradeIndex]={ give=row.give,get=row.get,nickname=row.nickname,
      dialogset=row.dialogset,texts={afterTrade=afterId} }
    mod.content.maps:patch(row.map, {
      objects = { __append = { {
        index=row.index,movement="STAY",name="CRYSTAL251_TRADE_NPC_"..offset,
        range="ANY_DIR",sprite=row.sprite,text=row.text,x=row.x,y=row.y,
      } } },
    })
    mod.content.map_scripts:register(row.map,{talk={
      [row.text]={{"face_player"},{"trade",tradeIndex,row.flag}},
    }})
    installed[#installed+1]={index=tradeIndex,map=row.map,x=row.x,y=row.y,
      give=row.give,get=row.get,nickname=row.nickname,flag=row.flag,text=row.text}
    locations[tradeIndex]=row.map:gsub("_"," ")
  end
  mod.content.field:override("trades",tableRows)
  mod.content.field:override("tradeLocations",locations)
  return installed
end

return Trades
