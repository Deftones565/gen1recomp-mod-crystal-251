-- Ordinary Kanto-world acquisition paths for Crystal's two additional HMs.
--
-- Crystal gives HM06 to the player through Lance after the Mahogany Rocket
-- operation and places HM07 as an item ball in Ice Path.  This conversion has
-- neither Johto map, so preserve those acquisition methods at their closest
-- Kanto progression equivalents:
--   * Lance gives HM06 after the Rocket Hideout Giovanni victory.
--   * HM07 is a deep ice-cave item ball in Seafoam Islands B4F.
--
-- TM01-TM50 and HM01-HM05 retain the base game's ordinary reward, pickup,
-- prize, and shop paths by machine number; crystal_machines.lua changes only
-- which move each numbered machine teaches.

local Progression = {}

local HM06_FLAG = "MOD_CRYSTAL251_GOT_HM06"
local LANCE_TEXT = "TEXT_CRYSTAL251_ROCKET_HIDEOUT_LANCE"
local LANCE_NAME = "CRYSTAL251_ROCKET_HIDEOUT_LANCE"
local HM07_NAME = "CRYSTAL251_SEAFOAM_HM07"
local HM07_TEXT = "TEXT_CRYSTAL251_SEAFOAM_HM07"

local function nextObjectIndex(map)
  local highest = 0
  for _, object in ipairs(map.objects or {}) do
    highest = math.max(highest, tonumber(object.index) or 0)
  end
  return highest + 1
end

local function installAcquisition(mod)
  local rocket = assert(mod.content.maps:get("ROCKET_HIDEOUT_B4F"),
    "missing ROCKET_HIDEOUT_B4F map")
  local seafoam = assert(mod.content.maps:get("SEAFOAM_ISLANDS_B4F"),
    "missing SEAFOAM_ISLANDS_B4F map")

  mod.content.maps:patch("ROCKET_HIDEOUT_B4F", { objects={ __append={ {
    index=nextObjectIndex(rocket), x=27, y=7, sprite="SPRITE_LANCE",
    movement="STAY", range="LEFT", text=LANCE_TEXT, name=LANCE_NAME,
  } } } })

  mod.content.map_scripts:register("ROCKET_HIDEOUT_B4F", { talk={
    [LANCE_TEXT]={
      { "face_player" },
      { "check_flag", "EVENT_BEAT_ROCKET_HIDEOUT_GIOVANNI" },
      { "jump_if_false", "rocket_active" },
      { "check_flag", HM06_FLAG },
      { "jump_if_true", "after" },
      { "show_text", "You drove TEAM\nROCKET out!\fThis HM will help\nyou master rough\vwater." },
      { "give_item", "HM_06" },
      { "set_flag", HM06_FLAG },
      { "show_text", "HM06 teaches\nWHIRLPOOL.\fUse it wisely!" },
      { "jump", "end" },

      { "label", "rocket_active" },
      { "show_text", "TEAM ROCKET is\nstill below.\fTheir leader must\nbe stopped!" },
      { "jump", "end" },

      { "label", "after" },
      { "show_text", "WHIRLPOOL can\ntrap foes in\vraging water." },
    },
  } })

  mod.content.maps:patch("SEAFOAM_ISLANDS_B4F", { objects={ __append={ {
    index=nextObjectIndex(seafoam), x=9, y=2, sprite="SPRITE_POKE_BALL",
    movement="STAY", range="NONE", item="HM_07", text=HM07_TEXT,
    name=HM07_NAME,
  } } } })

  return {
    hm06={ map="ROCKET_HIDEOUT_B4F", method="gift", flag=HM06_FLAG,
      object=LANCE_NAME },
    hm07={ map="SEAFOAM_ISLANDS_B4F", method="item_ball", object=HM07_NAME },
  }
end

-- MoveLearnMenu's builtin table reflects Red/Blue/Yellow's five HMs. Install
-- a mod-owned factory that decorates the builtin screen and consults the live
-- constants.hmMoves list, allowing Crystal to protect HM06 and HM07 without
-- changing the shared engine or affecting games where this mod is disabled.
local function installForgetProtection(mod)
  local screens = mod.content.screens
  local previous = screens:get("MoveLearnMenu")
  local previousNew
  if type(previous) == "function" then
    previousNew = previous
  elseif type(previous) == "table" then
    previousNew = previous.new
  end
  previousNew = previousNew or require("src.ui.MoveLearnMenu").new

  require("mods.CRYSTAL_251.lib.registry").upsert(screens, "MoveLearnMenu", {
    new=function(game, mon, newMoveId, onDone)
      -- Decorate the effective factory rather than rebuilding the vanilla
      -- screen. UI mods such as Useful Move Info can therefore keep their
      -- extra rows and controls while Crystal extends HM protection.
      local screen = previousNew(game, mon, newMoveId, onDone)
      local builtinUpdate = screen.update
      screen.update = function(self, dt)
        local input = self.game.input
        if self.selecting and input:wasPressed("a")
            and self.index <= #self.mon.moves then
          local selected = self.mon.moves[self.index]
          local isHM = false
          for _, moveId in ipairs(self.game.data.constants.hmMoves or {}) do
            if selected and selected.id == moveId then isHM = true break end
          end
          if isHM then
            local TextBox = require("src.render.TextBox")
            self.game.stack:push(TextBox.new(self.game,
              require("src.core.Strings")("HM techniques\ncan't be deleted!")))
            return
          end
        end
        return builtinUpdate(self, dt)
      end
      return screen
    end,
  })
end

function Progression.install(mod)
  local acquisition = installAcquisition(mod)
  installForgetProtection(mod)
  return acquisition
end

Progression.HM06_FLAG = HM06_FLAG
Progression.LANCE_TEXT = LANCE_TEXT
Progression.LANCE_NAME = LANCE_NAME
Progression.HM07_NAME = HM07_NAME
Progression.installForgetProtection = installForgetProtection

return Progression
