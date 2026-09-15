local RuntimePatches = require("mods.CRYSTAL_251.lib.runtime_patches")
-- Crystal battle-text soft wrapping.
--
-- Gen1Recomp's normal TextBox already soft-wraps text, but the battle queue
-- has a separate BattleState:startMessage path which only splits explicit
-- \n / \v control markers. Crystal generates many messages at runtime, so
-- long species names can make otherwise-correct text overflow the battle box.
-- Keep the fix mod-local: wrap Crystal battle text before the engine parser
-- sees it, using the same glyph/word boundaries as TextBox.paginate.

local Wrap = {}

local CLASSIC_COLS = 18
local WIDE_COLS = 36

local function messageColumns(battle)
  -- WIDE was added after Gen1Recomp 0.1.30. Detect it when available so this
  -- mod stays compatible with newer engines without wrapping at 18 too early.
  for _, method in ipairs({ "wideLayout", "isWideBattleLayout" }) do
    local fn = battle and battle[method]
    if type(fn) == "function" then
      local ok, wide = pcall(fn, battle)
      if ok and wide then return WIDE_COLS end
    end
  end
  return CLASSIC_COLS
end

local function lineSpans(text)
  local Font = require("src.render.Font")
  if type(Font.split) == "function" then
    return Font.split(text), Font
  end

  local spans = {}
  for i = 1, #text do spans[#spans + 1] = { from=i, to=i } end
  return spans, Font
end

local function fitCount(spans, columns, Font)
  local fit = math.min(#spans, columns)
  if type(Font.spansFitting) == "function" then
    local measured = Font.spansFitting(spans, columns * 8)
    if type(measured) == "number" then fit = math.min(fit, measured) end
  end
  return math.max(1, fit)
end

local function wrapLine(line, columns)
  local out = {}
  while true do
    local spans, Font = lineSpans(line)
    if #spans <= columns then
      out[#out + 1] = line
      break
    end

    local fit = fitCount(spans, columns, Font)
    if fit >= #spans then
      out[#out + 1] = line
      break
    end

    local cut = spans[fit].to
    for i = fit, 1, -1 do
      if line:sub(spans[i].from, spans[i].to) == " " then
        cut = spans[i].to
        break
      end
    end

    out[#out + 1] = line:sub(1, cut)
    line = line:sub(cut + 1)
  end
  return out
end

function Wrap.wrap(text, columns)
  if type(text) ~= "string" or text == "" then return text end
  columns = math.max(1, math.floor(tonumber(columns) or CLASSIC_COLS))

  local out = {}
  local pos = 1
  while true do
    local marker = text:find("[\n\v]", pos)
    local chunk = marker and text:sub(pos, marker - 1) or text:sub(pos)
    local lines = wrapLine(chunk, columns)
    for i, line in ipairs(lines) do
      if i > 1 then out[#out + 1] = "\n" end
      out[#out + 1] = line
    end
    if not marker then break end
    out[#out + 1] = text:sub(marker, marker)
    pos = marker + 1
  end
  return table.concat(out)
end

function Wrap.installRuntime()
  local BattleState = RuntimePatches.watch(require("src.battle.BattleState"))
  if BattleState._crystal251TextWrapBridge then return false end
  local originalStartMessage = BattleState.startMessage
  if type(originalStartMessage) ~= "function" then return false end

  BattleState._crystal251TextWrapBridge = true
  BattleState.startMessage = function(self, item)
    if not (self and self.crystal251Active and item
        and type(item.text) == "string") then
      return originalStartMessage(self, item)
    end

    local originalText = item.text
    local wrapped = Wrap.wrap(originalText, messageColumns(self))
    if wrapped == originalText then
      return originalStartMessage(self, item)
    end

    item.text = wrapped
    local ok, a, b, c = pcall(originalStartMessage, self, item)
    item.text = originalText
    if not ok then error(a, 0) end
    return a, b, c
  end
  return true
end

Wrap._test = {
  messageColumns = messageColumns,
  wrapLine = wrapLine,
}

return RuntimePatches.installers(Wrap)
