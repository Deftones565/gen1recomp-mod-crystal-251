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
T.eq(#run.errors, 0, "unimported mod loads cleanly")

local pushed
local game = {
  data=run.data,
  input={ wasPressed=function() return false end },
  stack={
    push=function(_, screen) pushed=screen end,
    pop=function() end,
  },
}
local items = run.loader.hooks:call("ui.title_menu.items",
  function(_, rows) return rows end, game, { { label="EXIT GAME" } })
T.eq(items[1].label, "IMPORT CRYSTAL", "missing cache adds the import title entry")
local ok, err = pcall(items[1].onSelect)
T.check(ok, "import title entry resolves its registered screen: " .. tostring(err))
T.check(type(pushed)=="table", "registered import screen is pushed")
T.eq(pushed and pushed.status, "CHOOSE CRYSTAL ROM", "import screen opens at the chooser")

run.release()
T.finish("crystal 251 import screen")
