local _, ns = ...

---------------------------------------------------------------------------
-- Groups and rules (the redesign's groundwork, build step 2, November 15).
-- Nothing on screen uses them yet: the Buy, Post and My auctions tabs and the
-- Groups page will (planning/REDESIGN_PLAN.md sections 3, 7 and 8).
--
-- Groups come in four kinds:
--   built in    a tree kept up to date by us, sorted by the game's own item type
--               (C_Item.GetItemInfoInstant's class and subclass; Forever uses the
--               modern trade goods subclasses: Cloth 7/5, Leather 7/6, Metal and
--               stone 7/7, Cooking 7/8, Herb 7/9, Elemental 7/10, Other 7/11,
--               Enchanting 7/12, Parts 7/1) plus a few hand lists. Players can add
--               items to a built-in group or take them out; "Restore" undoes that.
--   profession  "Tailoring materials" and "Tailoring crafts", made from the recipe
--               data (captured books and ForeverCrafts.lua), never kept by hand.
--   special     Watched items (watchItems) and Gray items (poor quality).
--   yours       groups the player makes, optionally under one of their own.
--
-- Rules: four kinds (post, buy, vendor, craft). Each group has, per kind, one of
--   nil / "parent"  same as the group above (a top-level group: Forever Ledger's default)
--   "default"       Forever Ledger's default (RULE_DEFAULTS, not editable: we tune them)
--   "off"           no rule of this kind
--   "rule:<id>"     one of the player's saved rules (shared by several groups)
--   { fields }      changed here, for this group only
-- An item's rule: its groups in order (yours, then profession, then built in, the
-- deepest first); the first whose chain sets something explicitly wins. "Same as
-- the group above" all the way up claims nothing, so the next group gets a say.
--
-- Saved (account-wide), ns.db.groups:
--   user    = { [gid] = { name, parent = gid or nil, items = { [itemID] = true }, t } }
--   added   = { [builtinGid] = { [itemID] = true } }   items put into a built-in group
--   removed = { [builtinGid] = { [itemID] = true } }   items taken out of one
--   rules   = { [gid] = { post, buy, vendor, craft } } (see above)
--   saved   = { [rid] = { name, kind, fields, t } }    the player's own rules
--   nextId  = the next number for a user group or saved rule
---------------------------------------------------------------------------

ns.RULE_KINDS = { "post", "buy", "vendor", "craft" }

-- Forever Ledger's defaults (REDESIGN_PLAN.md: Frank agreed the posting rule November 15).
-- Prices are percents of the usual price; undercut and profits are copper.
ns.RULE_DEFAULTS = {
  -- Post matches the cheapest (Frank, November 15: listings at one price sell in the order
  -- they went up, so 1c under only starts a race down); a rule can still undercut.
  post = { start = "usual", undercut = 0, floorPct = 70, belowFloor = "skip", keep = 0, hours = 24 },
  buy = { underPct = 80, breakEvenProfit = nil, maxQty = 200 },
  vendor = { protectRecipes = true, under = "vendor" },
  craft = { stock = 0, minProfit = 50 },
}

-- The built-in tree, in display order. match = { classID, subclassID or nil for any }.
-- list = a hand list (checked before the item types, so a gem isn't "Other materials").
local BUILTIN = {
  { id = "mat", name = "Materials" },
  { id = "mat.cloth", parent = "mat", name = "Cloth", match = { { 7, 5 } } },
  { id = "mat.leather", parent = "mat", name = "Leather and hides", match = { { 7, 6 } } },
  { id = "mat.metal", parent = "mat", name = "Ore, bars and stone", match = { { 7, 7 } } },
  { id = "mat.herb", parent = "mat", name = "Herbs", match = { { 7, 9 } } },
  { id = "mat.cooking", parent = "mat", name = "Meat, fish and eggs", match = { { 7, 8 } } },
  { id = "mat.elemental", parent = "mat", name = "Elemental", match = { { 7, 10 } } },
  { id = "mat.enchanting", parent = "mat", name = "Enchanting", match = { { 7, 12 } } },
  { id = "mat.gems", parent = "mat", name = "Gems and pearls",
    list = { 774, 818, 1206, 1210, 1529, 1705, 3864, 5498, 5500, 7909, 7910, 7971, 11754, 12361, 12363, 12364, 12799, 12800, 13926 } },
  { id = "mat.parts", parent = "mat", name = "Parts", match = { { 7, 1 }, { 7, 2 }, { 7, 3 } } },
  { id = "mat.other", parent = "mat", name = "Other materials", match = { { 7 }, { 5 } } },
  { id = "con", name = "Consumables" },
  { id = "con.potion", parent = "con", name = "Potions", match = { { 0, 1 } } },
  { id = "con.elixir", parent = "con", name = "Elixirs and flasks", match = { { 0, 2 }, { 0, 3 } } },
  { id = "con.food", parent = "con", name = "Food and drink", match = { { 0, 5 } } },
  { id = "con.bandage", parent = "con", name = "Bandages", match = { { 0, 7 } } },
  { id = "con.scroll", parent = "con", name = "Scrolls", match = { { 0, 4 } } },
  { id = "con.enhance", parent = "con", name = "Armor kits and enhancements", match = { { 0, 6 } } },
  { id = "con.ammo", parent = "con", name = "Ammo", match = { { 6 } } },
  { id = "con.other", parent = "con", name = "Other consumables", match = { { 0 } } },
  { id = "rec", name = "Recipes and patterns" },
  { id = "rec.alchemy", parent = "rec", name = "Alchemy", match = { { 9, 6 } } },
  { id = "rec.blacksmithing", parent = "rec", name = "Blacksmithing", match = { { 9, 4 } } },
  { id = "rec.cooking", parent = "rec", name = "Cooking", match = { { 9, 5 } } },
  { id = "rec.enchanting", parent = "rec", name = "Enchanting", match = { { 9, 8 } } },
  { id = "rec.engineering", parent = "rec", name = "Engineering", match = { { 9, 3 } } },
  { id = "rec.firstaid", parent = "rec", name = "First Aid", match = { { 9, 7 } } },
  { id = "rec.fishing", parent = "rec", name = "Fishing", match = { { 9, 9 } } },
  { id = "rec.leatherworking", parent = "rec", name = "Leatherworking", match = { { 9, 1 } } },
  { id = "rec.tailoring", parent = "rec", name = "Tailoring", match = { { 9, 2 } } },
  { id = "rec.other", parent = "rec", name = "Other recipes", match = { { 9 } } },
  { id = "gear", name = "Gear" },
  { id = "gear.weapon", parent = "gear", name = "Weapons", match = { { 2 } } },
  { id = "gear.cloth", parent = "gear", name = "Cloth armor", match = { { 4, 1 } } },
  { id = "gear.leather", parent = "gear", name = "Leather armor", match = { { 4, 2 } } },
  { id = "gear.mail", parent = "gear", name = "Mail armor", match = { { 4, 3 } } },
  { id = "gear.plate", parent = "gear", name = "Plate armor", match = { { 4, 4 } } },
  { id = "gear.shield", parent = "gear", name = "Shields", match = { { 4, 6 } } },
  { id = "gear.jewelry", parent = "gear", name = "Rings, necks and trinkets", match = { { 4, 0 } } },
  { id = "gear.other", parent = "gear", name = "Other gear", match = { { 4 } } },
  { id = "bags", name = "Bags and quivers", match = { { 1 }, { 11 } } },
  { id = "crates", name = "Crates and writs" },
  { id = "turnins", name = "Quest and Darkmoon turn-ins" },
  { id = "fishing", name = "Fishing", list = { 6256, 6365, 6367, 12225, 19970, 6529, 6530, 6532, 6533, 7307 } },
  { id = "lockbox", name = "Lockboxes",
    list = { 4632, 4633, 4634, 4636, 4637, 4638, 5758, 5759, 5760, 16882, 16883, 16884, 16885 } },
  { id = "pets", name = "Pets and mounts", match = { { 15, 2 }, { 15, 5 } } },
  { id = "misc", name = "Miscellaneous" },
}
-- Fishing poles are weapons in the game's data (2/20): the hand list puts them in Fishing.

-- Gear by level too (REDESIGN_PLAN.md: bind-on-equip gear by kind and level band; owner,
-- AN19, November 15): under each kind of gear, one group per band of required level.
-- An item the game hasn't described yet (no required level) stays in its kind's group.
local BANDS = { { 1, 15 }, { 16, 25 }, { 26, 35 }, { 36, 45 }, { 46, 55 }, { 56, 60 } }
do
  local withBands = {}
  for _, g in ipairs(BUILTIN) do
    withBands[#withBands + 1] = g
    if g.parent == "gear" then
      for _, b in ipairs(BANDS) do
        withBands[#withBands + 1] = { id = g.id .. ".l" .. b[1], parent = g.id, name = ("Level %d-%d"):format(b[1], b[2]) }
      end
    end
  end
  BUILTIN = withBands
end

local byId, children, listed, order = {}, {}, {}, {}
for i, g in ipairs(BUILTIN) do
  g.kind, g.order = "builtin", i
  byId[g.id] = g
  order[#order + 1] = g.id
  local p = g.parent or "root"
  children[p] = children[p] or {}
  table.insert(children[p], g.id)
  for _, item in ipairs(g.list or {}) do listed[item] = g.id end
end
ns.BUILTIN_GROUPS = BUILTIN

local function store()
  local g = ns.db.groups
  if type(g) ~= "table" then g = {}; ns.db.groups = g end
  for _, k in ipairs({ "user", "added", "removed", "rules", "saved" }) do
    if type(g[k]) ~= "table" then g[k] = {} end
  end
  g.nextId = tonumber(g.nextId) or 1
  return g
end

local function instant(id)
  local f = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
  if not f then return end
  local _, _, _, _, _, classID, subclassID = f(id)
  return classID, subclassID
end

local function quality(id)
  if C_Item and C_Item.GetItemQualityByID then
    local q = C_Item.GetItemQualityByID(id)
    if q then return q end
  end
  if not ns.GetItemInfo then return end
  -- (Its own line: "ns.GetItemInfo and ns.GetItemInfo(id)" would keep only the name.)
  local _, _, q = ns.GetItemInfo(id)
  return q
end
ns.ItemQuality = quality   -- (the Ledger's Rarity choice)

-- Items a hand list holds that change at run time: the crate bundles read from crate
-- tooltips, and the quest and Darkmoon Faire turn-ins.
-- Every crate's items are known by item number (Crates.lua CRATE_BUNDLES); a crate read
-- from its tooltip is saved as { qty =, name =, id = } parts (older saves { qty, name }).
local function inCrates(id)
  if ns.CrateTakesItem and ns.CrateTakesItem(id) then return true end
  local name = ns.ItemName and ns.ItemName(id)
  for _, crate in pairs(ns.db.crates or {}) do
    for _, bundle in ipairs(crate.bundles or {}) do
      for _, part in ipairs(bundle) do
        if part.id == id or (name and (part.name or part[2]) == name) then return true end
      end
    end
  end
  return false
end
local function isTurnIn(id)
  if ns.DARKMOON and ns.DARKMOON[id] then return true end
  local needs = ns.QuestNeeds and ns:QuestNeeds(id)
  return needs ~= nil and #needs > 0
end

-- A gear kind's level band for the item, by its required level (the kind if unknown).
local function bandOf(gid, id)
  if not ns.GetItemInfo then return gid end
  -- (Its own line: the fifth value is the required level.)
  local name, _, _, _, req = ns.GetItemInfo(id)
  if not (name and type(req) == "number") then return gid end
  for i = #BANDS, 1, -1 do
    if req >= BANDS[i][1] then return gid .. ".l" .. BANDS[i][1] end
  end
  return gid .. ".l1"
end

-- The deepest built-in group an item falls in by itself (before the player's changes).
local function naturalGroup(id)
  if listed[id] then return listed[id] end
  local c, s = instant(id)
  if c then
    for _, gid in ipairs(order) do
      for _, m in ipairs(byId[gid].match or {}) do
        if m[1] == c and (m[2] == nil or m[2] == s) then
          if byId[gid].parent == "gear" then return bandOf(gid, id) end
          return gid
        end
      end
    end
  end
  return "misc"
end
ns.NaturalGroup = naturalGroup   -- (tests)

-- Built-in groups the item is in, deepest first: its natural group unless taken out
-- (then its parent, unless taken out there too), the groups it was added to, and the
-- run-time hand lists (crates and writs, turn-ins).
local function builtinGroups(id)
  local g = store()
  local out, seen = {}, {}
  local function add(gid) if gid and not seen[gid] then seen[gid] = true; out[#out + 1] = gid end end
  -- Taken out of its group or any group above it (Codex review, November 15: out of
  -- Materials must mean out of Cloth too): it sits just above the highest one it was
  -- taken out of, or in no built-in group if that's a top-level one. The same for the
  -- groups it was added to and for its natural one.
  local function placed(gid)
    local cut, cur = nil, gid
    while cur do
      if g.removed[cur] and g.removed[cur][id] then cut = cur end
      cur = byId[cur] and byId[cur].parent
    end
    if cut then return byId[cut].parent end
    return gid
  end
  for gid, items in pairs(g.added) do if items[id] then add(placed(gid)) end end
  add(placed(naturalGroup(id)))
  if not (g.removed.crates and g.removed.crates[id]) and inCrates(id) then add("crates") end
  if not (g.removed.turnins and g.removed.turnins[id]) and isTurnIn(id) then add("turnins") end
  table.sort(out, function(a, b)
    local da, db = select(2, a:gsub("%.", "")), select(2, b:gsub("%.", ""))
    if da ~= db then return da > db end
    return byId[a].order < byId[b].order
  end)
  return out
end

---------------------------------------------------------------------------
-- Profession groups: made from every recipe we know (captured books first, then
-- ForeverCrafts.lua), rebuilt when the recipe book changes.
---------------------------------------------------------------------------
local profIndex, profStamp
local function professions()
  local stamp = ns.recipeBookStamp or 0
  if profIndex and profStamp == stamp then return profIndex end
  local idx = { mats = {}, crafts = {}, names = {} }
  local function add(prof, out, mats)
    idx.names[prof] = true
    if out then
      idx.crafts[out] = idx.crafts[out] or {}
      idx.crafts[out][prof] = true
    end
    for _, m in ipairs(mats or {}) do
      if m[1] then
        idx.mats[m[1]] = idx.mats[m[1]] or {}
        idx.mats[m[1]][prof] = true
      end
    end
  end
  -- A recipe captured from the game replaces ForeverCrafts.lua's row for the same
  -- profession and recipe (as RecipeBook.lua's CraftsUsing does; Codex review,
  -- November 15: the old row's materials stayed in the group).
  local seen = {}
  for prof, book in pairs(ns.db.recipeBook or {}) do
    for rid, r in pairs(book) do
      seen[prof .. ":" .. tostring(rid)] = true
      add(prof, r.out, r.r)
    end
  end
  for _, c in ipairs(ns.FOREVER_CRAFTS or {}) do
    if not seen[c.prof .. ":" .. tostring(c.id)] then add(c.prof, c.out, c.r) end
  end
  profIndex, profStamp = idx, stamp
  return idx
end
function ns:ForgetProfessionGroups() profIndex = nil end

local function profGroupId(prof, which) return "prof:" .. prof .. ":" .. which end

---------------------------------------------------------------------------
-- Looking groups up
---------------------------------------------------------------------------
-- { id, name, kind, parent } for any group id, or nil.
function ns:GroupInfo(gid)
  if type(gid) ~= "string" then return end
  if byId[gid] then
    local b = byId[gid]
    return { id = gid, name = b.name, kind = "builtin", parent = b.parent }
  end
  local prof, which = gid:match("^prof:(.+):(%a+)$")
  if prof and (which == "mats" or which == "crafts") then
    return { id = gid, name = prof .. (which == "mats" and " materials" or " crafts"), kind = "profession", prof = prof }
  end
  if gid == "watched" then return { id = gid, name = "Watched", kind = "special" } end
  if gid == "gray" then return { id = gid, name = "Gray items", kind = "special" } end
  local u = store().user[gid]
  if u then return { id = gid, name = u.name, kind = "user", parent = u.parent } end
end

-- The groups to show, in order: the built-in tree (each with its children), the
-- special groups, the profession groups, then yours. Each { id, name, kind, depth }.
function ns:GroupTree()
  local out = {}
  local function walk(parent, depth)
    for _, gid in ipairs(children[parent] or {}) do
      out[#out + 1] = { id = gid, name = byId[gid].name, kind = "builtin", depth = depth }
      walk(gid, depth + 1)
    end
  end
  walk("root", 0)
  out[#out + 1] = { id = "watched", name = "Watched", kind = "special", depth = 0 }
  out[#out + 1] = { id = "gray", name = "Gray items", kind = "special", depth = 0 }
  local profs = {}
  for p in pairs(professions().names) do profs[#profs + 1] = p end
  table.sort(profs)
  for _, p in ipairs(profs) do
    out[#out + 1] = { id = profGroupId(p, "mats"), name = p .. " materials", kind = "profession", depth = 0 }
    out[#out + 1] = { id = profGroupId(p, "crafts"), name = p .. " crafts", kind = "profession", depth = 0 }
  end
  local g = store()
  local function walkUser(parent, depth)
    local ids = {}
    for gid, u in pairs(g.user) do if u.parent == parent then ids[#ids + 1] = gid end end
    table.sort(ids, function(a, b) return (g.user[a].name or ""):lower() < (g.user[b].name or ""):lower() end)
    for _, gid in ipairs(ids) do
      out[#out + 1] = { id = gid, name = g.user[gid].name, kind = "user", depth = depth }
      walkUser(gid, depth + 1)
    end
  end
  walkUser(nil, 0)
  return out
end

-- Every group an item is in, most specific first: yours (deepest first), the special
-- ones, profession groups, then built in (deepest first).
function ns:ItemGroups(id)
  if not id then return {} end
  local g = store()
  local out = {}
  local mine = {}
  for gid, u in pairs(g.user) do
    if u.items and u.items[id] then mine[#mine + 1] = gid end
  end
  local function depthOf(gid)
    local d, u = 0, g.user[gid]
    while u and u.parent and d < 20 do d = d + 1; u = g.user[u.parent] end
    return d
  end
  table.sort(mine, function(a, b)
    local da, dbb = depthOf(a), depthOf(b)
    if da ~= dbb then return da > dbb end
    return a < b
  end)
  for _, gid in ipairs(mine) do out[#out + 1] = gid end
  if ns.db.watchItems and ns.db.watchItems[id] then out[#out + 1] = "watched" end
  if quality(id) == 0 then out[#out + 1] = "gray" end
  local idx = professions()
  for _, which in ipairs({ "mats", "crafts" }) do
    local profs = {}
    for p in pairs(idx[which][id] or {}) do profs[#profs + 1] = p end
    table.sort(profs)
    for _, p in ipairs(profs) do out[#out + 1] = profGroupId(p, which) end
  end
  for _, gid in ipairs(builtinGroups(id)) do out[#out + 1] = gid end
  return out
end

-- True if the item is in the group or one of the groups under it (a user group
-- counts its own sub-groups' items too).
-- An item's groups and every group above them, as a set.
local function withParents(id)
  local set = {}
  for _, mine in ipairs(ns:ItemGroups(id)) do
    local cur, steps = mine, 0
    while cur and steps < 20 and not set[cur] do
      set[cur] = true
      local info = ns:GroupInfo(cur)
      cur, steps = info and info.parent, steps + 1
    end
  end
  return set
end

-- The same as a set { [gid] = true }, for lists that filter many items at once
-- (ScanOnce.lua works it out once per item per scan).
function ns:ItemGroupSet(id) return withParents(id) end

function ns:GroupHas(gid, id)
  if not gid or not id then return false end
  if gid == "all" then return true end
  return withParents(id)[gid] == true
end

-- Items from `ids` (a list) that are in any of the groups in `gids` (ticked groups add
-- together). An empty `gids` keeps everything. Used to filter a scan's rows.
function ns:GroupFilter(gids, ids)
  if not gids or #gids == 0 then return ids end
  local out = {}
  for _, id in ipairs(ids) do
    local set = withParents(id)
    for _, gid in ipairs(gids) do
      if gid == "all" or set[gid] then out[#out + 1] = id; break end
    end
  end
  return out
end

---------------------------------------------------------------------------
-- Changing groups
---------------------------------------------------------------------------
function ns:NewGroup(name, parent)
  if type(name) ~= "string" or name:match("^%s*$") then return end
  local g = store()
  if parent and not g.user[parent] then parent = nil end
  local gid = "u" .. g.nextId
  g.nextId = g.nextId + 1
  g.user[gid] = { name = name, parent = parent, items = {}, t = time() }
  return gid
end

-- Deletes one of your groups; its sub-groups move up to its parent; its rules go.
function ns:DeleteGroup(gid)
  local g = store()
  local u = g.user[gid]
  if not u then return false end
  for _, other in pairs(g.user) do
    if other.parent == gid then other.parent = u.parent end
  end
  g.user[gid], g.rules[gid] = nil, nil
  return true
end

function ns:RenameGroup(gid, name)
  local u = store().user[gid]
  if not u or type(name) ~= "string" or name:match("^%s*$") then return false end
  u.name = name
  return true
end

-- Adds an item to one of your groups, or puts it into a built-in group (undoing a
-- removal there first). Profession and special groups can't be changed by hand.
function ns:AddToGroup(gid, id)
  local g = store()
  if g.user[gid] then
    g.user[gid].items = g.user[gid].items or {}
    g.user[gid].items[id] = true
    return true
  end
  if not byId[gid] then return false end
  if g.removed[gid] and g.removed[gid][id] then
    g.removed[gid][id] = nil
    if not next(g.removed[gid]) then g.removed[gid] = nil end
  end
  if not ns:GroupHas(gid, id) then
    g.added[gid] = g.added[gid] or {}
    g.added[gid][id] = true
  end
  return true
end

function ns:RemoveFromGroup(gid, id)
  local g = store()
  if g.user[gid] then
    if g.user[gid].items then g.user[gid].items[id] = nil end
    return true
  end
  if not byId[gid] then return false end
  if g.added[gid] and g.added[gid][id] then
    g.added[gid][id] = nil
    if not next(g.added[gid]) then g.added[gid] = nil end
  else
    -- Nothing to take out: say so rather than record a removal that changes nothing.
    if not ns:GroupHas(gid, id) then return false end
    g.removed[gid] = g.removed[gid] or {}
    g.removed[gid][id] = true
  end
  return true
end

-- What restoring would undo, for the confirmation: items added, items taken out,
-- rules changed (one built-in group, or all of them when gid is nil).
function ns:BuiltinChanges(gid)
  local g = store()
  local added, removed, rules = 0, 0, 0
  for b in pairs(byId) do
    if not gid or gid == b then
      for _ in pairs(g.added[b] or {}) do added = added + 1 end
      for _ in pairs(g.removed[b] or {}) do removed = removed + 1 end
      for _, kind in ipairs(ns.RULE_KINDS) do
        if g.rules[b] and g.rules[b][kind] ~= nil and g.rules[b][kind] ~= "parent" then rules = rules + 1 end
      end
    end
  end
  return added, removed, rules
end

-- Puts one built-in group's items back as we made it (its rules stay).
function ns:RestoreGroupItems(gid)
  if not byId[gid] then return false end
  local g = store()
  g.added[gid], g.removed[gid] = nil, nil
  return true
end

-- Puts every built-in group back: items and rules. Your groups and saved rules stay.
function ns:RestoreBuiltinGroups()
  local g = store()
  for b in pairs(byId) do g.added[b], g.removed[b], g.rules[b] = nil, nil, nil end
  return true
end

---------------------------------------------------------------------------
-- Rules
---------------------------------------------------------------------------
local function copy(t)
  local c = {}
  for k, v in pairs(t or {}) do c[k] = v end
  return c
end

-- The default rule of one kind as it applies: RULE_DEFAULTS, with the post rule's undercut
-- from Settings (Selling, Post tab: a CurseForge player asked for always undercutting,
-- November 18). A group's own or saved rule keeps the undercut it was given.
local function defaults(kind)
  local f = copy(ns.RULE_DEFAULTS[kind])
  local s = ns.db and ns.db.settings
  if kind == "post" and s and type(s.postUndercut) == "number" and s.postUndercut > 0 then f.undercut = s.postUndercut end
  return f
end
function ns:RuleDefaults(kind) return defaults(kind) end

local function validKind(kind)
  for _, k in ipairs(ns.RULE_KINDS) do if k == kind then return true end end
  return false
end

-- Sets a group's rule of one kind: "parent", "default", "off", "rule:<id>" or a table
-- of fields (changed here). nil means "parent".
function ns:SetGroupRule(gid, kind, ref)
  if not validKind(kind) or not ns:GroupInfo(gid) then return false end
  if type(ref) == "string" and ref ~= "parent" and ref ~= "default" and ref ~= "off" then
    local rid = ref:match("^rule:(.+)$")
    local saved = rid and store().saved[rid]
    if not saved or saved.kind ~= kind then return false end
  elseif type(ref) == "table" then
    ref = copy(ref)
  elseif ref ~= nil and type(ref) ~= "string" then
    return false
  end
  local g = store()
  if ref == "parent" then ref = nil end
  g.rules[gid] = g.rules[gid] or {}
  g.rules[gid][kind] = ref
  if not next(g.rules[gid]) then g.rules[gid] = nil end
  return true
end

-- A group's own setting of one kind (nil = same as the group above).
function ns:GroupRuleSetting(gid, kind)
  local r = store().rules[gid]
  return r and r[kind]
end

-- Follows a group's chain upward. Returns fields (nil when off), how it was set
-- ("default", "off", "rule", "changed"), the group that set it, the saved rule's id,
-- and whether anything in the chain set it (false: nothing did, so the default).
local function resolve(gid, kind)
  local g = store()
  local cur, steps = gid, 0
  while cur and steps < 20 do
    local ref = g.rules[cur] and g.rules[cur][kind]
    if ref ~= nil then
      if ref == "default" then return defaults(kind), "default", cur, nil, true end
      if ref == "off" then return nil, "off", cur, nil, true end
      if type(ref) == "table" then
        local f = defaults(kind)
        for k, v in pairs(ref) do f[k] = v end
        return f, "changed", cur, nil, true
      end
      local rid = type(ref) == "string" and ref:match("^rule:(.+)$")
      local saved = rid and g.saved[rid]
      if saved then
        local f = defaults(kind)
        for k, v in pairs(saved.fields or {}) do f[k] = v end
        return f, "rule", cur, rid, true
      end
      -- A rule that's gone counts as "same as above".
    end
    local info = ns:GroupInfo(cur)
    cur, steps = info and info.parent, steps + 1
  end
  return defaults(kind), "default", nil, nil, false
end

-- A group's rule of one kind as it applies: fields (nil when off), how ("default",
-- "off", "rule", "changed"), the group that set it, and the saved rule's id.
function ns:GroupRule(gid, kind)
  if not validKind(kind) then return end
  local f, how, from, rid = resolve(gid, kind)
  return f, how, from, rid
end

local function describe(how, from, rid)
  local name = from and ns:GroupInfo(from) and ns:GroupInfo(from).name
  if how == "default" and not from then return "Default" end
  if how == "rule" then
    local saved = store().saved[rid]
    return ("Your rule %s (%s)"):format(saved and saved.name or "?", name or "?")
  end
  if how == "changed" then return ("%s, changed here"):format(name or "?") end
  if how == "off" then return ("Off (%s)"):format(name or "?") end
  return ("Default (%s)"):format(name or "?")
end

-- The rule of one kind for an item: fields (nil when off), where it came from in words
-- ("Cloth, changed here", "Your rule Cheap mats (Herbs)", "Default"), and that group.
function ns:RuleFor(id, kind)
  if not validKind(kind) then return end
  for _, gid in ipairs(ns:ItemGroups(id)) do
    local f, how, from, rid, set = resolve(gid, kind)
    if set then return f, describe(how, from, rid), from end
  end
  return defaults(kind), "Default", nil
end

-- Saved rules: your own, shared by any groups that pick them.
function ns:SaveRule(name, kind, fields)
  if not validKind(kind) or type(name) ~= "string" or name:match("^%s*$") then return end
  local g = store()
  local rid = tostring(g.nextId)
  g.nextId = g.nextId + 1
  g.saved[rid] = { name = name, kind = kind, fields = copy(fields), t = time() }
  return rid
end

function ns:UpdateRule(rid, fields)
  local saved = store().saved[rid]
  if not saved then return false end
  saved.fields = copy(fields)
  return true
end

-- Groups using a saved rule (for "Used by 3 groups" and the delete confirmation).
function ns:RuleUsers(rid)
  local out = {}
  for gid, r in pairs(store().rules) do
    for _, kind in ipairs(ns.RULE_KINDS) do
      if r[kind] == "rule:" .. rid then out[#out + 1] = gid; break end
    end
  end
  table.sort(out)
  return out
end

-- Deletes a saved rule; the groups that used it go back to "same as the group above".
function ns:DeleteRule(rid)
  local g = store()
  if not g.saved[rid] then return false end
  for gid, r in pairs(g.rules) do
    for _, kind in ipairs(ns.RULE_KINDS) do
      if r[kind] == "rule:" .. rid then r[kind] = nil end
    end
    if not next(r) then g.rules[gid] = nil end
  end
  g.saved[rid] = nil
  return true
end
