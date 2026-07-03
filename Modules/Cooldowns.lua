--------------------------------------------------------------------------------
-- BDKMain - Cooldown-Leiste
-- Icon-Reihe für die wichtigen Blut-DK-Fähigkeiten. Cooldown-Swipes rendert
-- die Engine über Cooldown-Frames (kein eigenes Polling); aktive Buffs
-- bekommen einen Glow (UNIT_AURA mit Fast-Path-Filterung).
--------------------------------------------------------------------------------

local BDK = LibStub("AceAddon-3.0"):GetAddon("BDKMain")
local mod = BDK:NewModule("Cooldowns", "AceEvent-3.0")
local LCG = LibStub("LibCustomGlow-1.0")

local IsPlayerSpell = IsPlayerSpell
local GetPlayerAuraBySpellID = C_UnitAuras.GetPlayerAuraBySpellID

local db

-- Getrackte Fähigkeiten in Anzeige-Reihenfolge.
-- buffId: Aura, die während der Wirkdauer aktiv ist (für den Glow).
local TRACKED_SPELLS = {
	{ id = 49028,  name = "Tanzende Runenwaffe",      buffId = 81256 },
	{ id = 55233,  name = "Vampirblut",               buffId = 55233 },
	{ id = 48707,  name = "Antimagische Hülle",       buffId = 48707 },
	{ id = 48792,  name = "Eisgebundene Seelenstärke", buffId = 48792 },
	{ id = 194679, name = "Runenheilung",             buffId = 194679, charges = true },
	{ id = 50842,  name = "Blutkochen",               charges = true },
	{ id = 43265,  name = "Tod und Verfall" },
	{ id = 49039,  name = "Lichfürst",                buffId = 49039 },
	{ id = 219809, name = "Grabstein",                buffId = 219809 },
	{ id = 194844, name = "Knochensturm",             buffId = 194844 },
	{ id = 383269, name = "Monstrositätengliedmaße",  buffId = 383269 },
}
mod.TRACKED_SPELLS = TRACKED_SPELLS

--------------------------------------------------------------------------------
-- Icons
--------------------------------------------------------------------------------

function mod:CreateFrames()
	if self.frame then return end
	local f = CreateFrame("Frame", "BDKMainCooldownsFrame", UIParent)
	f:SetFrameStrata("MEDIUM")
	self.frame = f
	self.icons = {} -- [spellId] = button
	BDK:RegisterMovable("cooldowns", f, "BDKMain: Cooldowns")
end

local function getOrCreateIcon(self, entry)
	local btn = self.icons[entry.id]
	if btn then return btn end

	btn = CreateFrame("Frame", nil, self.frame)
	local icon = btn:CreateTexture(nil, "ARTWORK")
	icon:SetAllPoints()
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	local tex = C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(entry.id)
	icon:SetTexture(tex or 134400)
	btn.icon = icon

	local cd = CreateFrame("Cooldown", nil, btn, "CooldownFrameTemplate")
	cd:SetAllPoints()
	btn.cd = cd

	local chargeText = btn:CreateFontString(nil, "OVERLAY")
	chargeText:SetFont(BDK.FONT, 12, "OUTLINE")
	chargeText:SetPoint("BOTTOMRIGHT", -2, 2)
	btn.chargeText = chargeText

	btn.spellId = entry.id
	btn.buffId = entry.buffId
	self.icons[entry.id] = btn
	return btn
end

-- Baut die Icon-Reihe neu auf (bekannte + aktivierte Fähigkeiten)
function mod:RebuildIcons()
	local shown = 0
	local size, spacing = db.iconSize, db.spacing

	for _, entry in ipairs(TRACKED_SPELLS) do
		local known = IsPlayerSpell(entry.id)
		local enabled = db.spells[entry.id] ~= false
		local btn = self.icons[entry.id]
		if known and enabled then
			btn = getOrCreateIcon(self, entry)
			btn:SetSize(size, size)
			btn:ClearAllPoints()
			btn:SetPoint("TOPLEFT", shown * (size + spacing), 0)
			btn.cd:SetHideCountdownNumbers(not db.showCountdownNumbers)
			btn:Show()
			shown = shown + 1
		elseif btn then
			self:SetIconGlow(btn, false)
			btn:Hide()
		end
	end

	self.frame:SetSize(math.max(shown * (size + spacing) - spacing, size), size)
	self:UpdateAllCooldowns()
	self:RefreshGlows()
end

--------------------------------------------------------------------------------
-- Cooldowns & Aufladungen
--------------------------------------------------------------------------------

function mod:UpdateIconCooldown(btn)
	if not btn:IsShown() then return end
	local charges = C_Spell.GetSpellCharges and C_Spell.GetSpellCharges(btn.spellId)
	if charges and charges.maxCharges and charges.maxCharges > 1 then
		btn.chargeText:SetText(charges.currentCharges)
		if charges.currentCharges < charges.maxCharges then
			btn.cd:SetCooldown(charges.cooldownStartTime, charges.cooldownDuration)
			btn.cd:SetDrawSwipe(charges.currentCharges == 0)
		else
			btn.cd:Clear()
		end
		btn.icon:SetDesaturated(charges.currentCharges == 0)
		return
	end

	btn.chargeText:SetText("")
	local info = C_Spell.GetSpellCooldown and C_Spell.GetSpellCooldown(btn.spellId)
	if info and info.startTime and info.duration and info.duration > 1.6 then
		btn.cd:SetDrawSwipe(true)
		btn.cd:SetCooldown(info.startTime, info.duration)
		btn.icon:SetDesaturated(true)
	else
		btn.cd:Clear()
		btn.icon:SetDesaturated(false)
	end
end

function mod:UpdateAllCooldowns()
	for _, btn in pairs(self.icons) do
		self:UpdateIconCooldown(btn)
	end
end

--------------------------------------------------------------------------------
-- Aktiv-Glow über UNIT_AURA (Fast-Path: nur auf beobachtete Auren reagieren)
--------------------------------------------------------------------------------

function mod:SetIconGlow(btn, enabled)
	if enabled and not btn.glowActive then
		btn.glowActive = true
		LCG.ButtonGlow_Start(btn)
	elseif not enabled and btn.glowActive then
		btn.glowActive = false
		LCG.ButtonGlow_Stop(btn)
	end
end

function mod:RefreshGlows()
	if not db.activeGlow then
		for _, btn in pairs(self.icons) do self:SetIconGlow(btn, false) end
		return
	end
	local watched = self.watchedInstanceIDs
	if watched then wipe(watched) else watched = {} self.watchedInstanceIDs = watched end
	local buffMap = self.buffToButton
	if buffMap then wipe(buffMap) else buffMap = {} self.buffToButton = buffMap end

	for _, btn in pairs(self.icons) do
		if btn:IsShown() and btn.buffId then
			buffMap[btn.buffId] = btn
			local aura = GetPlayerAuraBySpellID(btn.buffId)
			self:SetIconGlow(btn, aura ~= nil)
			if aura then watched[aura.auraInstanceID] = true end
		elseif btn.glowActive then
			self:SetIconGlow(btn, false)
		end
	end
end

function mod:OnUnitAura(_, _, updateInfo)
	if not db.activeGlow then return end
	if updateInfo and not updateInfo.isFullUpdate then
		local relevant = false
		if updateInfo.addedAuras then
			local buffMap = self.buffToButton
			for _, aura in ipairs(updateInfo.addedAuras) do
				if buffMap and buffMap[aura.spellId] then relevant = true break end
			end
		end
		local watched = self.watchedInstanceIDs
		if not relevant and watched and updateInfo.removedAuraInstanceIDs then
			for _, id in ipairs(updateInfo.removedAuraInstanceIDs) do
				if watched[id] then relevant = true break end
			end
		end
		if not relevant then return end
	end
	self:RefreshGlows()
end

--------------------------------------------------------------------------------
-- Events / Lebenszyklus
--------------------------------------------------------------------------------

function mod:ApplySettings()
	db = BDK.db.profile.cooldowns
	if not self.frame then return end
	self.frame:SetScale(db.scale)
	BDK:RestorePosition(self.frame, db)
	self:RebuildIcons()
	self:UpdateVisibility()
end

function mod:UpdateVisibility()
	local f = self.frame
	if not f then return end
	f:SetShown(BDK.testMode or not BDK.db.profile.locked or InCombatLockdown())
end

function mod:OnCombatChanged()
	self:UpdateVisibility()
end

function mod:OnTalentsChanged()
	self:RebuildIcons()
end

function mod:OnEnable()
	db = BDK.db.profile.cooldowns
	self:CreateFrames()
	self:ApplySettings()
	self:RegisterEvent("SPELL_UPDATE_COOLDOWN", "UpdateAllCooldowns")
	self:RegisterEvent("SPELL_UPDATE_CHARGES", "UpdateAllCooldowns")
	self:RegisterUnitEvent("UNIT_AURA", "player", "OnUnitAura")
	self:RegisterEvent("TRAIT_CONFIG_UPDATED", "OnTalentsChanged")
	self:RegisterEvent("PLAYER_ENTERING_WORLD", "OnTalentsChanged")
	self:RegisterEvent("PLAYER_REGEN_DISABLED", "OnCombatChanged")
	self:RegisterEvent("PLAYER_REGEN_ENABLED", "OnCombatChanged")
end

function mod:OnDisable()
	self:UnregisterAllEvents()
	if self.frame then
		for _, btn in pairs(self.icons) do self:SetIconGlow(btn, false) end
		self.frame:Hide()
	end
end

--------------------------------------------------------------------------------
-- Testmodus
--------------------------------------------------------------------------------

function mod:SetTestMode()
	self:UpdateVisibility()
end
