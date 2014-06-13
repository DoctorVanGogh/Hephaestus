-----------------------------------------------------------------------------------------------
-- Craft Queue Item implementation
-- Copyright (c) 2014 DoctorVanGogh on Wildstar forums - all rights reserved
-----------------------------------------------------------------------------------------------

require "GameLib"
require "CraftingLib"

local MAJOR,MINOR = "DoctorVanGogh:Hephaestus:CraftQueueItem", 1

-- Get a reference to the package information if any
local APkg = Apollo.GetPackage(MAJOR)
-- If there was an older version loaded we need to see if this is newer
if APkg and (APkg.nVersion or 0) >= MINOR then
	return -- no upgrade needed
end
local oo = Apollo.GetPackage("DoctorVanGogh:Lib:Loop:Base").tPackage

local CraftQueueItem = APkg and APkg.tPackage or oo.class{}

local CraftUtil = Apollo.GetPackage("DoctorVanGogh:Hephaestus:CraftUtil").tPackage	

-------------------------------------------------------------
-- local values declarations
-------------------------------------------------------------
local knSupplySatchelStackSize = 250


local glog

function CraftQueueItem:OnLoad()
	-- import GeminiLogging
	local GeminiLogging = Apollo.GetPackage("Gemini:Logging-1.2").tPackage
	glog = GeminiLogging:GetLogger({
		level = GeminiLogging.DEBUG,
		pattern = "%d [%c:%n] %l - %m",
		appender = "GeminiConsole"
	})	
	
	self.log = glog	
end

function CraftQueueItem:__init(tSchematicInfo, nAmount, tQueue, ...)
	glog:debug("__init(%s, %s, %s, ...)", tostring(tSchematicInfo), tostring(nAmount), tostring(tQueue))

	ci = oo.rawnew(
		self, 
		{
			tSchematicInfo = tSchematicInfo,
			nAmount = nAmount,
			tArgs = arg,
			tQueue = tQueue		
		}
	)
	return ci
end

function CraftQueueItem:GetQueue()
	return self.tQueue
end

function CraftQueueItem:GetSchematicInfo()
	return self.tSchematicInfo
end

function CraftQueueItem:GetAmount()
	return self.nAmount
end

function CraftQueueItem:SetAmount(nAmount)
	self.nAmount = nAmount
end

function CraftQueueItem:CraftComplete()
	glog:debug("CraftQueueItem:CraftComplete()")


	self:SetAmount(self:GetAmount() - (self:GetCurrentCraftAmount() or 0))
	self:SetCurrentCraftAmount(nil)

	self:GetQueue():GetItemChangedHandlers()(self)
end

function CraftQueueItem:GetMaxCraftable()
	return CraftUtil:GetMaxCraftableForSchematic(self:GetSchematicInfo())
end

function CraftQueueItem:GetCurrentCraftAmount()
	return self.nCurrentCraftAmount
end

function CraftQueueItem:SetCurrentCraftAmount(nCount)
	glog:debug("CraftQueueItem:SetCurrentCraftAmount(%s)", tostring(nCount))
	self.nCurrentCraftAmount = nCount or 0
end

function CraftQueueItem:TryCraft()
	glog:debug("CraftQueueItem:TryCraft")

	if self:GetMaxCraftable() == 0 then
		glog:warn("Not enough materials - stopping")
		self:GetQueue():Stop()
		return
	end
	
	if not CraftUtil:CanCraft() then
		self:GetQueue():Stop()
		return
	end	
	
	
	local tSchematicInfo = self:GetSchematicInfo()
	
	if tSchematicInfo.nParentSchematicId and tSchematicInfo.nParentSchematicId ~= 0 and tSchematicInfo.nSchematicId ~= tSchematicInfo.nParentSchematicId then
		glog:warn("Cannot create variant items (yet) - stopping")
		self:GetQueue():Stop()
		return
	end
	
	local nAmount = self:GetAmount()
	
	if not nAmount or nAmount <= 0 then
		glog:warn("Nothing to craft...")
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
	local nCraftAtOnceMax = bIsAutoCraft and tSchematicInfo.nCraftAtOnceMax or 1
	local itemOutput = tSchematicInfo.itemOutput
	local nRoomForOutputItems = 0
	local unitPlayer = GameLib.GetPlayerUnit()
	
	-- make sure we have enough space in inventory
	--[[ removed - current calculation yields negative values sometimes...
	-- check satchel first
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
		glog:warn("Not enough room for output items - stopping")
		self:GetQueue():Stop()
		return		
	end
	
	local nCount = math.min(nMaxCraftCounts, math.min(self:GetAmount(), nCraftAtOnceMax))
	]]
	local nCount = math.min(nAmount, nCraftAtOnceMax)
	
	glog:debug("%s", tostring(nCount))	
	if not nCount then
		return
	end
	
	self:SetCurrentCraftAmount(nCount)	
	
	if bIsAutoCraft then
		glog:debug("CraftingLib.CraftItem(%s, nil, %s)", tostring(tSchematicInfo.nSchematicId), tostring(nCount))	

		CraftingLib.CraftItem(tSchematicInfo.nSchematicId, nil, nCount)
	else	
		glog:debug("CraftingLib.CraftItem(%s)", tostring(tSchematicInfo.nSchematicId))	
		
	
		CraftingLib.CraftItem(tSchematicInfo.nSchematicId, nil)	
		-- TODO: make some moves (later)
		
		glog:debug("CraftingLib.CompleteCraft()")		
		CraftingLib.CompleteCraft()
	end			
	
	self:GetQueue():GetItemChangedHandlers()(self)	
end


Apollo.RegisterPackage(
	CraftQueueItem, 
	MAJOR, 
	MINOR, 
	{
		"Gemini:Logging-1.2",
		"DoctorVanGogh:Hephaestus:CraftUtil",
		"DoctorVanGogh:Lib:Signal"		-- debatable if declaration necessary, but let's keep things clean
	}
)