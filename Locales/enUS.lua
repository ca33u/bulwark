--[[
  Bulwark localization.

  English is the source language: every user-facing string in the code is
  English and goes through ns.T(text). Other locale files call
  ns.AddLocale(code, table) with English keys; only the table for the
  client's locale is kept. A missing translation falls back to English.
]]

local ADDON_NAME, ns = ...
ns = ns or {}

local function ClientLocale()
	if type(GetLocale) == "function" then
		local ok, code = pcall(GetLocale)
		if ok and type(code) == "string" then
			return code
		end
	end
	return "enUS"
end

ns.LOCALE = ClientLocale()
ns.L = ns.L or {}

-- codes: "ruRU" or { "esES", "esMX" }
function ns.AddLocale(codes, strings)
	if type(codes) == "string" then
		codes = { codes }
	end
	for _, code in ipairs(codes) do
		if code == ns.LOCALE and type(strings) == "table" then
			for key, text in pairs(strings) do
				if type(text) == "string" and text ~= "" then
					ns.L[key] = text
				end
			end
		end
	end
end

function ns.T(text)
	local translated = ns.L[text]
	if translated ~= nil then
		return translated
	end
	return text
end
