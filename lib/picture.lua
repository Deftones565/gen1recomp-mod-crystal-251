local Picture = {}

local function requiredBytes(tilesWide, tilesHigh)
  return tilesWide * tilesHigh * 16
end

-- Crystal stores back pictures column-first (rgbgfx --columns), unlike its
-- front pictures. Return exactly one resting frame in ordinary row-major
-- tile order so both the PNG writer and visual tests exercise one code path.
function Picture.normalize(raw, tilesWide, tilesHigh, layout)
  local needed = requiredBytes(tilesWide, tilesHigh)
  assert(#raw >= needed, "short decompressed Crystal picture")
  local out = {}
  if layout == "columns" then
    for y = 0, tilesHigh - 1 do
      for x = 0, tilesWide - 1 do
        local source = (x * tilesHigh + y) * 16
        local target = (y * tilesWide + x) * 16
        for byte = 1, 16 do out[target + byte] = raw[source + byte] end
      end
    end
  else
    for i = 1, needed do out[i] = raw[i] end
  end
  return out
end

-- A palette-independent visual raster: one byte (shade 0..3) per pixel.
-- Hashing this catches tile order, bitplane order, dimensions and accidental
-- animation-frame changes without committing copyrighted sprite artwork.
function Picture.shadeRaster(raw, tilesWide, tilesHigh, layout)
  raw = Picture.normalize(raw, tilesWide, tilesHigh, layout)
  local pixels = {}
  for tile = 0, tilesWide * tilesHigh - 1 do
    local tx, ty = tile % tilesWide * 8, math.floor(tile / tilesWide) * 8
    for y = 0, 7 do
      local lo, hi = raw[tile * 16 + y * 2 + 1], raw[tile * 16 + y * 2 + 2]
      for x = 0, 7 do
        local mask = 2 ^ (7 - x)
        local shade = math.floor(lo / mask) % 2 + math.floor(hi / mask) % 2 * 2
        pixels[(ty + y) * tilesWide * 8 + tx + x + 1] = string.char(shade)
      end
    end
  end
  return table.concat(pixels)
end

-- Pixels connected to a boundary through shade 0 are the picture's paper,
-- while enclosed shade-0 pixels are white details that must remain visible.
-- Return a sparse one-based set so palette choice cannot affect alpha.
function Picture.boundaryTransparency(raster, width, height)
  assert(#raster == width * height, "Crystal shade raster has wrong dimensions")
  local transparent, queued, queue, head = {}, {}, {}, 1
  local function add(x, y)
    local index = y * width + x + 1
    if queued[index] or raster:byte(index) ~= 0 then return end
    queued[index] = true
    queue[#queue + 1] = index
  end
  for x = 0, width - 1 do add(x, 0); add(x, height - 1) end
  for y = 0, height - 1 do add(0, y); add(width - 1, y) end
  while head <= #queue do
    local index = queue[head]
    head = head + 1
    transparent[index] = true
    local zero = index - 1
    local x, y = zero % width, math.floor(zero / width)
    if x > 0 then add(x - 1, y) end
    if x + 1 < width then add(x + 1, y) end
    if y > 0 then add(x, y - 1) end
    if y + 1 < height then add(x, y + 1) end
  end
  return transparent
end

return Picture
