-- AnyReagent: an "at least one reagent in the bags" checkbox in the profession
-- window's Filter menu. Blizzard's own "have materials" filter keeps a recipe
-- only when EVERY reagent is in the bags; this one keeps it as soon as one
-- required reagent is there.
--
-- Rows are taken out of the list Blizzard built with the tree's own node:Remove
-- (no invalidation per node, one Invalidate at the end), and only the nodes this
-- addon removed are put back: another addon filtering the same list (CraftProfit)
-- keeps its own hidden rows. A category this filter emptied loses its header, and
-- a node left with no row at all loses its padding rows; the unlearned divider
-- goes when no unlearned category is left.
local addonName, ns = ...

local DB_NAME = "AnyReagentDB"
local CHAT_PREFIX = "[AnyReagent] "
local MENU_TITLE = "AnyReagent"

-- Player-facing text: English keys, French on a frFR client. A missing key
-- shows the key itself.
local FRENCH = {
	["At least one reagent in the bags"] = "Au moins un composant dans les sacs",
	["Click: turn the filter on / off"] = "Clic : activer / désactiver le filtre",
	["Filter on"] = "Filtre activé",
	["Filter off"] = "Filtre désactivé",
	["filter error: %s"] = "filtre en erreur : %s",
	["cannot refresh the list: %s"] = "rafraîchissement impossible : %s",
	["settings not loaded yet, try again in a moment."] = "réglages pas encore chargés, réessaie dans un instant.",
}
local function IsFrench()
	if type(GetLocale) ~= "function" then return false end
	local ok, locale = pcall(GetLocale)
	return ok and locale == "frFR"
end
local L = setmetatable(IsFrench() and FRENCH or {}, { __index = function(_, key) return key end })

local MENU_LABEL = L["At least one reagent in the bags"]
local MENU_HINT = L["Click: turn the filter on / off"]

local hiddenFor, hiddenList -- data provider on screen, { { parent, node, index }, ... }

local RefilterList -- defined with the list, used by every entry point

local function Print(message)
	if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
		DEFAULT_CHAT_FRAME:AddMessage(CHAT_PREFIX .. tostring(message))
	end
end

local function EnsureDB()
	if type(_G[DB_NAME]) ~= "table" then _G[DB_NAME] = {} end
	local db = _G[DB_NAME]
	if type(db.enabled) ~= "boolean" then db.enabled = false end -- off until asked for
	ns.db = db
end

local function IsEnabled()
	return ns.db ~= nil and ns.db.enabled == true
end

-----------------------------------------------------------------------------
-- What a recipe needs, and how much of it the bags hold
-----------------------------------------------------------------------------

local function BasicReagentType()
	return (Enum and Enum.CraftingReagentType and Enum.CraftingReagentType.Basic) or 0
end

local function NodeData(node)
	if not node then return nil end
	if type(node.GetData) == "function" then return node:GetData() end
	return node.data or node
end

-- Bags and the reagent bag only: the bank is not what you craft from. Any
-- value the client refuses to hand over counts as nothing.
local function ItemCount(itemID)
	if type(itemID) ~= "number" then return 0 end
	local count
	local api = C_Item
	if type(api) == "table" and type(api.GetItemCount) == "function" then
		local ok, value = pcall(api.GetItemCount, itemID, false, false, true)
		if ok and type(value) == "number" then count = value end
	end
	if count == nil and type(GetItemCount) == "function" then
		local ok, value = pcall(GetItemCount, itemID)
		if ok and type(value) == "number" then count = value end
	end
	return count or 0
end

-- itemIDs of every required basic reagent slot of a schematic, cached per recipe
-- (reagents do not change during a session). An empty table means "no reagent
-- slot"; nil means "the client could not tell us".
local schematicSlots = {}

local function ReagentSlots(recipeID)
	local cached = schematicSlots[recipeID]
	if cached then return cached end
	local api = C_TradeSkillUI
	if type(api) ~= "table" or type(api.GetRecipeSchematic) ~= "function" then return nil end
	local ok, schematic = pcall(api.GetRecipeSchematic, recipeID, false)
	if not ok or type(schematic) ~= "table" then return nil end
	local basic, slots = BasicReagentType(), {}
	for _, slot in ipairs(schematic.reagentSlotSchematics or {}) do
		local kind = slot.reagentType
		if (kind == nil or kind == basic) and slot.required ~= false then
			local items = {}
			for _, reagent in ipairs(slot.reagents or {}) do
				if type(reagent.itemID) == "number" then items[#items + 1] = reagent.itemID end
			end
			if #items > 0 then slots[#slots + 1] = items end
		end
	end
	schematicSlots[recipeID] = slots
	return slots
end

-- Whether a recipe keeps its row: as soon as one reagent of one required slot is
-- in the bags. A recipe with no reagent slot, or one the client cannot describe,
-- is never hidden.
local function HasReagent(recipeID)
	local slots = ReagentSlots(recipeID)
	if not slots or #slots == 0 then return true end
	for _, items in ipairs(slots) do
		for _, itemID in ipairs(items) do
			if ItemCount(itemID) >= 1 then return true end
		end
	end
	return false
end

-----------------------------------------------------------------------------
-- Rows
-----------------------------------------------------------------------------

-- Puts every node this filter took out of `dataProvider` back, in place thanks to
-- the parent's own comparator. Returns the nodes that were hidden (a set) or nil.
local function RestoreHidden(dataProvider)
	local hidden = hiddenFor == dataProvider and hiddenList or nil
	hiddenFor, hiddenList = nil, nil
	if not hidden then return nil end
	local was, parents = {}, {}
	for i = #hidden, 1, -1 do -- reverse order: a header goes back before the rows taken out of it
		local h = hidden[i]
		local nodes = h.parent:GetNodes()
		table.insert(nodes, math.min(h.index, #nodes + 1), h.node)
		parents[h.parent] = true
		was[h.node] = true
	end
	for parent in pairs(parents) do
		if parent.sortComparator then table.sort(parent:GetNodes(), parent.sortComparator) end
	end
	return was
end

local function Hide(parent, child, hidden)
	for index, node in ipairs(parent:GetNodes()) do
		if node == child then
			parent:Remove(child, true) -- TreeNodeMixin:Remove(node, skipInvalidation)
			hidden[#hidden + 1] = { parent = parent, node = child, index = index }
			return
		end
	end
end

-- Hides the recipes without a reagent under `node` (the root or a category), depth
-- first. Returns whether the node still shows a recipe, and whether this filter
-- removed anything below it.
local function FilterNode(node, hidden)
	local drop, paddings = {}, {}
	local hasRecipe, hasCategory, removed = false, false, false
	for _, child in ipairs(node:GetNodes() or {}) do
		local data = NodeData(child)
		if data and data.categoryInfo then
			local shows, sub = FilterNode(child, hidden)
			removed = removed or sub
			if shows or not sub then hasCategory = true else drop[#drop + 1] = child end
		elseif data and data.recipeInfo and data.recipeInfo.recipeID then
			if HasReagent(data.recipeInfo.recipeID) then hasRecipe = true else drop[#drop + 1] = child end
		elseif data and (data.topPadding or data.bottomPadding) then
			paddings[#paddings + 1] = child
		end
	end
	if #drop > 0 then removed = true end
	if removed and not hasRecipe and not hasCategory then
		for _, child in ipairs(paddings) do drop[#drop + 1] = child end
	end
	for _, child in ipairs(drop) do Hide(node, child, hidden) end
	return hasRecipe or hasCategory, removed
end

-- Applies (or removes) the filter on a recipe list data provider. Returns true
-- when the visible rows changed.
local function ApplyFilter(dataProvider)
	if not dataProvider then return false end
	local want = IsEnabled()
	if not want and hiddenFor ~= dataProvider then return false end
	if type(dataProvider.GetRootNode) ~= "function" then return false end
	local changed = false
	local ok, err = pcall(function()
		local was = RestoreHidden(dataProvider)
		local hidden = {}
		if want then
			hiddenFor, hiddenList = dataProvider, hidden -- recorded as we go, so an error cannot lose rows
			local root = dataProvider:GetRootNode()
			local _, removed = FilterNode(root, hidden)
			-- the unlearned divider only makes sense above an unlearned category
			if removed then
				local divider, unlearned
				for _, child in ipairs(root:GetNodes() or {}) do
					local data = NodeData(child)
					if data and data.isDivider then divider = child end
					if data and data.categoryInfo and data.categoryInfo.unlearned then unlearned = true end
				end
				if divider and not unlearned then Hide(root, divider, hidden) end
			end
		end
		if #hidden == 0 then hiddenFor, hiddenList = nil, nil end
		-- changed unless exactly the same rows were hidden again
		local same = (was ~= nil) == (#hidden > 0)
		if same and was then
			local count = 0
			for _ in pairs(was) do count = count + 1 end
			same = count == #hidden
			for _, h in ipairs(hidden) do
				if not was[h.node] then same = false break end
			end
		end
		changed = not same
	end)
	-- once per session: the bag refresh would repeat the same error on every loot
	if not ok and not ns.warned then
		ns.warned = true
		Print(L["filter error: %s"]:format(tostring(err)))
	end
	if changed and type(dataProvider.Invalidate) == "function" then
		local okInvalidate, errInvalidate = pcall(dataProvider.Invalidate, dataProvider)
		if not okInvalidate then Print(L["cannot refresh the list: %s"]:format(tostring(errInvalidate))) end
	end
	return changed
end

-- Blizzard's "no results" line follows what is really left in the list.
local function UpdateNoResultsText(dataProvider)
	if type(dataProvider) ~= "table" or type(dataProvider.IsEmpty) ~= "function" then return end
	local list = ProfessionsFrame and ProfessionsFrame.CraftingPage and ProfessionsFrame.CraftingPage.RecipeList
	if not list or not list.NoResultsText then return end
	local ok, empty = pcall(dataProvider.IsEmpty, dataProvider)
	if ok then list.NoResultsText:SetShown(empty and true or false) end
end

-- Re-filters the list that is on screen (no rebuild).
RefilterList = function()
	local page = ProfessionsFrame and ProfessionsFrame.CraftingPage
	local list = page and page.RecipeList
	local scrollBox = list and list.ScrollBox
	if not scrollBox or type(scrollBox.GetDataProvider) ~= "function" then return false end
	local dataProvider = scrollBox:GetDataProvider()
	if not ApplyFilter(dataProvider) then return false end
	UpdateNoResultsText(dataProvider)
	return true
end

-- Shared by the Filter menu checkbox, the addon compartment and /anyreagent.
function ns.SetEnabled(enabled)
	enabled = enabled and true or false
	if type(ns.db) ~= "table" then return end
	ns.db.enabled = enabled
	RefilterList()
	Print((enabled and L["Filter on"] or L["Filter off"]) .. ".")
end

-----------------------------------------------------------------------------
-- Setup
-----------------------------------------------------------------------------

local ready = false

local function Setup()
	if ready then return end
	if not ProfessionsFrame or not ProfessionsFrame.CraftingPage then return end
	local list = ProfessionsFrame.CraftingPage.RecipeList
	if not list or not list.ScrollBox then return end
	ready = true

	-- Every rebuild hands a new data provider to the list: filter it as it arrives.
	hooksecurefunc(list.ScrollBox, "SetDataProvider", function(_, dataProvider)
		if ApplyFilter(dataProvider) then UpdateNoResultsText(dataProvider) end
	end)

	if Menu and type(Menu.ModifyMenu) == "function" then
		pcall(Menu.ModifyMenu, "MENU_PROFESSIONS_FILTER", function(_, root)
			root:CreateDivider()
			root:CreateTitle(MENU_TITLE)
			root:CreateCheckbox(MENU_LABEL, IsEnabled, function() ns.SetEnabled(not IsEnabled()) end)
		end)
	end

	-- The list may already be built: filter it now.
	RefilterList()
end

local function OnEvent(_, event, ...)
	if event == "ADDON_LOADED" then
		local name = ...
		if name == addonName then EnsureDB() end
		if name == "Blizzard_Professions" then Setup() end
	elseif event == "PLAYER_LOGIN" then
		if ns.db == nil then EnsureDB() end
		-- our addon is not load-on-demand, Blizzard_Professions may have loaded first
		local api = C_AddOns
		if type(api) == "table" and type(api.IsAddOnLoaded) == "function" then
			local ok, loaded = pcall(api.IsAddOnLoaded, "Blizzard_Professions")
			if ok and loaded then Setup() end
		end
	elseif event == "TRADE_SKILL_SHOW" then
		Setup()
	elseif event == "BAG_UPDATE_DELAYED" then
		if ProfessionsFrame and type(ProfessionsFrame.IsShown) == "function" and ProfessionsFrame:IsShown() then
			RefilterList()
		end
	end
end

if type(CreateFrame) == "function" then
	local frame = CreateFrame("Frame", addonName .. "EventFrame")
	if frame then
		for _, event in ipairs({ "ADDON_LOADED", "PLAYER_LOGIN", "TRADE_SKILL_SHOW", "BAG_UPDATE_DELAYED" }) do
			frame:RegisterEvent(event)
		end
		frame:SetScript("OnEvent", OnEvent)
	end
end

if SlashCmdList then
	SLASH_ANYREAGENT1 = "/anyreagent"
	SlashCmdList["ANYREAGENT"] = function()
		if type(ns.db) ~= "table" then
			Print(L["settings not loaded yet, try again in a moment."])
			return
		end
		ns.SetEnabled(not IsEnabled())
	end
end

-----------------------------------------------------------------------------
-- Addon compartment (## AddonCompartmentFunc* in the toc)
-----------------------------------------------------------------------------

local function ShowTooltip(owner)
	if not GameTooltip or type(ns.db) ~= "table" then return end
	GameTooltip:SetOwner(owner, "ANCHOR_LEFT")
	GameTooltip:AddLine(MENU_TITLE)
	GameTooltip:AddLine(IsEnabled() and L["Filter on"] or L["Filter off"], 0.5, 0.8, 1)
	GameTooltip:AddLine(MENU_HINT, 1, 1, 1)
	GameTooltip:Show()
end

function AnyReagent_OnAddonCompartmentClick()
	if type(ns.db) ~= "table" then return end
	ns.SetEnabled(not IsEnabled())
end

function AnyReagent_OnAddonCompartmentEnter(_, menuButton)
	ShowTooltip(menuButton)
end

function AnyReagent_OnAddonCompartmentLeave()
	if GameTooltip then GameTooltip:Hide() end
end
