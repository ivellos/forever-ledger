local _, ns = ...
local localeName = GetLocale()
local language
local strings = {}
local patterns, cache, cacheCount
function ns.RegisterLocale(name, value)
  if name == localeName then
    language = value
    strings = value.strings or {}
    ns.localeFont = value.font
    patterns, cache, cacheCount = nil, nil, nil
  end
end
function ns.HasLocale() return language ~= nil end
function ns.GetLocaleData() return language end
function ns.InvalidateLocale() patterns, cache, cacheCount = nil, nil, nil end
local function escapePattern(text)
  return (text:gsub("([%%%^%$%(%)%.%[%]%*%+%-%?])", "%%%1"))
end
local spec = "%%[%-%+#0]*%d*%.?%d*[cdiouxXeEfgGqs]"
local function buildPatterns()
  patterns = {}
  for english, translated in pairs(strings) do
    if english:find(spec) and #english:gsub(spec, ""):gsub("[^%a]", "") >= 5 or (language.short and language.short[english]) then
      local parts, at, count, typed, kinds = {}, 1, 0, 0, {}
      while true do
        local first, last = english:find(spec, at)
        if not first then break end
        parts[#parts + 1] = escapePattern((english:sub(at, first - 1):gsub("%%%%", "%%")))
        local before = english:sub(at, first - 1)
        local conversion = english:sub(last, last)
        local prefix = english:sub(1, first - 1)
        local linkStart = prefix:match(".*()|H")
        local linkPrefix = linkStart and prefix:sub(linkStart)
        local _, linkDelimiters = (linkPrefix or ""):gsub("|h", "")
        local opaque = linkStart and (linkDelimiters == 0 or (linkPrefix:find("^|Hplayer:") and linkDelimiters < 2))
        for _, control in ipairs({ {"|T", "|t"}, {"|A", "|a"}, {"|K", "|k"} }) do
          local opened, closed = prefix:match(".*()" .. control[1]), prefix:match(".*()" .. control[2])
          if opened and (not closed or opened > closed) then opaque = true end
        end
        kinds[count + 1] = opaque and "opaque" or (before:sub(-4) == "|cff" or before:sub(-2) == "|c") and "color" or conversion
        if conversion ~= "s" and conversion ~= "q" then typed = typed + 1 end
        if before:sub(-4) == "|cff" then
          parts[#parts + 1] = "(%x%x%x%x%x%x)"
        elseif before:sub(-2) == "|c" then
          parts[#parts + 1] = "(%x%x%x%x%x%x%x%x)"
        else
          local kind = english:sub(last, last)
          if kind:find("[diu]") then
            parts[#parts + 1] = "([%+%-%s]*%d+)"
          elseif kind:find("[eEfgG]") then
            parts[#parts + 1] = "([%+%-%s%d%.eE]+)"
          elseif kind:find("[oxX]") then
            parts[#parts + 1] = "([%x%s]+)"
          elseif kind == "c" then
            parts[#parts + 1] = "(.)"
          else
            parts[#parts + 1] = "(.-)"
          end
        end
        count, at = count + 1, last + 1
      end
      parts[#parts + 1] = escapePattern((english:sub(at):gsub("%%%%", "%%")))
      patterns[#patterns + 1] = { pattern = "^" .. table.concat(parts) .. "$", text = translated, count = count, typed = typed, kinds = kinds, container = english == "%s (%s)" or english == "%s, %s", markup = english:find("|H",1,true) or english:find("|T",1,true) or english:find("|A",1,true) or english:find("|K",1,true), rank = #english:gsub(spec, "") }
    end
  end
  table.sort(patterns, function(a, b)
    if a.rank ~= b.rank then return a.rank > b.rank end
    if a.typed ~= b.typed then return a.typed > b.typed end
    return a.count < b.count
  end)
end
local localize
local function translatePattern(text, depth, markupOnly)
  if not patterns then buildPatterns() end
  for _, row in ipairs(patterns) do
    if not markupOnly or row.markup then
      local captures={text:match(row.pattern)}
      local valid = #captures==row.count
      if valid and row.container then
        for _, capture in ipairs(captures) do if capture:find("[()]") then valid=false;break end end
      end
      if valid then
        local index=0
        return (row.text:gsub(spec,function()
          index=index+1
          if row.kinds[index]=="s" or row.kinds[index]=="q" then return localize(captures[index],depth+1) end
          return captures[index]
        end):gsub("%%%%","%%"))
      end
    end
  end
end
local function remember(source, result)
  cache = cache or {}
  cacheCount = (cacheCount or 0) + 1
  if cacheCount > 1024 then cache, cacheCount = {}, 1 end
  cache[source] = result
  return result
end
localize = function(text, depth)
  if not language or (issecretvalue and issecretvalue(text)) or type(text) ~= "string" then return text end
  local direct = strings[text] or (language.upper and language.upper[text])
  if direct then return direct end
  if depth >= 16 or text == "" then return text end
  if cache and cache[text] then return cache[text] end
  -- Preserve link targets, textures, atlases, protected names and URLs byte for byte.
  if text:find("|H",1,true) or text:find("|T",1,true) or text:find("|A",1,true) or text:find("|K",1,true) or text:find("https?://") then
    local explicit=translatePattern(text,depth,true)
    if explicit then return remember(text,explicit) end
    local tokens, out, at={}, {}, 1
    while at<=#text do
      local first,last,kind
      for _,pair in ipairs({{"|H.-|h.-|h","link"},{"|T.-|t","opaque"},{"|A.-|a","opaque"},{"|K.-|k","opaque"},{"https?://[^%s|]+","opaque"}}) do
        local a,b=text:find(pair[1],at)
        if a and (not first or a<first) then first,last,kind=a,b,pair[2] end
      end
      if not first then out[#out+1]=text:sub(at);break end
      local token=text:sub(first,last)
      if kind=="link" then
        local lead,body,tail=token:match("^(|H.-|h)(.-)(|h)$")
        if lead and not lead:find("^|Hplayer:") then token=lead..localize(body,depth+1)..tail end
      end
      tokens[#tokens+1]=token
      out[#out+1]=text:sub(at,first-1).."\001"..#tokens.."\002"
      at=last+1
    end
    if #tokens>0 then
      local masked=localize(table.concat(out),depth+1)
      -- If no surrounding template matched, translate the visible pieces beside icons and links.
      if masked==table.concat(out) then
        local pieces,start={},1
        while true do
          local a,b=masked:find("\001%d+\002",start)
          if not a then pieces[#pieces+1]=localize(masked:sub(start),depth+1);break end
          pieces[#pieces+1]=localize(masked:sub(start,a-1),depth+1)
          pieces[#pieces+1]=masked:sub(a,b);start=b+1
        end
        masked=table.concat(pieces)
      end
      return remember(text,(masked:gsub("\001(%d+)\002",function(i) return tokens[tonumber(i)] end)))
    end
  end
  -- Input syntax and copied slash commands are never translated.
  if text:match("^%s*/") then return text end
  local result=translatePattern(text,depth,false)
  if result then return remember(text,result) end
  -- Translate visible segments between color controls; control bytes are untouched.
  if text:find("|c%x%x%x%x%x%x%x%x") or text:find("|r",1,true) then
    local out,at={},1
    while at<=#text do
      local a,b=text:find("|c%x%x%x%x%x%x%x%x",at)
      local ra,rb=text:find("|r",at,true)
      if ra and (not a or ra<a) then a,b=ra,rb end
      if not a then out[#out+1]=localize(text:sub(at),depth+1);break end
      out[#out+1]=localize(text:sub(at,a-1),depth+1)
      out[#out+1]=text:sub(a,b);at=b+1
    end
    return remember(text,table.concat(out))
  end
  -- Several status messages concatenate independently translated sentences.
  if text:find(". ",1,true) then
    local out,at,changed={},1,false
    while true do
      local a,b=text:find("%. +",at)
      if not a then
        local source=text:sub(at);local result=localize(source,depth+1)
        out[#out+1]=result;changed=changed or source~=result;break
      end
      local source=text:sub(at,a);local result=localize(source,depth+1)
      out[#out+1]=result..text:sub(a+1,b);changed=changed or source~=result;at=b+1
    end
    if changed then return remember(text,table.concat(out)) end
  end
  local leading,body,trailing=text:match("^(%s*)(.-)(%s*)$")
  if body~=text then return remember(text,leading..localize(body,depth+1)..trailing) end
  local inside=text:match("^%((.*)%)$")
  if inside then return remember(text,"("..localize(inside,depth+1)..")") end
  inside=text:match("^%[(.*)%]$")
  if inside then return remember(text,"["..localize(inside,depth+1).."]") end
  return remember(text,text)
end
function ns.LocalizeText(text) return localize(text,0) end

-- Units belong to rendered text. Editable prices and exported data keep their input syntax.
function ns.LocalizeDisplayText(text)
  text = ns.LocalizeText(text)
  if not language or type(text) ~= "string" or (issecretvalue and issecretvalue(text)) then return text end
  local function visible(s)
    return language.TransformVisible and language.TransformVisible(s, text) or s
  end
  local out,at={},1
  while at<=#text do
    local first,last
    for _,pattern in ipairs({"|H.-|h.-|h","|T.-|t","|A.-|a","|K.-|k","https?://[^%s|]+","|c%x%x%x%x%x%x%x%x","|r"}) do
      local a,b=text:find(pattern,at)
      if a and (not first or a<first) then first,last=a,b end
    end
    if not first then out[#out+1]=visible(text:sub(at));break end
    out[#out+1]=visible(text:sub(at,first-1));out[#out+1]=text:sub(first,last);at=last+1
  end
  return table.concat(out)
end
function ns.LocalizeFontString(fs)
  if not language or not fs or fs._flLocalized then return fs end
  fs._flLocalized = true
  local setText, setFormatted = fs.SetText, fs.SetFormattedText
  fs.SetText = function(self, text, ...) return setText(self, ns.LocalizeDisplayText(text), ...) end
  if setFormatted then
    fs.SetFormattedText = function(self, format, ...)
      local args,n={...},select("#",...)
      for i=1,n do args[i]=ns.LocalizeDisplayText(args[i]) end
      local result = setFormatted(self, ns.LocalizeDisplayText(format), unpack(args,1,n))
      if self.GetText then setText(self, ns.LocalizeDisplayText(self:GetText())) end
      return result
    end
  end
  return fs
end
function ns.LocalizeButton(button)
  if not language or not button or button._flLocalized then return button end
  button._flLocalized = true
  local function refresh(self, text)
    local font = self:GetFontString()
    if font then font:SetText(ns.LocalizeDisplayText(text)) end
  end
  hooksecurefunc(button, "SetText", refresh)
  return button
end
function ns:TooltipAddLine(text, ...) return GameTooltip:AddLine(ns.LocalizeDisplayText(text), ...) end
function ns:TooltipAddDoubleLine(left, right, ...) return GameTooltip:AddDoubleLine(ns.LocalizeDisplayText(left), ns.LocalizeDisplayText(right), ...) end

function ns.LocalizedPrint(...)
  local args,n={...},select("#",...)
  for i=1,n do args[i]=ns.LocalizeDisplayText(args[i]) end
  return print(unpack(args,1,n))
end
function ns:AddTooltipLine(tooltip,text,...) return tooltip:AddLine(ns.LocalizeDisplayText(text),...) end
function ns:AddTooltipDoubleLine(tooltip,left,right,...) return tooltip:AddDoubleLine(ns.LocalizeDisplayText(left),ns.LocalizeDisplayText(right),...) end
function ns:ShowPopup(which,text1,text2,data,...) return StaticPopup_Show(which,ns.LocalizeDisplayText(text1),ns.LocalizeDisplayText(text2),data,...) end
function ns.LocalizedRaidNotice(frame,text,...) return RaidNotice_AddMessage(frame,ns.LocalizeDisplayText(text),...) end
function ns:AddUIMessage(frame,text,...) return frame:AddMessage(ns.LocalizeDisplayText(text),...) end

function ns.FormatElapsed(seconds)
  if language and language.FormatElapsed then return language.FormatElapsed(seconds) end
  return seconds < 60 and (seconds .. "s") or ("%dm %ds"):format(math.floor(seconds / 60), seconds % 60)
end
