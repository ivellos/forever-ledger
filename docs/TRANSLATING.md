# Translating Forever Ledger

Forever Ledger is written in English. Each other language is one file in `Locales\`, which the addon loads only on a game client in that language. Anything without a translation shows in English, so a translation can be partial and still useful.

## How it works

- `Locale.lua` is the shared core. It picks the table for the client's language (`GetLocale()`) and translates text as it is shown: windows, buttons, tooltips and chat messages.
- `Locales\<code>.lua` holds one language: its strings, and optionally a font and a few helpers. Simplified Chinese (`Locales\zhCN.lua`) is the example to follow.
- The English text in the code is the key. When the English text changes, its old translation stops matching and the line shows in English until the file gets the new wording.
- `/fl api`, `/fl perf`, `/fl de`, `/fl trainer` and debug lines stay English on purpose, so bug reports read the same from every client.

## Starting a language

1. Copy the top of `Locales\zhCN.lua`: the early return for other clients, the `language` table, and `ns.RegisterLocale` at the end, with your language code (`deDE`, `frFR`, `esES`, `esMX`, `ptBR`, `ruRU`, `koKR`, `zhTW`, `itIT`).
2. Add the file to `ForeverLedger.toc`, right after `Locales\zhCN.lua`.
3. Get every English string to translate:

   ```
   lua5.1 tools/locale-report.lua new
   ```

   Each line comes out as `language.strings["English"] = ""`: fill in the quotes. A line left empty shows the English, the same as leaving it out.

## After each release

```
lua5.1 tools/locale-report.lua           how much each language covers
lua5.1 tools/locale-report.lua ruRU      only the strings ruRU has no entry for yet
```

The same summary runs on every push (GitHub Actions, Check code, "Translation coverage"). The report is a guide: it finds quoted text in the code that looks like something a player reads. A sentence built from pieces may need the whole sentence translated, which the report can't see.

## Rules for the strings

- Keep every `%s`, `%d`, `%.1f` and the like in the same order: the core fills them by position. You may leave out placeholders only at the end of a line. Word order around them is yours to change.
- Keep color codes (`|cffffd100` ... `|r`), item links and icons exactly as they are.
- Don't translate slash commands (`/fl ...`), setting keys or anything saved.
- Money stays in the game's coin icons where the addon shows them.

## Counted nouns

Some languages need three forms of a counted noun: 1 день, 2 дня, 5 дней. Write the
translation as a table of three strings:

```lua
language.strings["%d items"] = { "%d предмет", "%d предмета", "%d предметов" }
language.strings["%d item"] = { "%d предмет", "%d предмета", "%d предметов" }
```

and add `language.forms(n)` to the language file, returning 1, 2 or 3 for a number:

```lua
function language.forms(n)
  n = math.abs(tonumber(n) or 0)
  local mod100, mod10 = n % 100, n % 10
  if mod100 >= 11 and mod100 <= 14 then return 3 end
  if mod10 == 1 then return 1 end
  if mod10 >= 2 and mod10 <= 4 then return 2 end
  return 3
end
```

The core picks the form by the first number the message shows. A line with a number
but no noun (most of them) stays a plain string.

When the code builds a line from a number and a word before showing it, add the
finished singular and plural lines as keys too (`"%d item"` and `"%d items"` above):
the number is already in the text the core sees.

For a message the code assembles before showing it, translate the finished line:
`ns.LocalizeFormatted("%d items left", n)` formats first, then translates, so the form
sees the number. A language without `language.forms` keeps translating the template
and formatting after, as before.

## Optional parts of a language file

- `language.font`: a font with your alphabet, if the game's default doesn't cover it.
- `language.FormatElapsed(seconds)`: how "2m 5s" is written.
- `language.TransformVisible(text, whole)`: a last change to visible text (zhCN uses it for units).
- `language.postMarks`: the Post tab's state words, when one English word needs two translations.
- `language.chatWords`: words players use in your language when they ask for a crafter or a class service, for the Customers finder. Lower case:

  ```lua
  language.chatWords = {
    asking = { "ищу", "нужен" },          -- someone looking for help
    offering = { "продам", "крафчу" },    -- a crafter advertising (skipped)
    professions = { Enchanting = { "чант", "энчантер" } },
    services = { mage = { "вода", "еда" }, portal = { "портал" }, summon = { "суммон" }, lockpick = { "взлом" } },
  }
  ```

### Russian, as a worked example

`Locales\ruRU.lua` uses most of the optional parts:

- `language.forms` and three-form tables cover counted nouns.
- `language.TransformVisible` writes a range the Russian way: "1 to 3" becomes "1—3".
- `language.FormatElapsed` writes "2 мин 5 с", and `language.postMarks` supplies the Post tab's states, where one English word needs different Russian ones.
- `language.chatWords` teaches the Customers finder the Russian words for "looking for" and "offering", and the Russian names of professions and services.

`tests/test_localization.lua` loads both language files and checks their placeholders, and `lua5.1 tools/locale-report.lua ruRU` lists what Russian still misses. The same two commands check a new language.

## What the addon reads from the game

The addon never relies on English game text where an ID exists: professions by skill line, quests by quest ID, riding and Arcane Salvager by spell and item, the Trade channel by its channel number, Waylaid Crates by item, neutral auction houses by map. Names the game itself gives in your language (professions, quests, zones) are used for display without a translation entry. If you see game text that only works in English, please open an issue.
