--------------------------------------------------------------------------------
-- BDKMain - Ressourcen-Modul
-- 6 Runen mit Cooldown-Anzeige (RUNE_POWER_UPDATE) und Runenmacht-Leiste
-- (UNIT_POWER_UPDATE, nur "player") mit Markierung der Todesstoß-Kosten.
--------------------------------------------------------------------------------

local BDK = LibStub("AceAddon-3.0"):GetAddon("BDKMain")
local mod = BDK:NewModule("Resources", "AceEvent-3.0")

local DEATH_STRIKE_ID = 49998

local UnitPower, UnitPowerMax = UnitPower, UnitPowerMax
local GetRuneCooldown, GetTime = GetRuneCooldown, GetTime
local POWER_RUNIC = Enum.PowerType.RunicPower

local db

--------------------------------------------------------------------------------
-- Anzeige
--------------------------------------------------------------------------------

function mod:CreateFrames()
	if self.frame then return end

	local f = CreateFrame("Frame", "BDKMainResourcesFrame", UIParent)
	f:SetFrameStrata("MEDIUM")
	self.frame = f

	-- Runen-Reihe
	local runeRow = CreateFrame("Frame", nil, f)
	runeRow:SetPoint("TOPLEFT")
	runeRow:SetPoint("TOPRIGHT")
	self.runeRow = runeRow

	self.runes = {}
	for i = 1, 6 do
		local rune = CreateFrame("Frame", nil, runeRow)
		BDK.SkinFrame(rune)
		local fill = rune:CreateTexture(nil, "ARTWORK")
		fill:SetPoint("TOPLEFT", 1, -1)
		fill:SetPoint("BOTTOMRIGHT", -1, 1)
		fill:SetTexture(BDK.BAR_TEXTURE)
		rune.fill = fill
		local cd = CreateFrame("Cooldown", nil, rune, "CooldownFrameTemplate")
		cd:SetAllPoints(fill)
		cd:SetDrawEdge(false)
		cd:SetHideCountdownNumbers(true)
		rune.cd = cd
		self.runes[i] = rune
	end

	-- Runenmacht-Leiste
	local power = CreateFrame("Frame", nil, f)
	power:SetPoint("BOTTOMLEFT")
	power:SetPoint("BOTTOMRIGHT")
	BDK.SkinFrame(power)
	self.powerFrame = power

	local bar = CreateFrame("StatusBar", nil, power)
	bar:SetPoint("TOPLEFT", 1, -1)
	bar:SetPoint("BOTTOMRIGHT", -1, 1)
	bar:SetStatusBarTexture(BDK.BAR_TEXTURE)
	self.powerBar = bar

	local text = bar:CreateFontString(nil, "OVERLAY")
	text:SetFont(BDK.FONT, 11, "OUTLINE")
	text:SetPoint("CENTER")
	self.powerText = text

	-- Markierung der Todesstoß-Kosten (dünner vertikaler Strich)
	local marker = bar:CreateTexture(nil, "OVERLAY")
	marker:SetColorTexture(1, 1, 1, 0.9)
	marker:SetWidth(2)
	marker:SetPoint("TOP", bar, "TOPLEFT", 0, 0)
	marker:SetPoint("BOTTOM", bar, "BOTTOMLEFT", 0, 0)
	self.dsMarker = marker

	BDK:RegisterMovable("resources", f, "BDKMain: Ressourcen")
end

function mod:ApplySettings()
	db = BDK.db.profile.resources
	local f = self.frame
	if not f then return end

	local height = (db.showRunes and db.runeHeight or 0)
		+ (db.showRunicPower and db.powerHeight or 0)
		+ ((db.showRunes and db.showRunicPower) and 2 or 0)
	f:SetSize(db.width, math.max(height, 10))
	f:SetScale(db.scale)

	local texture = BDK:GetBarTexture()

	self.runeRow:SetHeight(db.runeHeight)
	self.runeRow:SetShown(db.showRunes)
	local runeWidth = (db.width - 5 * 2) / 6
	for i, rune in ipairs(self.runes) do
		rune:SetSize(runeWidth, db.runeHeight)
		rune:ClearAllPoints()
		if i == 1 then
			rune:SetPoint("TOPLEFT")
		else
			rune:SetPoint("TOPLEFT", self.runes[i - 1], "TOPRIGHT", 2, 0)
		end
		rune.fill:SetTexture(texture)
		rune.fill:SetVertexColor(db.runeColor.r, db.runeColor.g, db.runeColor.b)
		rune.cd:SetHideCountdownNumbers(not db.runeCooldownNumbers)
	end

	self.powerFrame:SetHeight(db.powerHeight)
	self.powerFrame:SetShown(db.showRunicPower)
	self.powerBar:SetStatusBarTexture(texture)
	self.powerText:SetShown(db.showPowerText)

	BDK:RestorePosition(f, db)
	self:UpdateDeathStrikeCost()
	self:UpdateAll()
end

--------------------------------------------------------------------------------
-- Runen
--------------------------------------------------------------------------------

function mod:UpdateRune(index)
	local rune = self.runes[index]
	if not rune or not db.showRunes then return end
	local start, duration, ready = GetRuneCooldown(index)
	if ready or BDK.testMode then
		rune.cd:Clear()
		rune.fill:SetAlpha(1)
	elseif start and duration then
		rune.cd:SetCooldown(start, duration)
		rune.fill:SetAlpha(0.35)
	end
end

function mod:OnRuneUpdate(_, runeIndex)
	if runeIndex then
		self:UpdateRune(runeIndex)
	else
		for i = 1, 6 do self:UpdateRune(i) end
	end
end

--------------------------------------------------------------------------------
-- Runenmacht
--------------------------------------------------------------------------------

-- Aktuelle Todesstoß-Kosten (berücksichtigt passive Talente wie Beinhaus)
function mod:UpdateDeathStrikeCost()
	local cost = 45
	if C_Spell and C_Spell.GetSpellPowerCost then
		local costs = C_Spell.GetSpellPowerCost(DEATH_STRIKE_ID)
		if costs then
			for _, c in ipairs(costs) do
				if c.type == POWER_RUNIC and c.cost and c.cost > 0 then
					cost = c.cost
					break
				end
			end
		end
	end
	self.dsCost = cost
	self:UpdateMarkerPosition()
end

function mod:UpdateMarkerPosition()
	if not db.showDeathStrikeMarker or not db.showRunicPower then
		self.dsMarker:Hide()
		return
	end
	local max = UnitPowerMax("player", POWER_RUNIC)
	if max <= 0 then self.dsMarker:Hide() return end
	local frac = self.dsCost / max
	if frac >= 1 then self.dsMarker:Hide() return end
	local barWidth = db.width - 2
	self.dsMarker:ClearAllPoints()
	self.dsMarker:SetPoint("TOP", self.powerBar, "TOPLEFT", frac * barWidth, 0)
	self.dsMarker:SetPoint("BOTTOM", self.powerBar, "BOTTOMLEFT", frac * barWidth, 0)
	self.dsMarker:Show()
end

function mod:UpdatePower()
	if not db.showRunicPower then return end
	local cur = BDK.testMode and 65 or UnitPower("player", POWER_RUNIC)
	local max = UnitPowerMax("player", POWER_RUNIC)
	if max <= 0 then max = 100 end

	self.powerBar:SetMinMaxValues(0, max)
	BDK.SmoothSetValue(self.powerBar, cur)
	self.powerText:SetText(cur .. " / " .. max)

	local c = db.powerColor
	if db.capWarning and cur >= max - 10 then c = db.capColor end
	self.powerBar:SetStatusBarColor(c.r, c.g, c.b)
end

function mod:OnMaxPower()
	self:UpdateDeathStrikeCost()
	self:UpdatePower()
end

--------------------------------------------------------------------------------
-- Sichtbarkeit & Events
--------------------------------------------------------------------------------

function mod:UpdateVisibility()
	local f = self.frame
	if not f then return end
	local show = BDK.testMode
		or not BDK.db.profile.locked
		or db.alwaysShow
		or InCombatLockdown()
		or UnitPower("player", POWER_RUNIC) > 0
	f:SetShown(show)
end

function mod:UpdateAll()
	self:UpdateVisibility()
	for i = 1, 6 do self:UpdateRune(i) end
	self:UpdatePower()
	self:UpdateMarkerPosition()
end

function mod:OnEnable()
	db = BDK.db.profile.resources
	self:CreateFrames()
	self:ApplySettings()
	self:RegisterEvent("RUNE_POWER_UPDATE", "OnRuneUpdate")
	self:RegisterUnitEvent("UNIT_POWER_UPDATE", "player", "OnPowerEvent")
	self:RegisterUnitEvent("UNIT_MAXPOWER", "player", "OnMaxPower")
	self:RegisterEvent("PLAYER_REGEN_DISABLED", "OnCombatChanged")
	self:RegisterEvent("PLAYER_REGEN_ENABLED", "OnCombatChanged")
	self:RegisterEvent("PLAYER_ENTERING_WORLD", "UpdateAll")
	self:RegisterEvent("TRAIT_CONFIG_UPDATED", "OnMaxPower")
	self:UpdateAll()
end

function mod:OnPowerEvent(_, _, powerType)
	if powerType == "RUNIC_POWER" then
		self:UpdatePower()
		self:UpdateVisibility()
	end
end

function mod:OnCombatChanged()
	self:UpdateVisibility()
end

function mod:OnDisable()
	self:UnregisterAllEvents()
	if self.frame then self.frame:Hide() end
end

--------------------------------------------------------------------------------
-- Testmodus
--------------------------------------------------------------------------------

function mod:SetTestMode()
	self:UpdateAll()
end
