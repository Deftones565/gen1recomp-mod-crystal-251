local Registry = {}

-- Content registries reject duplicate register() calls. Compatibility mods
-- commonly own the same base-game id, so every intentional replacement must
-- be expressed as an override. Keeping that decision here prevents new import
-- paths from accidentally bringing load-order crashes back.
function Registry.upsert(registry, id, value)
  assert(registry and registry.get and registry.register and registry.override,
    "registry must provide get/register/override")
  assert(id ~= nil, "registry id is required")
  if registry:get(id) ~= nil then
    registry:override(id, value)
    return "override"
  end
  registry:register(id, value)
  return "register"
end

return Registry
