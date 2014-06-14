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
	
local Queue = Apollo.GetPackage("DoctorVanGogh:Lib:Queue").tPackage
local CraftUtil = Apollo.GetPackage("DoctorVanGogh:Hephaestus:CraftUtil").tPackage	
local CraftQueueItem = Apollo.GetPackage("DoctorVanGogh:Hephaestus:CraftQueueItem").tPackage	

local oo = Apollo.GetPackage("DoctorVanGogh:Lib:Loop:Multiple").tPackage

local CraftQueue = APkg and APkg.tPackage

if not CraftQueue then
	local o = {	
		items={} 		
	}
	
	o.callbacks = o.callbacks or Apollo.GetPackage("Gemini:CallbackHandler-1.0").tPackage:New(o)
	
	CraftQueue = oo.class(o, Queue)
end

local glog


local ktQueueStates = {
	Paused = 1,
	Running = 2
}

CraftQueue.CollectionChanges = {
	Reset = "reset",
	Added = "added",
	Removed = "removed",
	Refreshed = "refeshed"
}

CraftQueue.EventOnCollectionChanged = "OnCollectionChanged"
CraftQueue.EventOnPropertyChanged = "OnPropertyChanged"
CraftQueue.PropertyIsRunning = "IsRunning"


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

function CraftQueue:FireCollectionChangedEvent(strEventType, ...)
	local items = nil
	if #arg > 0 then
		items = arg
	end
	glog:debug("FireCollectionChangedEvent %s, ", strEventType)
	
	self.callbacks:Fire(CraftQueue.EventOnCollectionChanged, nil, strEventType, items)
end

function CraftQueue:FirePropertyChangedEvent(strProperty)
	self.callbacks:Fire(CraftQueue.EventOnPropertyChanged, strProperty)
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
	self:FireCollectionChangedEvent(CraftQueue.CollectionChanges.Reset)
end


function CraftQueue:Clear()
	Queue.Clear(self)
	self:FireCollectionChangedEvent(CraftQueue.CollectionChanges.Reset)	
end

function CraftQueue:Remove(item)	
	if Queue.Remove(self, item) then
		self:FireCollectionChangedEvent(CraftQueue.CollectionChanges.Removed, item)
	end
end

function CraftQueue:Pop()
	glog:debug("Pop %s", inspect(self.items))
	local item = Queue.Pop(self)
	if item then
		self:FireCollectionChangedEvent(CraftQueue.CollectionChanges.Removed, item)
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
	
	self:FireCollectionChangedEvent(CraftQueue.CollectionChanges.Added, item)	
end

function CraftQueue:Forward(oItem)
	assert(oo.instanceof(oItem, CraftQueueItem))
	local idxMoved = Queue.Forward(self, oItem)
	if idxMoved then	
		self:FireCollectionChangedEvent(CraftQueue.CollectionChanges.Refreshed, oItem, self.items[idxMoved + 1])	
		return true		
	else
		return false
	end
end

function CraftQueue:Backward(oItem)
	assert(oo.instanceof(oItem, CraftQueueItem))
	local idxMoved = Queue.Backward(self, oItem)
	
	if idxMoved then
		self:FireCollectionChangedEvent(CraftQueue.CollectionChanges.Refreshed, oItem, self.items[idxMoved - 1])	
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
	
	self:FirePropertyChangedEvent(CraftQueue.PropertyIsRunning)
	
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
	
	self:FirePropertyChangedEvent(CraftQueue.PropertyIsRunning)
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
		"Gemini:CallbackHandler-1.0",
		"DoctorVanGogh:Lib:Queue",			
		"DoctorVanGogh:Hephaestus:CraftUtil",
		"DoctorVanGogh:Hephaestus:CraftQueueItem"			
	}
)