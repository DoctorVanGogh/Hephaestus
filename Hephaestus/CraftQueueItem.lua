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

local CraftQueueItem = APkg and APkg.tPackage or {}

-------------------------------------------------------------
-- local values declarations
-------------------------------------------------------------
local knSupplySatchelStackSize = 250


local mtCraftQueueItem = {}

local glog
local CraftUtil

function CraftQueueItem:OnLoad()
	-- import GeminiLogging
	local GeminiLogging = Apollo.GetPackage("Gemini:Logging-1.2").tPackage
	glog = GeminiLogging:GetLogger({
		level = GeminiLogging.DEBUG,
		pattern = "%d [%c:%n] %l - %m",
		appender = "GeminiConsole"
	})	
	
	self.log = glog
	
	-- import CraftUtil
	CraftUtil = Apollo.GetPackage("DoctorVanGogh:Hephaestus:CraftUtil").tPackage
end

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
	glog:debug("CraftQueueItem:SetAmount(%s)", tostring(nAmount))
	self.nAmount = nAmount
end

function mtCraftQueueItem:CraftComplete()
	glog:debug("CraftQueueItem:CraftComplete()")

	self:SetAmount(self:GetAmount() - self:GetCurrentCraftAmount())
	self.SetCurrentCraftAmount(nil)
	
	self:GetQueue():GetItemChangedHandlers()(self)
end

function mtCraftQueueItem:GetMaxCraftable()
	return CraftUtil:GetMaxCraftableForSchematic(self:GetSchematicInfo())
end

function mtCraftQueueItem:GetCurrentCraftAmount()
	return self.nCurrentCraftAmount
end

function mtCraftQueueItem:SetCurrentCraftAmount(nCount)
	glog:debug("CraftQueueItem:SetCurrentCraftAmount(%s)", tostring(nCount))
	self.nCurrentCraftAmount = nCount
end

function mtCraftQueueItem:TryCraft()
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
		glog:warn("Not enough room for output items - stopping")
		self:GetQueue():Stop()
		return		
	end
	
	local nCount = math.min(nMaxCraftCounts, math.min(self:GetAmount(), nCraftAtOnceMax))
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