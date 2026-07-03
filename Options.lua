--------------------------------------------------------------------------------
-- BDKMain - Optionen (AceConfig)
--------------------------------------------------------------------------------

local BDK = LibStub("AceAddon-3.0"):GetAddon("BDKMain")

local AceConfig = LibStub("AceConfig-3.0")
local AceConfigDialog = LibStub("AceConfigDialog-3.0")

-- Generische Getter/Setter: info[#info-1] = Modul-Schlüssel, info[#info] = Option
local function get(info)
	return BDK.db.profile[info[#info - 1]][info[#info]]
end

local function set(info, value)
	BDK.db.profile[info[#info - 1]][info[#info]] = value
	BDK:ApplySettings()
end

local function getColor(info)
	local c = get(info)
	return c.r, c.g, c.b
end

local function setColor(info, r, g, b)
	local c = get(info)
	c.r, c.g, c.b = r, g, b
	BDK:ApplySettings()
end

local function getRange(name, min, max, step, order, width)
	return { type = "range", name = name, min = min, max = max, step = step, order = order, width = width }
end

local function BuildOptions()
	local options = {
		type = "group",
		name = "BDKMain - Blut-Todesritter",
		childGroups = "tab",
		args = {
			general = {
				type = "group", name = "Allgemein", order = 1,
				args = {
					desc = {
						type = "description", order = 0,
						name = "Spezialisiertes Hilfs-Addon für den Blut-Todesritter. Außerhalb der Blut-Spezialisierung deaktiviert sich das Addon vollständig.\n",
					},
					locked = {
						type = "toggle", order = 1, name = "Anzeigen gesperrt",
						desc = "Entsperren, um alle Anzeigen per Drag & Drop zu verschieben.",
						get = function() return BDK.db.profile.locked end,
						set = function(_, v) BDK:SetLocked(v) end,
					},
					test = {
						type = "execute", order = 2, name = "Testmodus umschalten",
						desc = "Zeigt alle Anzeigen mit Beispielwerten (/bdk test).",
						func = function() BDK:SetTestMode(not BDK.testMode) end,
					},
					slash = {
						type = "description", order = 10,
						name = "\nBefehle: |cffc41e3a/bdk|r Optionen, |cffc41e3a/bdk test|r Testmodus, |cffc41e3a/bdk unlock|r verschieben, |cffc41e3a/bdk lock|r sperren",
					},
				},
			},

			boneShield = {
				type = "group", name = "Knochenschild", order = 2,
				get = get, set = set,
				args = {
					enabled = { type = "toggle", order = 1, name = "Aktiviert" },
					alwaysShow = { type = "toggle", order = 2, name = "Immer anzeigen", desc = "Sonst nur im Kampf oder mit aktivem Knochenschild." },
					headerBar = { type = "header", order = 5, name = "Leiste" },
					width = getRange("Breite", 100, 500, 2, 6),
					height = getRange("Höhe", 12, 60, 1, 7),
					scale = getRange("Skalierung", 0.5, 2, 0.05, 8),
					maxStacksDisplay = getRange("Skala (max. Stapel)", 5, 15, 1, 9),
					headerThresholds = { type = "header", order = 10, name = "Schwellen & Farben" },
					midStackThreshold = getRange("Gelb ab (Stapel) und weniger", 1, 12, 1, 11),
					lowStackThreshold = getRange("Rot/Warnung ab (Stapel) und weniger", 1, 10, 1, 12),
					expireSoonSeconds = getRange("Zeitwarnung bei Restlaufzeit (s)", 2, 15, 1, 13),
					colorHigh = { type = "color", order = 14, name = "Farbe: sicher", get = getColor, set = setColor },
					colorMid = { type = "color", order = 15, name = "Farbe: Warnung", get = getColor, set = setColor },
					colorLow = { type = "color", order = 16, name = "Farbe: kritisch", get = getColor, set = setColor },
					headerAlerts = { type = "header", order = 20, name = "Warnungen" },
					pulseEnabled = { type = "toggle", order = 21, name = "Puls-Animation", desc = "Leiste pulsiert im kritischen Zustand." },
					marrowrendGlow = { type = "toggle", order = 22, name = "Markverwüster-Hinweis", desc = "Leuchtendes Icon, wenn Knochenschild kritisch ist und mindestens 2 Runen bereit sind." },
					soundsOnlyInCombat = { type = "toggle", order = 23, name = "Sounds nur im Kampf", width = "full" },
					soundLowStack = {
						type = "select", order = 24, name = "Sound: wenige Stapel",
						desc = "Wird abgespielt, wenn die Stapel unter die rote Schwelle fallen.",
						values = function() return BDK:GetSoundValues() end,
						set = function(info, v) set(info, v) BDK:PlaySoundByKey(v, true) end,
					},
					soundExpiring = {
						type = "select", order = 25, name = "Sound: läuft bald aus",
						desc = "Wird abgespielt, wenn die Restlaufzeit die Zeitschwelle unterschreitet.",
						values = function() return BDK:GetSoundValues() end,
						set = function(info, v) set(info, v) BDK:PlaySoundByKey(v, true) end,
					},
					soundDropped = {
						type = "select", order = 26, name = "Sound: Schild weg",
						desc = "Wird abgespielt, wenn der Knochenschild komplett abfällt.",
						values = function() return BDK:GetSoundValues() end,
						set = function(info, v) set(info, v) BDK:PlaySoundByKey(v, true) end,
					},
				},
			},

			resources = {
				type = "group", name = "Ressourcen", order = 3,
				get = get, set = set,
				args = {
					enabled = { type = "toggle", order = 1, name = "Aktiviert" },
					showRunes = { type = "toggle", order = 2, name = "Runen anzeigen" },
					showRunicPower = { type = "toggle", order = 3, name = "Runenmacht anzeigen" },
					headerSize = { type = "header", order = 5, name = "Größe" },
					width = getRange("Breite", 100, 500, 2, 6),
					runeHeight = getRange("Höhe: Runen", 8, 40, 1, 7),
					powerHeight = getRange("Höhe: Runenmacht", 8, 40, 1, 8),
					scale = getRange("Skalierung", 0.5, 2, 0.05, 9),
					headerExtras = { type = "header", order = 10, name = "Extras" },
					showDeathStrikeMarker = {
						type = "toggle", order = 11, name = "Todesstoß-Markierung", width = "full",
						desc = "Markiert auf der Runenmacht-Leiste die aktuellen Todesstoß-Kosten (erkennt Talente wie Beinhaus automatisch).",
					},
					capWarning = {
						type = "toggle", order = 12, name = "Cap-Warnfarbe", width = "full",
						desc = "Färbt die Runenmacht-Leiste um, wenn Runenmacht verschwendet zu werden droht.",
					},
					runeColor = { type = "color", order = 13, name = "Farbe: Runen", get = getColor, set = setColor },
					powerColor = { type = "color", order = 14, name = "Farbe: Runenmacht", get = getColor, set = setColor },
					capColor = { type = "color", order = 15, name = "Farbe: Cap-Warnung", get = getColor, set = setColor },
				},
			},

			deathStrike = {
				type = "group", name = "Todesstoß", order = 4,
				get = get, set = set,
				args = {
					desc = {
						type = "description", order = 0,
						name = "Zeigt im Kampf die voraussichtliche Todesstoß-Heilung (Schaden der letzten 5 Sekunden).\n",
					},
					enabled = { type = "toggle", order = 1, name = "Aktiviert" },
					scale = getRange("Skalierung", 0.5, 2, 0.05, 2),
					headerGlow = { type = "header", order = 5, name = "Empfehlungs-Glow" },
					glowEnabled = {
						type = "toggle", order = 6, name = "Glow aktiv", width = "full",
						desc = "Hebt die Anzeige hervor, wenn sich ein Todesstoß besonders lohnt.",
					},
					glowHealPercent = getRange("Glow ab Heilung (% des Maximallebens)", 5, 50, 1, 7, "double"),
					glowOnCap = {
						type = "toggle", order = 8, name = "Glow bei Runenmacht-Cap", width = "full",
						desc = "Zusätzlich hervorheben, wenn Runenmacht überzulaufen droht.",
					},
				},
			},

			cooldowns = {
				type = "group", name = "Cooldowns", order = 5,
				get = get, set = set,
				args = {
					enabled = { type = "toggle", order = 1, name = "Aktiviert" },
					headerLayout = { type = "header", order = 2, name = "Darstellung" },
					iconSize = getRange("Icon-Größe", 20, 64, 1, 3),
					spacing = getRange("Abstand", 0, 20, 1, 4),
					scale = getRange("Skalierung", 0.5, 2, 0.05, 5),
					showCountdownNumbers = { type = "toggle", order = 6, name = "Countdown-Zahlen" },
					activeGlow = { type = "toggle", order = 7, name = "Glow bei aktiver Wirkung" },
					headerSpells = { type = "header", order = 10, name = "Fähigkeiten" },
					spellDesc = {
						type = "description", order = 11,
						name = "Es werden nur Fähigkeiten angezeigt, die dein Charakter tatsächlich kennt (Talente werden automatisch erkannt).\n",
					},
				},
			},
		},
	}

	-- Auswahl-Schalter für jede getrackte Fähigkeit
	local cdArgs = options.args.cooldowns.args
	local CooldownsModule = BDK:GetModule("Cooldowns")
	for i, entry in ipairs(CooldownsModule.TRACKED_SPELLS) do
		cdArgs["spell" .. entry.id] = {
			type = "toggle", order = 20 + i, name = entry.name,
			get = function() return BDK.db.profile.cooldowns.spells[entry.id] ~= false end,
			set = function(_, v)
				BDK.db.profile.cooldowns.spells[entry.id] = v and nil or false
				BDK:ApplySettings()
			end,
		}
	end

	-- Profile
	options.args.profiles = LibStub("AceDBOptions-3.0"):GetOptionsTable(BDK.db)
	options.args.profiles.order = 90

	return options
end

function BDK:SetupOptions()
	AceConfig:RegisterOptionsTable("BDKMain", BuildOptions)
	AceConfigDialog:SetDefaultSize("BDKMain", 700, 620)
	-- Eintrag im Blizzard-Optionsmenü (AddOns)
	AceConfigDialog:AddToBlizOptions("BDKMain", "BDKMain")
end
