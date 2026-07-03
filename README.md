# BDKMain

Spezialisiertes World-of-Warcraft-Addon für den **Blut-Todesritter** (Retail, Interface 12.0.5 / 12.0.7 / 12.1.0).

Außerhalb der Blut-Spezialisierung deaktiviert sich das Addon vollständig (alle Events abgemeldet, keine CPU-Last).

## Funktionen

### Knochenschild-Tracker (Herzstück)
- Animierte Leiste mit großer Stack-Zahl, Restlaufzeit und Restlaufzeit-Minileiste.
- Farbwechsel nach Stack-Anzahl (grün / gelb / rot, Schwellen einstellbar).
- Puls-Animation im kritischen Zustand.
- **Drei Sound-Warnungen** (Sounds pro Warnung wählbar):
  1. Stacks fallen unter die Schwelle (Standard: unter 3),
  2. Restlaufzeit unterschreitet die Zeitschwelle (Standard: 6 s),
  3. Knochenschild fällt komplett ab (zusätzlich Bildschirm-Hinweis „KNOCHENSCHILD FEHLT!“).
- Markverwüster-Erinnerung: leuchtendes Icon, wenn das Schild kritisch ist und mindestens 2 Runen bereit sind.

### Ressourcen
- 6 Runen mit Cooldown-Anzeige.
- Runenmacht-Leiste mit Markierung der aktuellen Todesstoß-Kosten (Talente wie Beinhaus werden automatisch erkannt) und Warnfarbe kurz vor dem Cap.

### Todesstoß-Helfer
- Zeigt im Kampf die voraussichtliche Todesstoß-Heilung (25 % des in den letzten 5 Sekunden erlittenen Schadens, mindestens 7 % des Maximallebens).
- Empfehlungs-Glow, wenn viel Heilung ansteht oder Runenmacht überzulaufen droht.

### Cooldown-Leiste
- Icons für Tanzende Runenwaffe, Vampirblut, Antimagische Hülle, Eisgebundene Seelenstärke, Runenheilung, Blutkochen, Tod und Verfall, Lichfürst sowie Talente (Grabstein, Knochensturm, Monstrositätengliedmaße).
- Nur bekannte Fähigkeiten werden angezeigt; aktive Wirkungen leuchten.

## Installation

1. Repository/Ordner nach `World of Warcraft/_retail_/Interface/AddOns/BDKMain` kopieren (der Ordner muss `BDKMain` heißen und die `BDKMain.toc` direkt enthalten).
2. Spiel (neu) starten oder `/reload`.

## Bedienung

| Befehl | Wirkung |
| --- | --- |
| `/bdk` | Optionsfenster öffnen |
| `/bdk test` | Testmodus (alle Anzeigen mit Beispielwerten) |
| `/bdk unlock` | Anzeigen entsperren und per Drag & Drop verschieben |
| `/bdk lock` | Anzeigen wieder sperren |
| `/bdk reset` | Profil zurücksetzen |

Erreichbar auch über das Addon-Fach an der Minimap oder `ESC → Optionen → AddOns → BDKMain`.

## Technik / Performance

- Ace3-basiert (AceAddon, AceEvent, AceDB mit Profilen, AceConfig), Glows über LibCustomGlow. Alle Libraries sind unter `Libs/` eingebettet.
- Komplett eventbasiert: Auren über `UNIT_AURA` (nur `player`) mit UpdateInfo-Fast-Path, Runen über `RUNE_POWER_UPDATE`, Runenmacht über `UNIT_POWER_UPDATE`.
- Ablauf-Warnung über neu berechnete Einmal-Timer statt Dauer-Ticker; Leisten-Animationen stoppen sich selbst.
- Kampflog (für die Todesstoß-Vorhersage) nur im Kampf registriert, mit Ringpuffer ohne Speicher-Allokationen pro Event.
- Warn-Sounds sind eingebaute Spiel-Sounds — keine Mediendateien nötig.
