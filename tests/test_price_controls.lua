local T = ...
local ns, S = T.ns, T.S
T.test("Typing the same automatic price marks it as yours; Escape cancels", function()
  local realFrame, realTip, realTheme = CreateFrame, GameTooltip, ns.Theme
  local function widget()
    local o = S.dummy()
    local oldIndex = getmetatable(o).__index
    setmetatable(o, { __index = function(self, key)
      if key:match("^[a-z]") then return nil end
      return oldIndex(self, key)
    end })
    o.SetText = function(self, text) self.text = text end
    o.GetText = function(self) return self.text or "" end
    o.HasFocus = function(self) return self.focus or false end
    o.GetStringWidth = function(self) return #(self.text or "") * 6 end
    o.HookScript = function(self, name, fn)
      local old = self.scripts[name]
      self.scripts[name] = function(...) if old then old(...) end; fn(...) end
    end
    o.CreateFontString = function() return widget() end
    o.GetFontString = function() return widget() end
    o.ClearFocus = function(self) self.focus = nil; self.scripts.OnEditFocusLost(self) end
    return o
  end
  local ok, err = pcall(function()
    CreateFrame = function() return widget() end
    GameTooltip = widget()
    assert(loadfile("Theme.lua"))("ForeverLedger", ns)
    ns.Theme:Apply()
    local e = { id = 89001, max = 1357, src = "usual" }
    local box = ns.Theme:MoneyBox(widget(), function(v) ns:SetListItemPrice(e, v) end, "g", true)
    box.confirmSame = true; box:SetValue(1357)
    box.scripts.OnEditFocusLost(box)
    T.eq(e.src, "usual", "focus alone is not a typed price")
    box:SetText("13s 57c"); box.scripts.OnTextChanged(box, true)
    box.scripts.OnEditFocusLost(box)
    T.eq(e.src, "you"); T.eq(e.max, 1357)
    e.src = "usual"
    box:SetText("99g"); box.scripts.OnTextChanged(box, true)
    box.scripts.OnEscapePressed(box)
    T.eq(e.src, "usual"); T.eq(e.max, 1357, "Escape doesn't commit")
    -- A narrow box shows a shortened amount; Escape mustn't save that (Codex review,
    -- October 6: 9999g 99s 99c became 9999g 99s, set by you).
    local f = { id = 89002, max = 99999999, src = "usual" }
    local narrow = ns.Theme:MoneyBox(widget(), function(v) ns:SetListItemPrice(f, v) end, "g", true)
    narrow.GetFont = function() return "font", 12, "" end
    narrow.GetWidth = function() return 66 end
    narrow.compact, narrow.confirmSame = true, true
    narrow:SetValue(99999999)
    T.eq(narrow:GetText(), "9999g99s", "too long at the smallest size: copper dropped")
    narrow.focus = true; narrow.scripts.OnEditFocusGained(narrow)
    T.eq(narrow:GetText(), "9999g 99s 99c", "clicking in shows the exact amount")
    narrow.scripts.OnEscapePressed(narrow)
    T.eq(f.src, "usual"); T.eq(f.max, 99999999, "Escape keeps the exact amount")
    narrow.scripts.OnEditFocusLost(narrow)
    T.eq(f.max, 99999999, "clicking away from the short form changes nothing")
    -- Silver dropped too, then typing and Escape: still the exact amount and automatic.
    f.max = 9999999999
    narrow:SetValue(9999999999)
    T.eq(narrow:GetText(), "999999g", "copper and silver dropped")
    narrow.focus = true; narrow.scripts.OnEditFocusGained(narrow)
    narrow:SetText("1g"); narrow.scripts.OnTextChanged(narrow, true)
    narrow.scripts.OnEscapePressed(narrow)
    T.eq(f.src, "usual"); T.eq(f.max, 9999999999, "typed then Escape keeps it")
  end)
  CreateFrame, GameTooltip, ns.Theme = realFrame, realTip, realTheme
  assert(ok, err)
end)
