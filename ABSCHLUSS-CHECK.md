# Abschluss-Check

Die Prüfliste aus Anforderung 48, Zeile für Zeile — und ehrlich getrennt nach
dem, was **nachgewiesen** ist, und dem, was **ungeprüft** bleibt.

Stand: 2026-09-11.

## Wie die Spalten zu lesen sind

| Zeichen | Bedeutung |
|---|---|
| ✅ **CI** | Auf einem echten macOS-Rechner gebaut und ausgeführt |
| ✅ **Test** | Durch automatische Tests abgedeckt |
| ✅ **Bild** | Im Simulator-Screenshot sichtbar |
| ⚠️ **ungeprüft** | Gebaut und kompiliert, aber nie ausgeführt |
| ❌ | Nicht möglich |

**„Ungeprüft" heißt nicht „vermutlich in Ordnung".** Es heißt: niemand hat es
je laufen sehen. Beim ersten Lauf auf einem echten Gerät ist damit zu rechnen,
dass dort etwas klemmt.

---

## Die Liste

| # | Punkt | Stand | Nachweis |
|---|---|---|---|
| 1 | Projekt baut ohne Fehler | ✅ CI | `xcodebuild` für iOS **und** Mac Catalyst, grün |
| 2 | App startet | ✅ Bild | Startseite im Simulator aufgenommen |
| 3 | Navigation funktioniert | ⚠️ teilweise | Tab-Leiste und Seitenleiste im Bild; nicht jeder Pfad wurde geklickt |
| 4 | Produktsuche funktioniert | ✅ Bild | 19 echte Treffer aus Open Food Facts |
| 5 | Produktdetails funktionieren | ✅ Bild | Nutella 400 g mit echtem Bild und echter Menge |
| 6 | Preisvergleich funktioniert | ✅ Bild | 3,53 € bei Lidl, aus 50 echten Preisen |
| 7 | Grundpreis korrekt berechnet | ✅ Test + Bild | 8,83 €/kg im Bild; dazu 20+ Tests mit `Decimal` |
| 8 | Favoriten funktionieren | ⚠️ ungeprüft | SwiftData-Modelle gebaut, nie im Betrieb gespeichert |
| 9 | Einkaufsliste funktioniert | ⚠️ ungeprüft | Optimierung durch 14 Tests gedeckt, Oberfläche nie bedient |
| 10 | Standort funktioniert | ⚠️ ungeprüft | Im Simulator keine Freigabe erteilt |
| 11 | Filialen korrekt angezeigt | ⚠️ ungeprüft | Overpass-Client getestet, Ansicht nie geöffnet |
| 12 | Routen funktionieren | ⚠️ ungeprüft | Übergabe an fremde Apps lässt sich im Simulator nicht abschließend prüfen |
| 13 | Apple Karten | ⚠️ ungeprüft | siehe 12 |
| 14 | Google Maps, falls installiert | ⚠️ ungeprüft | Im Simulator ist Google Maps nicht installiert |
| 15 | Preisverlauf funktioniert | ✅ Bild | 90-Tage-Diagramm mit echten Beobachtungen |
| 16 | Preisalarme vorbereitet | ⚠️ ungeprüft | iOS plant Hintergrundaufgaben selbst — im Simulator nicht erzwingbar |
| 17 | Fehlerfälle funktionieren | ✅ Bild | Der Ausfall von Open Food Facts trat **im Lauf wirklich auf** und wurde korrekt als Überlastung gemeldet |
| 18 | Offline-Verhalten | ⚠️ ungeprüft | Fehlerarten getestet, echter Netzausfall nie simuliert |
| 19 | Dark Mode | ✅ Bild | Die App ist durchgehend dunkel gestaltet |
| 20 | Accessibility berücksichtigt | ⚠️ teilweise | Beschriftungen gesetzt, Dynamic Type beachtet; kein VoiceOver-Durchgang |
| 21 | Keine Fake-Produktdaten | ✅ | Kein Mock-Service im Produktivcode |
| 22 | Keine erfundenen Preise | ✅ Test | Leere Daten ergeben `.noData`, niemals „0,00 €" |
| 23 | Keine erfundenen Filialen | ✅ | Ohne Koordinate wird eine Filiale verworfen |
| 24 | Keine erfundenen APIs | ✅ | Jeder Endpunkt wurde per `curl` live geprüft, bevor Code entstand |
| 25 | API-Schlüssel sicher | ✅ | Es gibt **keine** — der einzige Token liegt im Schlüsselbund |
| 26 | Läuft auf echtem iPhone | ❌ | Nicht möglich: kein Mac, und dauerhafte Installation braucht 99 €/Jahr |

---

## Was das unterm Strich heißt

**Belastbar nachgewiesen ist die Kette Daten → Rechnung → Anzeige.** Die App
holt echte Produkte, echte Preise und echte Filialdaten, rechnet daraus
korrekt Grundpreise und Vergleiche und stellt sie dar. Das ist auf
Screenshots von einem echten macOS-Rechner zu sehen, nicht behauptet.

**Nicht nachgewiesen ist alles, was Gerätefunktionen braucht.** Kamera,
Standort, Hintergrundaufgaben, Routenübergabe — das lässt sich ohne echtes
Gerät nicht abschließend prüfen, und ich behaupte es deshalb auch nicht.

Der wertvollste Einzelbefund kam ungeplant: In einem Lauf antwortete Open
Food Facts tatsächlich mit HTTP 503, und die App meldete „Die Datenquelle ist
gerade überlastet" statt „keine Treffer". Genau diese Unterscheidung war von
Anfang an die Kernregel des Projekts — sie hat sich unter echten Bedingungen
bewährt, ohne dass ich den Fall herbeigeführt hätte.

---

## Die zwei Fehler in der Aufgabenstellung

Beim Umsetzen sind zwei Rechenfehler in den Anforderungen aufgefallen. Beide
sind im Code zugunsten des **richtigen** Werts gelöst und durch Tests
festgehalten:

**Punkt 18** nennt für „REWE + Kaufland" 5,37 €. Mit den dort angegebenen
Preisen ist das nicht erreichbar — Kaufland ist bei allen drei Artikeln am
günstigsten, jede Aufteilung wird teurer. Richtig sind **5,57 € in einem
Markt**.

**Punkt 12** nennt zu „1,29 € statt 1,69 €" einen Rabatt von 22 %.
Nachgerechnet sind es 23,67 %, gerundet **24 %**.

---

## Womit weiterzumachen wäre

1. **Kamera direkt in der App** statt Fotoauswahl — für Preisschilder der
   natürlichere Weg.
2. **Ein Durchgang auf echtem Gerät**, sobald ein Mac verfügbar ist. Danach
   werden aus den ⚠️-Zeilen oben entweder ✅ oder konkrete Fehlerberichte.
3. **VoiceOver-Durchgang** mit eingeschaltetem Bildschirmleser.
4. **Preisprognose** (Anforderung 41) — bewusst noch nicht gebaut. Sie setzt
   deutlich mehr Beobachtungen je Produkt voraus, als in Deutschland
   vorliegen. Eine Vorhersage aus vier Datenpunkten wäre Kaffeesatzleserei.

Nachgetragen am 2026-09-11: **Preisänderungen** (Anforderung 25) und
**„Deine besten Deals"** (Anforderung 28) sind gebaut. Beide erscheinen nur,
wenn die Daten sie hergeben — eine Änderung braucht zwei tatsächlich
beobachtete Preise, ein Rabatt in Prozent den bekannten Ursprungspreis.
