--------------------------------------------------------------------------------
-- BDKMain - Todesstoß-Helfer
-- Rollierendes 5-Sekunden-Fenster des erlittenen Schadens (CLEU, nur im Kampf
-- registriert, Ringpuffer ohne Tabellen-Neuanlage) und daraus die
-- voraussichtliche Todesstoß-Heilung. Optionaler Glow, wenn sich der
-- Todesstoß besonders lohnt.
--------------------------------------------------------------------------------

local BDK = LibStub("AceAddon-3.0"):GetAddon("BDKMain")
local mod = BDK:NewModule("DeathStrike", "AceEvent-3.0")
local LCG = LibStub("LibCustomGlow-1.0")

local DEATH_STRIKE_ID = 49998
local WINDOW_SECONDS = 5      -- Todesstoß heilt anteilig vom Schaden der letzten 5 s
local HEAL_PERCENT = 0.25     -- 25 % des erlittenen Schadens
local MIN_HEAL_PERCENT = 0.07 -- Mindestheilung: 7 % des Maximallebens

local GetTime, UnitHealthMax, UnitPower, UnitPowerMax = GetTime, UnitHealthMax, UnitPower, UnitPowerMax
local CombatLogGetCurrentEventInfo = CombatLogGetCurrentEventInfo
local UnitGUID = UnitGUID
local POWER_RUNIC = Enum.PowerType.RunicPower

local db

-- Ringpuffer für erlittenen Schaden: feste Arrays, kein Garbage pro Event
local BUFFER_SIZE = 128
local hitTimes, hitAmounts = {}, {}
for i = 1, BUFFER_SIZE do hitTimes[i], hitAmounts[i] = 0, 0 end
local writeIndex = 0

local function recordDamage(amount)
	writeIndex = (writeIndex % BUFFER_SIZE) + 1
	hitTimes[writeIndex] = GetTime()
	hitAmounts[writeIndex] = amount
end

local function damageInWindow()
	local cutoff = GetTime() - WINDOW_SECONDS
	local sum = 0
	for i = 1, BUFFER_SIZE do
		if hitTimes[i] >= cutoff then
			sum = sum + hitAmounts[i]
		end
	end
	return sum
end

local function resetBuffer()
	for i = 1, BUFFER_SIZE do hitTimes[i] = 0 end
end

--------------------------------------------------------------------------------
-- Anzeige
--------------------------------------------------------------------------------

function mod:CreateFrames()
	if self.frame then return end

	local f = CreateFrame("Frame", "BDKMainDeathStrikeFrame", UIParent)
	f:SetFrameStrata("MEDIUM")
	f:SetSize(120, 30)
	BDK.SkinFrame(f)
	self.frame = f

	local icon = f:CreateTexture(nil, "ARTWORK")
	icon:SetSize(26, 26)
	icon:SetPoint("LEFT", 2, 0)
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	local tex = C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(DEATH_STRIKE_ID)
	icon:SetTexture(tex or "Interface\\Icons\\spell_deathknight_butcher2")
	self.icon = icon

	local text = f:CreateFontString(nil, "OVERLAY")
	text:SetFont(BDK.FONT, 14, "OUTLINE")
	self.healText = text

	BDK:RegisterMovable("deathStrike", f, "BDKMain: Todesstoß")
end

function mod:ApplySettings()
	db = BDK.db.profile.deathStrike
	if not self.frame then return end
	self.frame:SetScale(db.scale)

	self.icon:SetShown(db.showIcon)
	self.healText:SetFont(BDK.FONT, db.fontSize, "OUTLINE")
	local c = db.textColor
	self.healText:SetTextColor(c.r, c.g, c.b)
	self.healText:ClearAllPoints()
	if db.showIcon then
		self.healText:SetPoint("LEFT", self.icon, "RIGHT", 5, 0)
	else
		self.healText:SetPoint("CENTER")
	end

	BDK:RestorePosition(self.frame, db)
	self:UpdateDisplay()
end

--------------------------------------------------------------------------------
-- Berechnung & Darstellung
--------------------------------------------------------------------------------

function mod:GetPredictedHeal()
	local maxHealth = UnitHealthMax("player")
	local heal = HEAL_PERCENT * damageInWindow()
	local minHeal = MIN_HEAL_PERCENT * maxHealth
	if heal < minHeal then heal = minHeal end
	return heal, maxHealth
end

function mod:UpdateDisplay()
	local f = self.frame
	if not f then return end

	local inCombat = InCombatLockdown()
	local show = BDK.testMode or not BDK.db.profile.locked or inCombat
	f:SetShown(show)
	if not show then
		self:SetGlow(false)
		return
	end

	local heal, maxHealth
	if BDK.testMode and not inCombat then
		maxHealth = UnitHealthMax("player")
		heal = maxHealth * 0.22
	else
		heal, maxHealth = self:GetPredictedHeal()
	end
	self.healText:SetText("+" .. BDK.FormatNumber(heal))

	-- Glow: viel Heilung anstehend oder Runenmacht nahe am Cap
	local wantGlow = false
	if db.glowEnabled and (inCombat or BDK.testMode) then
		if heal >= maxHealth * (db.glowHealPercent / 100) then
			wantGlow = true
		elseif db.glowOnCap then
			local cur, max = UnitPower("player", POWER_RUNIC), UnitPowerMax("player", POWER_RUNIC)
			if max > 0 and cur >= max - 5 then wantGlow = true end
		end
	end
	self:SetGlow(wantGlow)
end

function mod:SetGlow(enabled)
	if enabled and not self.glowActive then
		self.glowActive = true
		local c = db.textColor
		LCG.PixelGlow_Start(self.frame, { c.r, c.g, c.b, 1 }, 8, 0.25, nil, 2)
	elseif not enabled and self.glowActive then
		self.glowActive = false
		LCG.PixelGlow_Stop(self.frame)
	end
end

--------------------------------------------------------------------------------
-- CLEU: nur im Kampf registriert, früher Abbruch für fremde Ziele
--------------------------------------------------------------------------------

local damageEvents = {
	SWING_DAMAGE = 12,          -- Amount-Argumentposition
	ENVIRONMENTAL_DAMAGE = 13,
	RANGE_DAMAGE = 15,
	SPELL_DAMAGE = 15,
	SPELL_PERIODIC_DAMAGE = 15,
	SPELL_BUILDING_DAMAGE = 15,
}

function mod:OnCombatLogEvent()
	local _, subevent, _, _, _, _, _, destGUID = CombatLogGetCurrentEventInfo()
	if destGUID ~= self.playerGUID then return end
	local amountIndex = damageEvents[subevent]
	if not amountIndex then return end
	local amount = select(amountIndex, CombatLogGetCurrentEventInfo())
	if type(amount) == "number" and amount > 0 then
		recordDamage(amount)
	end
end

function mod:OnCombatStart()
	resetBuffer()
	self.playerGUID = UnitGUID("player")
	self:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED", "OnCombatLogEvent")
	-- Anzeige-Ticker nur im Kampf (5x pro Sekunde)
	if not self.ticker then
		self.ticker = C_Timer.NewTicker(0.2, function() mod:UpdateDisplay() end)
	end
	self:UpdateDisplay()
end

function mod:OnCombatEnd()
	self:UnregisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
	if self.ticker then
		self.ticker:Cancel()
		self.ticker = nil
	end
	resetBuffer()
	self:UpdateDisplay()
end

--------------------------------------------------------------------------------
-- Events / Lebenszyklus
--------------------------------------------------------------------------------

function mod:OnEnable()
	db = BDK.db.profile.deathStrike
	self:CreateFrames()
	self:ApplySettings()
	self:RegisterEvent("PLAYER_REGEN_DISABLED", "OnCombatStart")
	self:RegisterEvent("PLAYER_REGEN_ENABLED", "OnCombatEnd")
	if InCombatLockdown() then
		self:OnCombatStart()
	else
		self:UpdateDisplay()
	end
end

function mod:OnDisable()
	self:UnregisterAllEvents()
	if self.ticker then
		self.ticker:Cancel()
		self.ticker = nil
	end
	self:SetGlow(false)
	if self.frame then self.frame:Hide() end
	resetBuffer()
end

--------------------------------------------------------------------------------
-- Testmodus
--------------------------------------------------------------------------------

function mod:SetTestMode()
	self:UpdateDisplay()
end
