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
    fail(("%s (got %q, want %q)"):format(message, tostring(got), tostring(want)))
  end
end

package.loaded["src.render.Font"] = {
  split = function(text)
    local spans = {}
    for i = 1, #text do spans[#spans + 1] = { from=i, to=i } end
    return spans
  end,
  spansFitting = function(spans, pixels)
    return math.min(#spans, math.floor(pixels / 8))
  end,
}

local BattleState = {}
BattleState.startMessage = function(self, item)
  self.parsedText = item.text
  return "parsed"
end
package.loaded["src.battle.BattleState"] = BattleState
package.loaded["mods.CRYSTAL_251.battle.crystal_text_wrap"] = nil
local Wrap = require("mods.CRYSTAL_251.battle.crystal_text_wrap")

local function withoutControls(text)
  return (text:gsub("[\n\v]", ""))
end
local function within(text, columns)
  text = text:gsub("\v", "\n")
  for line in (text .. "\n"):gmatch("(.-)\n") do
    if #line > columns then return false end
  end
  return true
end

local cases = {
  "DUNSPARCE is fully paralyzed!",
  "Enemy POKEMON got an ENCORE!",
  "DUNSPARCE's RAGE is building!",
  "Enemy POKEMON\nis hurt by its burn!",
}
for _, text in ipairs(cases) do
  local wrapped = Wrap.wrap(text, 18)
  ok(within(wrapped, 18), text .. " fits the classic battle box")
  eq(withoutControls(wrapped), withoutControls(text),
    text .. " keeps every printable character")
end

local control = "FIRST LINE\vSECOND LINE THAT MUST WRAP CLEANLY"
local wrappedControl = Wrap.wrap(control, 18)
ok(wrappedControl:find("\v", 1, true) ~= nil,
  "existing CONT control survives automatic wrapping")
ok(within(wrappedControl, 18), "CONT message also respects the width")

local longWord = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
local wrappedWord = Wrap.wrap(longWord, 18)
ok(within(wrappedWord, 18), "a word longer than the box splits safely")
eq(withoutControls(wrappedWord), longWord,
  "long-word fallback does not drop characters")

ok(Wrap.installRuntime(), "Crystal battle-text wrapper installs")
local firstWrapper = BattleState.startMessage
ok(not Wrap.installRuntime(), "Crystal battle-text wrapper installs only once")
eq(BattleState.startMessage, firstWrapper, "second install does not wrap twice")

local item = { text="Enemy POKEMON got an ENCORE!", auto=true }
local crystal = { crystal251Active=true }
eq(BattleState.startMessage(crystal, item), "parsed", "wrapped call preserves return value")
ok(within(crystal.parsedText, 18), "Crystal classic battle is auto-wrapped")
eq(item.text, "Enemy POKEMON got an ENCORE!",
  "queue item text is restored after parsing")
ok(item.auto, "queue item metadata is preserved")

local vanilla = { crystal251Active=false }
local vanillaItem = { text="Enemy POKEMON got an ENCORE!" }
BattleState.startMessage(vanilla, vanillaItem)
eq(vanilla.parsedText, vanillaItem.text,
  "non-Crystal battles keep the engine's original text path")

local wide = {
  crystal251Active=true,
  wideLayout=function() return true end,
}
local wideItem = { text="THIS MESSAGE IS LONGER THAN EIGHTEEN" }
BattleState.startMessage(wide, wideItem)
eq(wide.parsedText, wideItem.text,
  "newer WIDE battle layout uses its larger message width")

if failures > 0 then
  io.stderr:write(("%d/%d checks failed (Crystal battle text wrap)\n")
    :format(failures, checks))
  os.exit(1)
end
print(("%d/%d checks passed (Crystal battle text wrap)"):format(checks, checks))
