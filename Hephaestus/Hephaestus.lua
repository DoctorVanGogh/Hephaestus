-----------------------------------------------------------------------------------------------
-- Client Lua Script for Hephaestus
-- Copyright 2014 by DoctorVanGogh on Wildstar Forums - all rights reserved
-----------------------------------------------------------------------------------------------

require "GameLib"
require "CraftingLib"
require "Tooltip"

local kstrAddonName = "Hephaestus"


local Hephaestus = Apollo.GetPackage("Gemini:Addon-1.1").tPackage:NewAddon(
																	kstrAddonName, 
																	false,
																	{
																		"Drafto:Lib:inspect-1.2",
																		"Gemini:Logging-1.2",
																		"Gemini:Locale-1.0",
																		"Gemini:DB-1.0",
																		"CRBTradeskills",
																		"DoctorVanGogh:Lib:AddonRegistry",
																		"DoctorVanGogh:Hephaestus:CraftUtil",																		
																		"DoctorVanGogh:Hephaestus:CraftQueue",																		
																	},
																	"Gemini:Hook-1.0"
																)
local glog
local inspect
local CraftUtil
local CraftQueue 
local GeminiLocale

local knMaxCutoff = 1000

local knMinQueueWidth = 500
local knMinQueueHeight = 340

local kstrSpriteBlockerFail = "CRB_ActionBarIconSprites:sprActionBar_OrangeBorder"
local kstrSpriteBlockerPass = "CRB_ActionBarIconSprites:sprActionBar_GreenBorder"


local kstrSpriteBlockerDefault = "IconSprites:Icon_Mission_Explorer_ScavengerHunt"

local kstrBlockerLocalizationKeyFormat="Blocker%s"

-- GOTCHA: values should be defined in localiztion as string.format(kstrBlockerLocalizationKeyFormat, [value])
local ktCraftBlockers = {
	CraftingStation = "CraftingStation",
	Mounted = "Mounted",
	Ability = "Ability",
	Materials = "Materials",
	Inventory = "Inventory"
}

local ktCraftBlockersSprites = {
	[ktCraftBlockers.CraftingStation] 		= "IconSprites:Icon_MapNode_Map_Tradeskill",
	[ktCraftBlockers.Mounted]				= "IconSprites:Icon_Windows32_UI_CRB_InterfaceMenu_MountCustomization",
	[ktCraftBlockers.Ability]				= "DatachronSprites:btnAbilityNormal",
	[ktCraftBlockers.Materials]				= "IconSprites:Icon_Windows32_UI_CRB_InterfaceMenu_Credd",	
	[ktCraftBlockers.Inventory]				= "CRB_BaseBarSprites:btnHUD_InventoryBagPressed"
}

local ktAllowedTradeskillsNonAutocraft = {
	[CraftingLib.CodeEnumTradeskill.Architect] = true,
	[CraftingLib.CodeEnumTradeskill.Cooking] = true,
	[CraftingLib.CodeEnumTradeskill.Augmentor] = true	
}

local karPowerCoreTierToString =
{
	[CraftingLib.CodeEnumTradeskillTier.Novice] 	= Apollo.GetString("CRB_Tradeskill_Quartz"),
	[CraftingLib.CodeEnumTradeskillTier.Apprentice] = Apollo.GetString("CRB_Tradeskill_Sapphire"),
	[CraftingLib.CodeEnumTradeskillTier.Journeyman] = Apollo.GetString("CRB_Tradeskill_Diamond"),
	[CraftingLib.CodeEnumTradeskillTier.Artisan] 	= Apollo.GetString("CRB_Tradeskill_Chrysalus"),
	[CraftingLib.CodeEnumTradeskillTier.Expert] 	= Apollo.GetString("CRB_Tradeskill_Starshard"),
	[CraftingLib.CodeEnumTradeskillTier.Master] 	= Apollo.GetString("CRB_Tradeskill_Hybrid"),
}

local function GetBlockerStatus(self, eKey)
	if not self.wndQueue then
		return nil
	end

	if eKey == ktCraftBlockers.CraftingStation then
		local dummy, bResult = CraftUtil:CanCraft()
		return bResult
	elseif eKey == ktCraftBlockers.Mounted then
		local dummy1, dummy2, bResult = CraftUtil:CanCraft()
		return bResult	
	elseif eKey == ktCraftBlockers.Ability then
		local dummy1, dummy2, dummy3, bResult = CraftUtil:CanCraft()
		return bResult	
	elseif eKey == ktCraftBlockers.Materials then
		return self.wndQueue:GetData():Peek() and (self.wndQueue:GetData():Peek():GetMaxCraftable() > 0)
	elseif eKey == ktCraftBlockers.Inventory then
		return self.wndQueue:GetData():Peek() and (CraftUtil:GetInventoryCountForItem(self.wndQueue:GetData():Peek():GetSchematicInfo().itemOutput))
	end
end 


-- Replaces Hephaestus:OnLoad
function Hephaestus:OnInitialize()
	-- import inspect
	inspect = Apollo.GetPackage("Drafto:Lib:inspect-1.2").tPackage	

	-- setup logger
	local GeminiLogging = Apollo.GetPackage("Gemini:Logging-1.2").tPackage
	glog = GeminiLogging:GetLogger({
		level = GeminiLogging.INFO,
		pattern = "%d [%c:%n] %l - %m",
		appender = "GeminiConsole"
	})	
	self.log = glog	

	-- get localization
	GeminiLocale = Apollo.GetPackage("Gemini:Locale-1.0").tPackage
	self.localization = GeminiLocale:GetLocale(kstrAddonName)
	
	-- get tradeskill schematics reference
	local AddonRegistry = Apollo.GetPackage("DoctorVanGogh:Lib:AddonRegistry").tPackage
	self.tTradeskillSchematics = AddonRegistry:GetAddon("Tradeskills", "TradeskillSchematics")
	
	-- import CraftUtil
	CraftUtil = Apollo.GetPackage("DoctorVanGogh:Hephaestus:CraftUtil").tPackage
	
	-- import CraftQueue
	CraftQueue = Apollo.GetPackage("DoctorVanGogh:Hephaestus:CraftQueue").tPackage

	Apollo.RegisterEventHandler("WindowManagementReady", "OnWindowManagementReady", self)  	
	Apollo.RegisterEventHandler("InterfaceMenuListHasLoaded", "OnInterfaceMenuListHasLoaded", self)
	
	-- init db
	local dbDefaults = {
		char = {
			currentQueue = false
		},
		global = {
			queues = {}
		}
	}	
	self.db = Apollo.GetPackage("Gemini:DB-1.0").tPackage:New(self, dbDefaults)
	self.db.RegisterCallback(self, "OnDatabaseShutdown", "DatabaseShutdown")

end

-- Called when player has loaded and entered the world
function Hephaestus:OnEnable()
	self.xmlDoc = XmlDoc.CreateFromFile("Hephaestus.xml")
	self.xmlDoc:RegisterCallback("OnDocumentReady", self)  
end


function Hephaestus:OnDocumentReady()
	if not self.xmlDoc then
		return
	end
		
	self.wndQueue = Apollo.LoadForm(self.xmlDoc, "CraftQueue", nil, self)
	GeminiLocale:TranslateWindow(self.localization, self.wndQueue)	
	self.wndQueue:SetSizingMinimum(knMinQueueWidth, knMinQueueHeight)
	self.wndQueue:Show(false, true)
		
	local tCraftQueue = CraftQueue{}
		
	tCraftQueue.RegisterCallback(self, CraftQueue.EventOnCollectionChanged, "CollectionChanged")
	tCraftQueue.RegisterCallback(self, CraftQueue.EventOnPropertyChanged, "PropertyChanged")

	if self.db.char.currentQueue  then
		tCraftQueue:LoadFrom(self.db.char.currentQueue)	
	end
	
	self.wndQueue:SetData(tCraftQueue)		
	
	self.wndBlockersContainer = self.wndQueue:FindChild("BlockersContainer")
	for key, strName in pairs(ktCraftBlockers) do
		local wndBlocker = Apollo.LoadForm(self.xmlDoc, "StatusBlocker", self.wndBlockersContainer, self)
		wndBlocker:SetData(key)
		wndBlocker:FindChild("Icon"):SetSprite(ktCraftBlockersSprites[key] or kstrSpriteBlockerDefault)
	end
	
	self.wndBlockersContainer:ArrangeChildrenHorz()

	glog:debug("OnDocumentReady - db.char.currentQueue=%s", inspect(self.db.char.currentQueue))
	if self.db.char.currentQueue then
		tCraftQueue:LoadFrom(self.db.char.currentQueue)
	end	
	Apollo.RegisterSlashCommand("cq", "OnCraftQueue", self)
	Apollo.RegisterEventHandler("ToggleHephaestusCraftQueue", "ToggleQueueWindow", self)
	
	self:PostHook(self.tTradeskillSchematics, "Initialize")
	self:PostHook(self.tTradeskillSchematics, "DrawSchematic")
		
	if self.bWindowManagementReady then
		Event_FireGenericEvent("WindowManagementAdd", {wnd = self.wndQueue, strName = "Hephaestus Craft Queue"})	
	end
	
	Apollo.RegisterTimerHandler("Hephaestus_QueueBlockerUpdates", "OnUpdateQueueBlockers", self)
	
	Apollo.CreateTimer("Hephaestus_QueueBlockerUpdates", 1, true)	
end

function Hephaestus:CollectionChanged(sEvent, dummy, strChangeType, tItems)
	glog:debug("CollectionChanged(%s, %.f items)", strChangeType, tItems and #tItems or 0)
	if strChangeType == CraftQueue.CollectionChanges.Reset then 
		self:RecreateQueue()	
		self:UpdateInterfaceMenuAlerts()
	elseif strChangeType == CraftQueue.CollectionChanges.Added then 
		--for idx, item in ipairs(tItems) do
		--	self:AddQueueItem(item)
		--end
		--self:RefreshQueueHeader()
		
		self:RecreateQueue()				-- TODO: remove this once precursor/successor updates work
		self:UpdateInterfaceMenuAlerts()
	elseif strChangeType == CraftQueue.CollectionChanges.Removed then 
		--for idx, item in ipairs(tItems) do
		--	self:RemoveQueueItem(item)
		--end
		--self:RefreshQueueHeader()		
		
		self:RecreateQueue()				-- TODO: remove this once precursor/successor updates work
		self:UpdateInterfaceMenuAlerts()		
	elseif strChangeType == CraftQueue.CollectionChanges.Refreshed then 
		for idx, item in ipairs(tItems) do
			self:RefreshQueueItem(item)
		end	
	end	
	glog:debug("CollectionChanged DONE")
end

function Hephaestus:PropertyChanged(sEvent, dummy, strProperty)
	glog:debug("PropertyChanged(%s, nil, %s)",sEvent, strProperty)
	if strProperty == CraftQueue.PropertyIsRunning then
		self:IsRunningChanged()
	end
end


function Hephaestus:OnWindowManagementReady()
	if self.wndQueue then
		Event_FireGenericEvent("WindowManagementAdd", {wnd = self.wndQueue, strName = "Hephaestus Craft Queue"})		
	else
		self.bWindowManagementReady = true
	end
end


function Hephaestus:OnInterfaceMenuListHasLoaded()
	Event_FireGenericEvent(
		"InterfaceMenuList_NewAddOn", 
		kstrAddonName, 
		{
			"ToggleHephaestusCraftQueue", 
			"", 
			"Icon_Windows32_UI_CRB_InterfaceMenu_Tradeskills"}
		)

	self:UpdateInterfaceMenuAlerts()
end

function Hephaestus:UpdateInterfaceMenuAlerts()
	local nCount = (self.wndQueue and self.wndQueue:GetData() and self.wndQueue:GetData():GetCount()) or 0

	Event_FireGenericEvent("InterfaceMenuList_AlertAddOn", kstrAddonName, {nCount > 0, nil, nCount})
end


function Hephaestus:OnDisable()
  -- Unhook, Unregister Events, Hide/destroy windows that you created.
end

function Hephaestus:DatabaseShutdown(db)		
	self.db.char.currentQueue = self.wndQueue:GetData():Serialize()
end

------------------------------------------------------------
-- TradeskillSchematics Hooks
------------------------------------------------------------
--[[ 
	Slightly move the original 'Simple Craft' & 'Load Schematic'
	buttons, add out own dropdown next to them
	
	add 'x5' to output icon
]]
function Hephaestus:Initialize(luaCaller, wndParent, nSchematicId, strSearchQuery)
	local wndRightBottomPreview = luaCaller.wndMain:FindChild("RightBottomCraftPreview")

	self.wndAddQueueDropdown = wndRightBottomPreview:FindChild("AddQueueDropdown")	
	
	if not self.wndAddQueueDropdown then	
		-- move buttons out of the way
		wndRightBottomPreview:FindChild("RightBottomCraftBtn"):SetAnchorOffsets(-218, 13, -33, 61)
		wndRightBottomPreview:FindChild("RightBottomSimpleCraftBtn"):SetAnchorOffsets(-218, 13, -33, 61)
		
		-- add our dropdown arrow
		self.wndAddQueueDropdown = Apollo.LoadForm(self.xmlDoc, "AddQueueDropdown", wndRightBottomPreview, self)	
		GeminiLocale:TranslateWindow(self.localization, self.wndAddQueueDropdown)			
		self.wndDropdownRepeats = self.wndAddQueueDropdown:GetChildren()[1]
		self.wndAddQueueDropdown:AttachWindow(self.wndDropdownRepeats)			
	end
	
	local wndSchematicIcon = luaCaller.wndMain:FindChild("SchematicIcon")
	
	local wndOutputCount = wndSchematicIcon:FindChild("SchematicOutputCount")
	
	if not wndOutputCount  then
		wndOutputCount = Apollo.LoadForm(self.xmlDoc, "SchematicOutputCount", wndSchematicIcon, self)
		GeminiLocale:TranslateWindow(self.localization, wndOutputCount)			
		self.wndOutputCount = wndOutputCount
	end	
	
end

--[[
	Modifications:
		- Add 'x5' to output icon
		- Make Materials clickable for auto search/navigation
		- Add queue dropdown
]]
function Hephaestus:DrawSchematic(luaCaller, tSchematic)
	local tSchematicInfo = CraftingLib.GetSchematicInfo(tSchematic.nSchematicId)	
	
	local wndSchem = luaCaller.wndMain:FindChild("RightSide")	
	
	--[[ add output count ]]
	if self.wndOutputCount then
		local nCraftCount = tSchematicInfo.nCreateCount or 1
		local nCritCount = tSchematicInfo.nCritCount or 1
 
		local strText
		
		if nCraftCount ~= nCritCount then
			strText = string.format("x %.f(*%.f*)", nCraftCount, nCritCount)		
		else
			strText = string.format("x %.f", nCraftCount)
		end
		
		self.wndOutputCount:SetText(strText)
	end

	-- [[ add 'button' around materials, so we can catch the click events]]
	-- Materials
	local bHaveEnoughMats = true
	local nNumCraftable = 9000
	
	local wndMaterials = wndSchem:FindChild("MaterialsScroll")
	
	wndMaterials:DestroyChildren()
	for key, tMaterial in pairs(tSchematicInfo.tMaterials) do
		if tMaterial.nAmount > 0 then
			local wndMaterial = Apollo.LoadForm(self.xmlDoc, "MaterialsItem", wndMaterials, self)
			local nBackpackCount = tMaterial.itemMaterial:GetBackpackCount()
			wndMaterial:FindChild("MaterialsIcon"):SetSprite(tMaterial.itemMaterial:GetIcon())
			wndMaterial:FindChild("MaterialsName"):SetText(tMaterial.itemMaterial:GetName())
			wndMaterial:FindChild("MaterialsIcon"):SetText(String_GetWeaselString(Apollo.GetString("Achievements_ProgressBarProgress"), nBackpackCount, tMaterial.nAmount))
			wndMaterial:FindChild("MaterialsIconNotEnough"):Show(nBackpackCount < tMaterial.nAmount)
			luaCaller:HelperBuildItemTooltip(wndMaterial, tMaterial.itemMaterial)

			nNumCraftable = math.min(nNumCraftable, math.floor(nBackpackCount / tMaterial.nAmount))
			bHaveEnoughMats = bHaveEnoughMats and nBackpackCount >= tMaterial.nAmount
		end
	end

	-- Fake Material (Power Cores)
	if not luaCaller.bCoordCraft then
		local tAvailableCores = CraftingLib.GetAvailablePowerCores(tSchematic.nSchematicId)
		if tAvailableCores then -- Some crafts won't have power cores
			local wndMaterial = Apollo.LoadForm(self.xmlDoc, "MaterialsItem", wndMaterials, self)
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
	
	wndMaterials:ArrangeChildrenTiles(0)		
	
	
	--[[ add dropdown ]]
 	if not self.wndDropdownRepeats then
 		return
 	end

	if not tSchematicInfo then
		return
	end
	
	local repeatParent = self.wndDropdownRepeats:FindChild("RepeatDropdownBG_Art")
	local repeatContainer = repeatParent:FindChild("RepeatVariantsHolder")
	
	repeatContainer:DestroyChildren()
	local wndRepeatItem = Apollo.LoadForm(self.xmlDoc, "RepeatItem", repeatContainer, self)
	GeminiLocale:TranslateWindow(self.localization, wndRepeatItem)	
	self:UpdateRepeatItem(tSchematicInfo, wndRepeatItem)
	-- TODO: add variants

	repeatContainer:ArrangeChildrenVert()
	repeatParent:ArrangeChildrenVert()
	
	-- TODO: add 'blueprints' for circuit crafts
	self.wndAddQueueDropdown:Enable(tSchematicInfo.bIsAutoCraft or ktAllowedTradeskillsNonAutocraft[tSchematicInfo.eTradeskillId] or false)
end

------------------------------------------------------------
-- Hephaestus Event-Handlers
------------------------------------------------------------

function Hephaestus:OnUpdateQueueBlockers()
	if not self.wndBlockersContainer then
		return
	end


	
	for idx, wndBlocker in ipairs(self.wndBlockersContainer:GetChildren()) do
		local eKey = wndBlocker:GetData()
		local bStatus = GetBlockerStatus(self, eKey)
		local strTooltip = self.localization[string.format(kstrBlockerLocalizationKeyFormat, ktCraftBlockers[eKey])]
				
		if bStatus == nil then
			wndBlocker:FindChild("Status"):SetSprite(nil)
			if strTooltip then
				wndBlocker:SetTooltip(string.format(strTooltip, Apollo.GetString("CRB_Undecided")))
			end					
		elseif bStatus then
			wndBlocker:FindChild("Status"):SetSprite(kstrSpriteBlockerPass)				
			if strTooltip then
				wndBlocker:SetTooltip(string.format(strTooltip, Apollo.GetString("CRB_Yes")))
			end					
		else
			wndBlocker:FindChild("Status"):SetSprite(kstrSpriteBlockerFail)						
			if strTooltip then
				wndBlocker:SetTooltip(string.format(strTooltip, Apollo.GetString("CRB_No")))
			end					
		end
	end
end

function Hephaestus:RefreshQueueHeader()
	if not self.wndQueue or not self.wndQueue:GetData() then	
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
	
	self:OnUpdateQueueBlockers()
end

function Hephaestus:RecreateQueue()	
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
		GeminiLocale:TranslateWindow(self.localization, wndItem)
		self:RefreshQueueItem(item, wndItem, queue, idx)							
	end	
	queueContainer:ArrangeChildrenVert()	
		
end

function Hephaestus:RefreshQueue()
	if not self.wndQueue then	
		return
	end	
	local queue = self.wndQueue:GetData()	
	
	self:RefreshQueueHeader()
	
	-- recreate list
	local queueContainer = self.wndQueue:FindChild("QueueContainer")	
	for idx, wndItem in ipairs(queueContainer:GetChildren()) do
		local item = wndItem:GetData()
		self:RefreshQueueItem(item, wndItem, queue, idx)							
	end	
	queueContainer:ArrangeChildrenVert()			
end

function Hephaestus:AddQueueItem(item)
	glog:debug("Hephaestus:AddQueueItem(%s)", tostring(item))
	local queueContainer = self.wndQueue:FindChild("QueueContainer")	
	
	local wndItem = Apollo.LoadForm(self.xmlDoc, "QueueItem", queueContainer , self)
	GeminiLocale:TranslateWindow(self.localization, wndItem)
	self:RefreshQueueItem(item, wndItem, queue, idx)	
	
	queueContainer:ArrangeChildrenVert()		
end

function Hephaestus:RefreshQueueItemMoveButtons(wndQueueItem, bForwardEnable, bBackwardEnable)
	glog:debug("RefreshQueueItemMoveButtons(%s, %s)", tostring(bForwardEnable), tostring(bBackwardEnable))
	local btnUp = wndQueueItem:FindChild("MoveUpButton")
	local btnDown = wndQueueItem:FindChild("MoveDownButton")

	btnUp:Enable(bForwardEnable)
	btnDown:Enable(bBackwardEnable)		
end


function Hephaestus:RefreshQueueItem(item, wndItem, queue, index)
	glog:debug("Hephaestus:RefreshQueueItem(%s)", tostring(item))
	if not item then
		glog:debug("nil item:")
		glog:debug(debug.traceback())
		return
	end	
	
	local wndQueueContainer = self.wndQueue:FindChild("QueueContainer")
	
	if not wndItem or not index then
		for idx, wnd in ipairs(wndQueueContainer:GetChildren()) do		
			if item == wnd:GetData() then
				wndItem = wnd
				index = idx
				break
			end		
		end
	end
	
	if not wndItem then
		glog:error("wndItem is nil - %s", debug.traceback())
		return 
	end
	
	if not queue then
		queue = item:GetQueue()
	end
	
	local tSchematicInfo = item:GetSchematicInfo()

	local nAmount = item:GetAmount()		
	local bCurrentlyRunning = queue:IsRunning() and queue:Peek() == item or false
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

	self:HelperBuildItemTooltip(wndItem:FindChild("Item"), tSchematicInfo.itemOutput)
	
	wndItem:FindChild("Icon"):SetSprite(tSchematicInfo.itemOutput:GetIcon())
	wndItem:FindChild("Name"):SetText(tSchematicInfo.strName)
	
	spinnerAmount:Enable(not bCurrentlyRunning)
	spinnerAmount:SetMinMax(1, math.min(nMaxCraftable, 999))
	spinnerAmount:SetValue(nAmount)
			
	local bEnableUp = index and (index > 1) and (index > 2 or not bCurrentlyRunning)
	local bEnableDown = index and (index < queue:GetCount()) and (index > 1 or not bCurrentlyRunning)
			
	self:RefreshQueueItemMoveButtons(wndItem, bEnableUp, bEnableDown)
	
	btnRemove:Enable(not bCurrentlyRunning)
	
	wndItem:SetData(item)
end

function Hephaestus:RemoveQueueItem(item, wndItem)
	glog:debug("RemoveQueueItem %s", tostring(item))

	local queueContainer = self.wndQueue:FindChild("QueueContainer")

	if not wndItem then
		for idx, wnd in ipairs(queueContainer:GetChildren()) do		
			if item == wnd:GetData() then
				wndItem = wnd
				break
			end		
		end
	end
	
	if not wndItem then
		glog:error("wndItem is nil")
		return 
	end

	wndItem:Destroy()	
	queueContainer:ArrangeChildrenVert()	
end

function Hephaestus:OnQueueItemCountChanged(wndHandler, wndControl, fNewValue, fOldValue )
	if wndHandler ~= wndControl then
		return
	end
	
	wndControl:GetParent():GetParent():GetData():SetAmount(fNewValue)
end

function Hephaestus:OnRemoveQueueItem(wndHandler, wndControl)
	if wndHandler ~= wndControl then
		return
	end
		
	if not self.wndQueue then	
		return
	end

	local wndItem = wndControl:GetParent()	
	local item = wndItem:GetData()
	
	item:Remove()		

end

function Hephaestus:OnQueueClear(wndHandler, wndControl)
	if wndHandler ~= wndControl then
		return
	end

	if not self.wndQueue then	
		return
	end
	
	local queue = self.wndQueue:GetData()	
	queue:Clear()	
end

function Hephaestus:OnQueueStart(wndHandler, wndControl)
	if wndHandler ~= wndControl then
		return
	end
	
	if not self.wndQueue then	
		return
	end
	
	local queue = self.wndQueue:GetData()	
	queue:Start()
end

function Hephaestus:OnQueueStop(wndHandler, wndControl)
	if wndHandler ~= wndControl then
		return
	end
	
	if not self.wndQueue then	
		return
	end
	
	local queue = self.wndQueue:GetData()	
	queue:Stop()
end

function Hephaestus:IsRunningChanged()
	glog:debug("IsRunningChanged")
	self:RefreshQueue()

	local queue = self.wndQueue:GetData()
	
	-- add frame listener while crafting for castbar
	if queue:IsRunning() then
		glog:debug(" => Started")
		Apollo.RegisterEventHandler("VarChange_FrameCount", "OnFrame", self)		
	else
		glog:debug(" => Stopped")
		Apollo.RemoveEventHandler("VarChange_FrameCount", self)	
		
		self.wndQueue:FindChild("CastingFrame"):Show(false)	-- hide cast bar
	end
	
end

function Hephaestus:OnFrame()
	local unitPlayer = GameLib.GetPlayerUnit()
	
	self:UpdateCastingBar(self.wndQueue:FindChild("BG_Art"), unitPlayer)
end

-- copied almost 100% verbatim frim TargetFrame, TargetFrame.lua 
function Hephaestus:UpdateCastingBar(wndFrame, unitCaster)
	-- Casting Bar Update

	local bShowCasting = false
	local bEnableGlow = false
	local nZone = 0
	local nMaxZone = 0
	local nDuration = 0
	local nElapsed = 0
	local strSpellName = ""
	local nElapsed = 0
	local eType = Unit.CodeEnumCastBarType.None
	local strFillSprite = ""
	local strBaseSprite = ""
	local strGlowSprite = ""

	local wndCastFrame = wndFrame:FindChild("CastingFrame")
	local wndCastProgress = wndFrame:FindChild("CastingBar")
	local wndCastName = wndFrame:FindChild("CastingName")
	local wndCastBase = wndFrame:FindChild("CastingBase")

	-- results for GetCastBarType can be:
	-- Unit.CodeEnumCastBarType.None
	-- Unit.CodeEnumCastBarType.Normal
	-- Unit.CodeEnumCastBarType.Telegraph_Backlash
	-- Unit.CodeEnumCastBarType.Telegraph_Evade
	if unitCaster:ShouldShowCastBar() then
		eType = unitCaster:GetCastBarType()


		if eType ~= Unit.CodeEnumCastBarType.None then

			bShowCasting = true
			bEnableGlow = true
			nZone = 0
			nMaxZone = 1
			nDuration = unitCaster:GetCastDuration()
			nElapsed = unitCaster:GetCastElapsed()
			if wndCastProgress ~= nil then
				wndCastProgress:SetTickLocations(0, 100, 200, 300)
			end

			strSpellName = unitCaster:GetCastName()
		end
	end

	wndCastFrame:Show(bShowCasting)
	if wndCastProgress ~= nil then
		wndCastProgress:Show(bShowCasting)
		wndCastName:Show(bShowCasting)
	end

	if bShowCasting and nDuration > 0 and nMaxZone > 0 then
		if wndCastProgress ~= nil then
			-- add a countdown timer if nDuration is > 4.999 seconds.
			local strDuration = nDuration > 4999 and " (" .. string.format("%00.01f", (nDuration-nElapsed)/1000)..")" or ""
			
			wndCastProgress:Show(bShowCasting)
			wndCastProgress:SetMax(nDuration)
			wndCastProgress:SetProgress(nElapsed)
			wndCastProgress:EnableGlow(bEnableGlow)
			wndCastName:SetText(strSpellName .. strDuration)
		end
	end

end



function Hephaestus:ToggleQueueWindow()
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



function Hephaestus:OnCraftQueue()
	self:ToggleQueueWindow()
end

function Hephaestus:UpdateRepeatItem(tSchematicInfo, wndTarget)
	wndTarget:SetData(tSchematicInfo)
	wndTarget:FindChild("Name"):SetText(tSchematicInfo.strName)
	wndTarget:FindChild("Icon"):SetSprite(tSchematicInfo.itemOutput:GetIcon())
	
	local nCostPerItem = 0	-- TODO: calc by moves...
	local nMaxCraftable = CraftUtil:GetMaxCraftableForSchematic(tSchematicInfo)	-- TODO: factor in money, once things actually cost something
	
	local strMaxCount
	if nMaxCraftable < knMaxCutoff then
		strMaxCount = string.format("%3.f", nMaxCraftable)
	else
		strMaxCount = "*"
		nMaxCraftable = knMaxCutoff
	end	

	self:HelperBuildItemTooltip(wndTarget:FindChild("Item"), tSchematicInfo.itemOutput)	
	
	wndTarget:FindChild("CostsPerRepeat"):SetAmount(nCostPerItem)
	local wndCountSpinner = wndTarget:FindChild("CountSpinner")
	wndCountSpinner:SetMinMax(1, nMaxCraftable)
	wndCountSpinner:SetValue(nMaxCraftable)
	wndTarget:FindChild("MaxCount"):SetText(strMaxCount)
	
	local wndChance = wndTarget:FindChild("SuccessChance")
	wndChance:SetText("100%")		-- TODO: set this to real chance, color appropriately
	
	wndTarget:FindChild("CostsTotal"):SetAmount(nCostPerItem * nMaxCraftable)	
end

function Hephaestus:OnAddRepeatItem( wndHandler, wndControl, eMouseButton )
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

function Hephaestus:OnRepeatItemCountChanged(wndHandler, wndControl, fNewValue, fOldValue )
	if wndHandler ~= wndControl then
		return
	end
	
	local wndItem = wndControl:GetParent():GetParent()
	local costPerItem = wndItem:FindChild("CostsPerRepeat"):GetAmount()
	wndItem:FindChild("CostsTotal"):SetAmount(math.floor(costPerItem * fNewValue))
end

function Hephaestus:OnAutoQueueClose(wndHandler, wndControl)
	if wndHandler ~= wndControl then
		return		
	end
	
	self.wndQueue:Show(false)
end

function Hephaestus:HelperBuildItemTooltip(wndArg, itemCurr)
	Tooltip.GetItemTooltipForm(self, wndArg, itemCurr, {bPrimary = true, bSelling = false, itemCompare = itemCurr:GetEquippedItemForItemType()})
end


function Hephaestus:OnMoveQueueItemForward( wndHandler, wndControl, eMouseButton )
	if wndHandler ~= wndControl then
		return		
	end
	
	local item = wndControl:GetParent():GetData()
	
	item:MoveForward()	
end


function Hephaestus:OnMoveQueueItemBackward( wndHandler, wndControl, eMouseButton )
	if wndHandler ~= wndControl then
		return		
	end
	
	local item = wndControl:GetParent():GetData()
	
	item:MoveBackward()	
end

function Hephaestus:OnMaterialItemClick(wndHandler, wndControl)
	if wndHandler ~= wndControl then
		return
	end
	
	local strMaterialName = wndHandler:FindChild("MaterialsName"):GetText()
		
	local wndMain = self.tTradeskillSchematics.wndMain
	wndMain:FindChild("SearchTopLeftInputBox"):SetText(strMaterialName)
	self.tTradeskillSchematics:OnSearchTopLeftInputBoxChanged()	
end

