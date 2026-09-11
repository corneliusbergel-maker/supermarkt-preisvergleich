# Supermarkt-Preisvergleich (iPhone · iPad · Mac)

[![CI](https://github.com/corneliusbergel-maker/supermarkt-preisvergleich/actions/workflows/ci.yml/badge.svg)](https://github.com/corneliusbergel-maker/supermarkt-preisvergleich/actions/workflows/ci.yml)

Preisvergleich für deutsche Supermärkte — mit **echten** Daten aus offenen
Quellen, ohne erfundene Preise und ohne laufende Kosten.

Ein SwiftUI-Codebestand, drei Gerätearten: Universal-App für iPhone und iPad,
plus Mac Catalyst. Das Layout passt sich der Breite an (Tab-Leiste auf dem
iPhone, Seitenleiste auf iPad und Mac). Welche Funktion wo verfügbar ist —
und wo nicht — steht in [ARCHITEKTUR.md](ARCHITEKTUR.md), Abschnitt 4.4.

| Dokument | Inhalt |
|---|---|
| [ARCHITEKTUR.md](ARCHITEKTUR.md) | Technische Analyse, geprüfte Datenquellen, Feature-Matrix, Roadmap |
| [KOSTEN.md](KOSTEN.md) | Kosten & Limits **jeder** Abhängigkeit (Kurzfassung: 0 €) |

---

## Zwei Dinge vorweg

**1. Betrieb kostet 0 €.** Kein Backend, kein Hosting, kein API-Key, kein Abo.
Die App spricht direkt mit drei kostenlosen, offenen APIs. Einzige mögliche
Kostenstelle ist das Apple Developer Program (99 €/Jahr) — und das nur, wenn
du TestFlight, den App Store oder echten Push willst. Details in
[KOSTEN.md](KOSTEN.md).

**2. Gebaut werden kann nur auf einem Mac.** Xcode gibt es nicht für Windows.
Der Code entsteht hier, kompiliert wird dort. Siehe Abschnitt „Build".

---

## Projektstand

| Baustein | Status |
|---|---|
| Datenquellen-Recherche (live verifiziert) | ✅ fertig |
| Kostenanalyse | ✅ fertig |
| `PriceCore` — Geld, Mengen, Grundpreis | ✅ fertig, getestet |
| `PriceCore` — Produkt-Matching | ✅ fertig, getestet |
| `PriceCore` — Preisvergleich, Confidence, Umweg-Bewertung | ✅ fertig, getestet |
| `PriceCore` — Einkaufskorb-Optimierung | ✅ fertig, getestet |
| CI auf macOS-Runner (kostenlos, öffentliches Repo) | ✅ läuft grün |
| Xcode-Projekt (iPhone · iPad · Mac Catalyst) | ✅ baut auf allen drei |
| Design-System + adaptive Navigation | ✅ steht |
| CI-Screenshots aus dem Simulator | ✅ iPhone + iPad als Artefakt |
| Netzwerkschicht mit Fehler- und Wiederholungslogik | ✅ fertig, getestet |
| Open-Food-Facts-Client (Suche + Barcode) | ✅ fertig, getestet |
| Open-Prices-Client (Preise, Verlauf, Angebote) | ✅ fertig, getestet |
| Overpass-Client (Filialen, serialisiert + gecacht) | ✅ fertig, getestet |
| Standort (CoreLocation), Einstellungen | ✅ fertig |
| **Produktsuche mit echten Daten** | ✅ läuft |
| **Produktdetail: Preisvergleich, Verlauf, Route** | ✅ läuft |
| SwiftData: Favoriten, Einkaufsliste, Alarme | ✅ fertig |
| Barcode-Scanner (VisionKit) | ✅ fertig |
| Einkaufslisten-Optimierung in der Oberfläche | ✅ läuft |
| Preisalarme (lokal, BGAppRefreshTask) | ✅ fertig |
| Preise beitragen (Preisschild fotografieren) | ⏳ als Nächstes |
| Filialübersicht mit Karte | ⏳ danach |

---

## Aufbau

```
Supermarkt App/
├── Preisfuchs.xcodeproj/        Xcode-Projekt (synchronisierte Ordnergruppen)
├── Config/Info.plist
├── Preisfuchs/                  App-Target (SwiftUI)
│   ├── PreisfuchsApp.swift
│   ├── DesignSystem/            Farben, Typografie, Karten, Leerzustände
│   ├── Navigation/              Tab-Leiste bzw. Seitenleiste je nach Breite
│   ├── Persistence/             SwiftData: Favoriten, Liste, Alarme
│   ├── Services/                Standort, Einstellungen, Routen, Umgebung
│   └── Features/                Home · Suche · Produkt · Liste · Favoriten · Einstellungen
└── Packages/PriceCore/
    ├── Sources/PriceCore/       Rechenlogik, ohne Netz und ohne SwiftUI
    │   ├── Money.swift              Decimal-Geldbeträge, Dezimalparsing
    │   ├── Quantity.swift           Mengen ("6 x 1,5 l") normalisieren
    │   ├── UnitPrice.swift          Grundpreis nach PAngV
    │   ├── Product.swift            Produktmodell + Textnormalisierung
    │   ├── ProductMatcher.swift     Ist das dasselbe Produkt?
    │   ├── RetailerRegistry.swift   „Rewe" und „REWE" sind eine Kette
    │   ├── PriceObservation.swift   Preis + Herkunft + Verlässlichkeit
    │   ├── PriceComparator.swift    Sortieren, filtern, Umweg abwägen
    │   ├── BasketOptimizer.swift    Günstigster Gesamteinkauf
    │   └── GeoDistance.swift        Luftlinie (Haversine)
    ├── Sources/PriceData/       Anbindung der Datenquellen
    │   ├── HTTP.swift               Transport, Fehlerarten, Wiederholung
    │   ├── OpenFoodFactsClient.swift
    │   ├── OpenPricesClient.swift
    │   └── OverpassClient.swift     serialisiert + zwischengespeichert
    └── Tests/                    172 Tests
```

`PriceCore` und `PriceData` enthalten bewusst **kein** SwiftUI und keine
Fremdbibliothek. Damit lassen sie sich auf jedem Mac ohne Xcode-Projekt und
ohne Simulator prüfen. Kein Test ruft eine echte API auf — die Testvorlagen
sind aufgezeichnete echte Antworten.

---

## Logik testen (nur Mac, dauert ~30 Sekunden)

```bash
cd "Packages/PriceCore" && swift test
```

Das braucht nur die Xcode-Kommandozeilenwerkzeuge, kein Xcode-Projekt.
Die Tests decken unter anderem ab:

- Grundpreis: `1,49 € / 1,5 l = 0,993 €/l`, `4,99 € / 500 g = 9,98 €/kg`
- Packungsvergleich: 1-kg-Packung ist pro kg 18,67 % günstiger als 500 g
- Cent-Genauigkeit: 100 × 0,01 € ergibt exakt 1,00 € (mit `Double` nicht der Fall)
- Matching: „Coca-Cola Original 1,5L" = „Coca Cola 1.5 Liter"
- Matching: „Coca-Cola Zero" wird **nie** mit „Original" zusammengeführt
- Matching: 4 × 250 g ist nicht 1 × 250 g
- Verlässlichkeit: ohne Beleg oder mit unsicherer Zuordnung nie „bestätigt"
- Leere Daten ergeben `.noData`, niemals „0,00 €"
- Umweg: 10 ct sparen für 10,5 km Mehrweg lohnt nicht — 7 € für 4 km schon

Wenn ein Test fehlschlägt: Ausgabe herschicken, ich korrigiere. Ich kann hier
nicht kompilieren, deshalb ist dein erster `swift test` der eigentliche
Kompilier-Check.

---

## Ohne Mac entwickeln — so läuft es hier

Das Projekt wird auf Windows geschrieben und auf einem **kostenlosen
macOS-Runner bei GitHub Actions** gebaut, getestet und im Simulator
fotografiert. Für öffentliche Repositories ist das unbegrenzt kostenlos.

Bei jedem Push laufen:

| Job | Was er prüft |
|---|---|
| `PriceCore – Logik & Tests` | `swift build` + `swift test` |
| `App bauen (iOS)` | `xcodebuild` gegen den iOS-Simulator |
| `App bauen (Mac Catalyst)` | `xcodebuild` für macOS |
| `Screenshots (iPhone/iPad)` | Simulator starten, App öffnen, Bild aufnehmen |

Die Screenshots liegen als Artefakt am jeweiligen Lauf unter
**Actions → Lauf auswählen → Artifacts**.

Was damit **nicht** geht: die App auf ein echtes iPhone bringen. Dafür braucht
es eine Signatur von Apple und damit das Apple Developer Program (99 €/Jahr).
Siehe [KOSTEN.md](KOSTEN.md).

## Build auf einem eigenen Mac

Projekt in Xcode 16 oder neuer öffnen (`Preisfuchs.xcodeproj`), Schema
`Preisfuchs` wählen, bauen. Es sind keine Abhängigkeiten zu holen — das
Projekt nutzt ausschließlich Apple-Frameworks und das lokale Paket
`Packages/PriceCore`.

Für die Installation auf einem Gerät gibt es drei Wege:

| Weg | Voraussetzung | Kosten |
|---|---|---|
| Mac + Xcode, Sideload auf eigenes iPhone | Mac, kostenlose Apple-ID | 0 €, Signatur läuft nach 7 Tagen ab |
| Cloud-Mac per Remote-Desktop | Konto beim Anbieter | ca. 0,10 €/h, kein Abo nötig |
| GitHub Actions (macOS-Runner) + TestFlight | öffentliches Repo | CI 0 €, Verteilung 99 €/Jahr |

---

## Datenquellen & Namensnennung

Diese App nutzt offene Daten. Die Namensnennung ist Lizenzpflicht und wird in
den Einstellungen der App angezeigt:

- Produktdaten: **Open Food Facts**, ODbL
- Preisdaten: **Open Prices** (Open Food Facts), ODbL
- Filialdaten: **© OpenStreetMap-Mitwirkende**, ODbL

Nicht verwendet werden: Scraping von Händler-Websites, inoffizielle
Handels-APIs, kostenpflichtige Preisdienste. Begründung in
[ARCHITEKTUR.md](ARCHITEKTUR.md), Abschnitt 2.4.

---

## Grundregel des Projekts

> Ein fehlender Preis wird angezeigt. Ein erfundener niemals.

Jeder Preis trägt Quelle, Beobachtungsdatum und ein Verlässlichkeitsniveau.
Wo keine Daten vorliegen, sagt die App das — statt eine Zahl zu zeigen, die
gut aussieht.
