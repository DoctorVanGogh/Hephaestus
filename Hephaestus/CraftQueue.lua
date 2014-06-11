-----------------------------------------------------------------------------------------------
-- Craft Queue implementation
-- Copyright (c) 2014 DoctorVanGogh on Wildstar forums - all rights reserved
-----------------------------------------------------------------------------------------------

local MAJOR,MINOR = "DoctorVanGogh:Hephaestus:CraftQueue", 1

-- Get a reference to the package information if any
local APkg = Apollo.GetPackage(MAJOR)
-- If there was an older version loaded we need to see if this is newer
if APkg and (APkg.nVersion or 0) >= MINOR then
	return -- no upgrade needed
end

local CraftQueue = APkg and APkg.tPackage or {}

local mtCraftQueue = {}

local glog
local Queue
local Signal
local CraftUtil
local CraftQueueItem

local ktQueueStates = {
	Paused = 1,
	Running = 2
}

function CraftQueue:OnLoad()
	-- import GeminiLogging
	local GeminiLogging = Apollo.GetPackage("Gemini:Logging-1.2").tPackage
	glog = GeminiLogging:GetLogger({
		level = GeminiLogging.DEBUG,
		pattern = "%d [%c:%n] %l - %m",
		appender = "GeminiConsole"
	})	
	
	self.log = glog
	
	
	-- import Queue	
	Queue = Apollo.GetPackage("DoctorVanGogh:Lib:Queue").tPackage	
	
	-- import Signal
	Signal = Apollo.GetPackage("DoctorVanGogh:Lib:Signal").tPackage	
	
	-- import CraftUtil
	CraftUtil = Apollo.GetPackage("DoctorVanGogh:Hephaestus:CraftUtil").tPackage
	
	-- import CraftQueueItem
	CraftQueueItem = Apollo.GetPackage("DoctorVanGogh:Hephaestus:CraftQueueItem").tPackage	

	setmetatable(mtCraftQueue, { __index = Queue.GetMetatable()})	
end


function CraftQueue.new(t)
	t = t or {}
	t.items = t.items or {}
	t.handlers = t.handlers or {}
	t.handlers.changed = t.handlers.changed or Signal.new()
	t.handlers.itemChanged = t.handlers.itemChanged or Signal.new()
	t.handlers.itemRemoved = t.handlers.itemRemoved or Signal.new()

	return setmetatable(
		t,
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
	local item = CraftQueueItem.new(
		tSchematicInfo,
		nAmount,
		self,
		unpack(arg)
	)
	Queue.GetMetatable().Push(self, item)
	self.handlers.changed()
end


function mtCraftQueue:IsRunning()
	return self.state == ktQueueStates.Running
end

function mtCraftQueue:Start()
	if self.state == ktQueueStates.Running then
		glog:warn("Already running")
		return
	end

	-- empty? early bail out
	if #self.items == 0 then
		return
	end
	
	if not CraftUtil:CanCraft() then
		return
	end
	
	-- make sure enough materials are still present
	self.state = ktQueueStates.Running
	
	self.handlers.changed()	
	Apollo.RegisterEventHandler("CraftingInterrupted", "OnCraftingInterrupted", self)	
	Apollo.RegisterEventHandler("CraftingSchematicComplete", "OnCraftingSchematicComplete", self)		
	Apollo.RegisterTimerHandler("Hephaestus_DelayRecraftTimer", "OnRecraftDelay", self)
	
	Apollo.CreateTimer("Hephaestus_DelayRecraftTimer", 0.5, false)
	Apollo.StopTimer("Hephaestus_DelayRecraftTimer")
	
	self:Peek():TryCraft()		
end

function mtCraftQueue:Stop()
	if self.state == ktQueueStates.Paused and not self:IsRunning() then
		glog:warn("Already stopped")
		return
	end
	
	-- TODO: the removal may need to be delayed...
	Apollo.RemoveEventHandler("CraftingInterrupted",  self)	
	Apollo.RemoveEventHandler("OnCraftingSchematicComplete", self)	
	Apollo.StopTimer("Hephaestus_DelayRecraftTimer")
	
	self.state = ktQueueStates.Paused
	self.handlers.changed()	
end

-------------------------------------------------------------
-- Event handlers
-------------------------------------------------------------
function mtCraftQueue:OnCraftingSchematicComplete(idSchematic, bPass, nEarnedXp, arMaterialReturnedIds, idSchematicCrafted, idItemCrafted)
	glog:debug("CraftQueue:OnCraftingSchematicComplete(%s, %s, %s, %s, %s, %s)", tostring(idSchematic), tostring(bPass), tostring(nEarnedXp), tostring(arMaterialReturnedIds), tostring(idSchematicCrafted), tostring(idItemCrafted))
	
	if not self:IsRunning() then
		return
	end
	
	local top = self:Peek()
	
	if not bPass then	
		top:SetCurrentCraftAmount(nil)
	else
		top:CraftComplete()
	end
	
	glog:debug(" - top amount remaining: %s", tostring(self:Peek():GetAmount()))
	
	if top:GetAmount() == 0 then		
		self.handlers.itemRemoved(top)
		
		if self.GetCount() == 0 then
			self:Stop()
			return
		end		

	end
	
	-- cannot immediately recraft since we are still 'casting' from current craft
	Apollo.StartTimer("Hephaestus_DelayRecraftTimer")
end

function mtCraftQueue:OnCraftingInterrupted()
	glog:debug("CraftQueue:OnCraftingInterrupted")
	self:Stop()
end

function mtCraftQueue:OnRecraftDelay()
	glog:debug("CraftQueue:OnRecraftDelay")
	Apollo.StopTimer("Hephaestus_DelayRecraftTimer")
	
	local unitPlayer = GameLib.GetPlayerUnit()
	if unitPlayer:IsCasting() then
		glog:debug("  IsCasting=true")

		Apollo.StartTimer("Hephaestus_DelayRecraftTimer")	
	else	
		glog:debug("  IsCasting=false")

		self:Peek():TryCraft()
	end
end

	


Apollo.RegisterPackage(
	CraftQueue, 
	MAJOR, 
	MINOR, 
	{
		"Gemini:Logging-1.2",
		"DoctorVanGogh:Lib:Signal",
		"DoctorVanGogh:Lib:Queue",			
		"DoctorVanGogh:Hephaestus:CraftUtil",
		"DoctorVanGogh:Hephaestus:CraftQueueItem"			
	}
)