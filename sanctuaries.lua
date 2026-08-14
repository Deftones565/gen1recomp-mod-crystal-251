-- Visible, one-time legendary sanctuaries. Everything here is registered
-- through API 2: no generated map, engine script, or Dramatic Shape file is
-- changed. The island borrows the player's imported OVERWORLD blockset and
-- the cave borrows the imported Cerulean Cave geometry at merge time.

local Sanctuaries = {}

local ISLAND = "CRYSTAL_251_NAVEL_ISLE"
local CAVE = "CRYSTAL_251_TIDAL_CAVE"
local CAVE_TILESET = "CRYSTAL251_CAVERN"
local HO_OH_FLAG = "MOD_CRYSTAL_251_BEAT_HO_OH"
local LUGIA_FLAG = "MOD_CRYSTAL_251_BEAT_LUGIA"
local HO_OH_OBJECT = "CRYSTAL251_POKEMON_TOWER_HO_OH"
local CAVE_DOOR_BX, CAVE_DOOR_BY = 4, 2
local CAVE_DOOR_BLOCK, CAVE_WALL_BLOCK = 6, 87

local BADGES = {
  "BOULDERBADGE", "CASCADEBADGE", "THUNDERBADGE", "RAINBOWBADGE",
  "SOULBADGE", "MARSHBADGE", "VOLCANOBADGE", "EARTHBADGE",
}

local function copy(value)
  if type(value) ~= "table" then return value end
  local out = {}
  for key, child in pairs(value) do out[key] = copy(child) end
  return out
end

local function badgeCount(save)
  local count, inventory = 0, (save and save.inventory) or {}
  for _, badge in ipairs(BADGES) do
    if inventory[badge] then count = count + 1 end
  end
  return count
end

local ISLAND_BLOCKS = {
  -- Open water joins Cinnabar's new south channel seamlessly. The central
  -- two-block channel is intentionally long enough to hold real swimmers.
  67,67,67,67,67,67,67,67,67,67,67,67,67,67,
  -- The cave sits on the western half. Block 87 is the matching solid wall
  -- face; on badge eight it becomes block 6, the actual cave-door block.
  67,67,67, 62,63,59,67,67,11,11,122,122,67,67,
  67,67,67, 36,87,37,67,67,11,11,122,122,67,67,
  67,67,67,122,84, 8,67,67,11,11,122,122,67,67,
  67,67,67,122,84,122,122,84,122,11,11,122,67,67,
  67,67,67,122,84,122,122,84,122,122,11,122,67,67,
  -- A broad natural landing joins both halves of the island. Unlike the old
  -- layout it has no repeated vertical rock posts around the shoreline.
  67,67,67,122,122,122,122,84,122,11,122,122,67,67,
  67,67,67, 45,31,31,31,31,31,31,31,31,67,67,
  67,67,67,67,67,67,67,67,67,67,67,67,67,67,
}

local CAVE_BLOCKS = {
  0,0,0,0,0,0,0,0,0,0,
  0,25,25,25,25,25,25,25,25,0,
  0,25,118,25,25,25,25,118,25,0,
  0,25,25,25,25,25,25,25,25,0,
  0,25,118,25,25,25,25,118,25,0,
  0,25,25,25,60,25,25,25,25,0,
  0,0,0,0,0,0,0,0,0,0,
}

local function mapRecord(base)
  return {
    id=base.id, label=base.label, index=base.index, tileset=base.tileset,
    width=base.width, height=base.height, blocks=copy(base.blocks),
    borderBlock=base.borderBlock, palette=base.palette,
    warps=copy(base.warps or {}), objects=copy(base.objects or {}),
    signs=copy(base.signs or {}), connections=copy(base.connections or {}),
  }
end

function Sanctuaries.install(mod)
  -- Vanilla CAVERN deliberately blocks the direct $14 water <-> $05 floor
  -- tile pair. Tidal Cave's small decorative pools have no shore blocks, so
  -- that rule lets a player Surf in but never dismount. A mod-owned clone
  -- keeps the exact imported art/collision while limiting the ordinary
  -- water-to-land transition to this map; no base cave behavior is changed.
  local caveTileset=copy(assert(mod.content.tilesets:get("CAVERN")))
  caveTileset.id=CAVE_TILESET
  mod.content.tilesets:register(CAVE_TILESET,caveTileset)
  mod.content.field:patch("waterTilesets",{__append={CAVE_TILESET}})

  -- Open a narrow water channel through Cinnabar's south coast. Its sides
  -- retain the original shore blocks, visually framing the route offshore.
  local cinnabar = mapRecord(assert(mod.content.maps:get("CINNABAR_ISLAND")))
  local lastRow = (cinnabar.height - 1) * cinnabar.width
  for column=4,7 do cinnabar.blocks[lastRow + column] = 67 end
  cinnabar.connections.south = { map=ISLAND, offset=-2 }
  mod.content.maps:override("CINNABAR_ISLAND", cinnabar)

  mod.content.maps:register(ISLAND, {
    -- Route 21's outdoor index keeps Gen I's indoor encounter fallback from
    -- firing on every non-grass land tile. Map identity remains the unique id.
    id=ISLAND, label="TidalIsle", index=32, tileset="OVERWORLD",
    width=14, height=9, blocks=ISLAND_BLOCKS, borderBlock=67,
    palette="CINNABAR",
    connections={ north={ map="CINNABAR_ISLAND", offset=2 } },
    warps={ { x=8, y=5, destMap=CAVE, destWarp=1 } },
    objects={
      { index=1, movement="STAY", name="CRYSTAL251_TIDAL_SWIMMER_1",
        range="DOWN", sprite="SPRITE_SWIMMER", text="TEXT_CRYSTAL251_TIDAL_SWIMMER_1",
        trainerClass="OPP_SWIMMER", trainerParty=10, x=12, y=3 },
      { index=2, movement="STAY", name="CRYSTAL251_TIDAL_SWIMMER_2",
        range="UP", sprite="SPRITE_SWIMMER", text="TEXT_CRYSTAL251_TIDAL_SWIMMER_2",
        trainerClass="OPP_SWIMMER", trainerParty=13, x=14, y=7 },
      { index=3, movement="STAY", name="CRYSTAL251_TIDAL_BIRD_KEEPER",
        range="LEFT", sprite="SPRITE_BIRD", text="TEXT_CRYSTAL251_TIDAL_BIRD_KEEPER",
        trainerClass="OPP_BIRD_KEEPER", trainerParty=11, x=19, y=8 },
      { index=4, movement="STAY", name="CRYSTAL251_TIDAL_EXPLORER",
        range="RIGHT", sprite="SPRITE_COOLTRAINER_F", text="TEXT_CRYSTAL251_TIDAL_EXPLORER",
        trainerClass="OPP_JR_TRAINER_F", trainerParty=22, x=9, y=12 },
    },
    signs={ {
      x=21, y=12, text="TEXT_CRYSTAL251_NAVEL_ISLE_SIGN",
    } },
  })

  -- This is a separate map and encounter, despite using a proven imported
  -- cavern layout. The familiar geometry keeps collision and warp behavior
  -- reliable on every Red/Blue/Yellow import and in the 3D renderer.
  mod.content.maps:register(CAVE, {
    id=CAVE, label="TidalCave", index=1001, tileset=CAVE_TILESET,
    width=10, height=7, blocks=CAVE_BLOCKS, borderBlock=0,
    palette="CAVE", connections={},
    warps={ { x=9, y=11, destMap=ISLAND, destWarp=1 } },
    objects={ {
      index=1, level=60, movement="STAY",
      name="CRYSTAL251_TIDAL_CAVE_LUGIA", pokemon="LUGIA",
      range="DOWN", sprite="CRYSTAL_251_SPRITE_LUGIA",
      text="TEXT_CRYSTAL251_TIDAL_CAVE_LUGIA", x=10, y=3,
      habitatNote="ALL 8 BADGES; SURF SOUTH FROM CINNABAR",
    } },
    signs={},
  })

  -- The island has a small, coastal ecosystem. Ecology replaces these with
  -- its period-aware forms later, preserving the native ten-slot weights.
  mod.content.encounters:register(ISLAND, {
    grass={ rate=20, slots={
      {species="KRABBY",level=30}, {species="EXEGGCUTE",level=30},
      {species="KRABBY",level=31}, {species="TANGELA",level=30},
      {species="FARFETCHD",level=31}, {species="MARILL",level=31},
      {species="HOPPIP",level=30}, {species="SUNFLORA",level=31},
      {species="YANMA",level=32}, {species="PINSIR",level=32},
    } },
    water={ rate=15, slots={
      {species="TENTACOOL",level=30}, {species="TENTACOOL",level=31},
      {species="KRABBY",level=30}, {species="CHINCHOU",level=30},
      {species="TENTACOOL",level=32}, {species="CORSOLA",level=31},
      {species="REMORAID",level=31}, {species="QWILFISH",level=32},
      {species="MANTINE",level=33}, {species="DRATINI",level=30},
    } },
  })

  -- A new Lavender resident hints at Ho-Oh from the beginning without naming
  -- it. The position is an unused, passable town tile near the Tower.
  mod.content.maps:patch("LAVENDER_TOWN", {
    objects={ __append={ {
      index=4, movement="WALK", name="CRYSTAL251_LAVENDER_SKYWATCHER",
      range="ANY_DIR", sprite="SPRITE_GENTLEMAN",
      text="TEXT_CRYSTAL251_LAVENDER_SKYWATCHER", x=12, y=12,
    } } },
  })

  mod.content.maps:patch("POKEMON_TOWER_7F", {
    objects={ __append={ {
      hidden=true, index=5, level=60, movement="STAY",
      name=HO_OH_OBJECT, pokemon="HO_OH", range="DOWN",
      sprite="CRYSTAL_251_SPRITE_HO_OH",
      text="TEXT_CRYSTAL251_POKEMON_TOWER_HO_OH",
      -- Mr. Fuji's native object occupies (10,3). Keep Ho-Oh on the other
      -- summit tile so Gen I's first-object interaction order cannot route
      -- the encounter press into Fuji's dialogue.
      x=11, y=3,
      habitatNote="ALL 8 BADGES; RESCUE MR. FUJI",
    } } },
  })

  local function objectCtx(game, ow)
    return { game=game, save=game.save, overworld=ow }
  end

  mod.content.map_scripts:register("LAVENDER_TOWN", {
    talk={
      TEXT_CRYSTAL251_LAVENDER_SKYWATCHER={
        { "face_player" },
        { "show_text", "On clear nights,\na great shadow\vcircles the TOWER.\fIt glitters like\nthe morning sun...\vThen it is gone." },
      },
    },
  })

  mod.content.map_scripts:register("POKEMON_TOWER_7F", {
    onEnter=function(game, ow)
      local flags = (game.save and game.save.flags) or {}
      local force = mod.options:get("force_legendary") == true
      local available = not flags[HO_OH_FLAG] and
        (force or (badgeCount(game.save)>=8 and flags.EVENT_RESCUED_MR_FUJI))
      local Commands = require("src.script.Commands")
      if available then Commands.show_object(objectCtx(game,ow),"POKEMON_TOWER_7F",HO_OH_OBJECT)
      else Commands.hide_object(objectCtx(game,ow),"POKEMON_TOWER_7F",HO_OH_OBJECT) end
    end,
    talk={
      TEXT_CRYSTAL251_POKEMON_TOWER_HO_OH={
        { "play_cry", "HO_OH" },
        { "show_text", "The rainbow bird\nspreads its wings!" },
        { "check_flag", HO_OH_FLAG },
        { "jump_if_true", "done" },
        { "static_battle", "HO_OH", 60, HO_OH_FLAG },
        { "label", "done" },
      },
    },
  })

  mod.content.map_scripts:register(ISLAND, {
    onEnter=function(game, ow)
      local open = badgeCount(game.save)>=8 or mod.options:get("force_legendary")==true
      local Commands = require("src.script.Commands")
      Commands.replace_block(objectCtx(game,ow),CAVE_DOOR_BX,CAVE_DOOR_BY,
        open and CAVE_DOOR_BLOCK or CAVE_WALL_BLOCK)
    end,
    talk={
      TEXT_CRYSTAL251_NAVEL_ISLE_SIGN={
        { "show_text", "TIDAL ISLE\nThe sea is still." },
      },
    },
  })

  mod.content.map_scripts:register(CAVE, {
    talk={
      TEXT_CRYSTAL251_TIDAL_CAVE_LUGIA={
        { "play_cry", "LUGIA" },
        { "show_text", "The guardian of\nthe deep awakens!" },
        { "check_flag", LUGIA_FLAG },
        { "jump_if_true", "done" },
        { "static_battle", "LUGIA", 60, LUGIA_FLAG },
        { "label", "done" },
      },
    },
  })

  -- Trainer headers are runtime data rather than a public content registry.
  -- Installing these records from the mod keeps sight ranges and all three
  -- dialogue phases self-contained without modifying an engine/data file.
  local trainerText = {
    [1]={range=3,battle="The current carried\nyou right to me!",
      won="You rode that wave!",after="The tide changes,\nbut a good swimmer\vreads the water."},
    [2]={range=3,battle="No calm water here!\nLet's make a splash!",
      won="I lost my rhythm!",after="Strong currents hide\nrare POKéMON near\vthis island."},
    [3]={range=4,battle="Sea birds gather\nwhere the warm and\vcold winds meet!",
      won="Your team took wing!",after="My birds rest in the\ntall grass between\vlong flights."},
    [4]={range=3,battle="Eight BADGES or not,\nyou must respect\vthis wild place!",
      won="You understand it!",after="The cave wall changes\nonly for a proven\vTRAINER."},
  }
  for index,row in pairs(trainerText) do
    for phase,value in pairs({battle=row.battle,won=row.won,after=row.after}) do
      mod.content.text:register(("_CRYSTAL251_TIDAL_TRAINER_%d_%s")
        :format(index,phase:upper()),value)
    end
  end
  mod.events:on("game.ready",function(ev)
    local game=ev and ev.game
    if not (game and game.data) then return end
    game.data.trainer_headers.TidalIsle=game.data.trainer_headers.TidalIsle or {}
    for index,row in pairs(trainerText) do
      game.data.trainer_headers.TidalIsle[index]={range=row.range,
        battle=("_CRYSTAL251_TIDAL_TRAINER_%d_BATTLE"):format(index),
        won=("_CRYSTAL251_TIDAL_TRAINER_%d_WON"):format(index),
        after=("_CRYSTAL251_TIDAL_TRAINER_%d_AFTER"):format(index)}
    end
  end)

  return {
    island=ISLAND, cave=CAVE, hoOhFlag=HO_OH_FLAG, lugiaFlag=LUGIA_FLAG,
    hoOhObject=HO_OH_OBJECT, caveDoor={bx=CAVE_DOOR_BX,by=CAVE_DOOR_BY,
      open=CAVE_DOOR_BLOCK,closed=CAVE_WALL_BLOCK},badgeCount=badgeCount,
  }
end

return Sanctuaries
