-- Minimal WoW API stubs for loading Aggro.lua and Ranks.lua outside the game.
local noop = function() end
local widgetMeta
widgetMeta = {
	__index = function(self, key)
		if key == "CreateTexture" or key == "CreateFontString" then
			return function()
				return setmetatable({}, widgetMeta)
			end
		end
		if key == "GetCenter" then
			return function()
				return 0, 0
			end
		end
		if key == "GetEffectiveScale" then
			return function()
				return 1
			end
		end
		return noop
	end,
}
function CreateFrame()
	return setmetatable({}, widgetMeta)
end
UIParent = CreateFrame()
C_Timer = { After = noop }
SlashCmdList = { BULWARK = function() end }
hooksecurefunc = noop
print = print
format = string.format

function Check(cond, label)
	TESTS = (TESTS or 0) + 1
	if not cond then
		FAILED = (FAILED or 0) + 1
		io.write("FAIL  ", label, "\n")
	else
		io.write("ok    ", label, "\n")
	end
end

function LoadModule(path)
	local ns = {}
	local chunk = assert(loadfile(path))
	chunk("Bulwark", ns)
	return ns
end
