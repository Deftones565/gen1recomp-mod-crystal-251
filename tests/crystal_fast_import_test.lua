package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")

local tables, opaque = {}, {}
local overworld = {}
local game = {
  save = { version="red", meta={ playthroughId="fastimport" } },
  overworld = overworld,
  stack = { top=function() return overworld end },
}
local storage = {
  context = function() return { gameVersion="red", playthroughId="fastimport" } end,
  write = function(_, _, key, value) tables[key]=value return true end,
  read = function(_, _, key)
    if tables[key] then return tables[key] end
    return nil, "not_found"
  end,
  writeBytes = function(_, _, key, value) opaque[key]=value return true end,
  readBytes = function(_, _, key)
    if opaque[key] then return opaque[key] end
    return nil, "not_found"
  end,
  list = function() return {} end,
  delete = function() return true end,
}
local mod = { game=game, storage=storage }

local Cache = require("mods.CRYSTAL_251.lib.cache").bind(mod)
local firstPath = "crystal_251/generated/front/bulbasaur.png"
local secondPath = "crystal_251/generated/shiny/front/pikachu.png"
T.check(Cache.stageAsset(firstPath, {
  raster="\0\1\2\3", width=2, height=2, presentation="dex",
}), "first generated asset stages")
T.check(Cache.stageAsset(secondPath, {
  raster="\3\2\1\0", width=2, height=2,
  palette={{248,248,248},{160,120,80},{64,32,16},{0,0,0}},
}), "second generated asset stages")
T.check(Cache.stageContent({ schema=25, species={}, moves={} }),
  "content commit stages")
local done, err = Cache.persistMemoryStep(1)
T.check(not done and not err, "asset bundle commits before content marker")
done, err = Cache.persistMemoryStep(1)
T.check(done and not err, "content marker commits last")
T.check(type(opaque["cache/assets_bundle"])=="string",
  "all generated images use one opaque asset record")
T.check(type(tables["cache/content"])=="table",
  "content remains the ordinary public data record")

package.loaded["mods.CRYSTAL_251.lib.cache"] = nil
Cache = require("mods.CRYSTAL_251.lib.cache").bind(mod)
local content, state = Cache.readContentStatus()
T.eq(state, "found", "fresh process finds committed content")
T.eq(content.schema, 25, "fresh process reads bundled-cache schema")
local first = Cache.readAsset(firstPath)
local second = Cache.readAsset(secondPath)
T.eq(first.raster, "\0\1\2\3", "ordinary asset round-trips through bundle")
T.eq(first.presentation, "dex", "asset presentation metadata round-trips")
T.eq(second.raster, "\3\2\1\0", "shiny asset round-trips through bundle")
T.eq(second.palette[2][2], 120, "asset palette metadata round-trips")

T.finish("Crystal fast import cache")
