-- Crystal party-menu icon identities in National Dex order. Crystal reuses
-- these two-frame menu icons for Pokemon overworld objects, including the
-- Day Care boarders (MonMenuIcons / GetMonSprite).
local Icons = {}

Icons.MAX_INDEX = 38
Icons.BY_DEX = {
  22, 22, 22, 23, 23, 38, 21, 21, 21, 24, 24, 30, 24, 24, 11, 7,
  7, 7, 15, 15, 7, 7, 19, 19, 4, 4, 8, 8, 15, 15, 8, 15,
  15, 8, 9, 9, 15, 15, 2, 2, 31, 31, 10, 10, 10, 11, 11, 24,
  30, 3, 3, 15, 15, 8, 8, 27, 27, 15, 15, 1, 1, 1, 14, 14,
  14, 27, 27, 27, 10, 10, 10, 29, 29, 26, 26, 26, 16, 16, 36, 36,
  20, 20, 7, 7, 7, 13, 13, 18, 18, 17, 17, 12, 12, 12, 19, 14,
  14, 17, 17, 20, 20, 10, 10, 8, 8, 27, 27, 8, 18, 18, 16, 8,
  9, 10, 8, 6, 6, 6, 6, 5, 5, 14, 11, 14, 14, 14, 11, 16,
  6, 35, 13, 18, 15, 15, 15, 15, 20, 17, 17, 17, 17, 7, 32, 7,
  7, 7, 19, 19, 38, 14, 14, 10, 10, 10, 15, 15, 15, 8, 8, 8,
  15, 15, 7, 7, 11, 11, 11, 11, 31, 6, 6, 4, 9, 2, 9, 7,
  7, 7, 15, 8, 8, 10, 2, 2, 37, 1, 10, 10, 10, 8, 10, 10,
  11, 8, 8, 15, 15, 7, 36, 12, 25, 12, 16, 11, 11, 19, 11, 19,
  8, 8, 6, 11, 11, 11, 15, 8, 8, 18, 18, 16, 16, 17, 6, 6,
  8, 6, 7, 15, 15, 38, 16, 16, 20, 16, 8, 27, 27, 14, 14, 14,
  16, 9, 15, 15, 15, 8, 8, 8, 34, 33, 14,
}

function Icons.spriteId(index)
  index = math.max(1, math.min(Icons.MAX_INDEX, math.floor(tonumber(index) or 8)))
  return ("CRYSTAL_251_DAYCARE_ICON_%02d"):format(index)
end

return Icons
