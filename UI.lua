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
-- Main window: an Overview tab and a Shuffles tab
---------------------------------------------------------------------------
local main
local setView, layoutShuffles

local function scrollArea(bottom)
  local sf = CreateFrame("ScrollFrame", nil, main, "UIPanelScrollFrameTemplate")
  sf:SetPoint("TOPLEFT", 14, -58)
  sf:SetPoint("BOTTOMRIGHT", -32, bottom)
  local content = CreateFrame("Frame", nil, sf)
  content:SetSize(480, 10)
  sf:SetScrollChild(content)
  return sf, content
end

local function buildMain()
  if main then return main end
  main = makeWindow("ForeverLedgerFrame", 540, 470, "Forever Ledger " .. ns.VERSION)

  main.tabOverview = button(main, "Overview", 100, function() setView("overview") end)
  main.tabOverview:SetPoint("TOPLEFT", 14, -28)
  main.tabShuffles = button(main, "Shuffles", 100, function() setView("shuffles") end)
  main.tabShuffles:SetPoint("LEFT", main.tabOverview, "RIGHT", 4, 0)
  main.tabFlips = button(main, "Vendor flips", 110, function() setView("flips") end)
  main.tabFlips:SetPoint("LEFT", main.tabShuffles, "RIGHT", 4, 0)

  -- Overview
  local sf, content = scrollArea(66)
  local text = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  text:SetPoint("TOPLEFT")
  text:SetWidth(480)
  text:SetJustifyH("LEFT")
  text:SetJustifyV("TOP")
  text:SetSpacing(3)
  main.sf, main.text, main.content = sf, text, content

  main.status = main:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  main.status:SetPoint("BOTTOMLEFT", 16, 44)
  main.status:SetText("")

  local full = button(main, "Full scan", 130, function() ns.Scan:Start("full") end)
  full:SetPoint("BOTTOMLEFT", 14, 14)
  local scan = button(main, "Scan materials", 120, function() ns.Scan:Start("watch") end)
  scan:SetPoint("LEFT", full, "RIGHT", 6, 0)
  local exp = button(main, "Export", 65, function() ns:ShowExport() end)
  exp:SetPoint("LEFT", scan, "RIGHT", 6, 0)
  local imp = button(main, "Import", 65, function() ns:ShowImport() end)
  imp:SetPoint("LEFT", exp, "RIGHT", 6, 0)
  local csv = button(main, "Prices as text", 100, function() ns:ShowPricesCSV() end)
  csv:SetPoint("LEFT", imp, "RIGHT", 6, 0)
  main.scanBtn, main.fullBtn = scan, full
  main.overviewButtons = { full, scan, exp, imp, csv }

  -- Shuffles
  main.shuffleSF, main.shuffleContent = scrollArea(62)
  main.refreshBtn = button(main, "Refresh", 90, function() ns:RefreshShuffles() end)
  main.refreshBtn:SetPoint("BOTTOMLEFT", 14, 14)
  main.shuffleInfo = main:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  main.shuffleInfo:SetPoint("LEFT", main.refreshBtn, "RIGHT", 10, 0)
  main.shuffleInfo:SetPoint("RIGHT", main, "RIGHT", -16, 0)
  main.shuffleInfo:SetJustifyH("LEFT")

  setView("overview")
  return main
end

setView = function(view)
  main.view = view
  local overview = view == "overview"
  main.sf:SetShown(overview)
  for _, b in ipairs(main.overviewButtons) do b:SetShown(overview) end
  main.shuffleSF:SetShown(not overview)
  main.refreshBtn:SetShown(not overview)
  main.shuffleInfo:SetShown(not overview)
  -- The tab you're on stays highlighted.
  for tab, name in pairs({ [main.tabOverview] = "overview", [main.tabShuffles] = "shuffles", [main.tabFlips] = "flips" }) do
    if name == view then tab:LockHighlight() else tab:UnlockHighlight() end
  end
  if overview then
    ns:RefreshUI()
  elseif main.shuffles then
    layoutShuffles()
  else
    ns:RefreshShuffles()
  end
end

function ns:ToggleUI()
  local f = buildMain()
  if f:IsShown() then f:Hide() else ns:ScanSkillLines(); f:Show(); ns:RefreshUI() end
end

---------------------------------------------------------------------------
-- Minimap button: click to open the ledger, right-click for shuffles, drag to move
---------------------------------------------------------------------------
local mm

local function placeMinimapButton()
  local a = math.rad(ns.db.settings.minimapAngle or 200)
  local r = Minimap:GetWidth() / 2 + 5
  mm:ClearAllPoints()
  mm:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * r, math.sin(a) * r)
end

local function buildMinimapButton()
  if mm or not Minimap then return end
  mm = CreateFrame("Button", "ForeverLedgerMinimapButton", Minimap)
  mm:SetSize(31, 31)
  mm:SetFrameStrata("MEDIUM")
  mm:SetFrameLevel(Minimap:GetFrameLevel() + 8)
  mm:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  mm:RegisterForDrag("LeftButton")
  mm:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

  local bg = mm:CreateTexture(nil, "BACKGROUND")
  bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
  bg:SetSize(20, 20)
  bg:SetPoint("TOPLEFT", 7, -5)
  local icon = mm:CreateTexture(nil, "ARTWORK")
  icon:SetTexture("Interface\\Icons\\INV_Misc_Coin_01")
  icon:SetSize(17, 17)
  icon:SetPoint("TOPLEFT", 7, -6)
  local border = mm:CreateTexture(nil, "OVERLAY")
  border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
  border:SetSize(53, 53)
  border:SetPoint("TOPLEFT")

  mm:SetScript("OnClick", function(_, which)
    if which == "RightButton" then
      local f = buildMain()
      if not f:IsShown() then ns:ScanSkillLines(); f:Show() end
      setView("shuffles")
    else
      ns:ToggleUI()
    end
  end)
  mm:SetScript("OnDragStart", function(self)
    self:SetScript("OnUpdate", function()
      local mx, my = Minimap:GetCenter()
      local px, py = GetCursorPosition()
      local scale = Minimap:GetEffectiveScale()
      ns.db.settings.minimapAngle = math.deg(math.atan2(py / scale - my, px / scale - mx))
      placeMinimapButton()
    end)
  end)
  mm:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
  mm:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine("Forever Ledger")
    GameTooltip:AddLine("Click to open or close.", 1, 1, 1)
    GameTooltip:AddLine("Right-click for shuffles.", 1, 1, 1)
    GameTooltip:AddLine("Drag to move. /fl minimap hides it.", 0.7, 0.7, 0.7)
    GameTooltip:Show()
  end)
  mm:SetScript("OnLeave", function() GameTooltip:Hide() end)
  placeMinimapButton()
end

function ns:UpdateMinimapButton()
  if ns.db.settings.minimap then
    buildMinimapButton()
    if mm then mm:Show() end
  elseif mm then
    mm:Hide()
  end
end
ns:OnReady(function() ns:UpdateMinimapButton() end)

---------------------------------------------------------------------------
-- Shuffles tab: a list of rows; click one to show its steps underneath
---------------------------------------------------------------------------
local MAX_ROWS = 25       -- per section
local rows, details, openKeys = {}, {}, {}

local function getRow(i)
  local r = rows[i]
  if not r then
    r = CreateFrame("Button", nil, main.shuffleContent)
    r:SetHeight(18)
    r:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    r.right = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.right:SetPoint("RIGHT", -2, 0)
    r.right:SetJustifyH("RIGHT")
    r.left = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.left:SetPoint("LEFT", 2, 0)
    r.left:SetPoint("RIGHT", r.right, "LEFT", -8, 0)
    r.left:SetJustifyH("LEFT")
    r.left:SetWordWrap(false)
    r:SetScript("OnClick", function(self)
      if self.shuffle then
        openKeys[self.shuffle.key] = not openKeys[self.shuffle.key]
        layoutShuffles()
      end
    end)
    rows[i] = r
  end
  return r
end

local function getDetail(i)
  local fs = details[i]
  if not fs then
    fs = main.shuffleContent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetWidth(456)
    fs:SetJustifyH("LEFT")
    fs:SetJustifyV("TOP")
    fs:SetSpacing(2)
    details[i] = fs
  end
  return fs
end

-- "Use recipes from" checkboxes, one per character.
local boxes = {}
local function getBox(i)
  local cb = boxes[i]
  if not cb then
    cb = CreateFrame("CheckButton", nil, main.shuffleContent, "UICheckButtonTemplate")
    cb:SetSize(22, 22)
    cb.label = cb.Text or cb.text or cb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    cb.label:ClearAllPoints()
    cb.label:SetPoint("LEFT", cb, "RIGHT", 1, 0)
    cb:SetScript("OnClick", function(self)
      ns.db.settings.skipChars[self.charKey] = (not self:GetChecked()) or nil
      ns:InvalidateValues(true)
      ns:RefreshShuffles()
    end)
    boxes[i] = cb
  end
  return cb
end

-- Returns the height used.
local function layoutCharBoxes(content)
  if not main.charLabel then
    main.charLabel = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    main.charLabel:SetText("Use recipes from:")
  end
  main.charLabel:ClearAllPoints()
  main.charLabel:SetPoint("TOPLEFT", content, "TOPLEFT", 2, -5)

  local keys = {}
  for k in pairs(ns.db.chars) do keys[#keys + 1] = k end
  table.sort(keys)
  local x, y = main.charLabel:GetStringWidth() + 10, 0
  for i, key in ipairs(keys) do
    local c, cb = ns.db.chars[key], getBox(i)
    local cc = CLASS_COLORS[c.class or ""]
    cb.label:SetText(cc and ("|c" .. (cc.colorStr or "ffffffff") .. (c.name or "?") .. "|r") or (c.name or "?"))
    local width = 22 + cb.label:GetStringWidth() + 14
    if x + width > 470 then x, y = 0, y + 24 end
    cb:ClearAllPoints()
    cb:SetPoint("TOPLEFT", content, "TOPLEFT", x, -y)
    cb:SetChecked(not ns.db.settings.skipChars[key])
    cb.charKey = key
    cb:Show()
    x = x + width
  end
  for i = #keys + 1, #boxes do boxes[i]:Hide() end
  return y + 30
end

layoutShuffles = function()
  local content, data = main.shuffleContent, main.shuffles
  local flipsView = main.view == "flips"
  local y, nRows, nDetails = 0, 0, 0
  -- Recipes don't matter for vendor flips, so only the Shuffles tab has the checkboxes.
  if flipsView then
    if main.charLabel then main.charLabel:Hide() end
    for _, cb in ipairs(boxes) do cb:Hide() end
  else
    y = layoutCharBoxes(content)
    main.charLabel:Show()
  end

  local function row(left, right, s)
    nRows = nRows + 1
    local r = getRow(nRows)
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
    r:SetWidth(476)
    r.left:SetText(left)
    r.right:SetText(right or "")
    r.shuffle = s
    r:SetEnabled(s ~= nil)
    r:Show()
    y = y + 18
  end

  local function detail(text)
    nDetails = nDetails + 1
    local fs = getDetail(nDetails)
    fs:ClearAllPoints()
    fs:SetPoint("TOPLEFT", content, "TOPLEFT", 16, -y)
    fs:SetText(text)
    fs:Show()
    y = y + fs:GetStringHeight() + 8
  end

  local function section(title, list)
    row("|cffb9a2ff" .. title .. "|r")
    if #list == 0 then row("|cff999999  None at current prices.|r") end
    for i = 1, math.min(#list, MAX_ROWS) do
      local s = list[i]
      local open = openKeys[s.key]
      row((open and "|cff999999-|r " or "|cff999999+|r ") .. ns:ShuffleTitle(s), ns:ShuffleSummary(s), s)
      if open then detail(ns:ShuffleDetails(s)) end
    end
    y = y + 10
  end

  if flipsView then
    section("Buy on the auction house, sell straight to a vendor", data.flips)
  else
    section("Sells to a vendor (safe)", data.vendor)
    section("Sells on the auction house (depends on buyers)", data.ah)
    if #data.oneOff > 0 then section("One-off deals (fewer than 5 listed)", data.oneOff) end
  end

  for i = nRows + 1, #rows do rows[i]:Hide() end
  for i = nDetails + 1, #details do details[i]:Hide() end
  content:SetHeight(math.max(y, 10))
end

-- Item names arrive from the game a moment after they're first asked for.
-- Redraw the list once they do, so "item 4470" becomes "Simple Wood".
local redrawQueued = false
ns:On("GET_ITEM_INFO_RECEIVED", function()
  if redrawQueued or not main or not main:IsShown() or main.view ~= "shuffles" or not main.shuffles then return end
  redrawQueued = true
  C_Timer.After(0.5, function()
    redrawQueued = false
    if main:IsShown() and main.view == "shuffles" then layoutShuffles() end
  end)
end)

function ns:RefreshShuffles()
  if not main then return end
  local vendor, ah, oneOff, flips = ns:FindShuffles()
  main.shuffles = { vendor = vendor, ah = ah, oneOff = oneOff, flips = flips }
  main.shuffleInfo:SetText(("%d shuffles and %d vendor flips, worked out at %s. Click a row for details."):format(
    #vendor + #ah + #oneOff, #flips, date("%H:%M")))
  layoutShuffles()
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
  ns:UpdateFullScanButtons()
end

-- "Full scan: Ready", or a countdown until Blizzard allows the next one.
function ns:UpdateFullScanButtons()
  if not ns.db then return end
  local wait = ns.Scan:FullWait()
  local label, ready = "Full scan", false
  if wait == 0 then
    label, ready = "Full scan: Ready", true
  elseif wait < math.huge then
    label = ("Full scan: %d:%02d"):format(math.floor(wait / 60), wait % 60)
  end
  for _, b in ipairs({ main and main.fullBtn or false, ns.ahFullButton or false }) do
    if b then
      b:SetText(label)
      b:SetEnabled(ready and ns:IsAHOpen() and not ns.Scan.active)
    end
  end
end

-- Tick the countdown once a second while a button showing it is on screen.
ns:OnReady(function()
  C_Timer.NewTicker(1, function()
    if (main and main:IsShown()) or (ns.ahFullButton and ns.ahFullButton:IsVisible()) then
      ns:UpdateFullScanButtons()
    end
  end)
end)

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
    ns.ahButton = button(ah, "Scan materials", 120, function() ns.Scan:Start("watch") end)
    ns.ahButton:SetPoint("TOPRIGHT", ah, "TOPRIGHT", -30, -28)
    ns.ahFullButton = button(ah, "Full scan", 130, function() ns.Scan:Start("full") end)
    ns.ahFullButton:SetPoint("RIGHT", ns.ahButton, "LEFT", -4, 0)
  end
  ns:UpdateFullScanButtons()
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
