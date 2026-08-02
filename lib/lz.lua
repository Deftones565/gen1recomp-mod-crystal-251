-- Pokemon Crystal's LZ command stream, ported from pret/pokecrystal's
-- tools/lzcompress.c. Input and output are byte arrays indexed from one.
local LZ = {}

local function flipByte(value)
  local out = 0
  for bit = 0, 7 do
    if math.floor(value / 2 ^ bit) % 2 == 1 then
      out = out + 2 ^ (7 - bit)
    end
  end
  return out
end

function LZ.decompress(bytes, start)
  local pos, out = start or 1, {}
  local function byte()
    local value = type(bytes) == "string" and bytes:byte(pos) or bytes[pos]
    assert(value ~= nil, "truncated Crystal LZ stream")
    pos = pos + 1
    return value
  end
  while true do
    local header = byte()
    if header == 0xff then break end
    local command, length = math.floor(header / 32), header % 32
    if command == 7 then
      command = math.floor(length / 4)
      length = (length % 4) * 256 + byte()
    end
    length = length + 1
    if command == 0 then
      for _ = 1, length do out[#out + 1] = byte() end
    elseif command == 1 then
      local value = byte()
      for _ = 1, length do out[#out + 1] = value end
    elseif command == 2 then
      local a, b = byte(), byte()
      for i = 1, length do out[#out + 1] = i % 2 == 1 and a or b end
    elseif command == 3 then
      for _ = 1, length do out[#out + 1] = 0 end
    elseif command >= 4 and command <= 6 then
      local encoded = byte()
      local base
      if encoded >= 0x80 then
        base = #out - (encoded % 0x80)
      else
        base = encoded * 256 + byte() + 1
      end
      for i = 0, length - 1 do
        local source = command == 6 and base - i or base + i
        local value = assert(out[source], "invalid Crystal LZ back-reference")
        out[#out + 1] = command == 5 and flipByte(value) or value
      end
    else
      error("invalid Crystal LZ command " .. tostring(command))
    end
  end
  return out, pos
end

return LZ
