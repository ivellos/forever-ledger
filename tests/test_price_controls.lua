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
  end)
  CreateFrame, GameTooltip, ns.Theme = realFrame, realTip, realTheme
  assert(ok, err)
end)
