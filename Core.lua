--------------------------------------------------------------------------------
-- BDKMain - Core
-- Spezialisiertes Hilfs-Addon für den Blut-Todesritter.
-- Grundprinzip: komplett eventbasiert, außerhalb der Blut-Spezialisierung
-- werden alle Module deaktiviert und sämtliche Events abgemeldet.
--------------------------------------------------------------------------------

local ADDON_NAME = ...

local BDK = LibStub("AceAddon-3.0"):NewAddon("BDKMain", "AceEvent-3.0", "AceConsole-3.0")
_G.BDKMain = BDK

BDK.BLOOD_SPEC_ID = 250 -- Spezialisierungs-ID: Blut-Todesritter

-- Häufig genutzte API als lokale Upvalues (Hot-Path-Optimierung)
local GetTime, UnitClass, InCombatLockdown = GetTime, UnitClass, InCombatLockdown
local math_abs, math_min, string_format = math.abs, math.min, string.format

--------------------------------------------------------------------------------
-- Standardeinstellungen
--------------------------------------------------------------------------------

local defaults = {
	profile = {
		locked = true,
		boneShield = {
			enabled = true,
			width = 240, height = 28, scale = 1,
			position = { point = "CENTER", relPoint = "CENTER", x = 0, y = -160 },
			maxStacksDisplay = 10,      -- Skala der Leiste
			lowStackThreshold = 3,      -- <= gilt als kritisch (rot)
			midStackThreshold = 5,      -- <= gilt als Warnung (gelb)
			expireSoonSeconds = 6,      -- Restlaufzeit-Warnschwelle
			alwaysShow = false,         -- sonst: nur im Kampf / mit aktiver Aura
			soundsOnlyInCombat = true,
			soundLowStack = "raidwarning",
			soundExpiring = "alarmclock",
			soundDropped = "bosswhisper",
			pulseEnabled = true,
			marrowrendGlow = true,
			colorHigh = { r = 0.25, g = 0.85, b = 0.35 },
			colorMid  = { r = 0.95, g = 0.80, b = 0.15 },
			colorLow  = { r = 0.90, g = 0.15, b = 0.15 },
		},
		resources = {
			enabled = true,
			width = 240, scale = 1,
			runeHeight = 18, powerHeight = 16,
			position = { point = "CENTER", relPoint = "CENTER", x = 0, y = -196 },
			showRunes = true,
			showRunicPower = true,
			showDeathStrikeMarker = true,
			capWarning = true,          -- Runenmacht nahe Cap einfärben
			runeColor  = { r = 0.80, g = 0.10, b = 0.15 },
			powerColor = { r = 0.00, g = 0.65, b = 0.95 },
			capColor   = { r = 1.00, g = 0.35, b = 0.10 },
		},
		deathStrike = {
			enabled = true,
			scale = 1,
			position = { point = "CENTER", relPoint = "CENTER", x = 160, y = -178 },
			glowEnabled = true,
			glowHealPercent = 20,       -- Glow ab X % des Maximallebens als Heilung
			glowOnCap = true,           -- Glow bei Runenmacht nahe Cap
		},
		cooldowns = {
			enabled = true,
			iconSize = 34, spacing = 4, scale = 1,
			position = { point = "CENTER", relPoint = "CENTER", x = 0, y = -240 },
			showCountdownNumbers = true,
			activeGlow = true,
			spells = {}, -- [spellID] = false zum Ausblenden (Standard: alle bekannten an)
		},
	},
}

--------------------------------------------------------------------------------
-- Sound-Auswahl (eingebaute Spiel-Sounds, keine Mediendateien nötig)
--------------------------------------------------------------------------------

BDK.Sounds = {
	{ key = "none",        label = "Kein Sound",           id = nil },
	{ key = "raidwarning", label = "Schlachtzugswarnung",  id = 8959 },
	{ key = "readycheck",  label = "Bereitschaftscheck",   id = 8960 },
	{ key = "alarmclock",  label = "Wecker",               id = 12889 },
	{ key = "bosswhisper", label = "Boss-Warnung",         id = 37666 },
	{ key = "countdown",   label = "BG-Countdown",         id = 25477 },
	{ key = "pvpflag",     label = "PvP-Flagge",           id = 8174 },
	{ key = "invite",      label = "Einladung",            id = 880 },
}

local soundById = {}
for _, s in ipairs(BDK.Sounds) do soundById[s.key] = s end

-- Werteliste für AceConfig-Dropdowns
function BDK:GetSoundValues()
	local t = {}
	for _, s in ipairs(self.Sounds) do t[s.key] = s.label end
	return t
end

-- Spielt einen Sound aus der Auswahlliste ab; respektiert die Kampf-Beschränkung.
function BDK:PlaySoundByKey(key, ignoreCombatGate)
	local s = key and soundById[key]
	if not s or not s.id then return end
	if not ignoreCombatGate
		and self.db.profile.boneShield.soundsOnlyInCombat
		and not InCombatLockdown()
		and not self.testMode then
		return
	end
	PlaySound(s.id, "Master")
end

--------------------------------------------------------------------------------
-- Hilfsfunktionen (von allen Modulen genutzt)
--------------------------------------------------------------------------------

-- Kurzformat für große Zahlen ("12,3k", "1,2M")
function BDK.FormatNumber(n)
	if n >= 1e6 then
		return string_format("%.1fM", n / 1e6)
	elseif n >= 1e4 then
		return string_format("%.0fk", n / 1e3)
	elseif n >= 1e3 then
		return string_format("%.1fk", n / 1e3)
	end
	return tostring(math.floor(n + 0.5))
end

-- Weiches Animieren einer StatusBar zum Zielwert.
-- Das OnUpdate läuft nur, solange tatsächlich animiert wird, und stoppt sich selbst.
local function smoothOnUpdate(bar, elapsed)
	local cur, target = bar:GetValue(), bar._smoothTarget
	local diff = target - cur
	if math_abs(diff) < 0.01 then
		bar:SetValue(target)
		bar:SetScript("OnUpdate", nil)
		bar._smoothing = nil
	else
		bar:SetValue(cur + diff * math_min(elapsed * 12, 1))
	end
end

function BDK.SmoothSetValue(bar, value)
	bar._smoothTarget = value
	if not bar._smoothing then
		bar._smoothing = true
		bar:SetScript("OnUpdate", smoothOnUpdate)
	end
end

-- Sofort setzen (z. B. beim Initialisieren), bricht laufende Animation ab.
function BDK.SetValueInstant(bar, value)
	bar._smoothTarget = value
	bar._smoothing = nil
	bar:SetScript("OnUpdate", nil)
	bar:SetValue(value)
end

BDK.BAR_TEXTURE = "Interface\\TARGETINGFRAME\\UI-StatusBar"
BDK.FONT = "Fonts\\FRIZQT__.TTF"

-- Einheitlicher Rahmen + Hintergrund für alle Anzeigen
function BDK.SkinFrame(frame)
	if not frame.bdkBg then
		local bg = frame:CreateTexture(nil, "BACKGROUND")
		bg:SetAllPoints()
		bg:SetColorTexture(0, 0, 0, 0.55)
		frame.bdkBg = bg
	end
	if not frame.bdkBorder then
		local b = CreateFrame("Frame", nil, frame, "BackdropTemplate")
		b:SetPoint("TOPLEFT", -1, 1)
		b:SetPoint("BOTTOMRIGHT", 1, -1)
		b:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
		b:SetBackdropBorderColor(0, 0, 0, 0.9)
		frame.bdkBorder = b
	end
end

--------------------------------------------------------------------------------
-- Verschiebbare Frames (Unlock-Modus)
--------------------------------------------------------------------------------

local movableFrames = {} -- key -> frame

function BDK:RestorePosition(frame, dbTable)
	local p = dbTable.position
	frame:ClearAllPoints()
	frame:SetPoint(p.point, UIParent, p.relPoint, p.x, p.y)
end

function BDK:RegisterMovable(key, frame, label)
	movableFrames[key] = frame
	frame:SetMovable(true)
	frame:SetClampedToScreen(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", function(f)
		if not BDK.db.profile.locked then f:StartMoving() end
	end)
	frame:SetScript("OnDragStop", function(f)
		f:StopMovingOrSizing()
		local point, _, relPoint, x, y = f:GetPoint(1)
		-- Position immer im aktuell aktiven Profil speichern
		local p = BDK.db.profile[key].position
		p.point, p.relPoint, p.x, p.y = point, relPoint, x, y
	end)

	-- Beschriftung, die nur im Unlock-Modus sichtbar ist
	local overlay = frame:CreateTexture(nil, "OVERLAY")
	overlay:SetAllPoints()
	overlay:SetColorTexture(0.1, 0.6, 0.9, 0.25)
	overlay:Hide()
	local text = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	text:SetPoint("CENTER")
	text:SetText(label or key)
	text:Hide()
	frame.bdkUnlockOverlay, frame.bdkUnlockText = overlay, text

	self:RestorePosition(frame, self.db.profile[key])
	frame:EnableMouse(not self.db.profile.locked)
end

function BDK:SetLocked(locked)
	self.db.profile.locked = locked
	for _, frame in pairs(movableFrames) do
		frame:EnableMouse(not locked)
		frame.bdkUnlockOverlay:SetShown(not locked)
		frame.bdkUnlockText:SetShown(not locked)
	end
	-- Im Unlock-Modus alles per Testmodus anzeigen, damit man es platzieren kann
	self:SetTestMode(not locked)
	if locked then
		self:Print("Anzeigen gesperrt.")
	else
		self:Print("Anzeigen entsperrt - per Drag & Drop verschieben, danach /bdk lock.")
	end
end

--------------------------------------------------------------------------------
-- Spezialisierungs-Gate
--------------------------------------------------------------------------------

local MODULE_KEYS = {
	BoneShield = "boneShield",
	Resources = "resources",
	DeathStrike = "deathStrike",
	Cooldowns = "cooldowns",
}

function BDK.IsBloodDK()
	local _, class = UnitClass("player")
	if class ~= "DEATHKNIGHT" then return false end
	local specIndex
	if C_SpecializationInfo and C_SpecializationInfo.GetSpecialization then
		specIndex = C_SpecializationInfo.GetSpecialization()
	elseif GetSpecialization then
		specIndex = GetSpecialization()
	end
	if not specIndex then return false end
	local specID
	if C_SpecializationInfo and C_SpecializationInfo.GetSpecializationInfo then
		specID = C_SpecializationInfo.GetSpecializationInfo(specIndex)
	elseif GetSpecializationInfo then
		specID = GetSpecializationInfo(specIndex)
	end
	return specID == BDK.BLOOD_SPEC_ID
end

-- Aktiviert/deaktiviert alle Module je nach Spezialisierung und Einstellungen.
function BDK:UpdateModules()
	local isBlood = self.IsBloodDK()
	for moduleName, dbKey in pairs(MODULE_KEYS) do
		local mod = self:GetModule(moduleName)
		local shouldEnable = isBlood and self.db.profile[dbKey].enabled
		if shouldEnable and not mod:IsEnabled() then
			self:EnableModule(moduleName)
		elseif not shouldEnable and mod:IsEnabled() then
			self:DisableModule(moduleName)
		end
	end
	if not isBlood and self.testMode then
		self:SetTestMode(false)
	end
end

-- Einstellungen auf alle aktiven Module anwenden (nach Options-/Profilwechsel)
function BDK:ApplySettings()
	self:UpdateModules()
	for moduleName in pairs(MODULE_KEYS) do
		local mod = self:GetModule(moduleName)
		if mod:IsEnabled() and mod.ApplySettings then
			mod:ApplySettings()
		end
	end
end

--------------------------------------------------------------------------------
-- Testmodus
--------------------------------------------------------------------------------

BDK.testMode = false

function BDK:SetTestMode(enabled)
	enabled = not not enabled
	if enabled and not self.IsBloodDK() then
		self:Print("Testmodus benötigt die Blut-Spezialisierung.")
		return
	end
	self.testMode = enabled
	for moduleName in pairs(MODULE_KEYS) do
		local mod = self:GetModule(moduleName)
		if mod:IsEnabled() and mod.SetTestMode then
			mod:SetTestMode(enabled)
		end
	end
end

--------------------------------------------------------------------------------
-- Lebenszyklus
--------------------------------------------------------------------------------

function BDK:OnInitialize()
	self.db = LibStub("AceDB-3.0"):New("BDKMainDB", defaults, true)
	self.db.RegisterCallback(self, "OnProfileChanged", "OnProfileRefresh")
	self.db.RegisterCallback(self, "OnProfileCopied", "OnProfileRefresh")
	self.db.RegisterCallback(self, "OnProfileReset", "OnProfileRefresh")

	self:SetDefaultModuleState(false)
	self:SetupOptions() -- Options.lua

	self:RegisterChatCommand("bdk", "HandleSlashCommand")
	self:RegisterChatCommand("bdkmain", "HandleSlashCommand")
end

function BDK:OnEnable()
	self:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED", "OnSpecChanged")
	self:RegisterEvent("PLAYER_ENTERING_WORLD", "UpdateModules")
	self:UpdateModules()
end

function BDK:OnSpecChanged(_, unit)
	if unit == "player" then
		self:UpdateModules()
	end
end

function BDK:OnProfileRefresh()
	self:ApplySettings()
	self:SetLockedSilent(self.db.profile.locked)
end

function BDK:SetLockedSilent(locked)
	for _, frame in pairs(movableFrames) do
		frame:EnableMouse(not locked)
		frame.bdkUnlockOverlay:SetShown(not locked)
		frame.bdkUnlockText:SetShown(not locked)
	end
end

--------------------------------------------------------------------------------
-- Slash-Befehle & Optionen öffnen
--------------------------------------------------------------------------------

function BDK:HandleSlashCommand(input)
	input = (input or ""):lower():match("^%s*(%S*)")
	if input == "test" then
		self:SetTestMode(not self.testMode)
		self:Print("Testmodus " .. (self.testMode and "an" or "aus") .. ".")
	elseif input == "lock" then
		self:SetLocked(true)
	elseif input == "unlock" then
		self:SetLocked(false)
	elseif input == "reset" then
		self.db:ResetProfile()
		self:Print("Profil zurückgesetzt.")
	elseif input == "" or input == "config" or input == "options" then
		self:OpenOptions()
	else
		self:Print("Befehle: /bdk (Optionen), /bdk test, /bdk lock, /bdk unlock, /bdk reset")
	end
end

function BDK:OpenOptions()
	LibStub("AceConfigDialog-3.0"):Open("BDKMain")
end

-- Klick im Addon-Fach (Minimap-Dropdown)
function _G.BDKMain_OnAddonCompartmentClick()
	BDK:OpenOptions()
end
