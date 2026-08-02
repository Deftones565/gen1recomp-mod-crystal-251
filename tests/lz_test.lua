package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
local LZ = require("mods.CRYSTAL_251.lib.lz")

local out = LZ.decompress({ 0x02, 1, 2, 3, 0x21, 9, 0x42, 4, 5, 0x63, 0xff })
T.same(out, {1,2,3,9,9,4,5,4,0,0,0,0},
  "literal, iterate, alternate and zero commands decode")
local repeated = LZ.decompress({ 0x02, 0x12, 0x34, 0x56, 0x82, 0x82, 0xff })
T.same(repeated, {0x12,0x34,0x56,0x12,0x34,0x56}, "look-back command decodes")
T.finish("crystal 251 lz")
