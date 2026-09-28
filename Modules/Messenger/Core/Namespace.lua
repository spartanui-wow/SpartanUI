local addonName, ns = ...

-- Messenger core. Nothing under Core/ or UI/ may reference SpartanUI; the host adapter in
-- Host/ is the only file that knows which addon is carrying this module.

---@class Messenger
---@field db table AceDB object
---@field settings table Current profile (read and write)
---@field host MessengerHost
local M = {}
ns.Messenger = M

M.addonName = addonName
M.enabled = false
M.inCombat = false
M.UI = {}

---@class MessengerHost
---@field name string Display name of the carrying addon
---@field savedVariable string Global name of the SavedVariables table
---@field mediaPath string Path to the Media folder, with trailing backslashes
---@field logger? table Logger with debug/info/warning/error functions
---@field minimapHiddenByDefault? boolean
---@field emojiPath? string Folder with the emoji images (trailing backslashes); no emoji without it
---@field toggleBinding? string Binding command that runs M:Toggle, shown as a key picker in the options
---@field defaultToggleKey? string Key given to toggleBinding once per character, only if that key is free
---@field replyBinding? string Binding command that runs M:ReplyLast, for the Reply key override
---@field OpenOptions? fun()
---@field TurnOff? fun()

M.L = setmetatable({}, {
	__index = function(t, k)
		t[k] = k
		return k
	end,
})

local noop = function() end
M.log = { debug = noop, info = noop, warning = noop, error = noop }

----------------------------------------------------------------------------------------------------
-- Internal message bus
----------------------------------------------------------------------------------------------------

local listeners = {}

---@param message string
---@param fn function
function M:On(message, fn)
	listeners[message] = listeners[message] or {}
	table.insert(listeners[message], fn)
end

---@param message string
function M:Fire(message, ...)
	local list = listeners[message]
	if not list then
		return
	end
	for i = 1, #list do
		list[i](...)
	end
end

----------------------------------------------------------------------------------------------------
-- Game events (several owners may listen to the same event)
----------------------------------------------------------------------------------------------------

local eventFrame = CreateFrame('Frame')
local eventHandlers = {}

---Register a game event. Returns false when the client does not know the event.
---@param event string
---@param owner string
---@param fn fun(event: string, ...)
---@return boolean
function M:RegisterEvent(event, owner, fn)
	if not eventHandlers[event] then
		if not pcall(eventFrame.RegisterEvent, eventFrame, event) then
			return false
		end
		eventHandlers[event] = {}
	end
	eventHandlers[event][owner] = fn
	return true
end

---@param event string
---@param owner string
function M:UnregisterEvent(event, owner)
	local handlers = eventHandlers[event]
	if not handlers then
		return
	end
	handlers[owner] = nil
	if next(handlers) == nil then
		eventHandlers[event] = nil
		eventFrame:UnregisterEvent(event)
	end
end

eventFrame:SetScript('OnEvent', function(_, event, ...)
	local handlers = eventHandlers[event]
	if not handlers then
		return
	end
	for _, fn in pairs(handlers) do
		fn(event, ...)
	end
end)

----------------------------------------------------------------------------------------------------
-- Coalesced work: callers mark something dirty, it runs once on the next frame
----------------------------------------------------------------------------------------------------

local pending = {}
local pendingFrame = CreateFrame('Frame')
pendingFrame:Hide()
pendingFrame:SetScript('OnUpdate', function(self)
	self:Hide()
	local jobs = pending
	pending = {}
	-- One failing job must not drop the others queued for this frame
	for _, fn in pairs(jobs) do
		local ok, err = pcall(fn)
		if not ok then
			geterrorhandler()(err)
		end
	end
end)

---Run fn on the next frame. Repeated calls with the same id collapse into one run.
---@param id string
---@param fn function
function M:Defer(id, fn)
	pending[id] = fn
	pendingFrame:Show()
end
