--------------------------------------------------------------------------------
-- BDKMain - Knochenschild-Modul
-- Animierte Stack-Leiste + Restlaufzeit mit drei Warnstufen:
--   1) Stacks fallen unter die Schwelle
--   2) Restlaufzeit unterschreitet die Schwelle (Einmal-Timer, kein Ticker)
--   3) Knochenschild fällt komplett ab
-- Tracking rein über UNIT_AURA (nur "player") mit UpdateInfo-Filterung.
--------------------------------------------------------------------------------

local BDK = LibStub("AceAddon-3.0"):GetAddon("BDKMain")
local mod = BDK:NewModule("BoneShield", "AceEvent-3.0")
local LCG = LibStub("LibCustomGlow-1.0")

local BONE_SHIELD_ID = 195181 -- Aura "Knochenschild"
local MARROWREND_ID  = 195182 -- "Markverwüster"

local GetTime, InCombatLockdown = GetTime, InCombatLockdown
local GetPlayerAuraBySpellID = C_UnitAuras.GetPlayerAuraBySpellID
local GetRuneCooldown = GetRuneCooldown
local string_format = string.format

local db -- Kurzzugriff auf BDK.db.profile.boneShield

--------------------------------------------------------------------------------
-- Anzeige
--------------------------------------------------------------------------------

function mod:CreateFrames()
	if self.frame then return end

	local f = CreateFrame("Frame", "BDKMainBoneShieldFrame", UIParent)
	f:SetFrameStrata("MEDIUM")
	BDK.SkinFrame(f)
	self.frame = f

	-- Hauptleiste: Füllstand = Stacks
	local bar = CreateFrame("StatusBar", nil, f)
	bar:SetPoint("TOPLEFT", 1, -1)
	bar:SetPoint("BOTTOMRIGHT", -1, 5)
	bar:SetStatusBarTexture(BDK.BAR_TEXTURE)
	self.bar = bar

	-- Mini-Leiste unten: Restlaufzeit-Anteil
	local dur = CreateFrame("StatusBar", nil, f)
	dur:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -1)
	dur:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 1)
	dur:SetStatusBarTexture(BDK.BAR_TEXTURE)
	dur:SetStatusBarColor(0.75, 0.75, 0.75)
	dur:SetMinMaxValues(0, 1)
	self.durBar = dur

	-- Große Stack-Zahl
	local stackText = bar:CreateFontString(nil, "OVERLAY")
	stackText:SetFont(BDK.FONT, 18, "OUTLINE")
	stackText:SetPoint("LEFT", 6, 0)
	self.stackText = stackText

	-- Name / Status in der Mitte
	local label = bar:CreateFontString(nil, "OVERLAY")
	label:SetFont(BDK.FONT, 11, "OUTLINE")
	label:SetPoint("CENTER")
	label:SetText("Knochenschild")
	self.label = label

	-- Restlaufzeit rechts
	local timeText = bar:CreateFontString(nil, "OVERLAY")
	timeText:SetFont(BDK.FONT, 13, "OUTLINE")
	timeText:SetPoint("RIGHT", -6, 0)
	self.timeText = timeText

	-- Puls-Animation für den kritischen Zustand (läuft ohne OnUpdate-Skript)
	local pulse = f:CreateAnimationGroup()
	pulse:SetLooping("REPEAT")
	local fadeOut = pulse:CreateAnimation("Alpha")
	fadeOut:SetFromAlpha(1) fadeOut:SetToAlpha(0.45)
	fadeOut:SetDuration(0.35) fadeOut:SetOrder(1)
	local fadeIn = pulse:CreateAnimation("Alpha")
	fadeIn:SetFromAlpha(0.45) fadeIn:SetToAlpha(1)
	fadeIn:SetDuration(0.35) fadeIn:SetOrder(2)
	pulse:SetScript("OnFinished", function() f:SetAlpha(1) end)
	self.pulse = pulse

	-- Markverwüster-Erinnerung: Icon mit Glow rechts neben der Leiste
	local mr = CreateFrame("Frame", nil, f)
	mr:SetPoint("LEFT", f, "RIGHT", 6, 0)
	local mrIcon = mr:CreateTexture(nil, "ARTWORK")
	mrIcon:SetAllPoints()
	mrIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	local tex = C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(MARROWREND_ID)
	mrIcon:SetTexture(tex or "Interface\\Icons\\ability_deathknight_marrowrend")
	mr:Hide()
	self.marrowrend = mr

	-- Throttle-Ticker (10 Hz) nur für Zeittext/Zeitleiste, läuft nur bei aktiver Aura
	local acc = 0
	f:SetScript("OnUpdate", nil)
	self.timerFrame = CreateFrame("Frame", nil, f)
	self.timerFrame:Hide()
	self.timerFrame:SetScript("OnUpdate", function(_, elapsed)
		acc = acc + elapsed
		if acc >= 0.1 then
			acc = 0
			mod:UpdateTimeDisplay()
		end
	end)

	BDK:RegisterMovable("boneShield", f, "BDKMain: Knochenschild")
end

function mod:ApplySettings()
	db = BDK.db.profile.boneShield
	local f = self.frame
	if not f then return end
	f:SetSize(db.width, db.height + 5)
	f:SetScale(db.scale)
	self.bar:SetMinMaxValues(0, db.maxStacksDisplay)
	self.marrowrend:SetSize(db.height + 5, db.height + 5)
	BDK:RestorePosition(f, db)
	self:Refresh()
end

--------------------------------------------------------------------------------
-- Zustands-Update (nur bei Aura-Änderungen aufgerufen)
--------------------------------------------------------------------------------

local function stackColor(stacks)
	if stacks <= db.lowStackThreshold then return db.colorLow
	elseif stacks <= db.midStackThreshold then return db.colorMid
	else return db.colorHigh end
end

function mod:Refresh()
	if BDK.testMode then return self:ShowTestValues() end

	local aura = GetPlayerAuraBySpellID(BONE_SHIELD_ID)
	local prevStacks = self.stacks or 0

	if aura then
		self.stacks = aura.applications or 1
		self.expirationTime = aura.expirationTime
		self.duration = aura.duration
		self.auraInstanceID = aura.auraInstanceID

		-- Warnung 1: Stack-Schwelle nach unten durchbrochen
		if self.stacks <= db.lowStackThreshold and prevStacks > db.lowStackThreshold then
			BDK:PlaySoundByKey(db.soundLowStack)
		end
		self:ScheduleExpiryWarning()
	else
		-- Warnung 3: Schild komplett weg
		if prevStacks > 0 then
			BDK:PlaySoundByKey(db.soundDropped)
		end
		self.stacks = 0
		self.expirationTime = nil
		self.duration = nil
		self.auraInstanceID = nil
		self:CancelExpiryWarning()
	end

	self:UpdateDisplay()
end

-- Warnung 2 über einen einmaligen Timer, der bei jedem Aura-Update neu gesetzt
-- wird. Pro Ablaufzeitpunkt wird höchstens einmal gewarnt.
function mod:ScheduleExpiryWarning()
	self:CancelExpiryWarning()
	local remaining = self.expirationTime - GetTime()
	local untilWarn = remaining - db.expireSoonSeconds
	if untilWarn > 0 then
		self.expiryTimer = C_Timer.NewTimer(untilWarn, function()
			mod.expiryTimer = nil
			mod:FireExpiryWarning()
		end)
	else
		self:FireExpiryWarning()
	end
end

function mod:FireExpiryWarning()
	if self.stacks == 0 or not self.expirationTime then return end
	-- nicht doppelt für denselben Ablaufzeitpunkt warnen
	if self.lastExpiryWarnedFor == self.expirationTime then return end
	self.lastExpiryWarnedFor = self.expirationTime
	BDK:PlaySoundByKey(db.soundExpiring)
	self:UpdateDisplay()
end

function mod:CancelExpiryWarning()
	if self.expiryTimer then
		self.expiryTimer:Cancel()
		self.expiryTimer = nil
	end
end

--------------------------------------------------------------------------------
-- Darstellung
--------------------------------------------------------------------------------

function mod:IsCritical()
	if self.stacks == 0 then return InCombatLockdown() end
	if self.stacks <= db.lowStackThreshold then return true end
	local remaining = self.expirationTime and (self.expirationTime - GetTime()) or 0
	return remaining > 0 and remaining <= db.expireSoonSeconds
end

function mod:UpdateDisplay()
	local f = self.frame
	if not f then return end

	local show = BDK.testMode
		or not BDK.db.profile.locked
		or self.stacks > 0
		or InCombatLockdown()
		or db.alwaysShow
	f:SetShown(show)
	if not show then
		self.pulse:Stop()
		self.timerFrame:Hide()
		return
	end

	local stacks = self.stacks or 0
	BDK.SmoothSetValue(self.bar, stacks)
	self.stackText:SetText(stacks)

	local c = stackColor(stacks)
	if stacks == 0 then c = db.colorLow end
	self.bar:SetStatusBarColor(c.r, c.g, c.b)

	if stacks > 0 then
		self.label:SetText("Knochenschild")
		self.timerFrame:Show()
	else
		self.label:SetText(InCombatLockdown() and "KNOCHENSCHILD FEHLT!" or "Knochenschild")
		self.timeText:SetText("")
		self.durBar:SetValue(0)
		self.timerFrame:Hide()
	end
	self:UpdateTimeDisplay()

	-- Puls nur im kritischen Zustand
	if db.pulseEnabled and self:IsCritical() then
		if not self.pulse:IsPlaying() then self.pulse:Play() end
	else
		self.pulse:Stop()
		f:SetAlpha(1)
	end

	self:UpdateMarrowrendGlow()
end

-- Läuft über den 10-Hz-Throttle, nur solange die Aura aktiv ist.
function mod:UpdateTimeDisplay()
	if not self.expirationTime then return end
	local remaining = self.expirationTime - GetTime()
	if remaining <= 0 then
		-- UNIT_AURA mit dem Entfernen folgt sofort; hier nur Anzeige nullen
		self.timeText:SetText("0,0 s")
		self.durBar:SetValue(0)
		return
	end

	if remaining >= 10 then
		self.timeText:SetText(string_format("%d s", remaining))
	else
		self.timeText:SetText(string_format("%.1f s", remaining):gsub("%.", ","))
	end
	if self.duration and self.duration > 0 then
		self.durBar:SetValue(remaining / self.duration)
	end

	-- Farb-/Puls-Wechsel beim Erreichen der Zeitschwelle
	local critical = self:IsCritical()
	if critical ~= self.wasCritical then
		self.wasCritical = critical
		if db.pulseEnabled and critical then
			if not self.pulse:IsPlaying() then self.pulse:Play() end
		elseif not critical then
			self.pulse:Stop()
			self.frame:SetAlpha(1)
		end
		self:UpdateMarrowrendGlow()
	end
end

-- Markverwüster-Hinweis: kritischer Zustand + mindestens 2 Runen bereit
function mod:UpdateMarrowrendGlow()
	local mr = self.marrowrend
	if not db.marrowrendGlow then
		if mr:IsShown() then LCG.ButtonGlow_Stop(mr) mr:Hide() end
		return
	end
	local wantGlow = false
	if BDK.testMode then
		wantGlow = true
	elseif self:IsCritical() and InCombatLockdown() then
		local readyRunes = 0
		for i = 1, 6 do
			local _, _, ready = GetRuneCooldown(i)
			if ready then readyRunes = readyRunes + 1 end
		end
		wantGlow = readyRunes >= 2
	end
	if wantGlow and not mr:IsShown() then
		mr:Show()
		LCG.ButtonGlow_Start(mr)
	elseif not wantGlow and mr:IsShown() then
		LCG.ButtonGlow_Stop(mr)
		mr:Hide()
	end
end

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------

-- UNIT_AURA-Fast-Path: nur reagieren, wenn wirklich Knochenschild betroffen ist.
function mod:OnUnitAura(_, _, updateInfo)
	if updateInfo and not updateInfo.isFullUpdate then
		local relevant = false
		if updateInfo.addedAuras then
			for _, aura in ipairs(updateInfo.addedAuras) do
				if aura.spellId == BONE_SHIELD_ID then relevant = true break end
			end
		end
		if not relevant and self.auraInstanceID then
			if updateInfo.updatedAuraInstanceIDs then
				for _, id in ipairs(updateInfo.updatedAuraInstanceIDs) do
					if id == self.auraInstanceID then relevant = true break end
				end
			end
			if not relevant and updateInfo.removedAuraInstanceIDs then
				for _, id in ipairs(updateInfo.removedAuraInstanceIDs) do
					if id == self.auraInstanceID then relevant = true break end
				end
			end
		end
		if not relevant then return end
	end
	self:Refresh()
end

function mod:OnCombatChanged()
	self:UpdateDisplay()
end

function mod:OnEnable()
	db = BDK.db.profile.boneShield
	self:CreateFrames()
	self:ApplySettings()
	self:RegisterUnitEvent("UNIT_AURA", "player", "OnUnitAura")
	self:RegisterEvent("PLAYER_ENTERING_WORLD", "Refresh")
	self:RegisterEvent("PLAYER_REGEN_DISABLED", "OnCombatChanged")
	self:RegisterEvent("PLAYER_REGEN_ENABLED", "OnCombatChanged")
	self:Refresh()
end

function mod:OnDisable()
	self:UnregisterAllEvents()
	self:CancelExpiryWarning()
	if self.frame then
		self.pulse:Stop()
		self.timerFrame:Hide()
		if self.marrowrend:IsShown() then
			LCG.ButtonGlow_Stop(self.marrowrend)
			self.marrowrend:Hide()
		end
		self.frame:Hide()
	end
	self.stacks = 0
	self.expirationTime = nil
	self.auraInstanceID = nil
end

--------------------------------------------------------------------------------
-- Testmodus
--------------------------------------------------------------------------------

function mod:SetTestMode(enabled)
	if enabled then
		self.stacks = 4
		self.duration = 30
		self.expirationTime = GetTime() + 12
		self:CancelExpiryWarning()
		self:UpdateDisplay()
	else
		self.stacks = 0
		self.expirationTime = nil
		self:Refresh()
	end
end

function mod:ShowTestValues()
	self.stacks = 4
	self.duration = 30
	self.expirationTime = GetTime() + 12
	self:UpdateDisplay()
end
