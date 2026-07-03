std = "lua51"
max_line_length = false
self = false

exclude_files = {
	"Libs/",
}

ignore = {
	"212", -- ungenutzte Argumente (Event-Handler-Signaturen)
}

globals = {
	"BDKMain",
	"BDKMain_OnAddonCompartmentClick",
}

read_globals = {
	-- Lua/WoW-Basis
	"wipe", "format", "strsplit",
	-- Frames & UI
	"CreateFrame", "UIParent", "GameTooltip",
	-- API
	"GetTime", "InCombatLockdown", "PlaySound",
	"UnitClass", "UnitGUID", "UnitPower", "UnitPowerMax", "UnitHealthMax",
	"GetRuneCooldown", "IsPlayerSpell",
	"GetSpecialization", "GetSpecializationInfo",
	"CombatLogGetCurrentEventInfo",
	-- Namespaces
	"C_UnitAuras", "C_Spell", "C_Timer", "C_SpecializationInfo",
	"Enum",
	-- Libraries
	"LibStub",
}
