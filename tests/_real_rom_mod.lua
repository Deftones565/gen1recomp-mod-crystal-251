local Helper = {}

function Helper.load(T, raw)
  love.data = {
    hash=function(kind, value)
      assert(kind == "sha1" and value == raw)
      return "verified-crystal-v11"
    end,
    encode=function(container, encoding, digest)
      assert(container == "string" and encoding == "hex"
        and digest == "verified-crystal-v11")
      return "f2f52230b536214ef7c9924f483392993e226cfb"
    end,
  }
  local inner = T.fs.new(".")
  local fs = { root=inner.root }
  function fs.read(path)
    if path == "mods/CRYSTAL_251/baseroms/crystal.gbc" then return raw end
    return inner.read(path)
  end
  function fs.write(path, body) return inner.write(path, body) end
  function fs.load(path) return inner.load(path) end
  function fs.getInfo(path) return inner.getInfo(path) end
  function fs.getDirectoryItems(path)
    if path == "mods" then return { "CRYSTAL_251" } end
    return inner.getDirectoryItems(path)
  end
  local Data = require("src.core.Data")
  Data:load()
  local run = T.sdk.loadMod("mods/CRYSTAL_251", { data=Data, fs=fs })
  return run, assert(require("mods.CRYSTAL_251.lib.cache").readContent())
end

return Helper
