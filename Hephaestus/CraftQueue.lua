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

local Signal = Apollo.GetPackage("DoctorVanGogh:Lib:Signal").tPackage		
local Queue = Apollo.GetPackage("DoctorVanGogh:Lib:Queue").tPackage
local CraftUtil = Apollo.GetPackage("DoctorVanGogh:Hephaestus:CraftUtil").tPackage	
local CraftQueueItem = Apollo.GetPackage("DoctorVanGogh:Hephaestus:CraftQueueItem").tPackage	

local oo = Apollo.GetPackage("DoctorVanGogh:Lib:Loop:Multiple").tPackage

local CraftQueue = APkg and APkg.tPackage or oo.class(
												{	
													items={}, 
													handlers={
														changed = Signal{}, 
														itemChanged  = Signal{}, 
														itemRemoved = Signal{},
														stateChanged = Signal{},
													}
												}, 
												Queue)


local glog


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
	
	Apollo.RegisterTimerHandler("Hephaestus_DelayRecraftTimer", "OnRecraftDelay", self)
	
	Apollo.CreateTimer("Hephaestus_DelayRecraftTimer", 0.5, false)
	Apollo.StopTimer("Hephaestus_DelayRecraftTimer")	
end


function CraftQueue:Serialize()
	local result = {}
	for idx, item in ipairs(self.items) do
		table.insert(result, item:Serialize())
	end
	return result
end

function CraftQueue:LoadFrom(tStorage)
	Queue.Clear(self)
	for idx, item in ipairs(tStorage) do
		Queue.Push(self, CraftQueueItem:Deserialize(item, self))
	end
	self.handlers.changed()
end


function CraftQueue:GetChangedHandlers()
	return self.handlers.changed
end

function CraftQueue:GetItemChangedHandlers()
	return self.handlers.itemChanged
end

function CraftQueue:GetItemRemovedHandlers()
	return self.handlers.itemRemoved
end

function CraftQueue:GetStateChangedHandlers()
	return self.handlers.stateChanged
end

function CraftQueue:Clear()
	Queue.Clear(self)
	self.handlers.changed()
end

function CraftQueue:Remove(item)
	if Queue.Remove(self, item) then
		self.handlers.itemRemoved(item)
	end
end

function CraftQueue:Pop()
	local item = Queue.Pop(self)
	if item then
		self.handlers.itemRemoved(item)	
	end
end

function CraftQueue:Push(tSchematicInfo, nAmount,...)
	local item = CraftQueueItem (
		tSchematicInfo,
		nAmount,
		self,
		unpack(arg)
	)
	Queue.Push(self, item)
	self.handlers.changed()
end

function CraftQueue:Forward(oItem)
	assert(oo.instanceof(oItem, CraftQueueItem))
	if Queue.Forward(self, oItem) then
		self.handlers.changed()
		return true		
	else
		return false
	end
end

function CraftQueue:Backward(oItem)
	assert(oo.instanceof(oItem, CraftQueueItem))
	if Queue.Backward(self, oItem) then
		self.handlers.changed()
		return true
	else
		return false
	end
end

function CraftQueue:IsRunning()
	return self.state == ktQueueStates.Running
end

function CraftQueue:Start()
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
	
	self.handlers.stateChanged()	
	Apollo.RegisterEventHandler("CraftingInterrupted", "OnCraftingInterrupted", self)	
	Apollo.RegisterEventHandler("CraftingSchematicComplete", "OnCraftingSchematicComplete", self)		

	Apollo.StopTimer("Hephaestus_DelayRecraftTimer")
	
	self:Peek():TryCraft()		
end

function CraftQueue:Stop()
	if self.state == ktQueueStates.Paused and not self:IsRunning() then
		glog:warn("Already stopped")
		return
	end
	
	-- TODO: the removal may need to be delayed...
	Apollo.RemoveEventHandler("CraftingInterrupted",  self)	
	Apollo.RemoveEventHandler("OnCraftingSchematicComplete", self)	
	Apollo.StopTimer("Hephaestus_DelayRecraftTimer")
	
	self.state = ktQueueStates.Paused
	self.handlers.stateChanged()	
end

-------------------------------------------------------------
-- Event handlers
-------------------------------------------------------------
function CraftQueue:OnCraftingSchematicComplete(idSchematic, bPass, nEarnedXp, arMaterialReturnedIds, idSchematicCrafted, idItemCrafted)
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
	
	glog:debug(" - top amount remaining: %s", tostring(top:GetAmount()))
	
	if top:GetAmount() == 0 then
		self:Pop()
		
		local nQueueLength = self:GetCount()
		glog:debug("Queue length: %f.", nQueueLength)
		if nQueueLength == 0 then
			self:Stop()
			return
		end		

	end
	
	-- cannot immediately recraft since we are still 'casting' from current craft
	Apollo.StartTimer("Hephaestus_DelayRecraftTimer")
end

function CraftQueue:OnCraftingInterrupted(...)
	glog:debug("CraftQueue:OnCraftingInterrupted: %s", inspect(arg))
	self:Stop()
end

function CraftQueue:OnRecraftDelay()
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