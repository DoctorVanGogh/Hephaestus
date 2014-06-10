-----------------------------------------------------------------------------------------------
-- Client Lua Script for TradeskillSchematics
-- Copyright (c) NCsoft. All rights reserved
-- Additions for multi item crafting Copyright 2014 by DoctorVanGogh on Wildstar Forums
-----------------------------------------------------------------------------------------------

require "Window"
require "CraftingLib"
require "AchievementsLib"
require "GameLib"

local TradeskillSchematics = {}

local karPowerCoreTierToString =
{
	[CraftingLib.CodeEnumTradeskillTier.Novice] 	= Apollo.GetString("CRB_Tradeskill_Quartz"),
	[CraftingLib.CodeEnumTradeskillTier.Apprentice] = Apollo.GetString("CRB_Tradeskill_Sapphire"),
	[CraftingLib.CodeEnumTradeskillTier.Journeyman] = Apollo.GetString("CRB_Tradeskill_Diamond"),
	[CraftingLib.CodeEnumTradeskillTier.Artisan] 	= Apollo.GetString("CRB_Tradeskill_Chrysalus"),
	[CraftingLib.CodeEnumTradeskillTier.Expert] 	= Apollo.GetString("CRB_Tradeskill_Starshard"),
	[CraftingLib.CodeEnumTradeskillTier.Master] 	= Apollo.GetString("CRB_Tradeskill_Hybrid"),
}

local kTradeskillIdToIcon =
{
	[CraftingLib.CodeEnumTradeskill.Survivalist]	=	"IconSprites:Icon_Achievement_UI_Tradeskills_Survivalist",
	[CraftingLib.CodeEnumTradeskill.Architect]		=	"IconSprites:Icon_Achievement_UI_Tradeskills_Architect",
	[CraftingLib.CodeEnumTradeskill.Fishing]		=	"",
	[CraftingLib.CodeEnumTradeskill.Mining]			=	"IconSprites:Icon_Achievement_UI_Tradeskills_Miner",
	[CraftingLib.CodeEnumTradeskill.Relic_Hunter]	=	"IconSprites:Icon_Achievement_UI_Tradeskills_RelicHunter",
	[CraftingLib.CodeEnumTradeskill.Cooking]		=	"IconSprites:Icon_Achievement_UI_Tradeskills_Cooking",
	[CraftingLib.CodeEnumTradeskill.Outfitter]		=	"IconSprites:Icon_Achievement_UI_Tradeskills_Outfitter",
	[CraftingLib.CodeEnumTradeskill.Armorer]		=	"IconSprites:Icon_Achievement_UI_Tradeskills_Armorer",
	[CraftingLib.CodeEnumTradeskill.Farmer]			=	"IconSprites:Icon_Achievement_UI_Tradeskills_Farmer",
	[CraftingLib.CodeEnumTradeskill.Weaponsmith]	=	"IconSprites:Icon_Achievement_UI_Tradeskills_WeaponCrafting",
	[CraftingLib.CodeEnumTradeskill.Tailor]			=	"IconSprites:Icon_Achievement_UI_Tradeskills_Tailor",
	[CraftingLib.CodeEnumTradeskill.Runecrafting]	=	"",
	[CraftingLib.CodeEnumTradeskill.Augmentor]		=	"IconSprites:Icon_Achievement_UI_Tradeskills_Technologist",
}

local Queue = {}

local CraftQueue = {}


function TradeskillSchematics:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self
    return o
end

function TradeskillSchematics:Init()
    Apollo.RegisterAddon(self)
end

function TradeskillSchematics:OnSave(eType)
	if eType ~= GameLib.CodeEnumAddonSaveLevel.Character then
		return
	end
	local tSavedData = self.tSavedData or {}
	return tSavedData
end

function TradeskillSchematics:OnRestore(eType, tSavedData)
	if eType ~= GameLib.CodeEnumAddonSaveLevel.Character then
		return
	end
	self.tSavedData = tSavedData
end

function TradeskillSchematics:OnLoad()
	self.xmlDoc = XmlDoc.CreateFromFile("TradeskillSchematics.xml")
	self.xmlDoc:RegisterCallback("OnDocumentReady", self)
end

function TradeskillSchematics:OnDocumentReady()
	if self.xmlDoc == nil then
		return
	end

    Apollo.RegisterEventHandler("GenericEvent_InitializeSchematicsTree", "Initialize", self)

	Apollo.RegisterTimerHandler("Tradeskills_TimerCraftingStationCheck", "OnTimerCraftingStationCheck", self)
	Apollo.CreateTimer("Tradeskills_TimerCraftingStationCheck", 1, true)
	
	self.wndQueue = Apollo.LoadForm(self.xmlDoc, "AutocraftQueue", nil, self)
	self.wndQueue:Show(false, true)
		
	local tCraftQueue = CraftQueue.new()
	tCraftQueue:GetChangedHandlers():Add(self, "RecreateQueue")
	tCraftQueue:GetItemChangedHandlers():Add(self, "RefreshQueueItem")
	tCraftQueue:GetItemRemovedHandlers():Add(self, "RemovedQueueItem")	
	
	self.wndQueue:SetData(tCraftQueue)
	
	xxcc = self.wndQueue
	
	Apollo.RegisterSlashCommand("ac", "OnAutoCraft", self)
end

function TradeskillSchematics:Initialize(wndParent, nSchematicId, strSearchQuery)
	if not self.wndMain or not self.wndMain:IsValid() then
		Apollo.RegisterEventHandler("UpdateInventory", 				"OnUpdateInventory", self) -- TODO: Analyze performance
		Apollo.RegisterEventHandler("CraftingSchematicLearned", 	"OnCraftingSchematicLearned", self)
		Apollo.RegisterEventHandler("TradeSkills_Learned", 			"OnTradeSkills_Learned", self)
		Apollo.RegisterEventHandler("TradeskillLearnedFromTHOR", 	"OnTradeSkills_Learned", self)

		if self.tSavedData == nil then
			self.tSavedData = {}
		end

		if self.tSavedData.bFilterLocked == nil then
			self.tSavedData.bFilterLocked = false
		end

		if self.tSavedData.bFilterMats == nil then
			self.tSavedData.bFilterMats = false
		end

		self.wndMain = Apollo.LoadForm(self.xmlDoc, "TradeskillSchematicsForm", wndParent, self)
		self.wndMain:FindChild("LeftSideFilterLocked"):SetCheck(self.tSavedData.bFilterLocked)
		self.wndMain:FindChild("LeftSideFilterMaterials"):SetCheck(self.tSavedData.bFilterMats)

		self.wndLastBottomItemBtnBlue = nil
		self.bCoordCraft = false

		local wndMeasure = Apollo.LoadForm(self.xmlDoc, "TopLevel", nil, self)
		self.knTopLevelHeight = wndMeasure:GetHeight()
		wndMeasure:Destroy()

		wndMeasure = Apollo.LoadForm(self.xmlDoc, "MiddleLevel", nil, self)
		self.knMiddleLevelHeight = wndMeasure:GetHeight()
		wndMeasure:Destroy()

		wndMeasure = Apollo.LoadForm(self.xmlDoc, "BottomItem", nil, self)
		self.knBottomLevelHeight = wndMeasure:GetHeight()
		wndMeasure:Destroy()
				
		local wndDropdown = self.wndMain:FindChild("AddQueueDropdown")
		self.wndDropdownRepeats = wndDropdown:GetChildren()[1]
		
		wndDropdown:AttachWindow(self.wndDropdownRepeats)		
	end

	self:FullRedraw(nSchematicId)

	local tSchematic = self.wndMain:FindChild("RightSide"):GetData() -- Won't be set at initialize
	if tSchematic then
		self:DrawSchematic(tSchematic)
	end

	if strSearchQuery and string.len(strSearchQuery) > 0 then
		self.wndMain:FindChild("SearchTopLeftInputBox"):SetText(strSearchQuery)
		self:OnSearchTopLeftInputBoxChanged()
	end
end

function TradeskillSchematics:OnUpdateInventory()
	if not self.wndMain or not self.wndMain:IsValid() or not self.wndMain:IsVisible() then -- IsVisible() will consider parents as well
		return
	end

	self:FullRedraw(nSchematicId)
	local tSchematic = self.wndMain:FindChild("RightSide"):GetData() -- Won't be set at initialize
	if tSchematic then
		self:DrawSchematic(tSchematic)
	end
end

function TradeskillSchematics:OnTradeSkills_Learned()
	if self.wndMain and self.wndMain:IsValid() then
		self.wndMain:FindChild("LeftSideScroll"):DestroyChildren()
		self.wndMain:FindChild("RightSide"):SetData(nil)
		self.wndMain:FindChild("RightSide"):Show(false)
		self:FullRedraw()
	end
end

function TradeskillSchematics:OnCraftingSchematicLearned()
	if self.wndMain and self.wndMain:IsValid() then
		self.wndMain:FindChild("RightSide"):Show(false)
		self:FullRedraw()
	end
end

function TradeskillSchematics:RedrawFromUI(wndHandler, wndControl)
	self:FullRedraw()
end

function TradeskillSchematics:FullRedraw(nSchematicIdToOpen)
	-- Prebuild list
	local tTradeskills = {}
	for idx, tCurrTradeskill in ipairs(CraftingLib.GetKnownTradeskills()) do
		local tCurrTradeskillInfo = CraftingLib.GetTradeskillInfo(tCurrTradeskill.eId)
		if not tCurrTradeskillInfo.bIsHarvesting and idx ~= CraftingLib.CodeEnumTradeskill.Runecrafting then
			table.insert(tTradeskills, { tCurrTradeskill, tCurrTradeskillInfo })
		end
	end

	-- Since our top level is "Apprentice Weapon", "Novice Weapon" we use nTierIdx as the index instead of tTradeskill.id
	for idx, tCurrData in ipairs(tTradeskills) do
		local tCurrTradeskill = tCurrData[1]
		local tCurrTradeskillInfo = tCurrData[2]
		if tCurrTradeskillInfo.bIsHobby then
			local wndTop = self:LoadByName("TopLevel", self.wndMain:FindChild("LeftSideScroll"), tCurrTradeskill.eId)
			wndTop:FindChild("TopLevelBtnText"):SetText(tCurrTradeskill.strName)
			wndTop:FindChild("TopLevelIcon"):SetSprite(kTradeskillIdToIcon[tCurrTradeskill.eId])
			wndTop:FindChild("TopLevelBtn"):SetData({ tCurrTradeskill.eId, 0 }) -- ID is needed for GetSchematicList()

		elseif tCurrTradeskillInfo.bIsActive then
			local tMiddleCategories = AchievementsLib.GetTradeskillAchievementCategoryTree(tCurrTradeskill.eId)
			if tMiddleCategories then
				for nTierIdx = tCurrTradeskillInfo.eTier, 1, -1 do -- Start at current, then count down
					local tTier = tMiddleCategories.tSubGroups[nTierIdx]
					local wndTop = self:LoadByName("TopLevel", self.wndMain:FindChild("LeftSideScroll"), tTier.nSubGroupId)
					wndTop:FindChild("TopLevelBtnText"):SetText(tTier.strSubGroupName)
					wndTop:FindChild("TopLevelIcon"):SetSprite(kTradeskillIdToIcon[tCurrTradeskill.eId])
					wndTop:FindChild("TopLevelBtn"):SetData({ tCurrTradeskill.eId, nTierIdx }) -- ID is needed for GetSchematicList()
				end
			end
		end
	end

	local function HelperSortSchematicList(a, b)
		if not a or not b then -- TODO: Can be potentially nil?
			return true
		end

		if a.strItemTypeName and b.strItemTypeName and a.strItemTypeName == b.strItemTypeName then
			return a.strName < b.strName
		else
			return a.strItemTypeName < b.strItemTypeName
		end
	end

	-- Build the rest of the list if buttons are checked
	local tWndAndSchematicList = {}
	local bFilterLocked = self.wndMain:FindChild("LeftSideFilterLocked"):IsChecked()
	local bFilterMaterials = self.wndMain:FindChild("LeftSideFilterMaterials"):IsChecked()
	for idx, wndTop in pairs(self.wndMain:FindChild("LeftSideScroll"):GetChildren()) do
		local tTopLevelBtnData = wndTop:FindChild("TopLevelBtn"):GetData() -- {tCurrTradeskill.id, nIterationIdx}
		local tSchematicList = CraftingLib.GetSchematicList(tTopLevelBtnData[1], nil, tTopLevelBtnData[2], bFilterLocked)

		table.sort(tSchematicList, HelperSortSchematicList)
		tWndAndSchematicList[idx] = { wndTop, tSchematicList }
	end

	-- Iterate again, with a sorted and filtered list
	for idx, tData in pairs(tWndAndSchematicList) do
		local wndTop = tData[1]
		local tSchematicList = tData[2]
		for idx2, tSchematic in pairs(tSchematicList) do
			-- If told to open to a specific schematic
			if nSchematicIdToOpen then
				if nSchematicIdToOpen == tSchematic.nSchematicId then
					self.wndMain:FindChild("RightSide"):SetData(tSchematic)
					-- Redraw will occur right after and pick this up
				end
				wndTop:FindChild("TopLevelBtn"):SetCheck(false)
			end

			-- Main drawing
			local bHaveMaterials, bValidOneUse = self:HelperHaveEnoughMaterials(tSchematic)
			if bValidOneUse and (bHaveMaterials or not bFilterMaterials) then
				local wndMiddle = self:LoadByName("MiddleLevel", wndTop:FindChild("TopLevelItems"), "M"..tSchematic.eItemType) -- So we don't run into ID collisions
				wndMiddle:FindChild("MiddleLevelBtnText"):SetText(tSchematic.strItemTypeName)

				if wndMiddle:FindChild("MiddleLevelBtn"):IsChecked() then
					-- If we only draw the matching itemType then a filter updates needs a full redraw
					local bShowLock = not tSchematic.bIsKnown and not tSchematic.bIsOneUse
					local bShowMatsWarning = not bShowLock and not bHaveMaterials -- Implicit: If filtering by materials, this icon never shows
					local bOneTime = not bShowLock and bHaveMaterials and tSchematic.bIsOneUse
					local wndBottomItem = self:LoadByName("BottomItem", wndMiddle:FindChild("MiddleLevelItems"), "B"..tSchematic.nSchematicId)
					wndBottomItem:FindChild("BottomItemBtn"):SetData(tSchematic)
					wndBottomItem:FindChild("BottomItemBtnText"):SetText(tSchematic.strName)
					wndBottomItem:FindChild("BottomItemLockIcon"):Show(bShowLock)
					wndBottomItem:FindChild("BottomItemOneTimeIcon"):Show(bOneTime)
					wndBottomItem:FindChild("BottomItemMatsWarningIcon"):Show(bShowMatsWarning)
				end
			end
		end
	end

	-- Clean anything without children
	for idx, wndTop in pairs(self.wndMain:FindChild("LeftSideScroll"):GetChildren()) do
		if wndTop:FindChild("TopLevelItems") and #wndTop:FindChild("TopLevelItems"):GetChildren() == 0 then
			wndTop:Destroy()
		end
	end

	self:ResizeTree()
end

function TradeskillSchematics:ResizeTree()
	for key, wndTop in pairs(self.wndMain:FindChild("LeftSideScroll"):GetChildren()) do
		local nTopHeight = 25
		if wndTop:FindChild("TopLevelBtn"):IsChecked() then
			for key2, wndMiddle in pairs(wndTop:FindChild("TopLevelItems"):GetChildren()) do
				if wndMiddle:FindChild("MiddleLevelBtn"):IsChecked() then
					for key3, wndBot in pairs(wndMiddle:FindChild("MiddleLevelItems"):GetChildren()) do
						local wndBottomLevelBtnText = wndBot:FindChild("BottomItemBtn:BottomItemBtnText")
						if Apollo.GetTextWidth("CRB_InterfaceMedium_B", wndBottomLevelBtnText:GetText()) > wndBottomLevelBtnText:GetWidth() then -- TODO QUICK HACK
							local nBottomLeft, nBottomTop, nBottomRight, nBottomBottom = wndBot:GetAnchorOffsets()
							wndBot:SetAnchorOffsets(nBottomLeft, nBottomTop, nBottomRight, nBottomTop + (self.knBottomLevelHeight * 1.5))
						end
					end
				else
					wndMiddle:FindChild("MiddleLevelItems"):DestroyChildren()
				end

				local nMiddleHeight = wndMiddle:FindChild("MiddleLevelItems"):ArrangeChildrenVert(0)
				if nMiddleHeight > 0 then
					nMiddleHeight = nMiddleHeight + 15
				end

				local nLeft, nTop, nRight, nBottom = wndMiddle:GetAnchorOffsets()
				wndMiddle:SetAnchorOffsets(nLeft, nTop, nRight, nTop + self.knMiddleLevelHeight + nMiddleHeight)
				wndMiddle:FindChild("MiddleLevelItems"):ArrangeChildrenVert(0)
				nTopHeight = nTopHeight + nMiddleHeight
			end
		else
			wndTop:FindChild("TopLevelItems"):DestroyChildren()
			nTopHeight = 0
		end

		local nMiddleHeight = #wndTop:FindChild("TopLevelItems"):GetChildren() * self.knMiddleLevelHeight
		local nLeft, nTop, nRight, nBottom = wndTop:GetAnchorOffsets()
		wndTop:SetAnchorOffsets(nLeft, nTop, nRight, nTop + self.knTopLevelHeight + nMiddleHeight + nTopHeight)
		wndTop:FindChild("TopLevelItems"):ArrangeChildrenVert(0)
	end

	self.wndMain:FindChild("LeftSideScroll"):ArrangeChildrenVert(0)
	self.wndMain:FindChild("LeftSideScroll"):RecalculateContentExtents()
end

-----------------------------------------------------------------------------------------------
-- Random UI Buttons and Main Draw Method
-----------------------------------------------------------------------------------------------

function TradeskillSchematics:OnTimerCraftingStationCheck()
	if not self.wndMain or not self.wndMain:IsValid() then
		return
	end

	local tSchematicInfo = nil
	local tSchematic = self.wndMain:FindChild("RightSide"):GetData()
	if tSchematic then
		tSchematicInfo = CraftingLib.GetSchematicInfo(tSchematic.nSchematicId)
	end

	local bIsAutoCraft = tSchematicInfo and tSchematicInfo.bIsAutoCraft
	local bIsAtCraftingStation = CraftingLib.IsAtCraftingStation()
	self.wndMain:FindChild("RightBottomCraftBtn"):Show(not bIsAutoCraft)	
	self.wndMain:FindChild("RightBottomSimpleCraft"):Show(bIsAutoCraft and bIsAtCraftingStation)
	self.wndMain:FindChild("RightBottomSimpleCountContainer"):Show(bIsAutoCraft and bIsAtCraftingStation)
	self.wndMain:FindChild("RightBottomSimpleCountSpinner"):Show(bIsAutoCraft and bIsAtCraftingStation)
	self.wndMain:FindChild("RightBottomSimpleCraftBtn"):Show(bIsAutoCraft and bIsAtCraftingStation)
	if not bIsAtCraftingStation and bIsAutoCraft then
		self.wndMain:FindChild("RightBottomCraftPreview"):SetText(Apollo.GetString("Crafting_NotNearStation"))
	else
		self.wndMain:FindChild("RightBottomCraftPreview"):SetText("")
	end
end

function TradeskillSchematics:OnTopLevelBtnToggle(wndHandler, wndControl)
	self.wndMain:FindChild("RightSide"):Show(false)
	self:RedrawFromUI()
end

function TradeskillSchematics:OnMiddleLevelBtnToggle(wndHandler, wndControl)
	self.wndMain:FindChild("RightSide"):Show(false)
	self:RedrawFromUI()
end

function TradeskillSchematics:OnBottomItemUncheck(wndhandler, wndControl)
	self.wndMain:FindChild("RightSide"):Show(false)
	self:RedrawFromUI()
end

function TradeskillSchematics:OnBottomItemCheck(wndHandler, wndControl) -- BottomItemBtn, data is tSchematic
	-- Search and View All both use this UI button
	if self.wndLastBottomItemBtnBlue then -- TODO HACK
		self.wndLastBottomItemBtnBlue:SetTextColor(ApolloColor.new("UI_BtnTextGoldListNormal"))
	end

	if wndHandler:FindChild("BottomItemBtnText") then
		self.wndLastBottomItemBtnBlue = wndHandler:FindChild("BottomItemBtnText")
		wndHandler:FindChild("BottomItemBtnText"):SetTextColor(ApolloColor.new("UI_BtnTextGoldListPressed"))
	end

	local tSchematicInfo = CraftingLib.GetSchematicInfo(wndHandler:GetData().nSchematicId)
	local tTradeskillInfo = CraftingLib.GetTradeskillInfo(tSchematicInfo.eTradeskillId)
	self.bCoordCraft = tTradeskillInfo.bIsCoordinateCrafting

	self:DrawSchematic(wndHandler:GetData())
	self:OnTimerCraftingStationCheck()
end

function TradeskillSchematics:OnFiltersChanged(wndHandler, wndControl)
	self.wndMain:FindChild("LeftSideRefreshAnimation"):SetSprite("CRB_WindowAnimationSprites:sprWinAnim_BirthSmallTemp")
	self.wndMain:FindChild("LeftSideScroll"):DestroyChildren()

	self.tSavedData.bFilterLocked = self.wndMain:FindChild("LeftSideFilterLocked"):IsChecked()
	self.tSavedData.bFilterMats = self.wndMain:FindChild("LeftSideFilterMaterials"):IsChecked()

	self:FullRedraw()
	self.wndMain:FindChild("LeftSideScroll"):SetVScrollPos(0)
end

-----------------------------------------------------------------------------------------------
-- Schematics
-----------------------------------------------------------------------------------------------

function TradeskillSchematics:DrawSchematic(tSchematic)
	local tSchematicInfo = CraftingLib.GetSchematicInfo(tSchematic.nSchematicId)
	local wndSchem = self.wndMain:FindChild("RightSide")

	if not tSchematicInfo or not wndSchem then
		return
	end

	-- Source Achievement
	local achSource = tSchematicInfo.achSource
	if achSource then
		local bComplete = achSource:IsComplete()
		local nNumNeeded = achSource:GetNumNeeded()
		local nNumCompleted = bComplete and nNumNeeded or achSource:GetNumCompleted()

		if nNumNeeded == 0 and achSource:IsChecklist() then
			local tChecklistItems = achSource:GetChecklistItems()
			nNumNeeded = #tChecklistItems
			nNumCompleted = 0
			for idx, tData in ipairs(achSource:GetChecklistItems()) do
				if tData.schematicId and tData.isComplete then
					nNumCompleted = nNumCompleted + 1
				end
			end
		end

		wndSchem:FindChild("LockedLinkCheckmark"):Show(bComplete)
		wndSchem:FindChild("LockedLinkProgBar"):SetMax(nNumNeeded)
		wndSchem:FindChild("LockedLinkProgBar"):SetProgress(nNumCompleted)
		wndSchem:FindChild("LockedLinkProgBar"):EnableGlow(nNumCompleted > 0 and not bComplete)
		wndSchem:FindChild("LockedLinkBtn"):SetData(achSource)
		wndSchem:FindChild("LockedLinkProgText"):SetText(String_GetWeaselString(Apollo.GetString("Achievements_ProgressBarProgress"), nNumCompleted, nNumNeeded))
	end
	wndSchem:FindChild("LockedLinkBtn"):Show(achSource and not tSchematic.bIsKnown and not tSchematic.bIsAutoLearn)

	-- Materials
	local bHaveEnoughMats = true
	local nNumCraftable = 9000
	wndSchem:FindChild("MaterialsScroll"):DestroyChildren()
	for key, tMaterial in pairs(tSchematicInfo.tMaterials) do
		if tMaterial.nAmount > 0 then
			local wndMaterial = Apollo.LoadForm(self.xmlDoc, "MaterialsItem", wndSchem:FindChild("MaterialsScroll"), self)
			local nBackpackCount = tMaterial.itemMaterial:GetBackpackCount()
			wndMaterial:FindChild("MaterialsIcon"):SetSprite(tMaterial.itemMaterial:GetIcon())
			wndMaterial:FindChild("MaterialsName"):SetText(tMaterial.itemMaterial:GetName())
			wndMaterial:FindChild("MaterialsIcon"):SetText(String_GetWeaselString(Apollo.GetString("Achievements_ProgressBarProgress"), nBackpackCount, tMaterial.nAmount))
			wndMaterial:FindChild("MaterialsIconNotEnough"):Show(nBackpackCount < tMaterial.nAmount)
			self:HelperBuildItemTooltip(wndMaterial, tMaterial.itemMaterial)

			nNumCraftable = math.min(nNumCraftable, math.floor(nBackpackCount / tMaterial.nAmount))
			bHaveEnoughMats = bHaveEnoughMats and nBackpackCount >= tMaterial.nAmount
		end
	end

	-- Fake Material (Power Cores)
	if not self.bCoordCraft then
		local tAvailableCores = CraftingLib.GetAvailablePowerCores(tSchematic.nSchematicId)
		if tAvailableCores then -- Some crafts won't have power cores
			local wndMaterial = Apollo.LoadForm(self.xmlDoc, "MaterialsItem", wndSchem:FindChild("MaterialsScroll"), self)
			local nBackpackCount = 0
			for idx, itemMaterial in pairs(tAvailableCores) do
				nBackpackCount = nBackpackCount + itemMaterial:GetStackCount()
			end

			local strPowerCore = Apollo.GetString("CBCrafting_PowerCore")
			if karPowerCoreTierToString[tSchematicInfo.eTier] then
				strPowerCore = String_GetWeaselString(Apollo.GetString("Tradeskills_AnyPowerCore"), karPowerCoreTierToString[tSchematicInfo.eTier])
			end

			wndMaterial:FindChild("MaterialsIcon"):SetSprite("ClientSprites:Icon_ItemMisc_UI_Item_Crafting_PowerCore_Green")
			wndMaterial:FindChild("MaterialsIcon"):SetText(String_GetWeaselString(Apollo.GetString("Achievements_ProgressBarProgress"), nBackpackCount, "1"))
			wndMaterial:FindChild("MaterialsName"):SetText(strPowerCore)
			wndMaterial:FindChild("MaterialsIconNotEnough"):Show(nBackpackCount < 1)
			wndMaterial:SetTooltip(Apollo.GetString("CBCrafting_PowerCoreHelperTooltip"))
			nNumCraftable = math.min(nNumCraftable, nBackpackCount)
		end
	end

	local bIsCooking = tSchematicInfo.eTradeskillId == CraftingLib.CodeEnumTradeskill.Cooking
	wndSchem:Show(true)
	wndSchem:SetData(tSchematic)
	wndSchem:FindChild("RightBottomCraftBtn"):SetData(tSchematic.nSchematicId) -- This is pdated on OnTimerCraftingStationCheck based on RightBottomCraftPreview
	wndSchem:FindChild("RightBottomSimpleCraftBtn"):SetData(tSchematic.nSchematicId) -- This is updated on OnTimerCraftingStationCheck based on RightBottomCraftPreview
	wndSchem:FindChild("RightBottomSimpleCraftBtn"):Enable(bHaveEnoughMats) -- GOTCHA: RightBottomCraftBtn can be enabled with no mats, it just goes to a preview screen

	if tSchematicInfo.bIsAutoCraft then
		local maxCraftable = math.min(nNumCraftable or 1, tSchematicInfo.nCraftAtOnceMax or 1)				
		local spinner = wndSchem:FindChild("RightBottomSimpleCountSpinner")
		spinner:SetMinMax(1, maxCraftable)
		spinner:SetValue(1)
		
		local simpleContainer = wndSchem:FindChild("RightBottomSimpleCraft")		
		simpleContainer:DestroyAllPixies()
		simpleContainer:AddPixie({
			strText = " / "..tostring(maxCraftable),
			strFont = "CRB_InterfaceMedium_B",
			cr = {a=0, r=0, g=0, b=0},
			crText = {a=255, r=255, g=255, b=255},
			loc = {
				fPoints = {0,0,1,1},
				nOffsets = {91,14,0,-14},
			},
			flagsText = {
				DT_VCENTER = true
			}		
		})					
	end
	
	wndSchem:FindChild("SchematicName"):SetText(tSchematicInfo.strName)
	wndSchem:FindChild("SchematicIcon"):SetSprite(tSchematicInfo.itemOutput:GetIcon())
	wndSchem:FindChild("RightCookingMessage"):Show(not tSchematic.bIsKnown and bIsCooking)
	wndSchem:FindChild("SchematicIconLockBG"):Show(not tSchematic.bIsKnown and not tSchematic.bIsOneUse)
	wndSchem:FindChild("RightNoLinkMessage"):Show(not tSchematic.bIsKnown and not tSchematic.bIsAutoLearn and not bIsCooking and not achSource)
	self:HelperBuildItemTooltip(wndSchem:FindChild("SchematicIcon"), tSchematicInfo.itemOutput)

	-- Three line text
	local nRequiredLevel = tSchematicInfo.itemOutput:GetRequiredLevel()
	local strRequiredLevelAppend = nRequiredLevel == 0 and "" or (String_GetWeaselString(Apollo.GetString("Tradeskills_RequiredLevel"), nRequiredLevel) .." \n")
	local strNumCraftable = nNumCraftable == 0 and "" or String_GetWeaselString(Apollo.GetString("Tradeskills_MaterialsForX"), nNumCraftable)
	wndSchem:FindChild("SchematicItemType"):SetText(tSchematic.strItemTypeName.." \n"..strRequiredLevelAppend..strNumCraftable)

	-- TODO: Resize depending if there are Subrecipes
	local nLeft, nTop, nRight, nBottom = wndSchem:FindChild("RightTopBG"):GetAnchorOffsets()
	wndSchem:FindChild("RightTopBG"):SetAnchorOffsets(nLeft, nTop, nRight, #tSchematicInfo.tSubRecipes > 0 and 310 or 480) -- TODO: SUPER HARDCODED FORMATTING

	-- Subrecipes
	wndSchem:FindChild("RightSubrecipes"):Show(#tSchematicInfo.tSubRecipes > 0)
	wndSchem:FindChild("SubrecipesListScroll"):DestroyChildren()
	for key, tSubrecipe in pairs(tSchematicInfo.tSubRecipes) do
		local wndSubrecipe = Apollo.LoadForm(self.xmlDoc, "SubrecipesItem", wndSchem:FindChild("SubrecipesListScroll"), self)
		wndSubrecipe:FindChild("SubrecipesLeftDiscoverableBG"):Show(not tSubrecipe.bIsKnown and tSubrecipe.bIsUndiscovered)
		wndSubrecipe:FindChild("SubrecipesLeftLockedBG"):Show(not tSubrecipe.bIsKnown and not tSubrecipe.bIsUndiscovered)
		wndSubrecipe:FindChild("SubrecipesLeftIcon"):SetSprite(tSubrecipe.itemOutput:GetIcon())
		wndSubrecipe:FindChild("SubrecipesLeftName"):SetText(tSubrecipe.itemOutput:GetName())
		self:HelperBuildItemTooltip(wndSubrecipe, tSubrecipe.itemOutput)
		-- TODO SubrecipesRight for Critical Successes
	end

	wndSchem:FindChild("MaterialsScroll"):ArrangeChildrenTiles(0)
	wndSchem:FindChild("SubrecipesListScroll"):ArrangeChildrenTiles(0)
	
		
	-- hephaestus custom code
	if not self.wndDropdownRepeats then
		return
	end
	
	local repeatParent = self.wndDropdownRepeats:FindChild("RepeatDropdownBG_Art")
	local repeatContainer = repeatParent:FindChild("RepeatVariantsHolder")
	
	repeatContainer:DestroyChildren()
	local wndRepeatItem = Apollo.LoadForm(self.xmlDoc, "RepeatItem", repeatContainer, self)
	self:UpdateRepeatItem(tSchematicInfo, wndRepeatItem)
	-- TODO: add variants
	repeatContainer:ArrangeChildrenVert()
	repeatParent:ArrangeChildrenVert()	
end

function TradeskillSchematics:OnLockedLinkBtn(wndHandler, wndControl) -- LockedLinkBtn, data is achSource
	Event_FireGenericEvent("GenericEvent_OpenToSpecificTechTree", wndHandler:GetData())
end

function TradeskillSchematics:OnRightBottomCraftBtn(wndHandler, wndControl) -- RightBottomCraftBtn, data is tSchematicId
	Event_FireGenericEvent("GenericEvent_CraftFromPL", wndHandler:GetData())
	Event_FireGenericEvent("AlwaysHideTradeskills")
end

function TradeskillSchematics:OnRightBottomSimpleCraftBtn(wndHandler, wndControl) -- RightBottomSimpleCraftBtn, data is tSchematicId
	local tCurrentCraft = CraftingLib.GetCurrentCraft()
	if tCurrentCraft and tCurrentCraft.nSchematicId ~= 0 then
		Event_FireGenericEvent("GenericEvent_CraftFromPL", wndHandler:GetData())
	else	
		local nCount= wndHandler:GetParent():FindChild("RightBottomSimpleCountSpinner"):GetValue()				
		CraftingLib.CraftItem(wndHandler:GetData(), nil, nCount)	
	end
	Event_FireGenericEvent("AlwaysHideTradeskills")
end

-----------------------------------------------------------------------------------------------
-- Search
-----------------------------------------------------------------------------------------------

function TradeskillSchematics:ClearSearchBoxFocus(wndHandler, wndControl)
	wndHandler:SetFocus()
end

function TradeskillSchematics:OnSearchTopLeftClearBtn(wndHandler, wndControl)
	self.wndMain:FindChild("SearchTopLeftInputBox"):SetText("")
	self:OnSearchTopLeftInputBoxChanged(self.wndMain:FindChild("SearchTopLeftInputBox"), self.wndMain:FindChild("SearchTopLeftInputBox"))
	wndHandler:SetFocus() -- Focus on close button to steal focus from input
end

function TradeskillSchematics:OnSearchTopLeftInputBoxChanged() -- Also called in Lua
	local strInput = self.wndMain:FindChild("SearchTopLeftInputBox"):GetText():lower()
	local bInputExists = string.len(strInput) > 0

	self.wndMain:FindChild("LeftSideSearch"):Show(bInputExists)
	self.wndMain:FindChild("SearchTopLeftClearBtn"):Show(bInputExists)
	self.wndMain:FindChild("LeftSideSearchResultsList"):DestroyChildren()

	if not bInputExists then
		return
	end

	-- Search
	-- All Tradeskills -> All Schematics -> If Valid Schematics (hobby or right tier) then Draw Result
	for idx, tCurrTradeskill in ipairs(CraftingLib.GetKnownTradeskills()) do
		if idx ~= CraftingLib.CodeEnumTradeskill.Runecrafting then
			local tCurrTradeskillInfo = CraftingLib.GetTradeskillInfo(tCurrTradeskill.eId)
			for idx2, tSchematic in pairs(CraftingLib.GetSchematicList(tCurrTradeskill.eId, nil, nil, true)) do
				if tCurrTradeskillInfo.bIsHobby or tCurrTradeskillInfo.eTier >= tSchematic.eTier then
					self:HelperSearchBuildResult(self:HelperSearchNameMatch(tSchematic, strInput))
					for idx3, tSubSchem in pairs(self:HelperSearchSubschemNameMatch(tSchematic, strInput)) do
						self:HelperSearchBuildResult(tSchematic, tSubSchem)
					end
				end
			end
		end
	end

	local bNoResults = #self.wndMain:FindChild("LeftSideSearchResultsList"):GetChildren() == 0
	self.wndMain:FindChild("LeftSideSearchResultsList"):ArrangeChildrenVert(0)
	--self.wndMain:FindChild("LeftSideSearchFrame"):SetText(bNoResults and Apollo.GetString("Tradeskills_NoResults") or "")
end

-----------------------------------------------------------------------------------------------
-- Helpers
-----------------------------------------------------------------------------------------------

function TradeskillSchematics:HelperHaveEnoughMaterials(tSchematic)
	local bValidOneUse = true
	local bHasEnoughMaterials = true

	-- Materials
	local tSchematicInfo = CraftingLib.GetSchematicInfo(tSchematic.nSchematicId)
	for key, tMaterial in pairs(tSchematicInfo.tMaterials) do
		local nBackpackCount = tMaterial.itemMaterial:GetBackpackCount()
		if nBackpackCount < tMaterial.nAmount then
			bHasEnoughMaterials = false
		end
	end

	-- Fake Material
	if not self.bCoordCraft then
		local tAvailableCores = CraftingLib.GetAvailablePowerCores(tSchematic.nSchematicId)
		if tAvailableCores then -- Some crafts won't have power cores
			local nBackpackCount = 0
			for idx, tMaterial in pairs(tAvailableCores) do
				nBackpackCount = nBackpackCount + tMaterial:GetBackpackCount()
			end
			if nBackpackCount < 1 then
				bHasEnoughMaterials = false
			end
		end
	end

	-- One Use
	if tSchematic.bIsOneUse then
		local tFirstMat = tSchematicInfo.tMaterials[1] -- GOTCHA: Design has assured the recipe is always the first
		bValidOneUse = tFirstMat.itemMaterial:GetBackpackCount() >= tFirstMat.nAmount
	end

	return bHasEnoughMaterials, bValidOneUse
end

function TradeskillSchematics:HelperSearchBuildResult(tSchematic, tSubSchem)
	if not tSchematic then
		return
	end

	local tSchematicToUse = tSubSchem and tSubSchem or tSchematic
	local bShowLock = not tSchematicToUse.bIsKnown
	local bShowMatsWarning = not bShowLock and not self:HelperHaveEnoughMaterials(tSchematicToUse)
	local bOneTime = not bShowLock and not bShowMatsWarning and tSchematicToUse.bIsOneUse
	local wndBottomItem = self:LoadByName("BottomItem", self.wndMain:FindChild("LeftSideSearchResultsList"), tSchematicToUse.strName)
	wndBottomItem:FindChild("BottomItemBtn"):SetData(tSchematic) -- GOTCHA: The Button will intentionally always open the parent schematic
	wndBottomItem:FindChild("BottomItemLockIcon"):Show(bShowLock)
	wndBottomItem:FindChild("BottomItemOneTimeIcon"):Show(bOneTime)
	wndBottomItem:FindChild("BottomItemMatsWarningIcon"):Show(bShowMatsWarning)
	wndBottomItem:FindChild("BottomItemBtnText"):SetText(tSubSchem and String_GetWeaselString(Apollo.GetString("Tradeskills_SubAbrev"), tSubSchem.strName) or tSchematic.strName)
end

function TradeskillSchematics:HelperSearchNameMatch(tSchematic, strInput) -- strInput already :lower()
	local strBase = tSchematic.strName

	if strBase:lower():find(strInput, 1, true) then
		return tSchematic
	else
		return false
	end
end

function TradeskillSchematics:HelperSearchSubschemNameMatch(tSchematic, strInput) -- strInput already :lower()
	local tResult = {}
	for key, tSubrecipe in pairs(tSchematic.tSubRecipes or {}) do
		if tSubrecipe.strName:lower():find(strInput, 1, true) then
			table.insert(tResult, tSubrecipe)
		end
	end
	return tResult
end

function TradeskillSchematics:HelperBuildItemTooltip(wndArg, itemCurr)
	Tooltip.GetItemTooltipForm(self, wndArg, itemCurr, {bPrimary = true, bSelling = false, itemCompare = itemCurr:GetEquippedItemForItemType()})
end

function TradeskillSchematics:LoadByName(strForm, wndParent, strCustomName)
	local wndNew = wndParent:FindChild(strCustomName)
	if not wndNew then
		wndNew = Apollo.LoadForm(self.xmlDoc, strForm, wndParent, self)
		wndNew:SetName(strCustomName)
	end
	return wndNew
end

---- New queue stuff - TODO: refactor outside this addon
local knMaxCutoff = 1000
local knSupplySatchelStackSize = 250

local function info(strText)
	Print("INFO: "..(strText or ""))
end

local function err(strText)
	Print("ERROR: "..(strText or ""))
end

local function warn(strText)
	Print("WARN: "..(strText or ""))
end

local mtSignal = {}

function mtSignal:__add(tfnCallback) 
	if type(tfnCallback) == "function" then
		table.insert(self, tfnCallback)
	elseif type(tfnCallback) == "table" then
		if not getmetatable(tfnCallback).__call then
			error("Signal.Add requires a callable argument")
			return
		end	
		table.insert(self, tfnCallback)
	end
	
	return self
end


function mtSignal:__sub(tfnCallback)
	for idx, tfn in ipairs(self) do
		if tfn == tfnCallback then
			table.remove(self, idx)
			break
		end	
	end		
	
	return self		
end

function mtSignal:__call(...) 
	for idx, tfn in ipairs(self) do
		tfn(unpack(arg))
	end	
end

function mtSignal:Add(tOwner, strCallback)
	local fnCall = function(luaCaller, ...) 
		local t = luaCaller.tOwner
		local strClb = luaCaller.strCallback
		if t and strClb then
			t[strClb](t, unpack(arg))
		end
	end
	
	local tCallback = setmetatable({}, {__mode="v", __call = fnCall})
	tCallback.tOwner = tOwner
	tCallback.strCallback = strCallback	
		
	local tmp = self + tCallback
	
	return tCallback
end

mtSignal.__index = mtSignal

local Signal = {}

function Signal:new(t)
	return setmetatable(t or {}, mtSignal)
end

local function GuardCanCraft()
	local player = GameLib.GetPlayerUnit()
	if player == nil then
		err("Cannot get player unit - cannot start")
		return false
	end
	
	if not CraftingLib.IsAtCraftingStation() then
		err("Not at crafting station")
		return false
	end
	
	if player:IsMounted() then
		info("Player mounted - can't start")
		-- TODO auto dismount?
		return false
	end
	
	if player:IsCasting() then
		info("Player is casting - cannot start")
		return false
	end
	
	return true
end


local CraftQueueItem = {}

local mtCraftQueueItem = {}

function CraftQueueItem.new(tSchematicInfo, nAmount, tQueue, ...)
	return setmetatable(
		{ 
			tSchematicInfo = tSchematicInfo,
			nAmount = nAmount,
			tArgs = arg,
			tQueue = tQueue
		},
		{
			__index = mtCraftQueueItem
		}
	)	
end

function mtCraftQueueItem:GetQueue()
	return self.tQueue
end

function mtCraftQueueItem:GetSchematicInfo()
	return self.tSchematicInfo
end

function mtCraftQueueItem:GetAmount()
	return self.nAmount
end

function mtCraftQueueItem:SetAmount(nAmount)
	self.nAmount = nAmount
end

function mtCraftQueueItem:CraftComplete()
	self.nAmount = self.nAmount - self.nCurrentCraftAmount
	self.nCurrentCraftAmount = nil	
	
	self:GetQueue():GetItemChangedHandlers()(self)
end

local function CalcMaxCraftableForMaterials(tSchematicInfo)
	-- TODO: make this methods *start* at backbackcount, then add/subtract preceding items materials & results 
	-- 		 keep in mind, there are items that have same item as input and output - also increment by partial crafts

	local nNumCraftable = 9000
	
	for key, tMaterial in pairs(tSchematicInfo.tMaterials) do
		if tMaterial.nAmount > 0 then			
			local nBackpackCount = tMaterial.itemMaterial:GetBackpackCount()

			nNumCraftable = math.min(nNumCraftable, math.floor(nBackpackCount / tMaterial.nAmount))
		end
	end

	return nNumCraftable
end

function mtCraftQueueItem:GetMaxCraftable()

	return CalcMaxCraftableForMaterials(self:GetSchematicInfo())
end

function mtCraftQueueItem:GetCurrentCraftAmount()
	return self.nCurrentCraftAmount
end

function mtCraftQueueItem:SetCurrentCraftAmount(nCount)
	self.nCurrentCraftAmount = nCount
end

function mtCraftQueueItem:TryCraft()
	if self:GetMaxCraftable() == 0 then
		warn("Not enough materials - stopping")
		self:GetQueue():Stop()
		return
	end
	
	if not GuardCanCraft() then
		self:GetQueue():Stop()
		return
	end	
	
	
	local tSchematicInfo = self:GetSchematicInfo()
	
	if tSchematicInfo.nParentSchematicId and tSchematicInfo.nParentSchematicId ~= 0 and tSchematicInfo.nSchematicId ~= tSchematicInfo.nParentSchematicId then
		warn("Cannot create variant items (yet) - stopping")
		self:GetQueue():Stop()
		return
	end
	
	--[[ 
		available keys:
		- nSchematicId
		- strName
		- itemOutput
		- bIsAutoCraft
		- nCraftAtOnceMax 	
		- nParentSchematicId 
	]]
	local bIsAutoCraft = tSchematicInfo.bIsAutoCraft or false
	local nCraftAtOnceMax = tSchematicInfo.nCraftAtOnceMax or 1
	local itemOutput = tSchematicInfo.itemOutput
	local nRoomForOutputItems = 0
	local unitPlayer = GameLib.GetPlayerUnit()
	
	-- make sure we have enough space in inventory
	
	-- check satchel first
	if itemOutput.CanMoveToSupplySatchel() then
		local bFound = false
		for strCategory, arItems in pairs(unitPlayer:GetSupplySatchelItems(0)) do
			for idx, tCurrItem in ipairs(arItems) do
				if tCurrItem.itemMaterial == itemOutput then
					bFound = true
					nRoomForOutputItems = knSupplySatchelStackSize - tCurrItem.nCount					
					break
				end
			end
		end
		
		if not bFound then
			nRoomForOutputItems = knSupplySatchelStackSize
		end
	end

	-- calc free inventory slots
	local nMaxStackSize = itemOutput:GetMaxStackCount() or 1
	
	local nOccupiedInventory = #unitPlayer:GetInventoryItems() or 0
	local nTotalInventory = GameLib.GetTotalInventorySlots() or 0
	local nAvailableInventory = nTotalInventory - nOccupiedInventory
	nRoomForOutputItems = nRoomForOutputItems + nMaxStackSize * nAvailableInventory
	
	-- calc partial stacks in inventory
	for idx, tCurrItem in ipairs(unitPlayer:GetInventoryItems()) do	
		if tCurrItem.itemInBag == itemOutput then
			local nStackSize = tCurrItem.itemInBag:GetStackCount() or 0
			nRoomForOutputItems = nRoomForOutputItems + nMaxStackSize - nStackSize
		end	
	end
	
	-- calculate defensively, in case there are ever crit crafts with more output
	local nCraftCount = math.max(tSchematicInfo.nCreateCount or 1, tSchematicInfo.nCritCount or 1)
	
	local nMaxCraftCounts = math.floor(nRoomForOutputItems / nCraftCount)
	if nMaxCraftCounts < 1 then
		err("Not enough room for output items - stopping")
		self:GetQueue():Stop()
		return		
	end
	
	local nCount = math.min(nMaxCraftCounts, math.min(self:GetAmount(), nCraftAtOnceMax))
	self:SetCurrentCraftAmount(nCount)	
	
	if bIsAutoCraft then
		CraftingLib.CraftItem(tSchematicInfo.nSchematicId, nil, nCount)
	else		
		CraftingLib.CraftItem(tSchematicInfo.nSchematicId, nil)	
		-- TODO: make some moves (later)
		CraftingLib.CompleteCraft()
	end			
	
	self:GetQueue():GetItemChangedHandlers()(self)	
end




local ktQueueStates = {
	Paused = 1,
	Running = 2
}


local mtQueue = {}

function Queue.new(t)
	return setmetatable(
		t or { 
			items = {} 
		}, 
		{ 
			__index = mtQueue
		}
	)
end

function mtQueue:GetItems()
	return self.items
end

function mtQueue:Push(oItem)
	table.insert(self.items, oItem)
end

function mtQueue:Pop()
	if #self.items == 0 then
		return nil
	else
		local result = self[1]
		table.remove(self.items, 1)	
		return result
	end		
end

function mtQueue:Peek()
	if #self.items == 0 then
		return nil
	else
		return self.items[1]
	end		
end

function mtQueue:Clear()
	while #self.items ~= 0 do
		table.remove(self.items)	
	end
end

function mtQueue:Remove(tItem)
	for idx, item in ipairs(self.items) do
		if item == tItem then
			table.remove(self.items, idx)
			return true	
		end
	end
	return false
end

function mtQueue:GetCount()
	return #self.items
end

local mtCraftQueue = {}
setmetatable(mtCraftQueue, { __index = mtQueue})

function CraftQueue.new(t)
	return setmetatable(
		t or {
			items = {},
			handlers = {
				changed = Signal.new(),
				itemChanged = Signal.new(),
				itemRemoved = Signal.new()
			}	
		},
		{ __index = mtCraftQueue }
	)
end

function mtCraftQueue:GetChangedHandlers()
	return self.handlers.changed
end

function mtCraftQueue:GetItemChangedHandlers()
	return self.handlers.itemChanged
end

function mtCraftQueue:GetItemRemovedHandlers()
	return self.handlers.itemRemoved
end


function mtCraftQueue:Push(tSchematicInfo, nAmount,...)
	mtQueue.Push(
		self, 
		CraftQueueItem.new(
			tSchematicInfo,
			nAmount,
			self,
			unpack(arg)
		)
	)
	self.handlers.changed()
end


function mtCraftQueue:IsRunning()
	return self.state == ktQueueStates.Running
end

function mtCraftQueue:Start()
	if self.state == ktQueueStates.Running then
		warn("Already running")
		return
	end

	-- empty? early bail out
	if #self.items == 0 then
		return
	end
	
	if not GuardCanCraft() then
		return
	end
	
	-- make sure enough materials are still present
	self.state = ktQueueStates.Running
	
	self.handlers.changed()	
	Apollo.RegisterEventHandler("CombatLogCrafting", "OnCombatLogCrafting", self)
	Apollo.RegisterEventHandler("CraftingInterrupted", "OnCraftingInterrupted", self)	
	Apollo.RegisterEventHandler("OnCraftingSchematicComplete", "OnCraftingSchematicComplete", self)
	self:Peek():TryCraft()		
end

function mtCraftQueue:OnCraftingSchematicComplete(idSchematic, bPass, nEarnedXp, arMaterialReturnedIds, idSchematicCrafted, idItemCrafted)
	self:Peek():CraftComplete()
	
	if self:Peek():GetAmount() == 0 then
		local item = self:Pop()
		
		self.handlers.itemRemoved(item)
		
		if self.GetCount() == 0 then
			self:Stop()
			return
		end		

	end
	
	self:Peek():TryCraft()
end

function mtCraftQueue:CraftingInterrupted()
	self:Stop()
end

--[[
	Apollo.RegisterEventHandler("VarChange_FrameCount", "OnFrameChange", self)
]]
		


function mtCraftQueue:Stop()
	if self.state == ktQueueStates.Paused and not self:IsCraftRunning() then
		warn("Already stopped")
		return
	end
	
	-- TODO: the removal may need to be delayed...
	--Apollo.RemoveEventHandler("CombatLogCrafting", self)
	--Apollo.RemoveEventHandler("CraftingInterrupted",  self)	
	--Apollo.RemoveEventHandler("OnCraftingSchematicComplete", self)	
	
	self.state = ktQueueStates.Paused
	self.handlers.changed()	
end

function TradeskillSchematics:UpdateCastBar()
	-- TODO: implement
end

function TradeskillSchematics:RefreshQueueHeader()
	if not self.wndQueue then	
		return
	end	
	
	local queue = self.wndQueue:GetData()
	local nCount = queue:GetCount()
	
	local isRunning = queue:IsRunning()
	local btnStop = self.wndQueue:FindChild("StopButton")
	local btnStart = self.wndQueue:FindChild("StartButton")
	local btnClear = self.wndQueue:FindChild("ClearButton")
		
	if isRunning then
		btnStop:Enable(true)
		
		btnStop:Show(true)
		btnStart:Enable(false)
		btnStart:Show(false)
		btnClear:Enable(false)	
	else
		btnStop:Enable(false)
		btnStop:Show(false)
		btnStart:Enable(nCount > 0)		
		btnStart:Show(true)
		btnClear:Enable(nCount > 0)		
	end
	
	self:UpdateCastBar()	
end

function TradeskillSchematics:RecreateQueue()	
	if not self.wndQueue then	
		return
	end	
	
	local queue = self.wndQueue:GetData()
	
	self:RefreshQueueHeader()
	
	-- recreate list
	local queueContainer = self.wndQueue:FindChild("QueueContainer")	
	queueContainer:DestroyChildren()

	local items = queue:GetItems()
	
	for idx, item in ipairs(items) do
		local wndItem = Apollo.LoadForm(self.xmlDoc, "QueueItem", queueContainer , self)
		self:RefreshQueueItem(item, wndItem, queue)							
	end	
	queueContainer:ArrangeChildrenVert()	
		
end

function TradeskillSchematics:RefreshQueue()
	if not self.wndQueue then	
		return
	end	
	local queue = self.wndQueue:GetData()	
	
	self:RefreshQueueHeader()
	
	-- recreate list
	local queueContainer = self.wndQueue:FindChild("QueueContainer")	
	for idx, wndItem in ipairs(queueContainer:GetChildren()) do
		local item = wndItem:GetData()
		self:RefreshQueueItem(item, wndItem, queue)							
	end	
	queueContainer:ArrangeChildrenVert()			
end

function TradeskillSchematics:RefreshQueueItem(item, wndItem, queue)
	if not wndItem then
		for idx, wnd in ipairs(self.wndQueue:FindChild("QueueContainer"):GetChildren()) do		
			if item == wnd:GetData() then
				wndItem = wnd
				break
			end		
		end
	end
	
	if not wndItem then
		warn("wndItem is nil")
		return 
	end
	
	if not queue then
		queue = item:GetQueue()
	end
	
	local tSchematicInfo = item:GetSchematicInfo()
	local nAmount = item:GetAmount()		
	local bCurrentlyRunning = queue:IsRunning() and queue:Peek() == item
	local nMaxCraftable = item:GetMaxCraftable()
	local sCount
	if nMaxCraftable < knMaxCutoff then
		sCount = string.format("%3.f", nMaxCraftable)
	else
		sCount = "*"
	end
	
	local spinnerAmount = wndItem:FindChild("CountSpinner")
	local btnRemove = wndItem:FindChild("RemoveButton")
	local btnUp = wndItem:FindChild("MoveUpButton")
	local btnDown = wndItem:FindChild("MoveDownButton")
	local wndCount = wndItem:FindChild("Count")

	
	wndItem:FindChild("GlowActive"):Show(bCurrentlyRunning)
	wndCount:SetText(sCount)

	wndItem:FindChild("Icon"):SetSprite(tSchematicInfo.itemOutput:GetIcon())
	wndItem:FindChild("Name"):SetText(tSchematicInfo.strName)
	
	spinnerAmount:Enable(not bCurrentlyRunning)
	spinnerAmount:SetMinMax(1, math.min(nMaxCraftable, 999))
	spinnerAmount:SetValue(nAmount)
					
	btnUp:Enable(false)			-- NYI
	btnDown:Enable(false)		-- NYI

	btnRemove:Enable(not bCurrentlyRunning)
	
	wndItem:SetData(item)
end

function TradeskillSchematics:RemovedQueueItem(item, wndItem)
	if not wndItem then
		for idx, wnd in ipairs(self.wndQueue:FindChild("QueueContainer"):GetChildren()) do		
			if item == wnd:GetData() then
				wndItem = wnd
				break
			end		
		end
	end
	
	if not wndItem then
		warn("wndItem is nil")
		return 
	end

	wndItem:Destroy()	
	self.wndQueue:FindChild("QueueContainer"):ArrangeChildrenVert()	
end

function TradeskillSchematics:OnQueueItemCountChanged(wndHandler, wndControl, fNewValue, fOldValue )
	if wndHandler ~= wndControl then
		return
	end
	
	wndControl:GetParent():GetParent():GetData():SetAmount(fNewValue)
end

function TradeskillSchematics:OnRemoveQueueItem(wndHandler, wndControl)
	if wndHandler ~= wndControl then
		return
	end
		
	if not self.wndQueue then	
		return
	end
	
	local queue = self.wndQueue:GetData()
	
	local wndItem = wndControl:GetParent()	
	local item = wndItem:GetData()
		
	-- update data
	queue:Remove(item)
		
	-- update ui
	self:RemovedQueueItem(item, wndItem)
	self:RefreshQueueHeader()
end

function TradeskillSchematics:OnQueueClear(wndHandler, wndControl)
	if wndHandler ~= wndControl then
		return
	end

	if not self.wndQueue then	
		return
	end
	
	local queue = self.wndQueue:GetData()	
	queue:Clear()
	
	self:RecreateQueue(queue)
end

function TradeskillSchematics:OnQueueStart(wndHandler, wndControl)
	if wndHandler ~= wndControl then
		return
	end
	
	if not self.wndQueue then	
		return
	end
	
	local queue = self.wndQueue:GetData()	
	queue:Start()
	self:RefreshQueue()
end

function TradeskillSchematics:OnQueueStop(wndHandler, wndControl)
	if wndHandler ~= wndControl then
		return
	end
	
	if not self.wndQueue then	
		return
	end
	
	local queue = self.wndQueue:GetData()	
	queue:Stop()
	self:RefreshQueue()	
end

function TradeskillSchematics:ToggleQueueWindow()
	if not self.wndQueue then
		return
	end
		
	if self.wndQueue:IsShown() then
		self.wndQueue:Show(false)
	else
		self:RecreateQueue(self.wndQueue:GetData())
		self.wndQueue:Show(true)	
	end	
end



function TradeskillSchematics:OnAutoCraft()
	self:ToggleQueueWindow()
end

function TradeskillSchematics:UpdateRepeatItem(tSchematicInfo, wndTarget)
	wndTarget:SetData(tSchematicInfo)
	wndTarget:FindChild("Name"):SetText(tSchematicInfo.strName)
	wndTarget:FindChild("Icon"):SetSprite(tSchematicInfo.itemOutput:GetIcon())
	
	local nCostPerItem = 0	-- TODO: calc by moves...
	local nMaxCraftable = CalcMaxCraftableForMaterials(tSchematicInfo)	-- TODO: factor in money, once things actually cost something
	
	local strMaxCount
	if nMaxCraftable < knMaxCutoff then
		strMaxCount = string.format("%3.f", nMaxCraftable)
	else
		strMaxCount = "*"
		nMaxCraftable = knMaxCutoff
	end	
	
	wndTarget:FindChild("CostsPerRepeat"):SetAmount(nCostPerItem)
	local wndCountSpinner = wndTarget:FindChild("CountSpinner")
	wndCountSpinner:SetMinMax(1, nMaxCraftable)
	wndCountSpinner:SetValue(nMaxCraftable)
	wndTarget:FindChild("MaxCount"):SetText(strMaxCount)
	
	local wndChance = wndTarget:FindChild("SuccessChance")
	wndChance:SetText("100%")		-- TODO: set this to real chance, color appropriately
	
	wndTarget:FindChild("CostsTotal"):SetAmount(nCostPerItem * nMaxCraftable)	
end

function TradeskillSchematics:OnAddRepeatItem( wndHandler, wndControl, eMouseButton )
	if wndHandler ~= wndControl then
		return
	end
	
	if not self.wndQueue then
		return
	end
	
	self.wndQueue:Show(true)
	local queue = self.wndQueue:GetData()
	
	local wndItem = wndControl:GetParent()
	
	local tSchematicInfo = wndItem:GetData()
	local nCount = wndItem:FindChild("CountSpinner"):GetValue()
	
	queue:Push(tSchematicInfo, nCount)
end

function TradeskillSchematics:OnRepeatItemCountChanged(wndHandler, wndControl, fNewValue, fOldValue )
	if wndHandler ~= wndControl then
		return
	end
	
	local wndItem = wndControl:GetParent():GetParent()
	local costPerItem = wndItem:FindChild("CostsPerRepeat"):GetAmount()
	wndItem:FindChild("CostsTotal"):SetAmount(math.floor(costPerItem * fNewValue))
end

function TradeskillSchematics:OnAutoQueueClose(wndHandler, wndControl)
	if wndHandler ~= wndControl then
		return		
	end
	
	self.wndQueue:Show(false)
end
  
local TradeskillSchematicsInst = TradeskillSchematics:new()
TradeskillSchematicsInst:Init()
