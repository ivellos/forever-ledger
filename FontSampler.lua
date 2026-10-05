local _, ns = ...
local T = ns.Theme

---------------------------------------------------------------------------
-- /fl fonts: the same sample line in every font the game client might have, plain and
-- thickened, so the owner can pick fuller fonts for FL Default and FL Gilded (owner,
-- October 4: Arial Narrow and Friz looked thin; WoW has no bold setting, so it's the
-- font file or a trick). "missing" when the client doesn't have that file.
---------------------------------------------------------------------------
local FONTS = {
  { "Fonts\\FRIZQT__.TTF", "Friz Quadrata (WoW's own)" },
  { "Fonts\\ARIALN.TTF", "Arial Narrow" },
  { "Fonts\\2002.TTF", "2002 (Korean UI)" },
  { "Fonts\\2002B.TTF", "2002 Bold (Korean UI, bold)" },
  { "Fonts\\ARHei.TTF", "AR Hei (Chinese UI)" },
  { "Fonts\\bHEI01B.TTF", "Hei 01 Bold (Chinese, bold)" },
  { "Fonts\\bHEI00M.TTF", "Hei 00 (Chinese)" },
  { "Fonts\\bKAI00M.TTF", "Kai (Chinese)" },
  { "Fonts\\bLEI00D.TTF", "Lei (Chinese)" },
  { "Fonts\\ARKai_T.TTF", "AR Kai T" },
  { "Fonts\\K_Pagetext.TTF", "K Pagetext (book text)" },
  { "Fonts\\NIM_____.ttf", "Nimrod (zone text)" },
  { "Fonts\\MORPHEUS.TTF", "Morpheus" },
  { "Fonts\\skurri.ttf", "Skurri" },
}
local SAMPLE = "Price helper on the Sell tab   Gold making   1g 50s   Auction house"

local win
local function build()
  win = ns.ThemedWindow("ForeverLedgerFonts", 760, 560, T:TitleCode() .. "Fonts|r")
  local note = T:Text(win, 11, T.dim)
  note:SetPoint("TOPLEFT", 14, -40)
  note:SetPoint("RIGHT", win, "RIGHT", -14, 0)
  note:SetJustifyH("LEFT")
  note:SetText("Each font plain (left of the line) and thickened (under it, a copy one pixel to the right). Tell Claude the numbers you like for FL Default and FL Gilded.")
  local y = 66
  for i, f in ipairs(FONTS) do
    local name = T:Text(win, 11)
    name:SetPoint("TOPLEFT", 14, -y)
    name:SetWidth(200)
    name:SetJustifyH("LEFT")
    local plain = win:CreateFontString(nil, "OVERLAY")
    plain:SetPoint("TOPLEFT", 220, -y)
    plain:SetFont(f[1], 13, "")
    if plain:GetFont() then   -- (no font set: the client doesn't have the file)
      plain:SetTextColor(1, 1, 1, 1)
      plain:SetShadowColor(0, 0, 0, 0.8)
      plain:SetShadowOffset(1, -1)
      plain:SetText(SAMPLE)
      local thick = win:CreateFontString(nil, "OVERLAY")
      thick:SetPoint("TOPLEFT", 220, -(y + 16))
      thick:SetFont(f[1], 13, "")
      thick:SetTextColor(1, 1, 1, 1)
      thick:SetShadowColor(1, 1, 1, 0.6)   -- the trick: a light copy one pixel to the right
      thick:SetShadowOffset(1, 0)
      thick:SetText(SAMPLE)
      name:SetText(("%d. %s"):format(i, f[2]))
    else
      name:SetText(("%d. %s |cffee8597missing|r"):format(i, f[2]))
    end
    y = y + 34
  end
  win:SetHeight(y + 16)
end

function ns:ShowFonts()
  if not win then build() end
  win:Show()
end
