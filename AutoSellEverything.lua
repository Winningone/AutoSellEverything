-- AutoSellEverything (WoW 3.3.5 - Wrath of the Lich King)
-- Features:
--   - Auto-sells while merchant window is open
--   - Sells newly created/moved items while merchant remains open
--   - Ignore list by item ID or item link
--   - Quality filter by number or name
--   - GUI with:
--       * enable toggle
--       * quality checkboxes
--       * scrollable ignore list
--       * per-item remove buttons
--       * drag-and-drop ignore target

local frame = CreateFrame("Frame")
frame:RegisterEvent("MERCHANT_SHOW")
frame:RegisterEvent("MERCHANT_CLOSED")
frame:RegisterEvent("PLAYER_LOGIN")

AutoSellEverythingDB = AutoSellEverythingDB or {}
AutoSellEverythingDB.ignoreGlobal = AutoSellEverythingDB.ignoreGlobal or {}

AutoSellEverythingCharDB = AutoSellEverythingCharDB or {}
AutoSellEverythingCharDB.ignoreCharacter = AutoSellEverythingCharDB.ignoreCharacter or {}

if AutoSellEverythingDB.sellQualities == nil then
  AutoSellEverythingDB.sellQualities = {
    [0] = true, [1] = true, [2] = true, [3] = true,
    [4] = true, [5] = true, [6] = true, [7] = true
  }
end

if AutoSellEverythingDB.showTooltipNote == nil then
  AutoSellEverythingDB.showTooltipNote = true
end

local AUTOSELL_ENABLED = true

local sellQueue = {}
local queued = {}
local queueIndex = 1

local timeSinceLastSell = 0
local SELL_INTERVAL = 0.05

local GUIFrame = nil
local qualityChecks = {}
local ignoreEditBox = nil
local statusText = nil
local tooltipCheck = nil

local globalIgnoreRows = {}
local globalIgnoreScrollFrame = nil
local globalIgnoreContent = nil

local characterIgnoreRows = {}
local characterIgnoreScrollFrame = nil
local characterIgnoreContent = nil

local dragDropBox = nil

local QUALITY_NAME_TO_ID = {
  ["0"]=0, ["poor"]=0, ["junk"]=0, ["gray"]=0, ["grey"]=0,
  ["1"]=1, ["common"]=1, ["white"]=1,
  ["2"]=2, ["uncommon"]=2, ["green"]=2,
  ["3"]=3, ["rare"]=3, ["blue"]=3,
  ["4"]=4, ["epic"]=4, ["purple"]=4,
  ["5"]=5, ["legendary"]=5, ["orange"]=5,
  ["6"]=6, ["artifact"]=6,
  ["7"]=7, ["heirloom"]=7
}

local QUALITY_ID_TO_LABEL = {
  [0] = "Poor / Gray",
  [1] = "Common / White",
  [2] = "Uncommon / Green",
  [3] = "Rare / Blue",
  [4] = "Epic / Purple",
  [5] = "Legendary / Orange",
  [6] = "Artifact",
  [7] = "Heirloom"
}

local function Print(msg)
  if DEFAULT_CHAT_FRAME then
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99AutoSellEverything|r: " .. msg)
  end
end

local function MerchantIsOpen()
  return MerchantFrame and MerchantFrame:IsShown()
end

local function ClearQueue()
  sellQueue = {}
  queued = {}
  queueIndex = 1
  timeSinceLastSell = 0
end

local function EnsureBagTable(bag)
  if not queued[bag] then
    queued[bag] = {}
  end
  return queued[bag]
end

local function GetItemIDFromLink(itemLink)
  if not itemLink then return nil end
  local id = itemLink:match("item:(%d+)")
  return id and tonumber(id) or nil
end

local function MakeBasicItemLink(itemID)
  return ("|cffffffff|Hitem:%d:0:0:0:0:0:0:0|h[item:%d]|h|r"):format(itemID, itemID)
end

local function GetItemLinkFromID(itemID)
  local link = select(2, GetItemInfo(itemID))
  if link then
    return link
  end
  return MakeBasicItemLink(itemID)
end

local function GetItemNameFromID(itemID)
  local name = GetItemInfo(itemID)
  if name then return name end
  return "item:" .. tostring(itemID)
end

local function ParseQualityToken(tok)
  if not tok or tok == "" then return nil end
  tok = tok:lower()
  tok = tok:gsub("^%s+", ""):gsub("%s+$", "")
  return QUALITY_NAME_TO_ID[tok]
end

local function GetIgnoreTable(listType)
  if listType == "character" then
    AutoSellEverythingCharDB.ignoreCharacter = AutoSellEverythingCharDB.ignoreCharacter or {}
    return AutoSellEverythingCharDB.ignoreCharacter
  end

  AutoSellEverythingDB.ignoreGlobal = AutoSellEverythingDB.ignoreGlobal or {}
  return AutoSellEverythingDB.ignoreGlobal
end

local function GetIgnoreLabel(listType)
  if listType == "character" then
    return "Character"
  end
  return "Global"
end

local function GetIgnoreMembership(itemLink)
  local id = GetItemIDFromLink(itemLink)
  if not id then
    return false, false
  end

  local inGlobal = GetIgnoreTable("global")[id] == true
  local inCharacter = GetIgnoreTable("character")[id] == true
  return inGlobal, inCharacter
end

local function IsIgnored(itemLink)
  local inGlobal, inCharacter = GetIgnoreMembership(itemLink)
  return inGlobal or inCharacter
end

local function IsSellQuality(quality)
  if quality == nil then return false end
  return AutoSellEverythingDB.sellQualities[quality] == true
end

local function ItemIsSellable(itemLink)
  if not itemLink then return false end
  if IsIgnored(itemLink) then return false end

  local quality = select(3, GetItemInfo(itemLink))
  local sellPrice = select(11, GetItemInfo(itemLink))

  if not sellPrice or sellPrice <= 0 then return false end
  if not quality then return false end
  if not IsSellQuality(quality) then return false end

  return true
end

local function EnqueueIfNotQueued(bag, slot)
  local bagTbl = EnsureBagTable(bag)
  if bagTbl[slot] then return end

  local texture, _, locked = GetContainerItemInfo(bag, slot)
  if not texture or locked then return end

  local itemLink = GetContainerItemLink(bag, slot)
  if ItemIsSellable(itemLink) then
    sellQueue[#sellQueue + 1] = { bag = bag, slot = slot }
    bagTbl[slot] = true
  end
end

local function ScanAllBags()
  for bag = 0, 4 do
    local numSlots = GetContainerNumSlots(bag)
    for slot = 1, numSlots do
      EnqueueIfNotQueued(bag, slot)
    end
  end
end

local function StopSelling()
  frame:UnregisterEvent("BAG_UPDATE")
  pcall(function() frame:UnregisterEvent("BAG_UPDATE_DELAYED") end)
  frame:SetScript("OnUpdate", nil)
  ClearQueue()
end

local function StartSelling()
  if not AUTOSELL_ENABLED then return end
  if not MerchantIsOpen() then return end

  ClearQueue()
  ScanAllBags()

  frame:RegisterEvent("BAG_UPDATE")
  pcall(function() frame:RegisterEvent("BAG_UPDATE_DELAYED") end)

  frame:SetScript("OnUpdate", function(self, elapsed)
    if not MerchantIsOpen() or not AUTOSELL_ENABLED then
      StopSelling()
      return
    end

    timeSinceLastSell = timeSinceLastSell + elapsed
    if timeSinceLastSell < SELL_INTERVAL then return end
    timeSinceLastSell = 0

    local entry = sellQueue[queueIndex]
    if not entry then
      return
    end

    if queued[entry.bag] then
      queued[entry.bag][entry.slot] = nil
    end

    local texture, _, locked = GetContainerItemInfo(entry.bag, entry.slot)
    if texture and not locked then
      local itemLink = GetContainerItemLink(entry.bag, entry.slot)
      if ItemIsSellable(itemLink) then
        UseContainerItem(entry.bag, entry.slot)
      end
    end

    queueIndex = queueIndex + 1
  end)
end

local function RefreshSellingState()
  if MerchantIsOpen() and AUTOSELL_ENABLED then
    StartSelling()
  elseif not AUTOSELL_ENABLED then
    StopSelling()
  end
end

local function GetSortedIgnoredIDs(listType)
  local ids = {}
  for id, v in pairs(GetIgnoreTable(listType)) do
    if v then
      ids[#ids + 1] = id
    end
  end

  table.sort(ids, function(a, b)
    local an = GetItemNameFromID(a):lower()
    local bn = GetItemNameFromID(b):lower()
    if an == bn then return a < b end
    return an < bn
  end)

  return ids
end

local function PrintIgnoreList(listType)
  local ids = GetSortedIgnoredIDs(listType)
  local label = GetIgnoreLabel(listType)

  if #ids == 0 then
    Print(label .. " ignore list is empty.")
    return
  end

  for _, id in ipairs(ids) do
    Print(label .. " ignored: " .. GetItemLinkFromID(id))
  end
  Print(label .. " ignore list total: " .. #ids)
end

local function PrintAllIgnoreLists()
  PrintIgnoreList("global")
  PrintIgnoreList("character")
end

local function SetAllQualities(enabled)
  for q = 0, 7 do
    AutoSellEverythingDB.sellQualities[q] = enabled and true or nil
  end
end

local function AutoSellEverything_AddTooltipNote(tooltip, itemLink)
  if not AutoSellEverythingDB.showTooltipNote then return end
  if not tooltip or not itemLink then return end
  if tooltip.AutoSellEverythingNoteAdded then return end

  local inGlobal, inCharacter = GetIgnoreMembership(itemLink)
  if not inGlobal and not inCharacter then return end

  local text
  if inGlobal and inCharacter then
    text = "AutoSellEverything: Global + Character Ignore"
  elseif inGlobal then
    text = "AutoSellEverything: Global Ignore"
  else
    text = "AutoSellEverything: Character Ignore"
  end

  tooltip:AddLine(" ")
  tooltip:AddLine(text, 0.33, 1.0, 0.6)
  tooltip.AutoSellEverythingNoteAdded = true
  tooltip:Show()
end

local UpdateGlobalIgnoreListUI
local UpdateCharacterIgnoreListUI

local function UpdateGUI()
  if not GUIFrame then return end

  if statusText then
    statusText:SetText("Auto-sell is currently: " .. (AUTOSELL_ENABLED and "|cff00ff00Enabled|r" or "|cffff0000Disabled|r"))
  end

    for q = 0, 7 do
    if qualityChecks[q] then
      qualityChecks[q]:SetChecked(AutoSellEverythingDB.sellQualities[q] == true)
    end
  end

  if tooltipCheck then
    tooltipCheck:SetChecked(AutoSellEverythingDB.showTooltipNote == true)
  end

  if UpdateGlobalIgnoreListUI then
    UpdateGlobalIgnoreListUI()
  end

  if UpdateCharacterIgnoreListUI then
    UpdateCharacterIgnoreListUI()
  end
end

local function AddIgnoredItemByID(id, listType)
  if not id then
    Print("Could not read item ID.")
    return
  end

  local tbl = GetIgnoreTable(listType)
  local label = GetIgnoreLabel(listType)

  if tbl[id] then
    Print(label .. " ignore already contains: " .. GetItemLinkFromID(id))
    return
  end

  tbl[id] = true
  Print(label .. " ignored: " .. GetItemLinkFromID(id))
  RefreshSellingState()
  UpdateGUI()
end

local function AddIgnoredItemFromText(text, listType)
  if not text or text == "" then
    Print("Enter an item ID or paste an item link.")
    return
  end

  local tbl = GetIgnoreTable(listType)
  local label = GetIgnoreLabel(listType)
  local added = 0

  for id in string.gmatch(text, "item:(%d+)") do
    id = tonumber(id)
    if id and not tbl[id] then
      tbl[id] = true
      Print(label .. " ignored: " .. GetItemLinkFromID(id))
      added = added + 1
    end
  end

  if added == 0 then
    local id = tonumber(text)
    if id then
      if tbl[id] then
        Print(label .. " ignore already contains: " .. GetItemLinkFromID(id))
      else
        tbl[id] = true
        Print(label .. " ignored: " .. GetItemLinkFromID(id))
        added = 1
      end
    else
      Print("Could not read item ID or item link.")
      return
    end
  end

  RefreshSellingState()
  UpdateGUI()

  if ignoreEditBox then
    ignoreEditBox:SetText("")
    ignoreEditBox:ClearFocus()
  end
end

local function RemoveIgnoredItemByID(id, listType)
  if not id then return end

  local tbl = GetIgnoreTable(listType)
  local label = GetIgnoreLabel(listType)

  if not tbl[id] then return end

  tbl[id] = nil
  Print(label .. " ignore removed: " .. GetItemLinkFromID(id))
  RefreshSellingState()
  UpdateGUI()
end

local function TryAddIgnoredItemFromCursor(listType)
  local kind, itemID, itemLink = GetCursorInfo()
  if kind ~= "item" then
    Print("Drag an item from your bags onto the drop target.")
    return
  end

  local id = tonumber(itemID) or GetItemIDFromLink(itemLink)
  if not id then
    Print("Could not read dragged item.")
    ClearCursor()
    return
  end

  AddIgnoredItemByID(id, listType)
  ClearCursor()
end

local function CreateIgnoreRow(parent, index, rowWidth, linkWidth, listType)
  local row = CreateFrame("Frame", nil, parent)
  row:SetWidth(rowWidth)
  row:SetHeight(22)

  row.bg = row:CreateTexture(nil, "BACKGROUND")
  row.bg:SetAllPoints(row)
  row.bg:SetTexture("Interface\\Buttons\\WHITE8X8")
  if math.fmod(index, 2) == 0 then
    row.bg:SetVertexColor(1, 1, 1, 0.04)
  else
    row.bg:SetVertexColor(1, 1, 1, 0.08)
  end

  row.linkButton = CreateFrame("Button", nil, row)
  row.linkButton:SetPoint("LEFT", 4, 0)
  row.linkButton:SetWidth(linkWidth)
  row.linkButton:SetHeight(20)

  row.linkText = row.linkButton:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  row.linkText:SetAllPoints(row.linkButton)
  row.linkText:SetJustifyH("LEFT")

  row.linkButton:SetScript("OnClick", function(self)
    if self.itemLink and ChatFrameEditBox then
      if not ChatFrameEditBox:IsShown() then
        ChatFrame_OpenChat("")
      end
      ChatFrameEditBox:Insert(self.itemLink)
    end
  end)

  row.removeButton = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
  row.removeButton:SetWidth(50)
  row.removeButton:SetHeight(18)
  row.removeButton:SetPoint("RIGHT", -4, 0)
  row.removeButton:SetText("Remove")
  row.removeButton:SetScript("OnClick", function(self)
    RemoveIgnoredItemByID(self.itemID, self.listType)
  end)
  row.removeButton.listType = listType

  row:Hide()
  return row
end

UpdateGlobalIgnoreListUI = function()
  if not globalIgnoreContent then return end

  local ids = GetSortedIgnoredIDs("global")
  local rowHeight = 22
  local neededRows = #ids

  while #globalIgnoreRows < neededRows do
    local row = CreateIgnoreRow(globalIgnoreContent, #globalIgnoreRows + 1, 220, 160, "global")
    if #globalIgnoreRows == 0 then
      row:SetPoint("TOPLEFT", 0, 0)
      row:SetPoint("TOPRIGHT", -18, 0)
    else
      row:SetPoint("TOPLEFT", globalIgnoreRows[#globalIgnoreRows], "BOTTOMLEFT", 0, -2)
      row:SetPoint("TOPRIGHT", globalIgnoreRows[#globalIgnoreRows], "BOTTOMRIGHT", 0, -2)
    end
    globalIgnoreRows[#globalIgnoreRows + 1] = row
  end

  for i, row in ipairs(globalIgnoreRows) do
    local id = ids[i]
    if id then
      local link = GetItemLinkFromID(id)
      row.itemID = id
      row.itemLink = link
      row.linkButton.itemLink = link
      row.linkText:SetText(link)
      row.removeButton.itemID = id
      row.removeButton.listType = "global"
      row:Show()
    else
      row.itemID = nil
      row.itemLink = nil
      row.linkButton.itemLink = nil
      row:Hide()
    end
  end

  globalIgnoreContent:SetHeight(math.max(1, neededRows * (rowHeight + 2)))
end

UpdateCharacterIgnoreListUI = function()
  if not characterIgnoreContent then return end

  local ids = GetSortedIgnoredIDs("character")
  local rowHeight = 22
  local neededRows = #ids

  while #characterIgnoreRows < neededRows do
    local row = CreateIgnoreRow(characterIgnoreContent, #characterIgnoreRows + 1, 220, 160, "character")
    if #characterIgnoreRows == 0 then
      row:SetPoint("TOPLEFT", 0, 0)
      row:SetPoint("TOPRIGHT", -18, 0)
    else
      row:SetPoint("TOPLEFT", characterIgnoreRows[#characterIgnoreRows], "BOTTOMLEFT", 0, -2)
      row:SetPoint("TOPRIGHT", characterIgnoreRows[#characterIgnoreRows], "BOTTOMRIGHT", 0, -2)
    end
    characterIgnoreRows[#characterIgnoreRows + 1] = row
  end

  for i, row in ipairs(characterIgnoreRows) do
    local id = ids[i]
    if id then
      local link = GetItemLinkFromID(id)
      row.itemID = id
      row.itemLink = link
      row.linkButton.itemLink = link
      row.linkText:SetText(link)
      row.removeButton.itemID = id
      row.removeButton.listType = "character"
      row:Show()
    else
      row.itemID = nil
      row.itemLink = nil
      row.linkButton.itemLink = nil
      row:Hide()
    end
  end

  characterIgnoreContent:SetHeight(math.max(1, neededRows * (rowHeight + 2)))
end

local function CreateGUI()
  if GUIFrame then return end

  local backdrop = {
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true,
    tileSize = 16,
    edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 }
  }

GUIFrame = CreateFrame("Frame", "AutoSellEverythingConfigFrame", UIParent)
GUIFrame:SetWidth(560)
GUIFrame:SetHeight(590)
GUIFrame:SetPoint("CENTER")
GUIFrame:SetBackdrop(backdrop)
GUIFrame:SetBackdropColor(0, 0, 0, 1)
GUIFrame:EnableMouse(true)
GUIFrame:SetMovable(true)
GUIFrame:RegisterForDrag("LeftButton")
GUIFrame:SetScript("OnDragStart", function(self) self:StartMoving() end)
GUIFrame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
table.insert(UISpecialFrames, "AutoSellEverythingConfigFrame")
GUIFrame:Hide()

  local title = GUIFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOP", 0, -12)
  title:SetText("AutoSellEverything")

  local subtitle = GUIFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  subtitle:SetPoint("TOP", title, "BOTTOM", 0, -4)
  subtitle:SetText("Wrath of the Lich King 3.3.5")

  local closeButton = CreateFrame("Button", nil, GUIFrame, "UIPanelCloseButton")
  closeButton:SetPoint("TOPRIGHT", -4, -4)

  statusText = GUIFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  statusText:SetPoint("TOPLEFT", 18, -42)
  statusText:SetText("")

  local enableCheck = CreateFrame("CheckButton", nil, GUIFrame, "UICheckButtonTemplate")
enableCheck:SetPoint("TOPLEFT", 18, -68)
enableCheck:SetChecked(AUTOSELL_ENABLED)

local enableLabel = GUIFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
enableLabel:SetPoint("LEFT", enableCheck, "RIGHT", 4, 1)
enableLabel:SetText("Enable auto-sell")

enableCheck:SetScript("OnClick", function(self)
  AUTOSELL_ENABLED = self:GetChecked() and true or false
  Print("Auto-sell " .. (AUTOSELL_ENABLED and "enabled" or "disabled") .. ".")
  RefreshSellingState()
  UpdateGUI()
end)

  local qualityHeader = GUIFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  qualityHeader:SetPoint("TOPLEFT", 18, -102)
  qualityHeader:SetText("Sell Qualities")

  local yBase = -126
  for q = 0, 7 do
    local col = (q < 4) and 0 or 1
    local row = (q < 4) and q or (q - 4)

local cb = CreateFrame("CheckButton", nil, GUIFrame, "UICheckButtonTemplate")
cb:SetPoint("TOPLEFT", 20 + (col * 210), yBase - (row * 26))
cb:SetChecked(AutoSellEverythingDB.sellQualities[q] == true)
cb.qualityID = q

local cbLabel = GUIFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
cbLabel:SetPoint("LEFT", cb, "RIGHT", 4, 1)
cbLabel:SetText(q .. " - " .. QUALITY_ID_TO_LABEL[q])

cb:SetScript("OnClick", function(self)
  if self:GetChecked() then
    AutoSellEverythingDB.sellQualities[self.qualityID] = true
  else
    AutoSellEverythingDB.sellQualities[self.qualityID] = nil
  end
  RefreshSellingState()
  UpdateGUI()
end)

qualityChecks[q] = cb
  end

  local allBtn = CreateFrame("Button", nil, GUIFrame, "UIPanelButtonTemplate")
  allBtn:SetWidth(80)
  allBtn:SetHeight(22)
  allBtn:SetPoint("TOPLEFT", 20, -240)
  allBtn:SetText("All")
  allBtn:SetScript("OnClick", function()
    SetAllQualities(true)
    RefreshSellingState()
    UpdateGUI()
    Print("Quality filter set: ALL.")
  end)

    local noneBtn = CreateFrame("Button", nil, GUIFrame, "UIPanelButtonTemplate")
  noneBtn:SetWidth(80)
  noneBtn:SetHeight(22)
  noneBtn:SetPoint("LEFT", allBtn, "RIGHT", 8, 0)
  noneBtn:SetText("None")
  noneBtn:SetScript("OnClick", function()
    SetAllQualities(false)
    RefreshSellingState()
    UpdateGUI()
    Print("Quality filter set: NONE.")
  end)

    tooltipCheck = CreateFrame("CheckButton", nil, GUIFrame, "UICheckButtonTemplate")
  tooltipCheck:SetPoint("TOPLEFT", 20, -262)
  tooltipCheck:SetChecked(AutoSellEverythingDB.showTooltipNote == true)

  local tooltipCheckLabel = GUIFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  tooltipCheckLabel:SetPoint("LEFT", tooltipCheck, "RIGHT", 4, 1)
  tooltipCheckLabel:SetText("Show ignore-list note on item tooltips")

  tooltipCheck:SetScript("OnClick", function(self)
    AutoSellEverythingDB.showTooltipNote = self:GetChecked() and true or nil
    UpdateGUI()
    Print("Tooltip ignore note " .. ((AutoSellEverythingDB.showTooltipNote and "enabled") or "disabled") .. ".")
  end)

  local ignoreHeader = GUIFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  ignoreHeader:SetPoint("TOPLEFT", 18, -312)
  ignoreHeader:SetText("Ignore Lists")

  local ignoreHelp = GUIFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  ignoreHelp:SetPoint("TOPLEFT", 20, -332)
ignoreHelp:SetText("Alt-Left adds Global, Alt-Right adds Character, Shift-Alt-Left removes Global, Shift-Alt-Right removes Character.")

  ignoreEditBox = CreateFrame("EditBox", "AutoSellEverythingIgnoreEditBox", GUIFrame, "InputBoxTemplate")
  ignoreEditBox:SetAutoFocus(false)
  ignoreEditBox:SetWidth(220)
  ignoreEditBox:SetHeight(24)
  ignoreEditBox:SetPoint("TOPLEFT", 20, -356)

  ignoreEditBox:SetScript("OnEnterPressed", function(self)
    AddIgnoredItemFromText(self:GetText(), "global")
    self:SetFocus()
    self:HighlightText()
  end)

  ignoreEditBox:SetScript("OnEscapePressed", function(self)
    self:ClearFocus()
  end)

  ignoreEditBox:SetScript("OnEditFocusGained", function(self)
    self:HighlightText()
  end)

  local addGlobalBtn = CreateFrame("Button", nil, GUIFrame, "UIPanelButtonTemplate")
  addGlobalBtn:SetWidth(82)
  addGlobalBtn:SetHeight(22)
  addGlobalBtn:SetPoint("LEFT", ignoreEditBox, "RIGHT", 8, 0)
  addGlobalBtn:SetText("Add Global")
  addGlobalBtn:SetScript("OnClick", function()
    AddIgnoredItemFromText(ignoreEditBox:GetText(), "global")
    ignoreEditBox:SetFocus()
    ignoreEditBox:HighlightText()
  end)

  local addCharacterBtn = CreateFrame("Button", nil, GUIFrame, "UIPanelButtonTemplate")
  addCharacterBtn:SetWidth(94)
  addCharacterBtn:SetHeight(22)
  addCharacterBtn:SetPoint("LEFT", addGlobalBtn, "RIGHT", 8, 0)
  addCharacterBtn:SetText("Add Character")
  addCharacterBtn:SetScript("OnClick", function()
    AddIgnoredItemFromText(ignoreEditBox:GetText(), "character")
    ignoreEditBox:SetFocus()
    ignoreEditBox:HighlightText()
  end)

  local listIgnoreBtn = CreateFrame("Button", nil, GUIFrame, "UIPanelButtonTemplate")
  listIgnoreBtn:SetWidth(70)
  listIgnoreBtn:SetHeight(22)
  listIgnoreBtn:SetPoint("LEFT", addCharacterBtn, "RIGHT", 8, 0)
  listIgnoreBtn:SetText("To Chat")
  listIgnoreBtn:SetScript("OnClick", function()
    PrintAllIgnoreLists()
  end)

  dragDropBox = CreateFrame("Button", nil, GUIFrame)
  dragDropBox:SetWidth(500)
  dragDropBox:SetHeight(34)
  dragDropBox:SetPoint("TOPLEFT", 20, -388)
  dragDropBox:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = false,
    edgeSize = 12,
    insets = { left = 2, right = 2, top = 2, bottom = 2 }
  })
  dragDropBox:SetBackdropColor(0.08, 0.08, 0.08, 0.9)
  dragDropBox:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)

  dragDropBox.text = dragDropBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  dragDropBox.text:SetPoint("CENTER", 0, 0)
  dragDropBox.text:SetText("Drag one item here to add it to the Global ignore list")

  dragDropBox:SetScript("OnReceiveDrag", function()
    TryAddIgnoredItemFromCursor("global")
  end)

  dragDropBox:SetScript("OnMouseUp", function()
    local kind = GetCursorInfo()
    if kind then
      TryAddIgnoredItemFromCursor("global")
    end
  end)

  local globalHeader = GUIFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  globalHeader:SetPoint("TOPLEFT", 20, -428)
  globalHeader:SetText("Global Ignore")

  globalIgnoreScrollFrame = CreateFrame("ScrollFrame", "AutoSellEverythingGlobalIgnoreScrollFrame", GUIFrame, "UIPanelScrollFrameTemplate")
  globalIgnoreScrollFrame:SetWidth(238)
  globalIgnoreScrollFrame:SetHeight(104)
  globalIgnoreScrollFrame:SetPoint("TOPLEFT", 20, -448)

  globalIgnoreContent = CreateFrame("Frame", nil, globalIgnoreScrollFrame)
  globalIgnoreContent:SetWidth(220)
  globalIgnoreContent:SetHeight(1)
  globalIgnoreScrollFrame:SetScrollChild(globalIgnoreContent)

  local characterHeader = GUIFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  characterHeader:SetPoint("TOPLEFT", 282, -428)
  characterHeader:SetText("Character Ignore")

  characterIgnoreScrollFrame = CreateFrame("ScrollFrame", "AutoSellEverythingCharacterIgnoreScrollFrame", GUIFrame, "UIPanelScrollFrameTemplate")
  characterIgnoreScrollFrame:SetWidth(238)
  characterIgnoreScrollFrame:SetHeight(104)
  characterIgnoreScrollFrame:SetPoint("TOPLEFT", 282, -448)

  characterIgnoreContent = CreateFrame("Frame", nil, characterIgnoreScrollFrame)
  characterIgnoreContent:SetWidth(220)
  characterIgnoreContent:SetHeight(1)
  characterIgnoreScrollFrame:SetScrollChild(characterIgnoreContent)

  local clearGlobalBtn = CreateFrame("Button", nil, GUIFrame, "UIPanelButtonTemplate")
  clearGlobalBtn:SetWidth(110)
  clearGlobalBtn:SetHeight(22)
  clearGlobalBtn:SetPoint("TOPLEFT", 20, -558)
  clearGlobalBtn:SetText("Clear Global")
  clearGlobalBtn:SetScript("OnClick", function()
    AutoSellEverythingDB.ignoreGlobal = {}
    Print("Global ignore list cleared.")
    RefreshSellingState()
    UpdateGUI()
  end)

    local clearCharacterBtn = CreateFrame("Button", nil, GUIFrame, "UIPanelButtonTemplate")
  clearCharacterBtn:SetWidth(122)
  clearCharacterBtn:SetHeight(22)
  clearCharacterBtn:SetPoint("TOPLEFT", 282, -558)
  clearCharacterBtn:SetText("Clear Character")
  clearCharacterBtn:SetScript("OnClick", function()
    AutoSellEverythingCharDB.ignoreCharacter = {}
    Print("Character ignore list cleared.")
    RefreshSellingState()
    UpdateGUI()
  end)

  UpdateGUI()
end

local function ToggleGUI()
  CreateGUI()
  if GUIFrame:IsShown() then
    GUIFrame:Hide()
  else
    UpdateGUI()
    GUIFrame:Show()
  end
end

frame:SetScript("OnEvent", function(self, event)
  if event == "MERCHANT_SHOW" then
    if AUTOSELL_ENABLED then
      StartSelling()
    end
  elseif event == "MERCHANT_CLOSED" then
    StopSelling()
  elseif event == "BAG_UPDATE" or event == "BAG_UPDATE_DELAYED" then
    if AUTOSELL_ENABLED and MerchantIsOpen() then
      ScanAllBags()
    end
  end
end)

local function AutoSellEverything_InsertLink(link)
  if not link or not ignoreEditBox or not ignoreEditBox:HasFocus() then
    return false
  end

  ignoreEditBox:Insert(link)
  return true
end

hooksecurefunc("ChatEdit_InsertLink", function(link)
  AutoSellEverything_InsertLink(link)
end)

local function AutoSellEverything_HookTooltip(tooltip)
  if not tooltip or tooltip.AutoSellEverythingTooltipHooked then return end

  tooltip:HookScript("OnHide", function(self)
    self.AutoSellEverythingNoteAdded = nil
  end)

  tooltip:HookScript("OnTooltipCleared", function(self)
    self.AutoSellEverythingNoteAdded = nil
  end)

  tooltip:HookScript("OnTooltipSetItem", function(self)
    self.AutoSellEverythingNoteAdded = nil

    local itemLink = select(2, self:GetItem())
    if itemLink then
      AutoSellEverything_AddTooltipNote(self, itemLink)
    end
  end)

  tooltip.AutoSellEverythingTooltipHooked = true
end

AutoSellEverything_HookTooltip(GameTooltip)
AutoSellEverything_HookTooltip(ItemRefTooltip)
ShoppingTooltip1 = ShoppingTooltip1 or _G["ShoppingTooltip1"]
ShoppingTooltip2 = ShoppingTooltip2 or _G["ShoppingTooltip2"]
if ShoppingTooltip1 then AutoSellEverything_HookTooltip(ShoppingTooltip1) end
if ShoppingTooltip2 then AutoSellEverything_HookTooltip(ShoppingTooltip2) end

local function AutoSellEverything_TryModifiedBagClick(button, bag, slot)
  if not IsAltKeyDown() then return end
  if CursorHasItem() then return end
  if bag == nil or slot == nil then return end

  local itemLink = GetContainerItemLink(bag, slot)
  if not itemLink then return end

  local itemID = GetItemIDFromLink(itemLink)
  if not itemID then return end

  local isShiftDown = IsShiftKeyDown()

  if button == "LeftButton" then
  if isShiftDown then
    RemoveIgnoredItemByID(itemID, "global")
  else
    AddIgnoredItemByID(itemID, "global")
  end
elseif button == "RightButton" then
  if isShiftDown then
    RemoveIgnoredItemByID(itemID, "character")
  else
    AddIgnoredItemByID(itemID, "character")
  end
end
end

hooksecurefunc("ContainerFrameItemButton_OnModifiedClick", function(self, button)
  if not self then return end

  local bag = self:GetParent() and self:GetParent():GetID()
  local slot = self:GetID()

  AutoSellEverything_TryModifiedBagClick(button, bag, slot)
end)

SLASH_AUTOSELLTOGGLE1 = "/astoggle"
SLASH_AUTOSELLTOGGLE2 = "/autoselltoggle"
SlashCmdList["AUTOSELLTOGGLE"] = function()
  AUTOSELL_ENABLED = not AUTOSELL_ENABLED
  Print("Auto-sell " .. (AUTOSELL_ENABLED and "enabled" or "disabled") .. ".")
  RefreshSellingState()
  UpdateGUI()
end

SLASH_AUTOSELLSTATUS1 = "/asstatus"
SlashCmdList["AUTOSELLSTATUS"] = function()
  Print("Status: " .. (AUTOSELL_ENABLED and "enabled" or "disabled") .. ".")
end

SLASH_AUTOSELLIGNORE1 = "/asignore"
SlashCmdList["AUTOSELLIGNORE"] = function(msg)
  msg = msg or ""
  local cmd, rest = msg:match("^(%S+)%s*(.*)$")
  cmd = cmd and cmd:lower() or ""

  local function ParseScopeAndValue(text)
    local first, remainder = text:match("^(%S+)%s*(.*)$")
    first = first and first:lower() or ""
    if first == "global" or first == "g" then
      return "global", remainder
    elseif first == "character" or first == "char" or first == "c" then
      return "character", remainder
    end
    return "global", text
  end

  if cmd == "add" and rest and rest ~= "" then
    local scope, value = ParseScopeAndValue(rest)
    AddIgnoredItemFromText(value, scope)

  elseif (cmd == "remove" or cmd == "del" or cmd == "delete") and rest and rest ~= "" then
    local scope, value = ParseScopeAndValue(rest)
    local id = tonumber(value) or GetItemIDFromLink(value)
    if not id then
      Print("Could not read item ID. Use: /asignore remove [global|character] <itemID> or paste an item link.")
      return
    end
    RemoveIgnoredItemByID(id, scope)

  elseif cmd == "list" then
    local scope = (rest and rest ~= "" and rest:lower()) or "all"
    if scope == "global" or scope == "g" then
      PrintIgnoreList("global")
    elseif scope == "character" or scope == "char" or scope == "c" then
      PrintIgnoreList("character")
    else
      PrintAllIgnoreLists()
    end

  elseif cmd == "clear" then
    local scope = (rest and rest ~= "" and rest:lower()) or "global"
    if scope == "character" or scope == "char" or scope == "c" then
      AutoSellEverythingCharDB.ignoreCharacter = {}
      Print("Character ignore list cleared.")
    else
      AutoSellEverythingDB.ignoreGlobal = {}
      Print("Global ignore list cleared.")
    end
    RefreshSellingState()
    UpdateGUI()

  else
    Print("Commands: /asignore add [global|character] <id|link>, /asignore remove [global|character] <id|link>, /asignore list [global|character], /asignore clear [global|character]")
  end
end

SLASH_AUTOSELLQUALITY1 = "/asquality"
SlashCmdList["AUTOSELLQUALITY"] = function(msg)
  msg = msg or ""
  local cmd, rest = msg:match("^(%S+)%s*(.*)$")
  cmd = cmd and cmd:lower() or ""

  local function PrintQualityList()
    local t = {}
    for q = 0, 7 do
      if AutoSellEverythingDB.sellQualities[q] then
        t[#t + 1] = q .. "(" .. QUALITY_ID_TO_LABEL[q] .. ")"
      end
    end
    if #t == 0 then
      Print("Sell qualities: (none)")
    else
      Print("Sell qualities: " .. table.concat(t, " "))
    end
  end

  if cmd == "" or cmd == "list" then
    PrintQualityList()
    return
  end

  if cmd == "all" then
    SetAllQualities(true)
    Print("Quality filter set: ALL.")
    PrintQualityList()
    RefreshSellingState()
    UpdateGUI()
    return
  end

  if cmd == "none" then
    SetAllQualities(false)
    Print("Quality filter set: NONE.")
    PrintQualityList()
    RefreshSellingState()
    UpdateGUI()
    return
  end

  if cmd == "set" then
    SetAllQualities(false)
    local enabled = 0
    for tok in (rest or ""):gmatch("%S+") do
      local q = ParseQualityToken(tok)
      if q ~= nil then
        if not AutoSellEverythingDB.sellQualities[q] then
          enabled = enabled + 1
        end
        AutoSellEverythingDB.sellQualities[q] = true
      end
    end
    Print("Quality filter set: " .. enabled .. " enabled.")
    PrintQualityList()
    RefreshSellingState()
    UpdateGUI()
    return
  end

  if cmd == "add" and rest and rest ~= "" then
    local q = ParseQualityToken(rest:match("^%S+"))
    if q == nil then
      Print("Usage: /asquality add <0-7|name>")
      return
    end
    AutoSellEverythingDB.sellQualities[q] = true
    Print("Enabled quality " .. q .. " (" .. QUALITY_ID_TO_LABEL[q] .. ").")
    RefreshSellingState()
    UpdateGUI()
    return
  end

  if (cmd == "remove" or cmd == "del" or cmd == "delete") and rest and rest ~= "" then
    local q = ParseQualityToken(rest:match("^%S+"))
    if q == nil then
      Print("Usage: /asquality remove <0-7|name>")
      return
    end
    AutoSellEverythingDB.sellQualities[q] = nil
    Print("Disabled quality " .. q .. " (" .. QUALITY_ID_TO_LABEL[q] .. ").")
    RefreshSellingState()
    UpdateGUI()
    return
  end

  Print("Commands: /asquality list | all | none | set <q...> | add <q> | remove <q>")
end

SLASH_AUTOSELLGUI1 = "/asgui"
SLASH_AUTOSELLGUI2 = "/autosellgui"
SlashCmdList["AUTOSELLGUI"] = function()
  ToggleGUI()
end