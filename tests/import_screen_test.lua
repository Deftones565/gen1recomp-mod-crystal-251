package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
local Data = require("src.core.Data")
Data:load()

local oldInfo = love.filesystem.getInfo
love.filesystem.getInfo = function(path, kind)
  if path == "crystal_251/content.json" then return nil end
  return oldInfo(path, kind)
end
local run = T.sdk.loadMod("mods/CRYSTAL_251", { data=Data })
love.filesystem.getInfo = oldInfo
T.eq(#run.errors, 1, "missing required ROM is reported by the launcher")
T.check(tostring(run.errors[1].error or run.errors[1].message or run.errors[1]):find("required import",1,true),
  "missing ROM reports the required import")
local items = run.loader.hooks:call("ui.title_menu.items",
  function(_, rows) return rows end, {}, { {label="EXIT GAME"} })
T.eq(items[1].label,"EXIT GAME","missing ROM does not add an unusable title action")
run.release()
T.finish("Crystal required import gating")
