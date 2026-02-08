--------------------------------------------------------------------------------
---- Library Namespace
--------------------------------------------------------------------------------

local QTip = LibStub:GetLibrary('LibQTip-2.0')

---@class LibQTip-2.0.ScriptManager
---@field FrameScriptMetadata table<LibQTip-2.0.ScriptFrame, LibQTip-2.0.ScriptTypeMetadata?>
local ScriptManager = QTip.ScriptManager

ScriptManager.FrameScriptMetadata = ScriptManager.FrameScriptMetadata or {}

---@class LibQTip-2.0.ScriptFrame: BackdropTemplate, Frame
---@field Tooltip LibQTip-2.0.Tooltip

---@class LibQTip-2.0.ScriptMetadata
---@field Parameters? table
---@field Handler fun(frame: LibQTip-2.0.ScriptFrame, ...)

---@alias LibQTip-2.0.ScriptType
---|"OnEnter"
---|"OnLeave"
---|"OnMouseDown"
---|"OnMouseUp"
---|"OnReceiveDrag"

---@alias LibQTip-2.0.ScriptTypeMetadata table<LibQTip-2.0.ScriptType, LibQTip-2.0.ScriptMetadata?>

--------------------------------------------------------------------------------
---- Constants
--------------------------------------------------------------------------------

---@type table<LibQTip-2.0.ScriptType, fun(frame: LibQTip-2.0.ScriptFrame, ...)>
local FrameScriptHandler = {
	OnEnter = function(frame, ...)
		local highlightFrame = frame.Tooltip.HighlightFrame

		highlightFrame:SetParent(frame)
		highlightFrame:SetAllPoints(frame)
		highlightFrame:Show()

		ScriptManager:CallScriptHandler(frame, 'OnEnter', ...)
	end,
	OnLeave = function(frame, ...)
		local highlightFrame = frame.Tooltip.HighlightFrame

		highlightFrame:Hide()
		highlightFrame:ClearAllPoints()
		highlightFrame:SetParent(nil)

		ScriptManager:CallScriptHandler(frame, 'OnLeave', ...)
	end,
	OnMouseDown = function(frame, ...)
		ScriptManager:CallScriptHandler(frame, 'OnMouseDown', ...)
	end,
	OnMouseUp = function(frame, ...)
		ScriptManager:CallScriptHandler(frame, 'OnMouseUp', ...)
	end,
	OnReceiveDrag = function(frame, ...)
		ScriptManager:CallScriptHandler(frame, 'OnReceiveDrag', ...)
	end,
}

--------------------------------------------------------------------------------
---- Methods
--------------------------------------------------------------------------------

---@param frame LibQTip-2.0.ScriptFrame
---@param scriptType LibQTip-2.0.ScriptType
function ScriptManager:CallScriptHandler(frame, scriptType, ...)
	local scriptMetadata = ScriptManager.FrameScriptMetadata[frame][scriptType]

	if scriptMetadata then
		scriptMetadata.Handler(frame, unpack(scriptMetadata.Parameters), ...)
	end
end

-- Clears all scripts matching a LibQTip-2.0.ScriptType from the frame.
---@param frame LibQTip-2.0.ScriptFrame
function ScriptManager:ClearScripts(frame)
	for scriptType in pairs(FrameScriptHandler) do
		self:RawSetScript(frame, scriptType, nil)
	end

	local scriptTypeMetadata = self.FrameScriptMetadata[frame]

	if not scriptTypeMetadata then
		return
	end

	if scriptTypeMetadata.OnEnter or scriptTypeMetadata.OnLeave or scriptTypeMetadata.OnMouseDown or scriptTypeMetadata.OnMouseUp or scriptTypeMetadata.OnReceiveDrag then
		frame:EnableMouse(false)
	end

	self.FrameScriptMetadata[frame] = nil
end

---@param frame Frame
---@param scriptType ScriptFrame
---@param handler? function
function ScriptManager:RawSetScript(frame, scriptType, handler)
	QTip.FrameMetatable.__index.SetScript(frame, scriptType, handler)
end

---@param frame LibQTip-2.0.ScriptFrame
---@param scriptType LibQTip-2.0.ScriptType
---@param handler? fun(arg, ...)
---@param ...? unknown Data to be passed to the script function.
function ScriptManager:SetScript(frame, scriptType, handler, ...)
	if not FrameScriptHandler[scriptType] then
		return
	end

	local scriptTypeMetadata = self.FrameScriptMetadata[frame]

	if not scriptTypeMetadata then
		scriptTypeMetadata = {}

		self.FrameScriptMetadata[frame] = scriptTypeMetadata
	end

	if handler then
		scriptTypeMetadata[scriptType] = {
			Handler = handler,
			Parameters = { ... },
		}
	else
		scriptTypeMetadata[scriptType] = nil
	end

	if scriptType == 'OnMouseDown' or scriptType == 'OnMouseUp' or scriptType == 'OnReceiveDrag' then
		if handler then
			self:RawSetScript(frame, scriptType, FrameScriptHandler[scriptType])
		else
			self:RawSetScript(frame, scriptType, nil)
		end
	end

	if scriptTypeMetadata.OnEnter or scriptTypeMetadata.OnLeave or scriptTypeMetadata.OnMouseDown or scriptTypeMetadata.OnMouseUp or scriptTypeMetadata.OnReceiveDrag then
		frame:EnableMouse(true)

		self:RawSetScript(frame, 'OnEnter', FrameScriptHandler.OnEnter)
		self:RawSetScript(frame, 'OnLeave', FrameScriptHandler.OnLeave)
	else
		frame:EnableMouse(false)

		self:RawSetScript(frame, 'OnEnter', nil)
		self:RawSetScript(frame, 'OnLeave', nil)
	end
end
