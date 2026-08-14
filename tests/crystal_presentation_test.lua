package.path = "./?.lua;./?/init.lua;" .. package.path

local checks, failures = 0, 0
local function fail(message)
  failures = failures + 1
  io.stderr:write("FAIL " .. message .. "\n")
end
local function ok(value, message)
  checks = checks + 1
  if not value then fail(message) end
end
local function eq(got, want, message)
  checks = checks + 1
  if got ~= want then
    fail(("%s (got %s, want %s)"):format(message, tostring(got), tostring(want)))
  end
end

local Extractor = require("mods.CRYSTAL_251.lib.extractor")
local helper = Extractor._test

local scriptRaw = string.char(
  1, 7,
  0xfe, 2,
  2, 7,
  3, 7,
  0xfd, 2,
  0, 5,
  0xff)
local sequence = helper.parsePicAnimationScript(helper.Reader.new(scriptRaw), 0, 0x4000)
local expected = { 1, 2, 3, 2, 3, 0 }
eq(#sequence, #expected, "Crystal picture repeat script expands to six frames")
for index, frame in ipairs(expected) do
  eq(sequence[index].frame, frame, "Crystal picture frame " .. index)
end
eq(sequence[1].duration, 7, "Crystal picture frame duration is retained")

local function patch(raw, offset, bytes)
  return raw:sub(1, offset) .. string.char(unpack(bytes))
    .. raw:sub(offset + #bytes + 1)
end

local raw = string.rep("\0", 0xd5000)
local framesTable = 0x35 * 0x4000
local bitmasksTable = 0x34 * 0x4000
raw = patch(raw, framesTable, { 0x00, 0x41 })
raw = patch(raw, 0x35 * 0x4000 + 0x100, { 0x00, 0x42 })
raw = patch(raw, 0x35 * 0x4000 + 0x200, { 0x00, 25 })
raw = patch(raw, bitmasksTable, { 0x00, 0x43 })
raw = patch(raw, 0x34 * 0x4000 + 0x300, { 0x01, 0, 0, 0 })
local front = {}
for index = 1, 26 * 16 do front[index] = index > 25 * 16 and 0xff or 0 end
local rendered = helper.animationFrame(helper.Reader.new(raw), front, 5, 5, 1, 1,
  framesTable, 0x35, bitmasksTable, 0x34)
eq(rendered[1], 0xff, "Crystal picture bitmask replaces the selected resting tile")
eq(rendered[17], 0, "Crystal picture bitmask leaves unselected tiles unchanged")

local cryRaw = string.rep("\0", 0x6000)
local pointerOffset = 0x100
for index = 0, 68 do
  local headerAddress = 0x4000 + index * 16
  cryRaw = patch(cryRaw, pointerOffset + index * 3,
    { 1, headerAddress % 256, math.floor(headerAddress / 256) })
  cryRaw = patch(cryRaw, 0x4000 + index * 16, { 0x04, 0x00, 0x50 })
end
eq(helper.findCryPointers(helper.Reader.new(cryRaw)), pointerOffset,
  "Crystal cry pointer table is found structurally")
ok(helper.validCryHeader(helper.Reader.new(cryRaw), 1, 0x4000),
  "Crystal cry header validation accepts channel 5")
local addresses = require("mods.CRYSTAL_251.addresses").revisions
  ["f2f52230b536214ef7c9924f483392993e226cfb"].addresses
eq(addresses.cryPointers.bank, 0x3a, "retail Crystal cry pointer bank is explicit")
eq(addresses.cryPointers.address, 0x51b0,
  "retail Crystal cry pointer address is explicit")
eq(addresses.unownFramesPointers.address, 0x59a9,
  "retail Crystal Unown frame pointers are explicit")

package.loaded["mods.CRYSTAL_251.battle.crystal_presentation"] = nil
local Presentation = require("mods.CRYSTAL_251.battle.crystal_presentation")

local function registry(initial)
  local values = initial or {}
  return {
    get=function(_, id) return values[id] end,
    register=function(_, id, value)
      assert(values[id] == nil, "duplicate register " .. tostring(id))
      values[id] = value
    end,
    override=function(_, id, value)
      assert(values[id] ~= nil, "missing override " .. tostring(id))
      values[id] = value
    end,
    values=values,
  }
end

local moveBase = {}
local aliasCount = 0
for move, alias in pairs(Presentation.moveAliases) do
  aliasCount = aliasCount + 1
  moveBase[alias] = moveBase[alias] or { seq={ { sub=1 } }, source=alias }
end
for _, alias in pairs(Presentation.specialAliases) do
  moveBase[alias] = moveBase[alias] or { seq={ { sub=2 } }, source=alias }
end
eq(aliasCount, 86, "all 86 Generation II moves have presentation aliases")
local mod = { content={ battle_anims=registry(moveBase), cries=registry({ BULBASAUR={header={}} }) } }
local cache = {
  species={ { id="BULBASAUR" }, { id="CHIKORITA" } },
  cries={
    { chip={blob="a",channels={}} },
    { chip={blob="b",channels={}} },
  },
}
Presentation.register(mod, cache)
for move in pairs(Presentation.moveAliases) do
  ok(mod.content.battle_anims:get(move) ~= nil, move .. " resolves to a battle animation")
end
for name in pairs(Presentation.specialAliases) do
  ok(mod.content.battle_anims:get(name) ~= nil, name .. " resolves to a presentation animation")
end
eq(mod.content.cries:get("BULBASAUR").chip.blob, "a",
  "existing cry is overridden with a chip definition")
eq(mod.content.cries:get("CHIKORITA").chip.blob, "b",
  "new data-only cry is registered")

local BattleState = {
  drawBattlerPic=function(self, battler)
    self.drawnSprite = battler.sprite
    return battler.sprite
  end,
}
package.loaded["src.battle.BattleState"] = BattleState
package.loaded["src.render.Assets"] = {
  image=function(path) return { path=path } end,
}
package.loaded["src.render.PaletteFX"] = { mode="gbc" }
Presentation.resetForTests()
Presentation.configure({ species={ {
  id="CHIKORITA",
  frontAnimation={ frames={
    { path="frame1.png", shinyPath="shiny1.png", duration=2 },
    { path="frame2.png", shinyPath="shiny2.png", duration=3 },
  } },
} } })
eq(Presentation.installRuntime(), true, "presentation runtime installs once")
eq(Presentation.installRuntime(), false, "presentation runtime installation is idempotent")
local baseSprite = { path="base.png" }
local battler = { isPlayer=false, mon={ species="CHIKORITA" }, sprite=baseSprite }
local battle = setmetatable({ frame=0, introSlide=0 }, { __index=BattleState })
battle:drawBattlerPic(battler, 0, 0, 1)
eq(battle.drawnSprite.path, "frame1.png", "front animation starts on the first imported frame")
eq(battler.sprite, baseSprite, "front animation draw restores the battler sprite")
battle.frame = 2
battle:drawBattlerPic(battler, 0, 0, 1)
eq(battle.drawnSprite.path, "frame2.png", "front animation advances by Crystal duration")
battle.frame = 5
battle:drawBattlerPic(battler, 0, 0, 1)
eq(battle.drawnSprite, baseSprite, "front animation returns to the resting sprite")

local retainedFxBattler = {
  isPlayer=false, mon={ species="CHIKORITA" }, sprite=baseSprite,
}
local retainedFxBattle = setmetatable({
  frame=0, introSlide=0, picFx={ [retainedFxBattler]={ ox=0, oy=0 } },
}, { __index=BattleState })
retainedFxBattle:drawBattlerPic(retainedFxBattler, 0, 0, 1)
eq(retainedFxBattle.drawnSprite.path, "frame1.png",
  "inactive retained engine picture state does not suppress front animation")
retainedFxBattle.picFx[retainedFxBattler].kind = "blink"
retainedFxBattle:drawBattlerPic(retainedFxBattler, 0, 0, 1)
eq(retainedFxBattle.drawnSprite, baseSprite,
  "active engine picture effect temporarily suppresses front animation")

local shinyBattler = {
  isPlayer=false,
  mon={ species="CHIKORITA", dvs={ attack=2, defense=10, speed=10, special=10 } },
  sprite=baseSprite,
}
local shinyBattle = setmetatable({ frame=0, introSlide=0 }, { __index=BattleState })
shinyBattle:drawBattlerPic(shinyBattler, 0, 0, 1)
eq(shinyBattle.drawnSprite.path, "shiny1.png", "shiny front animation uses shiny frames")

package.loaded["src.render.PaletteFX"].mode = "og"
battle.frame = 1
battle:drawBattlerPic(battler, 0, 0, 1)
eq(battle.drawnSprite, baseSprite,
  "front animation yields to monochrome palette modes")
package.loaded["src.render.PaletteFX"].mode = "gbc"

local replacementMon = { species="CHIKORITA" }
battler.mon = replacementMon
battle.frame = 40
battle:drawBattlerPic(battler, 0, 0, 1)
eq(battle.drawnSprite.path, "frame1.png",
  "front animation restarts when the active monster changes")

Presentation.configure({
  species={},
  unownForms={ {
    letter="Z",
    frontAnimation={ frames={
      { path="unown_z.png", shinyPath="unown_z_shiny.png", duration=4 },
    } },
  } },
})
local unownBattler = {
  isPlayer=false,
  mon={ species="UNOWN", crystal251Form="Z" },
  sprite=baseSprite,
}
local unownBattle = setmetatable({ frame=0, introSlide=0 }, { __index=BattleState })
unownBattle:drawBattlerPic(unownBattler, 0, 0, 1)
eq(unownBattle.drawnSprite.path, "unown_z.png",
  "Unown uses its form-specific Crystal front animation")

if failures > 0 then
  io.stderr:write(("%d/%d checks failed (Crystal presentation)\n")
    :format(failures, checks))
  os.exit(1)
end
print(("%d/%d checks passed (Crystal presentation)"):format(checks, checks))
