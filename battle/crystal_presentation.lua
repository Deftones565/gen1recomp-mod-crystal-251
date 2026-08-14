local Presentation = {}

local MOVE_ALIASES = {
  SKETCH="MIMIC", TRIPLE_KICK="DOUBLE_KICK", THIEF="ABSORB",
  SPIDER_WEB="STRING_SHOT", MIND_READER="FOCUS_ENERGY",
  NIGHTMARE="DREAM_EATER", FLAME_WHEEL="FIRE_SPIN", SNORE="SONICBOOM",
  CURSE="CONFUSE_RAY", FLAIL="THRASH", CONVERSION2="CONVERSION",
  AEROBLAST="RAZOR_WIND", COTTON_SPORE="STUN_SPORE", REVERSAL="COUNTER",
  SPITE="DISABLE", POWDER_SNOW="BLIZZARD", PROTECT="LIGHT_SCREEN",
  MACH_PUNCH="MEGA_PUNCH", SCARY_FACE="LEER", FAINT_ATTACK="QUICK_ATTACK",
  SWEET_KISS="LOVELY_KISS", BELLY_DRUM="FOCUS_ENERGY",
  SLUDGE_BOMB="SLUDGE", MUD_SLAP="SAND_ATTACK", OCTAZOOKA="WATER_GUN",
  SPIKES="POISON_STING", ZAP_CANNON="THUNDERBOLT", FORESIGHT="FLASH",
  DESTINY_BOND="CONFUSE_RAY", PERISH_SONG="SING", ICY_WIND="BLIZZARD",
  DETECT="LIGHT_SCREEN", BONE_RUSH="BONEMERANG", LOCK_ON="FOCUS_ENERGY",
  OUTRAGE="THRASH", SANDSTORM="ROCK_SLIDE", GIGA_DRAIN="MEGA_DRAIN",
  ENDURE="HARDEN", CHARM="TAIL_WHIP", ROLLOUT="ROCK_SLIDE",
  FALSE_SWIPE="SLASH", SWAGGER="CONFUSION", MILK_DRINK="SOFTBOILED",
  SPARK="THUNDERSHOCK", FURY_CUTTER="CUT", STEEL_WING="WING_ATTACK",
  MEAN_LOOK="LEER", ATTRACT="LOVELY_KISS", SLEEP_TALK="METRONOME",
  HEAL_BELL="SING", RETURN="TAKE_DOWN", PRESENT="EGG_BOMB",
  FRUSTRATION="RAGE", SAFEGUARD="LIGHT_SCREEN", PAIN_SPLIT="RECOVER",
  SACRED_FIRE="FIRE_BLAST", MAGNITUDE="EARTHQUAKE",
  DYNAMICPUNCH="MEGA_PUNCH", MEGAHORN="HORN_ATTACK",
  DRAGONBREATH="DRAGON_RAGE", BATON_PASS="TELEPORT", ENCORE="MIMIC",
  PURSUIT="QUICK_ATTACK", RAPID_SPIN="CONSTRICT", SWEET_SCENT="PETAL_DANCE",
  IRON_TAIL="SLAM", METAL_CLAW="SCRATCH", VITAL_THROW="SEISMIC_TOSS",
  MORNING_SUN="RECOVER", SYNTHESIS="RECOVER", MOONLIGHT="RECOVER",
  HIDDEN_POWER="SWIFT", CROSS_CHOP="KARATE_CHOP", TWISTER="GUST",
  RAIN_DANCE="SURF", SUNNY_DAY="FIRE_BLAST", CRUNCH="BITE",
  MIRROR_COAT="COUNTER", PSYCH_UP="MEDITATE", EXTREMESPEED="QUICK_ATTACK",
  ANCIENTPOWER="ROCK_SLIDE", SHADOW_BALL="NIGHT_SHADE",
  FUTURE_SIGHT="PSYCHIC_M", ROCK_SMASH="MEGA_PUNCH",
  WHIRLPOOL="FIRE_SPIN", BEAT_UP="COMET_PUNCH",
}

local SPECIAL_ALIASES = {
  CRYSTAL_RAIN="SURF",
  CRYSTAL_SUN="FIRE_BLAST",
  CRYSTAL_SANDSTORM="ROCK_SLIDE",
  IN_SANDSTORM="ROCK_SLIDE",
  IN_WHIRLPOOL="FIRE_SPIN",
  IN_NIGHTMARE="DREAM_EATER",
}

local animations
local unownAnimations
local installed
local imageCache = setmetatable({}, { __mode="v" })

local function copy(value)
  if type(value) ~= "table" then return value end
  local out = {}
  for key, child in pairs(value) do out[key] = copy(child) end
  return out
end

local function shiny(mon)
  local dvs = mon and mon.dvs
  if not dvs then return false end
  local attack = { [2]=true,[3]=true,[6]=true,[7]=true,
    [10]=true,[11]=true,[14]=true,[15]=true }
  return dvs.defense == 10 and dvs.speed == 10 and dvs.special == 10
    and attack[dvs.attack] == true
end


local function unownLetter(mon)
  if mon and mon.crystal251Form then return mon.crystal251Form end
  local dvs = mon and mon.dvs
  if not dvs then return "A" end
  local function middle(value)
    value = value or 0
    return value % 8 - value % 2
  end
  local value = middle(dvs.attack) * 32 + middle(dvs.defense) * 8
    + middle(dvs.speed) * 2 + math.floor(middle(dvs.special) / 2)
  return string.char(64 + math.max(1, math.min(26, math.floor(value / 10) + 1)))
end

local function framePath(frame, mon)
  if shiny(mon) and frame.shinyPath then return frame.shinyPath end
  return frame.path
end

local function presentationMode()
  local mode = require("src.render.PaletteFX").mode
  return mode == "gbc" or mode == "redpp"
end

local function loadImage(path)
  local image = imageCache[path]
  if not image then
    image = require("src.render.Assets").image(path)
    imageCache[path] = image
  end
  return image
end

local function animationFrame(battle, battler, definition)
  battle._crystal251PicAnimations = battle._crystal251PicAnimations or {}
  local state = battle._crystal251PicAnimations[battler]
  if not state or state.mon ~= battler.mon or state.definition ~= definition then
    state = { start=battle.frame or 0, mon=battler.mon, definition=definition }
    battle._crystal251PicAnimations[battler] = state
  end
  local elapsed = (battle.frame or 0) - state.start
  for _, frame in ipairs(definition.frames or {}) do
    if elapsed < frame.duration then return loadImage(framePath(frame, battler.mon)) end
    elapsed = elapsed - frame.duration
  end
end

local function activePicFx(battle, battler)
  local state = battle.picFx and battle.picFx[battler]
  if not state then return false end
  return state.kind ~= nil or state.hidden == true or state.minimized == true
    or (state.ox or 0) ~= 0 or (state.oy or 0) ~= 0
end

function Presentation.register(mod, cache)
  for move, alias in pairs(MOVE_ALIASES) do
    if not mod.content.battle_anims:get(move) then
      local definition = assert(mod.content.battle_anims:get(alias), alias)
      mod.content.battle_anims:register(move, copy(definition))
    end
  end
  for name, alias in pairs(SPECIAL_ALIASES) do
    if not mod.content.battle_anims:get(name) then
      local definition = assert(mod.content.battle_anims:get(alias), alias)
      mod.content.battle_anims:register(name, copy(definition))
    end
  end
  for index, row in ipairs(cache.cries or {}) do
    local species = assert(cache.species[index]).id
    local definition = {
      chip=assert(row.chip), pitch=0, length=128,
    }
    if mod.content.cries:get(species) then
      mod.content.cries:override(species, definition)
    else
      mod.content.cries:register(species, definition)
    end
  end
end

function Presentation.configure(cache)
  animations = {}
  unownAnimations = {}
  for _, row in ipairs(cache.species or {}) do
    if row.frontAnimation then animations[row.id] = row.frontAnimation end
  end
  for _, row in ipairs(cache.unownForms or {}) do
    if row.frontAnimation then unownAnimations[row.letter] = row.frontAnimation end
  end
end

function Presentation.installRuntime()
  if installed then return false end
  installed = true
  local BattleState = require("src.battle.BattleState")
  local original = BattleState.drawBattlerPic
  BattleState.drawBattlerPic = function(self, battler, x, y, scale)
    local definition
    if animations and battler and not battler.isPlayer and battler.mon then
      if battler.mon.species == "UNOWN" then
        definition = unownAnimations and unownAnimations[unownLetter(battler.mon)]
      else
        definition = animations[battler.mon.species]
      end
    end
    if not definition or not presentationMode() or self.showEnemyTrainer
        or self.enemySendingOut or (self.introSlide or 0) > 0
        or self.blackedOut or self.grayPics or battler.fainted
        or battler.substituteHP or activePicFx(self, battler) then
      return original(self, battler, x, y, scale)
    end
    local frame = animationFrame(self, battler, definition)
    if not frame then return original(self, battler, x, y, scale) end
    local sprite = battler.sprite
    battler.sprite = frame
    local result = original(self, battler, x, y, scale)
    battler.sprite = sprite
    return result
  end
  return true
end

function Presentation.resetForTests()
  installed = nil
  animations = nil
  unownAnimations = nil
  imageCache = setmetatable({}, { __mode="v" })
end

Presentation.moveAliases = MOVE_ALIASES
Presentation.specialAliases = SPECIAL_ALIASES

return Presentation
