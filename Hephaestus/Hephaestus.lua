-----------------------------------------------------------------------------------------------
-- Client Lua Script for Hephaestus
-- Copyright 2014 by DoctorVanGogh on Wildstar Forums
-----------------------------------------------------------------------------------------------

require "CraftingLib"

local Hephaestus = Apollo.GetPackage("Gemini:Addon-1.1").tPackage:NewAddon(
																	"Hephaestus", 
																	false,
																	{
																		"Drafto:Lib:inspect-1.2",
																		"Gemini:Logging-1.2",
																		"Tradeskills"
																		"DoctorVanGogh:Lib:AddonRegistry",
																	},
																	"Gemini:Hook-1.0"
																	)
local glog
local inspect

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

	-- get tradeskill schematics reference
	local AddonRegistry = Apollo.GetPackage("DoctorVanGogh:Lib:AddonRegistry").tPackage
	self.tTradeskillSchematics = AddonRegistry:GetAddon("Tradeskills", "TradeskillSchematics")
	
  -- do init tasks here, like setting default states
  -- or setting up slash commands.
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
	
	self:PostHook(self.tTradeskillSchematics, "OnTimerCraftingStationCheck")
	self:PostHook(self.tTradeskillSchematics, "DrawSchematic")
	self:PostHook(self.tTradeskillSchematics, "Initialize")
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
	Show/hide our spinner+button combo for simple crafts
]]
function Hephaestus:OnTimerCraftingStationCheck(luaCaller)
	if not luaCaller.wndMain or not luaCaller.wndMain:IsValid() then
		return
	end

	local tSchematicInfo = nil
	local tSchematic = luaCaller.wndMain:FindChild("RightSide"):GetData()
	if tSchematic then
		tSchematicInfo = CraftingLib.GetSchematicInfo(tSchematic.nSchematicId)
	end

	local bIsAutoCraft = tSchematicInfo and tSchematicInfo.bIsAutoCraft
	local bIsAtCraftingStation = CraftingLib.IsAtCraftingStation()

	luaCaller.wndMain:FindChild("RightBottomSimpleCraft"):Show(bIsAutoCraft and bIsAtCraftingStation)
end

--[[
	update our spinner+button combo for simple crafts
]]
function Hephaestus:DrawSchematic(luaCaller, tSchematic)
	local tSchematicInfo = CraftingLib.GetSchematicInfo(tSchematic.nSchematicId)
	local wndSchem = luaCaller.wndMain:FindChild("RightSide")

	if not tSchematicInfo or not wndSchem then
		return
	end
	
	if tSchematicInfo.bIsAutoCraft then
		local nNumCraftable = 9000
		for key, tMaterial in pairs(tSchematicInfo.tMaterials) do
			if tMaterial.nAmount > 0 then
				local nBackpackCount = tMaterial.itemMaterial:GetBackpackCount()
				nNumCraftable = math.min(nNumCraftable, math.floor(nBackpackCount / tMaterial.nAmount))
			end
		end
	
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
end

--[[ 
	Removes the original 'Simple Craft' button and replaces it with our own
	spinner+button combo.
]]
function Hephaestus:Initialize(luaCaller, wndParent, nSchematicId, strSearchQuery)
	local wndPreview = luaCaller.wndMain:FindChild("RightBottomCraftPreview")
	local wndSimpleCraft = wndPreview:FindChild("RightBottomSimpleCraft")
	
	if not wndSimpleCraft then	
		local btnSimpleCraft = wndPreview:FindChild("RightBottomSimpleCraftBtn")
		btnSimpleCraft:Destroy()
		
		Apollo.LoadForm(self.xmlDoc, "RightBottomSimpleCraft", wndPreview, self)	
	end
end

------------------------------------------------------------
-- Hephaestus Event-Handlers
------------------------------------------------------------
function Hephaestus:OnRightBottomSimpleCraftBtn(wndHandler, wndControl) -- RightBottomSimpleCraftBtn, data is tSchematicId
	local tCurrentCraft = CraftingLib.GetCurrentCraft()
	if tCurrentCraft and tCurrentCraft.nSchematicId ~= 0 then
		Event_FireGenericEvent("GenericEvent_CraftFromPL", wndHandler:GetData())
	else	
		local nCount= wndHandler:GetParent():FindChild("RightBottomSimpleCountSpinner"):GetValue()				
		CraftingLib.CraftItem(wndHandler:GetData(), nil, nCount)	
	end
	Event_FireGenericEvent("AlwaysHideTradeskills")
end