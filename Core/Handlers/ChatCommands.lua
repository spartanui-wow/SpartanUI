---@class SUI
local SUI = SUI
local L = SUI.L
local module = SUI:NewModule('Handler.ChatCommands') ---@type SUI.Module
SUI.Handlers.ChatCommands = module
local SUIChatCommands, CommandDetails, enabled = {}, {}, false

function SUI:ChatCommand(input)
	if not input or input:trim() == '' then
		SUI.Options:ToggleOptions()
		return
	end

	-- If input begins with '>' character, handle it as a path
	if input:sub(1, 1) == '>' then
		local pathInput = input:sub(2) -- Remove the leading '>'
		local args = { strsplit('>', pathInput) }
		for i, arg in ipairs(args) do
			args[i] = arg:trim()
		end
		SUI.Options:ToggleOptions(args)
		return
	end

	-- Parse command and arguments (e.g., "move reset" -> command="move", arg="reset")
	local command, arg = strsplit(' ', input, 2)
	command = command:trim()
	if arg then
		arg = arg:trim()
	end

	-- Execute the command with its argument
	if SUIChatCommands[command] then
		SUIChatCommands[command](arg)
	else
		SUI:Print('Unknown command: ' .. input)
		SUI:Print('Try /sui > Artwork to navigate to a specific options page')
	end
end

if AddonCompartmentFrame then
	AddonCompartmentFrame:RegisterAddon({
		text = 'Spartan|cffe21f1fUI',
		icon = 'Interface\\AddOns\\SpartanUI\\images\\Spartan-Helm',
		registerForAnyClick = true,
		notCheckable = true,
		func = function(btn, arg1, arg2, checked, mouseButton)
			if IsShiftKeyDown() then
				-- Toggle custom MoveIt frame mover system
				if SUI.MoveIt and SUI.MoveIt.MoverMode then
					SUI.MoveIt.MoverMode:Toggle()
				end
				return
			end
			-- if mouseButton == 'LeftButton' then
			-- elseif mouseButton == 'MiddleButton' then
			-- elseif mouseButton == 'RightButton' then
			-- end

			SUI.Options:ToggleOptions()
		end,
		funcOnEnter = function()
			-- GameTooltip:ClearLines()
			GameTooltip:SetOwner(AddonCompartmentFrame, 'ANCHOR_CURSOR_RIGHT')
			GameTooltip:AddDoubleLine('|TInterface/Addons/SpartanUI/images/Spartan-helm:20:20|t |cffffffffSpartan|cffe21f1fUI', '|cffffffff' .. (SUI.releaseType or '') .. tostring(SUI.Version))
			GameTooltip:AddLine(' ', 1, 1, 1)
			GameTooltip:AddLine('|cffeda55fLeft-Click|r to toggle the options window.', 1, 1, 1)
			GameTooltip:AddLine('|cffeda55fShift-Click|r to toggle the movement system.', 1, 1, 1)
			GameTooltip:Show()
		end,
	})
end

local function AddToOptions(arg)
	local settings = CommandDetails[arg]

	if settings.arguments then
		if settings.arguments.required then
		else
			SUI.opt.args.Help.args.ChatCommands.args[arg] = {
				name = '',
				type = 'group',
				inline = true,
				args = {
					[arg] = {
						name = (settings.commandDescription or ''),
						type = 'input',
						width = 'full',
						order = 1,
						get = function()
							return '/sui ' .. arg
						end,
						set = function() end,
					},
				},
			}
			local i = 2
			for k, v in pairs(settings.arguments) do
				if type(v) ~= 'boolean' then
					SUI.opt.args.Help.args.ChatCommands.args[arg].args[k] = {
						name = (v or ''),
						type = 'input',
						width = 'full',
						order = i,
						get = function()
							return '/sui ' .. arg .. ' ' .. k
						end,
						set = function() end,
					}
					i = i + 1
				end
			end
		end
	else
		SUI.opt.args.Help.args.ChatCommands.args[arg] = {
			name = (settings.commandDescription or ''),
			type = 'input',
			width = 'full',
			get = function()
				return '/sui ' .. arg
			end,
			set = function() end,
		}
	end
end

---@param arg string the chat command to register
---@param func function the function that will be called when the command is used
---@param commandDescription string the description of the command
---@param arguments? table the arguments that the command takes
---@param silent? boolean if adding the command should error silently
function SUI:AddChatCommand(arg, func, commandDescription, arguments, silent)
	if SUIChatCommands[arg] then
		if not silent then
			SUI:Error(arg .. ' Chat command has already been added')
		end
		return
	end

	-- Add the command in
	SUIChatCommands[arg] = func

	-- Setup the details table
	CommandDetails[arg] = {
		func = func,
		commandDescription = commandDescription,
		arguments = arguments,
	}

	-- if OnEnable has ran add to options
	if enabled then
		AddToOptions(arg)
	end
end

function module:OnEnable()
	SUI.opt.args.Help.args.ChatCommands = {
		name = L['Chat commands'],
		type = 'group',
		args = {},
	}
	for k, _ in pairs(CommandDetails) do
		AddToOptions(k)
	end
	enabled = true
end
