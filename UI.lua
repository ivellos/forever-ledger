local _, ns = ...

local KEY_ITEMS = {
  { 2589, "Linen Cloth" }, { 2592, "Wool Cloth" }, { 10940, "Strange Dust" },
  { 10938, "Lesser Magic Essence" }, { 10939, "Greater Magic Essence" },
  { 10998, "Lesser Astral Essence" }, { 11082, "Greater Astral Essence" }, { 10978, "Small Glimmering Shard" },
}

local function makeWindow(name, w, h, titleText)
  local ok, f = pcall(CreateFrame, "Frame", name, UIParent, "BasicFrameTemplateWithInset")
  if not ok or not f then
    f = CreateFrame("Frame", name, UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    if f.SetBackdrop then
      f:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background", edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", edgeSize = 24, insets = { left = 6, right = 6, top = 6, bottom = 6 } })
    end
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -2, -2)
  end
  f:SetSize(w, h)
  f:SetPoint("CENTER")
  f:SetFrameStrata("DIALOG")
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  f:SetClampedToScreen(true)
  f:Hide()
  tinsert(UISpecialFrames, name)
  f.title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  if f.TitleBg then f.title:SetPoint("LEFT", f.TitleBg, "LEFT", 6, 0) else f.title:SetPoint("TOP", 0, -12) end
  f.title:SetText(titleText)
  return f
end

local function button(parent, label, width, onClick)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetSize(width, 24)
  b:SetText(label)
  b:SetScript("OnClick", onClick)
  return b
end

---------------------------------------------------------------------------
-- Main window
---------------------------------------------------------------------------
local main
local function buildMain()
  if main then return main end
  main = makeWindow("ForeverLedgerFrame", 540, 470, "Forever Ledger " .. ns.VERSION)

  local sf = CreateFrame("ScrollFrame", nil, main, "UIPanelScrollFrameTemplate")
  sf:SetPoint("TOPLEFT", 14, -32)
  sf:SetPoint("BOTTOMRIGHT", -32, 66)
  local content = CreateFrame("Frame", nil, sf)
  content:SetSize(480, 10)
  sf:SetScrollChild(content)
  local text = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  text:SetPoint("TOPLEFT")
  text:SetWidth(480)
  text:SetJustifyH("LEFT")
  text:SetJustifyV("TOP")
  text:SetSpacing(3)
  main.text, main.content = text, content

  main.status = main:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  main.status:SetPoint("BOTTOMLEFT", 16, 44)
  main.status:SetText("")

  local scan = button(main, "Scan auction house", 150, function() ns.Scan:Start("watch") end)
  scan:SetPoint("BOTTOMLEFT", 14, 14)
  local exp = button(main, "Export", 90, function() ns:ShowExport() end)
  exp:SetPoint("LEFT", scan, "RIGHT", 6, 0)
  local imp = button(main, "Import", 90, function() ns:ShowImport() end)
  imp:SetPoint("LEFT", exp, "RIGHT", 6, 0)
  local csv = button(main, "Prices as text", 120, function() ns:ShowPricesCSV() end)
  csv:SetPoint("LEFT", imp, "RIGHT", 6, 0)
  main.scanBtn = scan
  return main
end

function ns:ToggleUI()
  local f = buildMain()
  if f:IsShown() then f:Hide() else ns:ScanSkillLines(); f:Show(); ns:RefreshUI() end
end

local CLASS_COLORS = RAID_CLASS_COLORS or {}

function ns:RefreshUI()
  if not main or not main:IsShown() or not ns.db then return end
  local L = {}
  local function add(s) L[#L + 1] = s or "" end

  add("|cffb9a2ffYour characters|r")
  local keys = {}
  for k in pairs(ns.db.chars) do keys[#keys + 1] = k end
  table.sort(keys)
  if #keys == 0 then add("  None yet. Log in on each character once.") end
  for _, k in ipairs(keys) do
    local c = ns.db.chars[k]
    local cc = CLASS_COLORS[c.class or ""]
    local nameStr = cc and ("|c" .. (cc.colorStr or "ffffffff") .. (c.name or "?") .. "|r") or (c.name or "?")
    add(("  %s, level %s %s"):format(nameStr, c.level or "?", c.faction or ""))
    local profNames = {}
    for p in pairs(c.profs or {}) do profNames[#profNames + 1] = p end
    table.sort(profNames)
    if #profNames == 0 then add("      No professions saved yet.") end
    for _, p in ipairs(profNames) do
      local info = c.profs[p]
      local n = info.recipeCount or 0
      local recipes = n > 0 and (n .. " recipes saved") or "|cffee8597open this profession's window to save its recipes|r"
      add(("      %s %s/%s, %s"):format(p, info.rank or "?", info.max or "?", recipes))
    end
  end

  add("")
  add("|cffb9a2ffKey prices|r  |cff999999(" .. ns.MarketKey() .. ")|r")
  for _, item in ipairs(KEY_ITEMS) do
    local price, src, t = ns:GetPrice(item[1])
    if price then
      add(("  %s: %s |cff999999%s %s|r"):format(item[2], ns.Money(price), src or "", t and ns.Age(t) or ""))
    else
      add(("  %s: |cff999999no price yet|r"):format(item[2]))
    end
  end

  add("")
  add("|cffb9a2ffPrice data|r")
  local market = ns.db.prices[ns.MarketKey()] or {}
  local count, newest, oldest = 0, 0, nil
  for _, rec in pairs(market) do
    count = count + 1
    if rec.t then
      newest = math.max(newest, rec.t)
      oldest = oldest and math.min(oldest, rec.t) or rec.t
    end
  end
  add(("  %d items priced. Newest %s, oldest %s."):format(count, newest > 0 and ns.Age(newest) or "never", oldest and ns.Age(oldest) or "never"))
  local ext = ns:ExternalSources()
  add("  Other auction addons: " .. (#ext > 0 and table.concat(ext, ", ") or "none found"))
  add("  Price source: " .. ns.db.settings.source .. " (change with /fl source)")
  local vb = 0
  for _ in pairs(ns.db.vendorBuy) do vb = vb + 1 end
  add(("  %d vendor prices saved. Open any vendor to add theirs."):format(vb))

  add("")
  add("|cff999999Scan while the auction house is open. Hover any item to see its ledger price. Type /fl help for commands.|r")

  main.text:SetText(table.concat(L, "\n"))
  main.content:SetHeight(main.text:GetStringHeight() + 10)
  main.scanBtn:SetEnabled(ns:IsAHOpen())
end

function ns:UpdateScanStatus(done, total)
  if main and main.status then
    main.status:SetText(total and total > 0 and ("Scanning: %d of %d"):format(done, total) or "")
    if done and total and done >= total then
      C_Timer.After(3, function() if main then main.status:SetText("") end end)
    end
  end
end

-- A scan button on the auction house window itself.
function ns:OnAHShow()
  local ah = AuctionHouseFrame or AuctionFrame
  if ah and not ns.ahButton then
    ns.ahButton = button(ah, "Ledger scan", 110, function() ns.Scan:Start("watch") end)
    ns.ahButton:SetPoint("TOPRIGHT", ah, "TOPRIGHT", -30, -28)
  end
  ns:RefreshUI()
end

---------------------------------------------------------------------------
-- Text window for export, import and CSV
---------------------------------------------------------------------------
local io
local function ioWindow()
  if io then return io end
  io = makeWindow("ForeverLedgerIO", 560, 380, "Forever Ledger")
  io.help = io:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  io.help:SetPoint("TOPLEFT", 16, -32)
  io.help:SetWidth(520)
  io.help:SetJustifyH("LEFT")

  local sf = CreateFrame("ScrollFrame", nil, io, "UIPanelScrollFrameTemplate")
  sf:SetPoint("TOPLEFT", 16, -64)
  sf:SetPoint("BOTTOMRIGHT", -34, 48)
  local eb = CreateFrame("EditBox", nil, sf)
  eb:SetMultiLine(true)
  eb:SetFontObject(ChatFontNormal)
  eb:SetWidth(500)
  eb:SetAutoFocus(false)
  eb:SetMaxLetters(0)
  eb:SetScript("OnEscapePressed", function() io:Hide() end)
  sf:SetScrollChild(eb)
  io.eb = eb

  io.action = button(io, "Import", 110, function() end)
  io.action:SetPoint("BOTTOMRIGHT", -16, 14)
  return io
end

function ns:ShowExport()
  local f = ioWindow()
  f.title:SetText("Export")
  f.help:SetText("Press Ctrl+A, then Ctrl+C to copy. Paste it into Import on your other account, or send it to Claude.")
  f.eb:SetText(ns:Export())
  f.action:Hide()
  f:Show()
  f.eb:SetFocus()
  f.eb:HighlightText()
end

function ns:ShowImport()
  local f = ioWindow()
  f.title:SetText("Import")
  f.help:SetText("Paste an export from your other account with Ctrl+V, then click Import. Newer data replaces older data.")
  f.eb:SetText("")
  f.action:SetText("Import")
  f.action:SetScript("OnClick", function()
    local ok, msg = ns:Import(f.eb:GetText())
    ns:Print(msg)
    if ok then f:Hide(); ns:RefreshUI() end
  end)
  f.action:Show()
  f:Show()
  f.eb:SetFocus()
end

-- Readable price list for the web calculator or a chat with Claude.
function ns:PricesCSV()
  local rows = { "item_id,name,price_copper,cheapest_copper,listed,source,age_minutes,vendor_pays_copper,vendor_charges_copper" }
  local market = ns.db.prices[ns.MarketKey()] or {}
  local ids, seen = {}, {}
  for id in pairs(market) do if not seen[id] then seen[id] = true; ids[#ids + 1] = id end end
  for _, id in ipairs(ns:WatchList()) do if not seen[id] then seen[id] = true; ids[#ids + 1] = id end end
  table.sort(ids)
  for _, id in ipairs(ids) do
    local rec = market[id]
    local name = ns.GetItemInfo(id) or ("item " .. id)
    local sell = ns:GetSellPrice(id)
    local buy = ns.db.vendorBuy[id]
    if rec or buy then
      rows[#rows + 1] = table.concat({
        id, (name:gsub(",", "")),
        rec and rec.a or "", rec and rec.m or "", rec and rec.q or "",
        rec and rec.src or "", rec and rec.t and math.floor((time() - rec.t) / 60) or "",
        sell or "", buy and buy.p or "",
      }, ",")
    end
  end
  return table.concat(rows, "\n")
end

function ns:ShowPricesCSV()
  local f = ioWindow()
  f.title:SetText("Prices as text")
  f.help:SetText("Press Ctrl+A, then Ctrl+C. Paste this into a chat with Claude to check flips at today's prices.")
  f.eb:SetText(ns:PricesCSV())
  f.action:Hide()
  f:Show()
  f.eb:SetFocus()
  f.eb:HighlightText()
end
