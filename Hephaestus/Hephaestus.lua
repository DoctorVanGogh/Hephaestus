-----------------------------------------------------------------------------------------------
-- Client Lua Script for Hephaestus
-- Copyright 2014 by DoctorVanGogh on Wildstar Forums - all rights reserved
-----------------------------------------------------------------------------------------------

require "GameLib"
require "CraftingLib"

local Hephaestus = Apollo.GetPackage("Gemini:Addon-1.1").tPackage:NewAddon(
																	"Hephaestus", 
																	false,
																	{
																		"Drafto:Lib:inspect-1.2",
																		"Gemini:Logging-1.2",
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

-- Replaces Hephaestus:OnLoad
function Hephaestus:OnInitialize()
	-- import inspect
	inspect = Apollo.GetPackage("Drafto:Lib:inspect-1.2").tPackage	

	-- setup logger
	local GeminiLogging = Apollo.GetPackage("Gemini:Logging-1.2").tPackage
	glog = GeminiLogging:GetLogger({
		level = GeminiLogging.DEBUG,
		pattern = "%d [%c:%n] %l - %m",
		appender = "GeminiConsole"
	})	
	self.log = glog	

	-- get tradeskill schematics reference
	local AddonRegistry = Apollo.GetPackage("DoctorVanGogh:Lib:AddonRegistry").tPackage
	self.tTradeskillSchematics = AddonRegistry:GetAddon("Tradeskills", "TradeskillSchematics")
	
	-- import CraftUtil
	CraftUtil = Apollo.GetPackage("DoctorVanGogh:Hephaestus:CraftUtil").tPackage
	
	-- import CraftQueue
	CraftQueue = Apollo.GetPackage("DoctorVanGogh:Hephaestus:CraftQueue").tPackage

	Apollo.RegisterEventHandler("WindowManagementReady", "OnWindowManagementReady", self)  	
end

-- Called when player has loaded and entered the world
function Hephaestus:OnEnable()
  -- Do more initialization here, that really enables the use of your addon.
  -- Register Events, Hook functions, Create Frames, Get information from 
  -- the game that wasn't available in OnInitialize.  Here you can Load XML, etc.

	self.xmlDoc = XmlDoc.CreateFromFile("Hephaestus.xml")
	self.xmlDoc:RegisterCallback("OnDocumentReady", self)  
  
end

function Hephaestus:OnDocumentReady()
	if not self.xmlDoc then
		return
	end
		
	self.wndQueue = Apollo.LoadForm(self.xmlDoc, "AutocraftQueue", nil, self)
	self.wndQueue:Show(false, true)
		
	local tCraftQueue = CraftQueue{}
	tCraftQueue:GetChangedHandlers():Add(self, "RecreateQueue")
	tCraftQueue:GetItemChangedHandlers():Add(self, "RefreshQueueItem")
	tCraftQueue:GetItemRemovedHandlers():Add(self, "RemovedQueueItem")	
	
	self.wndQueue:SetData(tCraftQueue)	
	
	Apollo.RegisterSlashCommand("ac", "OnAutoCraft", self)
	
	self:PostHook(self.tTradeskillSchematics, "Initialize")
	self:PostHook(self.tTradeskillSchematics, "DrawSchematic")
		
	if self.bWindowManagementReady then
		Event_FireGenericEvent("WindowManagementAdd", {wnd = self.wndQueue, strName = "Hephaestus Craft Queue"})	
	end
end


function Hephaestus:OnWindowManagementReady()
	if self.wndQueue then
		Event_FireGenericEvent("WindowManagementAdd", {wnd = self.wndQueue, strName = "Hephaestus Craft Queue"})		
	else
		self.bWindowManagementReady = true
	end
end


function Hephaestus:OnDisable()
  -- Unhook, Unregister Events, Hide/destroy windows that you created.
  -- You would probably only use an OnDisable if you want to 
  -- build a "standby" mode, or be able to toggle modules on/off.
end

------------------------------------------------------------
-- TradeskillSchematics Hooks
------------------------------------------------------------
--[[ 
	Slightly move the original 'Simple Craft' & 'Load Schematic'
	buttons, add out own dropdown next to them
]]
function Hephaestus:Initialize(luaCaller, wndParent, nSchematicId, strSearchQuery)
	local wndRightBottomPreview = luaCaller.wndMain:FindChild("RightBottomCraftPreview")

	local wndAddQueueDropdown = wndRightBottomPreview:FindChild("AddQueueDropdown")
	
	if not wndAddQueueDropdown then	
		-- move buttons out of the way
		wndRightBottomPreview:FindChild("RightBottomCraftBtn"):SetAnchorOffsets(-218, 13, -33, 61)
		wndRightBottomPreview:FindChild("RightBottomSimpleCraftBtn"):SetAnchorOffsets(-218, 13, -33, 61)
		
		-- add our dropdown arrow
		wndAddQueueDropdown = Apollo.LoadForm(self.xmlDoc, "AddQueueDropdown", wndRightBottomPreview, self)	
		self.wndDropdownRepeats = wndAddQueueDropdown:GetChildren()[1]
		wndAddQueueDropdown:AttachWindow(self.wndDropdownRepeats)			
	end
end

function Hephaestus:DrawSchematic(luaCaller, tSchematic)

	if not self.wndDropdownRepeats then
		return
	end

	local tSchematicInfo = CraftingLib.GetSchematicInfo(tSchematic.nSchematicId)
	
	if not tSchematicInfo then
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

------------------------------------------------------------
-- Hephaestus Event-Handlers
------------------------------------------------------------

---- New queue stuff - TODO: refactor outside this addon
local knMaxCutoff = 1000


function Hephaestus:UpdateCastBar()
	-- TODO: implement
end

function Hephaestus:RefreshQueueHeader()
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
		self:RefreshQueueItem(item, wndItem, queue)							
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
		self:RefreshQueueItem(item, wndItem, queue)							
	end	
	queueContainer:ArrangeChildrenVert()			
end

function Hephaestus:RefreshQueueItem(item, wndItem, queue)
	glog:debug("Hephaestus:RefreshQueueItem(%s)", tostring(item))
	if not item then
		glog:debug("nil item:")
		glog:debug(debug.traceback())
		return
	end	
	
	if not wndItem then
		for idx, wnd in ipairs(self.wndQueue:FindChild("QueueContainer"):GetChildren()) do		
			if item == wnd:GetData() then
				wndItem = wnd
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

function Hephaestus:RemovedQueueItem(item, wndItem)
	if not wndItem then
		for idx, wnd in ipairs(self.wndQueue:FindChild("QueueContainer"):GetChildren()) do		
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
	self.wndQueue:FindChild("QueueContainer"):ArrangeChildrenVert()	
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
	
	local queue = self.wndQueue:GetData()
	
	local wndItem = wndControl:GetParent()	
	local item = wndItem:GetData()
		
	-- update data
	queue:Remove(item)
		
	-- update ui
	self:RemovedQueueItem(item, wndItem)
	self:RefreshQueueHeader()
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
	
	self:RecreateQueue(queue)
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
	self:RefreshQueue()
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
	self:RefreshQueue()	
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



function Hephaestus:OnAutoCraft()
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