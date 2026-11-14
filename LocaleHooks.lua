local _, ns = ...

-- Display hooks only: never initialize or override the player's settings.
ns:OnReady(function()
  if not ns.HasLocale() then return end
  local original = ns.Print
  if original then
    ns.Print = function(self, text, ...) return original(self, ns.LocalizeText(text), ...) end
  end
  for name, dialog in pairs(StaticPopupDialogs or {}) do
    if name:find("^FOREVER_LEDGER_") or name == "FLEDGER_RELOAD" then
      for _, key in ipairs({ "text", "button1", "button2", "button3" }) do
        if type(dialog[key]) == "string" then dialog[key] = ns.LocalizeText(dialog[key]) end
      end
    end
  end
end)
