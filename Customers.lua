local _, ns = ...

---------------------------------------------------------------------------
-- Customer finder: watches chat for players asking for something your current
-- character can do ("LF enchanter to enchant wrists", "anyone tailoring bags?",
-- "WTB [item you can craft]", and for Mages "LF water / portal") and tells you, with a
-- clickable name to whisper them. It only reads chat; you do the talking.
---------------------------------------------------------------------------
local THROTTLE = 180        -- seconds before the same player can alert again
local LOG_SIZE = 50

-- Words that name each profession in a request (lowercase, matched on word edges).
local WORDS = {
  Enchanting = { "enchanter", "enchanters", "enchanting", "enchant", "enchants", "ench" },
  Tailoring = { "tailor", "tailors", "tailoring" },
  Alchemy = { "alchemist", "alchemists", "alchemy", "alch" },
  Blacksmithing = { "blacksmith", "blacksmiths", "blacksmithing", "bs" },
  Leatherworking = { "leatherworker", "leatherworkers", "leatherworking", "lw" },
  Engineering = { "engineer", "engineers", "engineering", "engi" },
  Cooking = { "cook", "cooking" },
}
-- Someone looking for help, not offering it.
local ASKING = { "lf", "lfm", "looking for", "need", "needs", "anyone", "any", "wtb", "can someone", "who can",
  "somebody", "someone" }
-- Crafters advertising: skip these.
local OFFERING = { "lfw", "wts", "selling", "can make", "can craft", "offering", "my services", "have all" }
-- Mage services, for Mages.
local MAGE = { "water", "portal", "port", "food", "mage table" }

local lastAlert = {}

-- True if `text` contains `word` as a whole word (or phrase).
local function has(text, word)
  return (" " .. text .. " "):find("[^%w]" .. word:gsub("(%W)", "%%%1") .. "[^%w]") ~= nil
end
local function any(text, list)
  for _, w in ipairs(list) do if has(text, w) then return w end end
end

-- What the current character can offer: professions, and items its recipes make.
local function offers()
  local c = ns.db.chars[ns.CharKey()]
  local profs, items = {}, {}
  for prof, p in pairs(c and c.profs or {}) do
    profs[prof] = true
    for _, rec in pairs(p.recipes or {}) do
      if rec.out then items[rec.out] = prof end
    end
  end
  return profs, items
end

-- Returns what the message asks for (e.g. "Enchanting", "Mage services") or nil.
local function wanted(msg)
  local text = msg:lower():gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
  if any(text, OFFERING) then return end
  local profs, items = offers()
  -- "WTB [Item]" for something you can craft.
  if has(text, "wtb") or any(text, ASKING) then
    for id in msg:gmatch("item:(%d+)") do
      local prof = items[tonumber(id)]
      if prof then return prof .. ": " .. (ns.ItemName(tonumber(id)) or "an item you craft") end
    end
  end
  if not any(text, ASKING) then return end
  for prof in pairs(profs) do
    if WORDS[prof] and any(text, WORDS[prof]) then return prof end
  end
  local _, class = UnitClass("player")
  if class == "MAGE" and any(text, MAGE) then return "Mage services" end
end

local function onChat(msg, sender, channel)
  local s = ns.db and ns.db.settings
  if not (s and s.customers) or not msg or not sender then return end
  local me = GetUnitName and GetUnitName("player", true)
  if sender == me or sender == UnitName("player") then return end
  local what = wanted(msg)
  if not what then return end
  if lastAlert[sender] and GetTime() - lastAlert[sender] < THROTTLE then return end
  lastAlert[sender] = GetTime()
  local where = channel and channel ~= "" and channel:match("^(%S+)") or "chat"
  ns:Print(("Customer? |Hplayer:%s|h[%s]|h (%s, %s): %s"):format(sender, sender, where, what, msg))
  if s.customerSound and PlaySound and SOUNDKIT and SOUNDKIT.TELL_MESSAGE then PlaySound(SOUNDKIT.TELL_MESSAGE) end
  local log = ns.db.customers or {}
  ns.db.customers = log
  log[#log + 1] = { t = time(), who = sender, what = what, msg = msg, c = ns.CharKey() }
  while #log > LOG_SIZE do table.remove(log, 1) end
end

-- The 9th value is the channel's plain name ("Trade", "Services").
ns:On("CHAT_MSG_CHANNEL", function(msg, sender, _, channelName, _, _, _, _, baseName)
  onChat(msg, sender, baseName or channelName)
end)
ns:On("CHAT_MSG_SAY", function(msg, sender) onChat(msg, sender, "Say") end)
ns:On("CHAT_MSG_YELL", function(msg, sender) onChat(msg, sender, "Yell") end)

-- For testing: /fl customer <message> runs a message through the finder.
function ns:TestCustomer(msg)
  local what = wanted(msg or "")
  ns:Print(what and ("That would alert: " .. what) or "That wouldn't alert (not a request for something this character does).")
end
