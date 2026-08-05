-- Mod-local interpreter for Pokemon Crystal battle command streams.
--
-- The retail game stores each move effect as a compact list of battle
-- commands.  This module provides the same execution shape without changing
-- the engine: scripts are immutable declarative rows, handlers are supplied by
-- the Crystal subsystem that owns a phase, and unported battle-phase commands
-- remain visible in the script instead of disappearing into ad-hoc callbacks.

local Interpreter = {}
Interpreter.__index = Interpreter

local PHASE = {
  checkturn="battle", checkobedience="battle", usedmovetext="battle",
  doturn="battle", checkhit="battle", effectchance="battle",
  moveanim="battle", moveanimnosub="battle", failuretext="battle",
  applydamage="battle", criticaltext="battle", supereffectivetext="battle",
  checkfaint="battle", buildopponentrage="battle", kingsrock="battle",
  dispatch_effect="battle",

  -- Command-specific damage families migrated in patch 0015.
  storeenergy="battle", unleashenergy="battle", resettypematchup="battle",
  bidefailtext="battle", constantdamage="battle", ohko="battle",
  counter="battle", mirrorcoat="battle", present="battle",
  checkfuturesight="battle", futuresight="battle", movedelay="battle",
  startloop="battle", lowersub="battle", raisesub="battle",
  beatup="battle", clearmissdamage="battle", cleartext="battle",
  supereffectivelooptext="battle", endloop="battle",
  beatupfailtext="battle",

  -- Repeated-hit and consecutive-use families migrated in patch 0016.
  checkrampage="battle", rampage="battle", ragedamage="battle", rage="battle",
  checkrollout="battle", rolloutpower="battle", furycutter="battle",
  triplekick="battle", kickcounter="battle", poisontarget="battle",

  -- Major status and volatile commands migrated in patch 0017.
  checksafeguard="battle", sleeptarget="battle", burntarget="battle",
  freezetarget="battle", paralyzetarget="battle", confusetarget="battle",
  flinchtarget="battle", poison="battle", paralyze="battle",
  confuse="battle", substitute="battle", leechseed="battle",
  disable="battle", encore="battle", nightmare="battle",
  protect="battle", endure="battle", safeguard="battle",
  perishsong="battle", arenatrap="battle", traptarget="battle",
  mist="battle", focusenergy="battle", attract="battle", foresight="battle",
  forceswitch="battle", batonpass="battle", pursuit="battle", spikes="battle",

  critical="damage", damagestats="damage", damagecalc="damage",
  stab="damage", damagevariation="damage",

  endmove="all",
}

Interpreter.PHASE = PHASE

local function normalize(command)
  if type(command) == "string" then return { op=command } end
  assert(type(command) == "table", "Crystal command must be a string or table")
  local op = command.op or command[1]
  assert(type(op) == "string" and op ~= "", "Crystal command is missing op")
  local row = {}
  for key, value in pairs(command) do row[key] = value end
  row.op = op
  row[1] = nil
  return row
end

local function copyCommands(commands)
  local out = {}
  for i, command in ipairs(commands or {}) do out[i] = normalize(command) end
  return out
end

function Interpreter.new(extra)
  local self = setmetatable({ handlers={}, compiled=setmetatable({}, { __mode="k" }) }, Interpreter)
  for name, row in pairs(PHASE) do
    self.handlers[name] = { phase=row }
  end
  for name, handler in pairs(extra or {}) do self:register(name, handler) end
  return self
end

function Interpreter:register(name, handler, phase)
  assert(type(name) == "string" and name ~= "", "Crystal command name is required")
  if type(handler) == "table" then
    self.handlers[name] = { fn=handler.fn, phase=handler.phase or phase or "all" }
  else
    self.handlers[name] = { fn=handler, phase=phase or (PHASE[name] or "all") }
  end
  return self
end

function Interpreter:knows(name)
  return self.handlers[name] ~= nil or PHASE[name] ~= nil
end

function Interpreter:compile(script)
  assert(type(script) == "table", "Crystal move script must be a table")
  local cached = self.compiled[script]
  if cached then return cached end
  local compiled = {
    id=script.id, index=script.index, effect=script.effect,
    effectByte=script.effectByte, effectName=script.effectName,
    mode=script.mode, commands=copyCommands(script.commands),
  }
  self.compiled[script] = compiled
  return compiled
end

function Interpreter:validate(script)
  local compiled = self:compile(script)
  if not compiled.id then return false, "script is missing move id" end
  if not compiled.index then return false, compiled.id .. " is missing move index" end
  if #compiled.commands == 0 then return false, compiled.id .. " has no commands" end
  for _, command in ipairs(compiled.commands) do
    if not self:knows(command.op) then
      return false, compiled.id .. " uses unknown command " .. tostring(command.op)
    end
  end
  if compiled.commands[#compiled.commands].op ~= "endmove" then
    return false, compiled.id .. " does not terminate with endmove"
  end
  return true
end

function Interpreter:run(script, ctx, phase)
  phase = phase or "all"
  ctx = ctx or {}
  local compiled = self:compile(script)
  local state = ctx.state or {}
  state.script = compiled
  -- A subsystem may seed state.ctx with its public battle-effect context.
  -- Keep that facade instead of replacing it with this interpreter wrapper.
  state.ctx = state.ctx or ctx
  state.trace = state.trace or {}

  for _, command in ipairs(compiled.commands) do
    local registered = self.handlers[command.op] or { phase=PHASE[command.op] or "all" }
    local commandPhase = registered.phase or "all"
    if phase == "all" or commandPhase == "all" or commandPhase == phase then
      state.trace[#state.trace + 1] = command.op
      local fn = (ctx.handlers and ctx.handlers[command.op]) or registered.fn
      if fn then
        local result = fn(state, command, ctx)
        if result ~= nil then state.result = result end
      end
      if state.stop or command.op == "endmove" then break end
    end
  end
  return state
end

return Interpreter
