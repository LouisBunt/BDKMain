-- Test-Harness: lädt BDKMain mit gemockter WoW-API und spielt Szenarien durch.
-- Aufruf: lua5.1 harness.lua /pfad/zum/addon

local ADDON_DIR = arg[1] or "."

--------------------------------------------------------------------------------
-- Mock-Uhr, Timer, Sounds
--------------------------------------------------------------------------------

local now = 1000
local timers = {}
local playedSounds = {}

local function advance(dt)
	local target = now + dt
	while true do
		-- nächsten fälligen Timer suchen
		local nextAt, nextIdx
		for i, t in ipairs(timers) do
			if not t.cancelled and t.at <= target and (not nextAt or t.at < nextAt) then
				nextAt, nextIdx = t.at, i
			end
		end
		if not nextIdx then break end
		local t = timers[nextIdx]
		now = t.at
		if t.interval then
			t.at = t.at + t.interval
		else
			t.cancelled = true
		end
		t.fn()
	end
	now = target
end

--------------------------------------------------------------------------------
-- WoW-API-Mocks
--------------------------------------------------------------------------------

local function autoMock(explicit)
	local obj = explicit or {}
	return setmetatable(obj, {
		__index = function(t, k)
			local fn = function() end
			rawset(t, k, fn)
			return fn
		end,
	})
end

local frameCount = 0
local function makeRegion(kind, parent)
	local r
	r = autoMock({
		mockKind = kind,
		mockParent = parent,
		mockShown = true,
		mockValue = 0,
		mockText = nil,
		scripts = {},
		Show = function(self) self.mockShown = true end,
		Hide = function(self) self.mockShown = false end,
		SetShown = function(self, v) self.mockShown = not not v end,
		IsShown = function(self) return self.mockShown end,
		SetValue = function(self, v) self.mockValue = v end,
		GetValue = function(self) return self.mockValue end,
		SetText = function(self, v) self.mockText = tostring(v or "") end,
		GetText = function(self) return self.mockText end,
		SetScript = function(self, name, fn) self.scripts[name] = fn end,
		GetScript = function(self, name) return self.scripts[name] end,
		GetPoint = function() return "CENTER", nil, "CENTER", 0, 0 end,
		SetMinMaxValues = function(self, lo, hi) self.mockMin, self.mockMax = lo, hi end,
		SetStatusBarColor = function(self, red, g, b) self.mockColor = { red, g, b } end,
		SetCooldown = function(self, s, d) self.mockCd = { s, d } end,
		Clear = function(self) self.mockCd = nil end,
	})
	return r
end

local function makeFrame(kind, parent)
	frameCount = frameCount + 1
	local f = makeRegion(kind or "Frame", parent)
	f.CreateTexture = function(self) return makeRegion("Texture", self) end
	f.CreateFontString = function(self) return makeRegion("FontString", self) end
	f.CreateAnimationGroup = function(self)
		local ag = makeRegion("AnimationGroup", self)
		ag.mockPlaying = false
		ag.Play = function(a) a.mockPlaying = true end
		ag.Stop = function(a) a.mockPlaying = false end
		ag.IsPlaying = function(a) return a.mockPlaying end
		ag.CreateAnimation = function(a) return makeRegion("Animation", a) end
		return ag
	end
	return f
end

local combatLockdown = false
local runicPower, runicPowerMax = 30, 100
local currentAura = nil -- Bone-Shield-Aura
local specID = 250
local cleuData = nil

_G.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
_G.format = string.format
_G.GetTime = function() return now end
_G.InCombatLockdown = function() return combatLockdown end
_G.PlaySound = function(id) playedSounds[#playedSounds + 1] = id end
_G.UnitClass = function() return "Todesritter", "DEATHKNIGHT" end
_G.UnitGUID = function() return "Player-1234" end
_G.UnitPower = function() return runicPower end
_G.UnitPowerMax = function() return runicPowerMax end
_G.UnitHealthMax = function() return 1000000 end
_G.GetRuneCooldown = function() return 0, 0, true end
_G.IsPlayerSpell = function(id) return id ~= 219809 end -- Grabstein "nicht skillt"
_G.GetSpecialization = function() return 1 end
_G.GetSpecializationInfo = function() return specID end
_G.CombatLogGetCurrentEventInfo = function() return unpack(cleuData, 1, 20) end
_G.Enum = { PowerType = { RunicPower = 6 } }
_G.UIParent = makeFrame("UIParent")
_G.CreateFrame = function(kind, name, parent) return makeFrame(kind, parent) end

_G.C_Timer = {
	NewTimer = function(delay, fn)
		local t = { at = now + delay, fn = fn }
		t.Cancel = function(self) self.cancelled = true end
		timers[#timers + 1] = t
		return t
	end,
	NewTicker = function(interval, fn)
		local t = { at = now + interval, interval = interval, fn = fn }
		t.Cancel = function(self) self.cancelled = true end
		timers[#timers + 1] = t
		return t
	end,
}

_G.C_UnitAuras = {
	GetPlayerAuraBySpellID = function(spellId)
		if currentAura and currentAura.spellId == spellId then return currentAura end
		return nil
	end,
}

_G.C_Spell = {
	GetSpellTexture = function() return 12345 end,
	GetSpellCooldown = function() return { startTime = 0, duration = 0 } end,
	GetSpellCharges = function() return nil end,
	GetSpellPowerCost = function() return { { type = 6, cost = 40 } } end,
}

--------------------------------------------------------------------------------
-- Ace3-/Library-Stubs (nur die genutzte Oberfläche)
--------------------------------------------------------------------------------

local libs = {}

local function eventMixin(obj)
	obj.mockEvents = {}
	obj.RegisterEvent = function(self, event, handler)
		self.mockEvents[event] = handler or event
	end
	obj.RegisterUnitEvent = function(self, event, unit, handler)
		self.mockEvents[event] = handler or event
	end
	obj.UnregisterEvent = function(self, event) self.mockEvents[event] = nil end
	obj.UnregisterAllEvents = function(self) wipe(self.mockEvents) end
	obj.FireEvent = function(self, event, ...)
		local h = self.mockEvents[event]
		if not h then return false end
		if type(h) == "string" then
			assert(type(self[h]) == "function", "fehlender Handler " .. tostring(h) .. " für " .. event)
			self[h](self, event, ...)
		else
			h(event, ...)
		end
		return true
	end
end

local AceAddonStub = {}
function AceAddonStub:NewAddon(name, ...)
	local addon = { name = name, modules = {}, defaultModuleState = true }
	eventMixin(addon)
	addon.Print = function(_, msg) print("  [Print] " .. tostring(msg)) end
	addon.RegisterChatCommand = function() end
	addon.SetDefaultModuleState = function(self, s) self.defaultModuleState = s end
	addon.NewModule = function(self, modName)
		local m = { name = modName, enabled = false }
		eventMixin(m)
		m.IsEnabled = function(mm) return mm.enabled end
		self.modules[modName] = m
		return m
	end
	addon.GetModule = function(self, modName)
		return assert(self.modules[modName], "unbekanntes Modul " .. modName)
	end
	addon.EnableModule = function(self, modName)
		local m = self:GetModule(modName)
		if not m.enabled then
			m.enabled = true
			if m.OnEnable then m:OnEnable() end
		end
	end
	addon.DisableModule = function(self, modName)
		local m = self:GetModule(modName)
		if m.enabled then
			m.enabled = false
			if m.OnDisable then m:OnDisable() end
		end
	end
	AceAddonStub.lastAddon = addon
	return addon
end
function AceAddonStub:GetAddon(name) return assert(AceAddonStub.lastAddon) end
libs["AceAddon-3.0"] = AceAddonStub

local function deepcopy(t)
	if type(t) ~= "table" then return t end
	local r = {}
	for k, v in pairs(t) do r[k] = deepcopy(v) end
	return r
end

libs["AceDB-3.0"] = {
	New = function(_, _, defaults)
		local db = { profile = deepcopy(defaults.profile) }
		db.RegisterCallback = function() end
		db.ResetProfile = function(self) self.profile = deepcopy(defaults.profile) end
		return db
	end,
}

local registeredOptions = {}
libs["AceConfig-3.0"] = {
	RegisterOptionsTable = function(_, name, opts) registeredOptions[name] = opts end,
}
libs["AceConfigDialog-3.0"] = autoMock({})
libs["AceDBOptions-3.0"] = {
	GetOptionsTable = function() return { type = "group", name = "Profile", args = {} } end,
}

local glowLog = {}
libs["LibCustomGlow-1.0"] = {
	ButtonGlow_Start = function(f) glowLog[#glowLog + 1] = "button_start" end,
	ButtonGlow_Stop = function(f) glowLog[#glowLog + 1] = "button_stop" end,
	PixelGlow_Start = function(f) glowLog[#glowLog + 1] = "pixel_start" end,
	PixelGlow_Stop = function(f) glowLog[#glowLog + 1] = "pixel_stop" end,
}

_G.LibStub = setmetatable({}, {
	__call = function(_, name)
		return assert(libs[name], "LibStub: fehlende Library " .. tostring(name))
	end,
})

--------------------------------------------------------------------------------
-- Addon laden (gleiche Reihenfolge wie die TOC)
--------------------------------------------------------------------------------

local files = {
	"Core.lua",
	"Modules/BoneShield.lua",
	"Modules/Resources.lua",
	"Modules/DeathStrike.lua",
	"Modules/Cooldowns.lua",
	"Options.lua",
}
for _, f in ipairs(files) do
	local chunk = assert(loadfile(ADDON_DIR .. "/" .. f))
	chunk("BDKMain", {})
end

local BDK = _G.BDKMain
assert(BDK, "BDKMain-Global fehlt")

--------------------------------------------------------------------------------
-- Szenarien
--------------------------------------------------------------------------------

local failures = 0
local function check(cond, label)
	if cond then
		print("OK  " .. label)
	else
		failures = failures + 1
		print("FAIL " .. label)
	end
end

local function lastSound() return playedSounds[#playedSounds] end
local function soundCount() return #playedSounds end

-- Initialisierung
BDK:OnInitialize()
BDK:OnEnable()
check(BDK.db and BDK.db.profile.boneShield.enabled, "DB initialisiert")

local bs = BDK:GetModule("BoneShield")
local res = BDK:GetModule("Resources")
local ds = BDK:GetModule("DeathStrike")
local cds = BDK:GetModule("Cooldowns")
check(bs:IsEnabled() and res:IsEnabled() and ds:IsEnabled() and cds:IsEnabled(),
	"alle Module auf Blut-Spec aktiviert")

-- Spec-Wechsel: alles aus
specID = 251
BDK:FireEvent("PLAYER_SPECIALIZATION_CHANGED", "player")
check(not bs:IsEnabled() and not res:IsEnabled() and not ds:IsEnabled() and not cds:IsEnabled(),
	"alle Module außerhalb der Blut-Spec deaktiviert")
specID = 250
BDK:FireEvent("PLAYER_SPECIALIZATION_CHANGED", "player")
check(bs:IsEnabled(), "Module nach Rückwechsel wieder aktiv")

-- === Knochenschild ===
combatLockdown = true

-- Aura mit 10 Stacks, 30 s
currentAura = { spellId = 195181, applications = 10, duration = 30,
	expirationTime = now + 30, auraInstanceID = 111 }
bs:FireEvent("UNIT_AURA", "player",
	{ addedAuras = { { spellId = 195181 } } })
check(bs.stacks == 10, "Knochenschild: 10 Stacks erkannt")
check(soundCount() == 0, "Knochenschild: kein Sound beim Aufbau")
check(bs.frame:IsShown(), "Knochenschild: Leiste sichtbar")

-- irrelevantes UNIT_AURA wird ignoriert (Fast-Path)
local before = bs.stacks
currentAura.applications = 9 -- dürfte NICHT gelesen werden
bs:FireEvent("UNIT_AURA", "player",
	{ addedAuras = { { spellId = 999 } }, updatedAuraInstanceIDs = { 42 } })
check(bs.stacks == before, "Knochenschild: irrelevantes UNIT_AURA ignoriert")
currentAura.applications = 10

-- Stacks fallen unter Schwelle (10 -> 2): Warnung 1
currentAura.applications = 2
bs:FireEvent("UNIT_AURA", "player", { updatedAuraInstanceIDs = { 111 } })
check(bs.stacks == 2, "Knochenschild: Stack-Drop erkannt")
check(soundCount() == 1 and lastSound() == 8959, "Warnung 1: Sound bei wenigen Stacks (Schlachtzugswarnung)")
check(bs.pulse:IsPlaying(), "Knochenschild: Puls im kritischen Zustand")

-- Refresh auf 8 Stacks: Puls aus, Timer neu
currentAura.applications = 8
currentAura.expirationTime = now + 30
bs:FireEvent("UNIT_AURA", "player", { updatedAuraInstanceIDs = { 111 } })
check(not bs.pulse:IsPlaying(), "Knochenschild: Puls endet nach Auffrischen")

-- Warnung 2: Restlaufzeit < 6 s über Einmal-Timer
advance(25) -- 30 - 25 = 5 s Rest => Timer bei 24 s gefeuert
check(soundCount() == 2 and lastSound() == 12889, "Warnung 2: Sound bei ablaufender Restlaufzeit (Wecker)")
advance(2)
check(soundCount() == 2, "Warnung 2: keine Doppel-Warnung für denselben Ablauf")

-- Warnung 3: Schild fällt komplett ab
currentAura = nil
bs:FireEvent("UNIT_AURA", "player", { removedAuraInstanceIDs = { 111 } })
check(bs.stacks == 0, "Knochenschild: Abfallen erkannt")
check(soundCount() == 3 and lastSound() == 37666, "Warnung 3: Sound bei komplettem Verlust (Boss-Warnung)")
check(bs.label:GetText() == "KNOCHENSCHILD FEHLT!", "Knochenschild: Fehlt-Hinweis im Kampf")

-- Sound-Gate außerhalb des Kampfes
combatLockdown = false
currentAura = { spellId = 195181, applications = 2, duration = 30,
	expirationTime = now + 30, auraInstanceID = 222 }
bs:FireEvent("UNIT_AURA", "player", { addedAuras = { { spellId = 195181 } } })
currentAura = nil
bs:FireEvent("UNIT_AURA", "player", { removedAuraInstanceIDs = { 222 } })
check(soundCount() == 3, "Sounds außerhalb des Kampfes unterdrückt (Standardeinstellung)")

-- === Todesstoß-Helfer ===
combatLockdown = true
ds:FireEvent("PLAYER_REGEN_DISABLED")
local function dealDamage(amount)
	cleuData = { now, "SPELL_DAMAGE", false, "Enemy-1", "Boss", 0, 0,
		"Player-1234", "Spieler", 0, 0, 0, "Zauber", 1, amount }
	ds:FireEvent("COMBAT_LOG_EVENT_UNFILTERED")
end
dealDamage(300000)
dealDamage(60000)
local heal = ds:GetPredictedHeal()
check(math.abs(heal - 90000) < 1, "Todesstoß: 25 % von 360k = 90k vorhergesagt")

advance(6) -- Fenster läuft ab
heal = ds:GetPredictedHeal()
check(math.abs(heal - 70000) < 1, "Todesstoß: nach 5 s greift die Mindestheilung (7 % von 1M)")

-- Swing-Schaden (andere Argumentposition)
cleuData = { now, "SWING_DAMAGE", false, "Enemy-1", "Boss", 0, 0,
	"Player-1234", "Spieler", 0, 0, 200000 }
ds:FireEvent("COMBAT_LOG_EVENT_UNFILTERED")
heal = ds:GetPredictedHeal()
check(math.abs(heal - 70000) < 1, "Todesstoß: 25 % von 200k unter Mindestheilung -> 70k")
dealDamage(400000)
heal = ds:GetPredictedHeal()
check(math.abs(heal - 150000) < 1, "Todesstoß: Swing+Zauber aufsummiert (25 % von 600k)")

-- fremdes Ziel wird ignoriert
cleuData = { now, "SPELL_DAMAGE", false, "Enemy-1", "Boss", 0, 0,
	"Player-9999", "Anderer", 0, 0, 0, "Zauber", 1, 999999 }
ds:FireEvent("COMBAT_LOG_EVENT_UNFILTERED")
check(math.abs(ds:GetPredictedHeal() - 150000) < 1, "Todesstoß: Schaden an anderen ignoriert")

ds:FireEvent("PLAYER_REGEN_ENABLED")
check(ds.mockEvents["COMBAT_LOG_EVENT_UNFILTERED"] == nil, "Todesstoß: CLEU nach Kampfende abgemeldet")

-- === Ressourcen ===
runicPower = 95
res:FireEvent("UNIT_POWER_UPDATE", "player", "RUNIC_POWER")
local c = res.powerBar.mockColor
check(c and c[1] == 1 and c[2] == 0.35, "Runenmacht: Cap-Warnfarbe bei 95/100")
check(res.dsCost == 40, "Todesstoß-Kosten aus der API übernommen (40)")

-- === Cooldowns ===
check(cds.icons[49028] and cds.icons[49028]:IsShown(), "Cooldowns: Tanzende Runenwaffe angezeigt")
check(cds.icons[219809] == nil or not cds.icons[219809]:IsShown(), "Cooldowns: ungelerntes Talent (Grabstein) ausgeblendet")

-- === Optionen ===
local opts = registeredOptions["BDKMain"]
check(opts ~= nil, "Optionstabelle registriert")
if type(opts) == "function" then opts = opts() end
check(type(opts) == "table" and opts.args.boneShield and opts.args.profiles,
	"Optionstabelle generierbar (inkl. Knochenschild & Profile)")

-- get/set-Roundtrip über die generischen Handler
local widthOpt = opts.args.boneShield.args.width
check(widthOpt and widthOpt.type == "range", "Options: Breiten-Regler vorhanden")
local getFn = opts.args.boneShield.get
local setFn = opts.args.boneShield.set
local info = { "boneShield", "width" }
setFn(info, 300)
check(getFn(info) == 300 and BDK.db.profile.boneShield.width == 300, "Options: get/set-Roundtrip")

-- === Testmodus & Lock ===
BDK:SetTestMode(true)
check(BDK.testMode and bs.frame:IsShown(), "Testmodus: Anzeigen sichtbar")
BDK:SetTestMode(false)
BDK:SetLocked(false)
check(not BDK.db.profile.locked and BDK.testMode, "Unlock: Testmodus automatisch an")
BDK:SetLocked(true)
check(BDK.db.profile.locked and not BDK.testMode, "Lock: Testmodus wieder aus")

print(("\n%d Prüfungen fehlgeschlagen."):format(failures))
os.exit(failures == 0 and 0 or 1)
