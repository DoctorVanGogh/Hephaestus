-----------------------------------------------------------------------------------------------
-- Craft utility routines
-- Copyright (c) 2014 DoctorVanGogh on Wildstar forums - all rights reserved
-----------------------------------------------------------------------------------------------

local MAJOR,MINOR = "DoctorVanGogh:Hephaestus:CraftUtil", 1

-- Get a reference to the package information if any
local APkg = Apollo.GetPackage(MAJOR)
-- If there was an older version loaded we need to see if this is newer
if APkg and (APkg.nVersion or 0) >= MINOR then
	return -- no upgrade needed
end

local CraftUtil = APkg and APkg.tPackage or {}

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
	if player == nil then
		glog:warn("Cannot get player unit - cannot start")
		return false
	end
	
	if not CraftingLib.IsAtCraftingStation() then
		glog:warn("Not at crafting station")
		return false
	end
	
	if player:IsMounted() then
		glog:info("Player mounted - can't start")
		-- TODO auto dismount?
		return false
	end
	
	if player:IsCasting() then
		glog:info("Player is casting - cannot start")
		return false
	end
	
	return true
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


Apollo.RegisterPackage(
	CraftUtil, 
	MAJOR, 
	MINOR, 
	{
		"Gemini:Logging-1.2"
	}
)