# Supermarkt-Preisvergleich (iPhone · iPad · Mac)

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
| `PriceCore` — Einkaufskorb-Optimierung | ⏳ als Nächstes |
| Xcode-App-Projekt, Design-System, Oberfläche | ⏳ danach |
| API-Clients (OFF, Open Prices, Overpass) | ⏳ danach |

---

## Aufbau

```
Supermarkt App/
├── ARCHITEKTUR.md
├── KOSTEN.md
├── README.md
└── Packages/
    └── PriceCore/              Rechenlogik, plattformunabhängig
        ├── Package.swift
        ├── Sources/PriceCore/
        │   ├── Money.swift           Decimal-Geldbeträge, Dezimalparsing
        │   ├── Quantity.swift        Mengen ("6 x 1,5 l") normalisieren
        │   ├── UnitPrice.swift       Grundpreis nach PAngV
        │   ├── Product.swift         Produktmodell + Textnormalisierung
        │   ├── ProductMatcher.swift  Ist das dasselbe Produkt?
        │   ├── PriceObservation.swift Preis + Herkunft + Verlässlichkeit
        │   ├── PriceComparator.swift Sortieren, filtern, Umweg abwägen
        │   └── GeoDistance.swift     Luftlinie (Haversine)
        └── Tests/PriceCoreTests/     ~70 Tests
```

`PriceCore` enthält bewusst **kein** SwiftUI und keine Fremdbibliothek. Damit
lässt es sich auf jedem Mac ohne Xcode-Projekt und ohne Simulator prüfen — der
einzige Teil des Projekts, der von Windows aus überhaupt verifizierbar
vorbereitet werden kann.

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

## Build (Mac erforderlich)

Sobald das Xcode-Projekt steht, kommt hier die vollständige Anleitung für
Öffnen, Signing und Installation aufs iPhone. Bis dahin die drei Wege im
Überblick:

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
