local Bag = require("src.inventory.Bag")

local HeldItems = {}

local SCREEN_ID = "Crystal251HeldItemPicker"

local function itemName(data, id)
  local def = data and data.items and data.items[id]
  return (def and def.name) or id or "ITEM"
end

local function monName(data, mon)
  local def = mon and data and data.pokemon and data.pokemon[mon.species]
  return (mon and mon.nickname) or (def and def.name)
    or (mon and mon.species) or "POKéMON"
end

-- Crystal keeps key items and machines in PACK pockets that cannot be given.
-- Mail needs its compose/erase-message flow; until that flow exists, refusing
-- it is safer than creating held mail with no message attached.
function HeldItems.canGive(data, mon, itemId)
  if not mon then return false, "no_pokemon" end
  if mon.isEgg then return false, "egg" end
  local def = data and data.items and data.items[itemId]
  if not def then return false, "unknown_item" end
  if def.isMail or def.mail then return false, "mail" end
  if def.keyItem or Bag.isBadge(itemId) then return false, "key_item" end
  if def.machine then return false, "machine" end
  return true
end

local function canReturnHeldItem(data, save, heldId, givingId)
  local inv = save.inventory
  local heldCount = inv[heldId] or 0
  if heldCount >= 99 then return false end
  if heldCount > 0 or Bag.isBadge(heldId) then return true end

  local slotsAfterRemoval = Bag.slots(save)
  if (inv[givingId] or 0) == 1 then slotsAfterRemoval = slotsAfterRemoval - 1 end
  return slotsAfterRemoval < Bag.capacity(data)
end

-- All inventory checks happen before mutation. A failed Give/Switch therefore
-- cannot lose an item or perturb bagOrder.
function HeldItems.give(data, save, mon, itemId)
  local ok, reason = HeldItems.canGive(data, mon, itemId)
  if not ok then return false, reason end
  if not save or not save.inventory or (save.inventory[itemId] or 0) < 1 then
    return false, "not_owned"
  end

  local old = mon.heldItem
  if old == itemId then return false, "already_holding" end
  if old and not canReturnHeldItem(data, save, old, itemId) then
    return false, "bag_full"
  end

  Bag.remove(save, itemId, 1)
  if old then
    -- Preflight above guarantees this add. Keep the guard defensive for saves
    -- whose inventory is changed by another hook during the operation.
    if not Bag.add(save, old, 1, data) then
      Bag.add(save, itemId, 1, data)
      return false, "bag_full"
    end
  end
  mon.heldItem = itemId
  return true, old and "swapped" or "given", old
end

function HeldItems.take(data, save, mon)
  if not mon or not mon.heldItem then return false, "nothing_held" end
  local held = mon.heldItem
  if not Bag.add(save, held, 1, data) then return false, "bag_full" end
  mon.heldItem = nil
  return true, "taken", held
end

local function failureText(reason)
  if reason == "egg" then return "An EGG can't hold\nan item."
  elseif reason == "mail" then return "MAIL needs a written\nmessage to be held."
  elseif reason == "key_item" or reason == "machine" then
    return "That item can't\nbe held."
  elseif reason == "bag_full" then return "The PACK is full."
  elseif reason == "nothing_held" then return "It isn't holding\nanything."
  elseif reason == "already_holding" then return "It's already holding\nthat item."
  elseif reason == "not_owned" then return "That item is no\nlonger in the PACK."
  end
  return "That item can't\nbe held."
end

function HeldItems.install(mod)
  mod.content.screens:register(SCREEN_ID, {
    new = function(game, opts)
      opts = opts or {}
      local mon = opts.mon
      local rows = {}
      for _, id in ipairs(Bag.order(game.save)) do
        local def = game.data.items[id]
        rows[#rows + 1] = {
          value = id,
          label = itemName(game.data, id),
          right = "x" .. tostring(game.save.inventory[id]),
        }
      end

      local list
      local function show(text, onDone, textOpts)
        game.stack:push(mod.ui.TextBox.new(game, text, onDone, textOpts))
      end
      local function applyGive(id)
        local ok, result = HeldItems.give(game.data, game.save, mon, id)
        if not ok then show(failureText(result)) return end
        list:close()
        local name = monName(game.data, mon)
        if result == "swapped" then
          show(name .. " switched\nheld items.")
        else
          show(name .. " is now holding\n" .. itemName(game.data, id) .. ".")
        end
      end
      list = mod.ui.ListMenu.new(game, "GIVE WHICH?", rows, {
        kind = "crystal-held-items",
        pageJump = true,
        onChoose = function(row)
          if not row then return end
          local allowed, reason = HeldItems.canGive(game.data, mon, row.value)
          if not allowed then show(failureText(reason)) return end
          if mon.heldItem then
            show("Switch the two\nitems?", nil, {
              choice = function(yes) if yes then applyGive(row.value) end end,
            })
          else
            applyGive(row.value)
          end
        end,
      })
      return list
    end,
  })

  local function openItemMenu(game, mon)
    local choices = {
      { label = "GIVE", onSelect = function()
          mod.ui.push(game, SCREEN_ID, { mon = mon })
        end },
    }
    if mon.heldItem then
      choices[#choices + 1] = { label = "TAKE", onSelect = function()
        local ok, reason, held = HeldItems.take(game.data, game.save, mon)
        local text = ok
          and ("Took " .. itemName(game.data, held) .. " from\n"
            .. monName(game.data, mon) .. ".")
          or failureText(reason)
        game.stack:push(mod.ui.TextBox.new(game, text))
      end }
    end
    game.stack:push(mod.ui.Menu.new(game, choices, {
      tx = 11, ty = 6, tw = 9,
    }))
  end

  mod.hooks:wrap("ui.party.submenu", function(next, game, items, mon, ctx)
    local out = next(game, items, mon, ctx)
    if type(out) ~= "table" or not mon or (ctx and ctx.battle) then return out end
    table.insert(out, math.min(3, #out + 1), {
      label = "ITEM",
      onSelect = function() openItemMenu(game, mon) end,
    })
    return out
  end)

  HeldItems.screenId = SCREEN_ID
  HeldItems.failureText = failureText
  return HeldItems
end

return HeldItems
