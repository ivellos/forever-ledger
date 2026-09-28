# Builds ClassicRecipes.lua: where each Tailoring, Enchanting, Cooking, First Aid and
# Fishing recipe came from in original Classic (every vendor, the mobs it drops from,
# quests), where those NPCs stand, and Classic trainers for these professions.
# Sources (both MIT licence):
#   wow-classic-items by nexus-devs  https://github.com/nexus-devs/wow-classic-items
#     (the list of recipe items, quests)
#   pfQuest by shagu                 https://github.com/shagu/pfQuest
#     (vendors, drops, NPC names, factions and positions)
# Run from the repo root:  powershell -File tools\build-classic-data.ps1

$ErrorActionPreference = "Stop"
$tmp = Join-Path $env:TEMP "fl-classic-data"
New-Item -ItemType Directory -Force $tmp | Out-Null
function Get($url, $file) { $p = Join-Path $tmp $file; Invoke-WebRequest $url -OutFile $p; Get-Content $p -Raw -Encoding UTF8 }

$nexus = "https://raw.githubusercontent.com/nexus-devs/wow-classic-items/master/data/json"
$pf = "https://raw.githubusercontent.com/shagu/pfQuest/master/db"
$items = (Get "$nexus/data.json" "items.json") | ConvertFrom-Json
$pfItems = Get "$pf/items.lua" "pf-items.lua"
$pfUnits = Get "$pf/units.lua" "pf-units.lua"
$pfNames = Get "$pf/enUS/units.lua" "pf-unit-names.lua"
$pfZones = Get "$pf/enUS/zones.lua" "pf-zone-names.lua"

$profs = "Tailoring", "Enchanting", "Cooking", "First Aid", "Fishing"
$prefix = '^(Formula|Pattern|Recipe|Manual|Plans|Schematic):\s*'
$inv = [Globalization.CultureInfo]::InvariantCulture
function Q([string]$s) { '"' + ($s -replace '\\', '\\' -replace '"', '\"') + '"' }
function Num($n) { ([double]$n).ToString($inv) }

# Classic trainers (Alliance and neutral) for these professions, from memory of
# Classic: names are checked against pfQuest, which adds positions.
$trainers = @(
  @("Georgio Bolero", "Tailoring", "Artisan"), @("Timothy Worthington", "Tailoring", "Artisan"),
  @("Sellandus", "Tailoring", ""), @("Jormund Stonebrow", "Tailoring", ""), @("Me'lynn", "Tailoring", ""), @("Eldrin", "Tailoring", ""),
  @("Annora", "Enchanting", "Artisan"), @("Kitta Firewind", "Enchanting", "Expert"), @("Lucan Cordell", "Enchanting", ""), @("Gimble Thistlefuzz", "Enchanting", ""),
  @("Dirge Quikcleave", "Cooking", "Artisan"), @("Stephen Ryback", "Cooking", ""), @("Daryl Riknussun", "Cooking", ""), @("Alegorn", "Cooking", ""), @("Tomas", "Cooking", ""),
  @("Doctor Gustaf VanHowzen", "First Aid", "Artisan"), @("Deneb Walker", "First Aid", "Expert"), @("Shaina Fuller", "First Aid", ""), @("Nissa Firestone", "First Aid", ""), @("Michelle Belle", "First Aid", ""),
  @("Nat Pagle", "Fishing", "Artisan"), @("Old Man Heming", "Fishing", "Expert"), @("Arnold Leland", "Fishing", ""), @("Grimnur Stonebrand", "Fishing", "")
)
$trainerNotes = @{ "Deneb Walker" = "sells the Expert First Aid book"; "Nat Pagle" = "through his quests"; "Old Man Heming" = "sells the Expert Fishing book" }

# pfQuest tables -------------------------------------------------------------
$zoneName = @{}
foreach ($m in [regex]::Matches($pfZones, '\[(\d+)\] = "((?:[^"\\]|\\.)*)"')) { $zoneName[[int]$m.Groups[1].Value] = $m.Groups[2].Value }
$unitName = @{}; $idsByName = @{}
foreach ($m in [regex]::Matches($pfNames, '\[(\d+)\] = "((?:[^"\\]|\\.)*)"')) {
  $id = [int]$m.Groups[1].Value; $n = $m.Groups[2].Value -replace '\\(.)', '$1'
  $unitName[$id] = $n
  if (-not $idsByName[$n]) { $idsByName[$n] = New-Object System.Collections.Generic.List[int] }
  $idsByName[$n].Add($id)
}
function Blocks($text) {
  $h = @{}
  # Empty entries are "[17] = {}," on one line; the rest end with "  },".
  foreach ($m in [regex]::Matches($text, '(?s)\n  \[(\d+)\] = \{(?:\}|(.*?)\n  \}),')) { $h[[int]$m.Groups[1].Value] = $m.Groups[2].Value }
  $h
}
$itemBlock = Blocks $pfItems
$unitBlock = Blocks $pfUnits
function Pairs($block, $key) {
  $out = @()
  $m = [regex]::Match($block, "(?s)\[`"$key`"\] = \{(.*?)\n    \},")
  if ($m.Success) { foreach ($p in [regex]::Matches($m.Groups[1].Value, '\[(\d+)\] = ([\d.]+)')) { $out += [pscustomobject]@{ id = [int]$p.Groups[1].Value; v = [double]$p.Groups[2].Value } } }
  , $out
}
function UnitInfo($id) {
  $b = $unitBlock[$id]
  if (-not $b) { return $null }
  $fac = [regex]::Match($b, '\["fac"\] = "(\w+)"').Groups[1].Value
  # Prefer a spot in a capital city (Darnassus NPCs are also listed under Teldrassil).
  $all = [regex]::Matches($b, '\{ ([\d.]+), ([\d.]+), (\d+), \d+ \}')
  $c = $all | Where-Object { @(1519, 1537, 1657) -contains [int]$_.Groups[3].Value } | Select-Object -First 1
  if (-not $c) { $c = $all | Select-Object -First 1 }
  $spawns = [regex]::Matches($b, '\{ [\d.]+, [\d.]+, \d+, \d+ \}').Count
  $info = @{ fac = $fac; spawns = $spawns }
  if ($c) { $info.x = [double]$c.Groups[1].Value; $info.y = [double]$c.Groups[2].Value; $info.zone = $zoneName[[int]$c.Groups[3].Value] }
  $info
}

# Recipes ----------------------------------------------------------------------
$later = { param($id) ($id -ge 21892 -and $id -le 21919) -or ($id -ge 22530 -and $id -le 22565) -or $id -eq 22647 -or $id -ge 24000 }
$recipes = $items | Where-Object { $_.class -eq "Recipe" -and $profs -contains $_.subclass -and $_.name -match $prefix -and -not (& $later $_.itemId) } | Sort-Object name
$npcs = @{}
$lines = New-Object System.Collections.Generic.List[string]
foreach ($r in $recipes) {
  $b = $itemBlock[[int]$r.itemId]
  $vendors = if ($b) { Pairs $b "V" } else { @() }
  $drops = if ($b) { Pairs $b "U" } else { @() }
  $f = @("item = $($r.itemId)")
  # Skill needed to learn it, from the item's tooltip: "Requires Tailoring (70)".
  $req = $r.tooltip | Where-Object { $_.label -match '^Requires (Tailoring|Enchanting|Cooking|First Aid|Fishing) \((\d+)\)' } | Select-Object -First 1
  if ($req -and $req.label -match '\((\d+)\)') { $f += "skill = $($Matches[1])" }
  $s = $r.source
  if ($vendors.Count -gt 0) {
    $f += 'kind = "vendor"'
    if ($s -and $s.category -eq "Vendor" -and $s.cost) { $f += "cost = $($s.cost)" }
    $ids = @($vendors | ForEach-Object { $_.id } | Where-Object { $unitName[$_] })
    $f += "vendors = { $(($ids | ForEach-Object { $_ }) -join ', ') }"
    foreach ($id in $ids) { $npcs[$id] = $true }
  } elseif ($s -and $s.category -eq "Quest") {
    $f += 'kind = "quest"'
    $q = $s.quests | Select-Object -First 1
    if ($q) { $f += "quest = $(Q $q.name)"; if ($q.faction) { $f += "faction = $(Q $q.faction)" } }
  } elseif ($drops.Count -gt 0) {
    # Few mobs with a real chance: a mob drop. Many with tiny chances: a world drop.
    # Objects, not pairs: a single [id, chance] pair would be unrolled by the pipeline.
    $top = @($drops | Sort-Object { - $_.v } | Where-Object { $unitName[$_.id] } | Select-Object -First 5)
    $f += $(if ($drops.Count -le 5 -or $top[0].v -ge 3) { 'kind = "mob"' } else { 'kind = "drop"' })
    $f += "mobs = { $(($top | ForEach-Object { "{ $($_.id), $(Num $_.v) }" }) -join ', ') }"
    if ($drops.Count -gt 5) { $f += "mobCount = $($drops.Count)" }
    foreach ($t in $top) { $npcs[$t.id] = $true }
  } elseif ($s) {
    $f += 'kind = "drop"'
    if ($s.dropChance) { $f += "chance = $(Num ([math]::Round([double]$s.dropChance * 100, 2)))" }
  } else { continue }
  $lines.Add("  [$(Q (($r.name -replace $prefix, '').ToLower()))] = { $($f -join ', ') },")
}

# Trainers ---------------------------------------------------------------------
$trainerLines = New-Object System.Collections.Generic.List[string]
foreach ($t in $trainers) {
  $name, $prof, $tier = $t
  $pick = $null
  foreach ($id in ($idsByName[$name] | Where-Object { $_ })) {
    $u = UnitInfo $id
    if ($u -and ($u.fac -eq "" -or $u.fac -match 'A')) { if ($u.x) { $pick = $id; break } elseif (-not $pick) { $pick = $id } }
  }
  $f = @("name = $(Q $name)", "profession = $(Q $prof)")
  if ($tier) { $f += "tier = $(Q $tier)" }
  if ($trainerNotes[$name]) { $f += "title = $(Q $trainerNotes[$name])" }
  if ($name -eq "Annora") { $f += 'zone = "inside Uldaman (Badlands)"' }   # inside the dungeon, so no position
  if ($pick) { $f += "npc = $pick"; $npcs[$pick] = $true } else { Write-Warning "Trainer not found in pfQuest: $name" }
  $trainerLines.Add("  { $($f -join ', ') },")
}

# NPCs -------------------------------------------------------------------------
$npcLines = New-Object System.Collections.Generic.List[string]
foreach ($id in ($npcs.Keys | Sort-Object)) {
  $u = UnitInfo $id
  $f = @("$(Q $unitName[$id])")
  if ($u -and $u.fac) { $f += "fac = $(Q $u.fac)" }
  if ($u -and $u.zone) { $f += "zone = $(Q $u.zone), x = $(Num $u.x), y = $(Num $u.y)" }
  if ($u -and $u.spawns -gt 1) { $f += "spawns = $($u.spawns)" }
  $npcLines.Add("  [$id] = { name = $($f -join ', ') },")
}

$out = @(
  "local _, ns = ...",
  "",
  "-- Original Classic data for the Recipes tab, unconfirmed in Forever until seen in game.",
  "-- Generated by tools/build-classic-data.ps1 from wow-classic-items (nexus-devs) and",
  "-- pfQuest (shagu), both MIT licence. Don't edit by hand; rerun the script.",
  "--",
  "-- CLASSIC_RECIPES[recipe name] = { item, skill (needed to learn), kind = vendor | mob | drop | quest,",
  "--   vendors = { npcID, ... }, cost, mobs = { { npcID, drop chance % }, ... } (top 5),",
  "--   mobCount (all mobs that drop it), chance, quest, faction }",
  "-- CLASSIC_NPCS[npcID] = { name, fac = A | H | AH, zone, x, y (0-100), spawns }",
  "-- CLASSIC_TRAINERS = { { name, profession, tier, title, npc }, ... }",
  "ns.CLASSIC_RECIPES = {"
) + $lines + @("}", "", "ns.CLASSIC_NPCS = {") + $npcLines + @("}", "", "ns.CLASSIC_TRAINERS = {") + $trainerLines + @("}")
[IO.File]::WriteAllLines((Join-Path (Get-Location) "ClassicRecipes.lua"), $out, (New-Object Text.UTF8Encoding $false))
"Wrote $($lines.Count) recipes, $($npcLines.Count) NPCs, $($trainerLines.Count) trainers to ClassicRecipes.lua"


