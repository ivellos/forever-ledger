-- Run `luacheck *.lua` from the repository root, as CI does.
-- Check syntax and global access; leave existing style/unused-local cleanup separate.
std = "lua51"
only = { "0", "1" }
codes = true

-- Maintained WoW API names, including guarded Classic fallbacks. This is a lint
-- vocabulary, not a promise that an API exists in Forever: runtime guards still apply.
-- Do not generate this list from addon identifiers or allow arbitrary new globals.
read_globals = {
  -- Modern API namespaces and engine objects (fields vary between game clients).
  "C_AddOns", "C_AuctionHouse", "C_ChatInfo", "C_ClassTalents", "C_Container",
  "C_CurrencyInfo", "C_CVar", "C_GameRules", "C_GossipInfo", "C_Item", "C_Map",
  "C_MerchantFrame", "C_MountJournal", "C_PartyInfo", "C_PetJournal", "C_PvP",
  "C_QuestLog", "C_Seasons", "C_SpecializationInfo", "C_Spell", "C_SpellBook",
  "C_SuperTrack", "C_Talent", "C_Texture", "C_Timer", "C_TooltipInfo", "C_ToyBox",
  "C_TradeSkillUI", "C_Traits", "C_UnitAuras", "C_XMLUtil", "Enum", "ItemLocation",
  "TooltipDataProcessor", "UiMapPoint",

  -- Frames, UI enums, localized strings and constants supplied by Blizzard.
  "AuctionFrame", "AuctionHouseFrame", "AuctionHouseFrameDisplayMode",
  "GameTooltip", "ItemRefTooltip", "Minimap", "ProfessionsFrame", "RaidWarningFrame",
  "TradeFrameRecipientNameText", "TradeSkillFrame", "UIErrorsFrame", "UIParent",
  "ATTACHMENTS_MAX_RECEIVE", "BOOKTYPE_SPELL", "CLASS_ICON_TCOORDS", "CONTAINER_SLOTS",
  "ERR_AUCTION_SOLD_S", "ERR_AUCTION_WON_S", "ERR_CHAT_PLAYER_NOT_FOUND_S", "ERR_ITEM_NOT_FOUND",
  "ERR_TRADE_CANCELLED", "ERR_TRADE_COMPLETE", "LOCALIZED_CLASS_NAMES_MALE",
  "LOOT_ITEM_SELF", "LOOT_ITEM_SELF_MULTIPLE", "NUM_BAG_SLOTS", "NUM_BANKBAGSLOTS",
  "NUM_TOTAL_EQUIPPED_BAG_SLOTS", "RAID_CLASS_COLORS", "SOUNDKIT", "STANDARD_TEXT_FONT",
  "CANCEL", "NO", "OKAY", "SAVE", "YES",

  -- Common engine helpers, events, names, money, sound and cursor/UI functions.
  "Ambiguate", "ChatFrame_AddMessageEventFilter", "ChatFrame_SendTell", "ClearCursor",
  "ClearOverrideBindings", "CreateFrame", "date", "debugprofilestop", "geterrorhandler",
  "GetCoinTextureString", "GetCurrentKeyBoardFocus", "GetCursorInfo", "GetCursorPosition",
  "GetCVar", "GetFileIDFromPath", "GetMoney", "GetMouseFoci", "GetMouseFocus",
  "GetNormalizedRealmName", "GetRealmID", "GetRealmName", "GetRealZoneText",
  "GetMinimapZoneText", "GetScreenWidth", "GetSubZoneText", "GetTime", "GetUnitName",
  "GetZoneText", "HandleModifiedItemClick", "hooksecurefunc", "InCombatLockdown",
  "InviteUnit", "IsAltKeyDown", "IsControlKeyDown", "ITEM_QUALITY_COLORS", "BreakUpLargeNumbers", "IsInGroup", "IsInGuild", "IsInInstance", "IsInRaid",
  "IsModifiedClick", "IsMouseButtonDown", "IsPVPTimerRunning", "issecretvalue",
  "IsShiftKeyDown", "PlaySound", "RaidNotice_AddMessage", "ReloadUI", "SendChatMessage",
  "SetCVar", "StaticPopup_Show", "time", "tinsert", "wipe",
  "UnitBuff", "UnitClass", "UnitExists", "UnitFactionGroup", "UnitFullName", "UnitGUID",
  "UnitIsDead", "UnitLevel", "UnitName", "UnitReaction",

  -- Items, loot, merchants, mail, trade, professions, spells and older API fallbacks.
  "GetActiveTalentGroup", "GetAddOnMemoryUsage", "GetAddOnMetadata", "IsAddOnLoaded",
  "UpdateAddOnMemoryUsage", "GetChannelDisplayInfo", "GetChannelName",
  "EnumerateServerChannels", "GetNumDisplayChannels", "GetInboxHeaderInfo",
  "GetInboxInvoiceInfo", "GetInboxItem", "GetInboxNumItems", "GetInstanceInfo",
  "GetItemCount", "GetItemIcon", "GetItemInfo", "GetItemInfoInstant", "GetLootSlotInfo",
  "GetLootSlotLink", "GetLootSourceInfo", "GetNumLootItems", "GetMerchantItemCostInfo",
  "GetMerchantItemCostItem", "GetMerchantItemID", "GetMerchantItemInfo",
  "GetMerchantNumItems", "GetNumCompanions", "GetNumSkillLines", "GetNumSpellTabs",
  "GetNumTalents", "GetNumTalentTabs", "GetNumTrainerServices", "GetPlayerTradeMoney",
  "GetProfessionInfo", "GetProfessions", "GetQuestGreenRange", "GetQuestsCompleted",
  "GetSkillLineInfo", "GetSpecialization", "GetSpellBookItemName", "GetSpellInfo",
  "GetSpellTabInfo", "GetTalentTabInfo", "GetTargetTradeMoney", "GetTradePlayerItemInfo",
  "GetTradePlayerItemLink", "GetTradeTargetItemInfo", "GetTradeTargetItemLink",
  "GetTrainerServiceCost", "GetTrainerServiceDescription", "GetTrainerServiceInfo",
  "GetTrainerServiceLevelReq", "GetTrainerServiceSkillReq", "GetTrainerServiceTypeFilter",
  "SetTrainerServiceTypeFilter", "IsPlayerSpell", "IsSpellKnown", "UnitCharacterPoints",

  -- Optional addon APIs: used only behind their existing runtime checks.
  "AucAdvanced", "Auctionator", "EllesmereUI", "TSM_API",
}

-- Blizzard tables whose fields the addon deliberately registers or mutates.
globals = { "StaticPopupDialogs", "SlashCmdList", "UISpecialFrames", "ColorPickerFrame" }

-- Only Core owns these global registrations. Other files must use the namespace.
files["Core.lua"] = {
  globals = { "ForeverLedgerDB", "SLASH_FOREVERLEDGER1", "SLASH_FOREVERLEDGER2" },
}
