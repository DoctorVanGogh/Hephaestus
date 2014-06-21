-----------------------------------------------------------------------------------------------
-- Craft utility routines
-- Copyright (c) 2014 DoctorVanGogh on Wildstar forums - all rights reserved
-----------------------------------------------------------------------------------------------

require "GameLib"

local MAJOR,MINOR = "DoctorVanGogh:Hephaestus:CraftUtil", 1

-- Get a reference to the package information if any
local APkg = Apollo.GetPackage(MAJOR)
-- If there was an older version loaded we need to see if this is newer
if APkg and (APkg.nVersion or 0) >= MINOR then
	return -- no upgrade needed
end

local CraftUtil = APkg and APkg.tPackage or {}

local knSupplySatchelStackSize = 250

local glog

function CraftUtil:OnLoad()
	local GeminiLogging = Apollo.GetPackage("Gemini:Logging-1.2").tPackage
	glog = GeminiLogging:GetLogger({
		level = GeminiLogging.INFO,
		pattern = "%d [%c:%n] %l - %m",
		appender = "GeminiConsole"
	})	
	
	self.log = glog
end


function CraftUtil:CanCraft()
	local player = GameLib.GetPlayerUnit()
		
	local bCanCraft, bAtCraftingStation, bNotMounted, bNotBusy 
	
	if player ~= nil then
		bAtCraftingStation = CraftingLib.IsAtCraftingStation()
		bNotMounted = not player:IsMounted()
		bNotBusy = not player:IsCasting() 		-- what about jumping, trading?		
		
		return bAtCraftingStation and bNotMounted and bNotBusy, bAtCraftingStation, bNotMounted, bNotBusy				
	else
		return false		
	end	
end

function CraftUtil:GetMaxCraftableForSchematic(tSchematicInfo)
	-- TODO: make this methods *start* at backpackcount, then add/subtract preceding items materials & results 
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

--[[
	Calculated the maximum number of an item we could fit inside the palyers inventory
	Checks: empty slots, partial stacks, partial supply sachel stacks
]]
function CraftUtil:GetInventoryCountForItem(tItem)
	-- TODO: make this method use 'dynamic inventory state' methods
	local unitPlayer = GameLib.GetPlayerUnit()

	local nCount = 0
	local nMaxStackSize = tItem:GetMaxStackCount() or 1
	
	-- assume all free inventory slots will be filled by full stacks
	local nOccupiedInventory = #unitPlayer:GetInventoryItems() or 0
	local nTotalInventory = GameLib.GetTotalInventorySlots() or 0
	local nAvailableInventory = nTotalInventory - nOccupiedInventory
	nCount = nCount + nMaxStackSize * nAvailableInventory	
	

	-- check for partial stacks in inventory
	for idx, tCurrItem in ipairs(unitPlayer:GetInventoryItems()) do	
		if tCurrItem.itemInBag:GetItemId() == tItem:GetItemId() then
			local nStackSize = tCurrItem.itemInBag:GetStackCount() or 0
			nCount = nCount + (nMaxStackSize - nStackSize)
		end	
	end	
	
	-- check for partial stacks in supply satchel
	for strCategory, arItems in pairs(unitPlayer:GetSupplySatchelItems(0)) do
		for idx, tCurrItem in ipairs(arItems) do
			if tCurrItem.itemMaterial:GetItemId() == tItem:GetItemId() then				
				nCount = nCount + (knSupplySatchelStackSize - tCurrItem.nCount)					
				break
			end
		end
	end	

	return nCount
end


Apollo.RegisterPackage(
	CraftUtil, 
	MAJOR, 
	MINOR, 
	{
		"Gemini:Logging-1.2"
	}
)