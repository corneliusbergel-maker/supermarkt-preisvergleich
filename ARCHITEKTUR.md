# Supermarkt-Preisvergleich iOS – Technische Analyse & Architektur

> Stand: 2026-09-10. Alle Zahlen in diesem Dokument wurden am 2026-09-10 durch
> **echte Live-Abfragen** der genannten APIs gemessen, nicht geschätzt.
>
> Kosten und Limits jeder einzelnen Abhängigkeit: **[KOSTEN.md](KOSTEN.md)**.
> Kurzfassung: Betrieb dauerhaft 0 €, kein Backend, kein API-Key, kein Abo.

---

## 0. Der Blocker, der zuerst geklärt werden muss

**Xcode läuft ausschließlich auf macOS. Es gibt keine Windows-Version.**
Dieser Rechner ist Windows 11. Daraus folgt hart:

| Was | Auf diesem Windows-PC möglich? |
|---|---|
| Swift/SwiftUI-Code schreiben | ✅ ja |
| Xcode-Projekt erzeugen | ✅ ja (Projektdatei ist Text) |
| **Kompilieren / Build** | ❌ nein |
| **iOS-Simulator** | ❌ nein |
| **Auf iPhone installieren** | ❌ nein |
| Tests ausführen | ❌ nein |

Es gibt **keine** legale, funktionierende Umgehung unter Windows.
(Hackintosh/macOS-VM verstößt gegen die Apple-Lizenz und scheitert an der
Signing-Infrastruktur. "Swift für Windows" kann kein UIKit/SwiftUI/iOS-SDK.)

### Realistische Wege zum iPhone

| Weg | Kosten | iPhone-Installation |
|---|---|---|
| **A** Eigener/geliehener Mac | einmalig | ✅ direkt, auch kostenlos (7-Tage-Sideload) |
| **B** Cloud-Mac (Scaleway M1 ca. 0,10 €/h, MacinCloud ca. 20 $/Monat) | laufend | ✅ über Remote-Desktop wie ein echter Mac |
| **C** CI-Build (GitHub Actions macOS-Runner / Codemagic) + TestFlight | CI oft gratis, **Apple Developer Program 99 €/Jahr Pflicht** | ✅ App kommt per TestFlight aufs iPhone, ganz ohne Mac |

**Konsequenz für die Zusammenarbeit:** Ich kann den Code schreiben, aber nicht
beweisen, dass er kompiliert. Deshalb wird das Projekt so gebaut, dass
Kompilierfehler minimal wahrscheinlich sind: **null Fremdbibliotheken**, nur
Apple-Frameworks, kleine Dateien, und die reine Rechenlogik (Grundpreis,
Matching, Sortierung) in einem plattformunabhängigen Swift-Package, das später
auf dem Mac per `swift test` isoliert prüfbar ist.

---

## 1. Die Kernfrage: Gibt es überhaupt echte Preisdaten?

Deine wichtigste Regel ist "keine erfundenen Daten". Also die ehrliche Antwort
vorweg:

> **Ein vollständiger, tagesaktueller Preisvergleich aller deutschen
> Supermärkte ist mit legalen, zuverlässigen Datenquellen heute NICHT
> realisierbar.** Kein deutscher Lebensmittelhändler stellt eine öffentliche
> Preis-API bereit. Was es gibt, ist eine echte, aber dünne Datenbasis.

Das ist kein Grund, das Projekt zu beerdigen – aber es bestimmt das Design:
Die App wird um **Datenehrlichkeit** herum gebaut, nicht um die Illusion von
Vollständigkeit.

---

## 2. Geprüfte Datenquellen (live verifiziert)

### 2.1 Open Food Facts – Produktdatenbank — VERIFIZIERT ✅

- Endpoint: `https://world.openfoodfacts.org/api/v2/product/{barcode}.json`
- Lizenz: ODbL (offen), kostenlos, **kein API-Key**
- Live-Test (EAN 5449000054227) lieferte:

```
product_name:     "Coca-Cola Original Taste"
brands:           "COCA-COLA SERVICES SA/NV, Coca-Cola"
quantity:         "1 L"      product_quantity: 1000 (ml)
countries_tags:   [... "en:germany" ...]
image_url:        https://images.openfoodfacts.org/.../front_en.563.400.jpg
```

- **Liefert:** Barcode, Name, Marke, Menge + normalisierte Menge in ml/g,
  Kategorien, Labels, Produktbild, Nutri-Score.
- **Liefert NICHT:** Preise.

#### Nachtrag 2026-09-11: zwei Suchwege, nicht einer

Für die Freitextsuche gibt es zwei Dienste, und der Unterschied ist wichtig:

| Dienst | Antwortzeit | `product_quantity` | Verlässlichkeit |
|---|---|---|---|
| `search.openfoodfacts.org/search` | ~0,3 s | ❌ nur Freitext | gut |
| `world.openfoodfacts.org/cgi/search.pl` | schwankend | ✅ normalisiert | **schlecht** |

Gemessen am 2026-09-11: Die klassische Route antwortete **dreimal
hintereinander mit HTTP 503**, während der Index in 0,3 s lieferte.

Konsequenz: Der Index ist der Hauptweg, die klassische Route springt nur bei
einer vorübergehenden Störung ein. Da der Index keine normalisierte Menge
führt, kommt sie dort aus dem Freitext (`"600 g"`); lässt der sich nicht
deuten, lädt die Produktdetailseite den vollständigen Datensatz über
`/api/v2/product/{code}` nach.

Zweiter Unterschied, der leicht übersehen wird: `brands` ist im Index ein
**Feld** (`["Ferrero","Nutella"]`), in der klassischen Route ein
kommagetrennter **Text**. Ein Decoder für nur eine Form verliert je nach
Quelle die Marke — und damit die Markenprüfung im Produktabgleich.
- **Rolle:** Produktkatalog, Barcode-Auflösung, Grundlage für die
  Grundpreisberechnung (`product_quantity` ist maschinenlesbar) und für das
  Produkt-Matching (gleicher Barcode = garantiert gleiches Produkt).

### 2.2 Open Prices – Preisdatenbank — VERIFIZIERT ✅, aber DÜNN in DE ⚠️

- Endpoint: `https://prices.openfoodfacts.org/api/v1/...`
- Lizenz: ODbL, kostenlos. Lesen ohne Key, **Schreiben mit Bearer-Token**.
- Prinzip: Community-erfasste, **belegpflichtige** Preise (Foto vom
  Preisschild oder Kassenbon als "proof").

**Gemessene Datenlage am 2026-09-10** (`/prices?lat=..&lon=..&radius_km=25`):

| Region (25 km Radius) | Preise gesamt | letzte 90 Tage | letzte 30 Tage |
|---|---|---|---|
| Berlin | 2.069 | 836 | **382** |
| München | 2.128 | – | – |
| Münster | 815 | – | – |
| Hamburg | 116 | – | – |
| *Paris (Vergleich)* | *80.131* | – | – |
| **Weltweit gesamt** | **311.563** | | |

**Händler in Berlin** (Stichprobe: 100 neueste Preise):
Kaufland 38 · Netto Marken-Discount 30 · Rewe 11 · Aldi Nord 9 · Lidl 6 · dm 1

**Neuester Eintrag:** 2026-09-09 (= gestern). Die Datenbank lebt.
**Rabatt-Flag:** `price_is_discounted` vorhanden (3 von 100 im Sample).

**Ehrliche Bewertung:** Die Quelle ist real, aktuell und deckt genau deine
Wunsch-Händler ab – aber die Abdeckung reicht **nicht** für "jedes Produkt in
jedem Markt". Für ein beliebiges Produkt wird die App häufig
"Keine Preisdaten in deiner Nähe" anzeigen müssen. Genau das hast du gefordert.

**Direkt nutzbare Endpunkte** (aus dem OpenAPI-Schema extrahiert):

| Endpoint | Feature aus deiner Liste |
|---|---|
| `GET /prices?product_code=&lat=&lon=&radius_km=` | #7 Preisvergleich, #16 günstigster Markt in der Nähe |
| `GET /prices?...&price_is_discounted=true` | #12 Angebotserkennung |
| `GET /prices?...&date__gte=` | #24 Datenqualität, #32 Veraltet-Kennzeichnung |
| `GET /prices/stats` | #10 Preisverlauf-Statistik |
| `GET /locations/nearby?lat=&lon=&radius_km=` | #13 Filialen |
| `GET /locations/compare?location_id_a=&location_id_b=` | #18 Einkaufsoptimierung |
| `GET /products/code/{code}` | #20 Produktdetail |
| `POST /prices` + `POST /proofs/upload` | **Eigene Preise beitragen** |

### 2.3 OpenStreetMap / Overpass – Filialdaten — VERIFIZIERT ✅

- Endpoint: `https://overpass-api.de/api/interpreter` (POST, Overpass QL)
- Lizenz: ODbL, kostenlos, kein Key. Namensnennung „© OpenStreetMap-Mitwirkende" ist Pflicht.
- **Live gemessenes Limit** (`/api/status`, 2026-09-10):

```
Rate limit: 2        <- nur 2 gleichzeitige Abfragen pro IP
2 slots available now.
```

  Konsequenz: Anfragen werden **serialisiert** (nie parallel), Ergebnisse pro
  Kachel 7 Tage lokal gecacht, HTTP 429 mit Backoff behandelt.
- Live-Test (3 km um Berlin-Mitte) lieferte pro Filiale u. a.:

```json
{ "type":"node", "id":58489979, "lat":52.5098189, "lon":13.4073729,
  "tags": { "brand":"Netto Marken-Discount", "brand:wikidata":"Q879858",
            "shop":"supermarket", "opening_hours":"Mo-Sa 07:00-24:00; Su off",
            "addr:street":"Alte Jakobstraße", "addr:housenumber":"83",
            "addr:postcode":"10179", "addr:city":"Berlin",
            "website":"https://www.netto-online.de/filialen/...",
            "wheelchair":"no", "payment:visa":"yes" } }
```

- **Rolle:** #13 Filialen, #14 Standort, #15 Route, #30 max. Entfernung,
  Öffnungszeiten. Deutschland ist in OSM sehr gut gepflegt.
- Wichtig: `brand:wikidata` ist der **stabile Schlüssel** zur Händler-
  Normalisierung – in den Daten kommt "Rewe" *und* "REWE" vor, die Wikidata-ID
  ist eindeutig.

### 2.4 Was NICHT geht – geprüft und verworfen

| Quelle | Status | Begründung |
|---|---|---|
| REWE / EDEKA / Lidl / Aldi / Kaufland offizielle Preis-API | ❌ | Keine öffentlich dokumentierte Entwickler-API auffindbar. Die Mobile-Apps nutzen private, nicht dokumentierte Endpunkte ohne Nutzungserlaubnis. |
| Kaufland Marketplace API | ⚠️ | Existiert, aber für Marktplatz-**Händler** (eigene Angebote verwalten) – kein Filial-Preisabruf. |
| marktguru (`api.marktguru.de`) | ⚠️ riskant | Inoffizieller Endpoint, in Foren/Home-Assistant-Skripten kursierend. Nicht dokumentiert, kein Nutzungsrecht, jederzeit abschaltbar, AGB- und § 87b-UrhG-Risiko. **Nicht einbauen.** |
| Kommerzielle Scraper-APIs (z. B. Pepesto) | ❓ ungeprüft | Behaupten REWE-Daten. Kostenpflichtig, Datenherkunft und Rechtslage von mir **nicht verifiziert**. Nur nach eigener Prüfung + Vertrag. |
| Eigenes Scraping der Händler-Shops | ❌ | Verstößt regelmäßig gegen AGB; Datenbankherstellerrecht (§ 87b UrhG); technische Schutzmaßnahmen. Für eine App im App Store untragbar. |

---

## 3. Die Konsequenz: "Ehrliche Daten" als Produktprinzip

Statt Lücken zu kaschieren, wird die Lücke zum Feature. Jeder Preis in der App
trägt einen **Confidence-Grad**, der direkt aus den Daten abgeleitet – nicht
geraten – wird:

```
HIGH    Preis <= 7 Tage alt, mit Beleg (proof), exakter Barcode-Treffer
MEDIUM  Preis <= 30 Tage alt
LOW     Preis  > 30 Tage alt   -> UI: "Möglicherweise veraltet"
NONE    kein Preis vorhanden   -> UI: "Keine Preisdaten in deiner Nähe"
```

Die UI zeigt nie eine Zahl ohne Datum. Kein Fallback auf Demo-Werte.
Wo nichts ist, steht "unbekannt" – und ein Button **"Preis beitragen"**.

**Das löst zugleich das Datenproblem:** Über `POST /proofs/upload` +
`POST /prices` kann die App Preisschild-Fotos beitragen. Damit sind die
Produkte, die *dich* interessieren, ab dem ersten Scan mit echten Daten
belegt – und die Daten bleiben offen für alle.

---

## 4. Architektur

### 4.1 Reine Client-Architektur

Alle drei Quellen sind öffentliche, key-freie APIs. Die App spricht direkt mit
ihnen. Ergebnis: 0 € Infrastruktur, kein Serverbetrieb, keine Secrets im
Client, keine DSGVO-Auftragsverarbeitung.

```
+---------------------- iOS App (SwiftUI) -----------------------+
|  Views       Home · Search · Liste · Favoriten · Settings       |
|  ------------------------------------------------------------  |
|  Domain      PriceComparison · UnitPrice · ProductMatcher       |
|  (Swift Package, testbar, plattformunabhängig) BasketOptimizer  |
|  ------------------------------------------------------------  |
|  Services    ProductRepo · PriceRepo · StoreRepo                |
|              LocationService · RouteService · AlertScheduler    |
|  ------------------------------------------------------------  |
|  Persistence SwiftData (Favoriten, Liste, Alarme, Cache)        |
+--------+-----------------+------------------+------------------+
         |                 |                  |
   Open Food Facts    Open Prices        Overpass / OSM
   (Produkte)         (Preise)           (Filialen)
```

### 4.2 Kein Backend – dauerhaft (Anforderung #51)

Ursprünglich war für Push-Benachrichtigungen ein kleines Backend geplant
(ca. 5–10 €/Monat). **Das entfällt ersatzlos**, weil das Projekt kostenlos
betreibbar sein muss. Details in [KOSTEN.md](KOSTEN.md).

Der Grund, warum auch ein Gratis-Hoster nichts ändern würde:

> Remote Push läuft auf iOS ausschließlich über Apples APNs. Ein APNs-Schlüssel
> setzt das Apple Developer Program (99 €/Jahr) voraus; kostenlose
> Entwicklerprofile enthalten die Push-Berechtigung nicht. **Echter Push ist
> auf iOS also grundsätzlich nicht kostenlos** – unabhängig vom Server.

**Stattdessen, kostenlos:** Preisalarme laufen auf dem Gerät.
`BGAppRefreshTask` weckt die App gelegentlich, prüft abonnierte Produkte gegen
Open Prices und löst eine **lokale** Benachrichtigung aus.

Ehrliche Einschränkung, die auch in der UI so steht: iOS entscheidet selbst,
wann ein Background-Refresh läuft. Ein Preisalarm kann deshalb verspätet oder
gar nicht feuern. Er ist eine Bequemlichkeit, keine Garantie.

Damit gilt: kein Server, keine Datenbank, kein Hosting, keine Secrets, keine
Auftragsverarbeitung – **0 € Betriebskosten, dauerhaft**.

### 4.3 Technologie-Entscheidungen

| Bereich | Wahl | Warum |
|---|---|---|
| UI | SwiftUI, iOS 17+ | `@Observable`, moderne Navigation, Referenzdesign gut umsetzbar |
| Persistenz | **SwiftData** | nativ, keine Dependency, Migrationen, gut für Favoriten/Liste/Cache |
| Netzwerk | URLSession + async/await | kein Alamofire nötig |
| Barcode | **VisionKit `DataScannerViewController`** | Apple-nativ, EAN-13/8, kein Fremd-SDK |
| Diagramme | **Swift Charts** | nativ, Dark Mode + Accessibility inklusive |
| Karten/Route | MapKit `MKMapItem.openMaps` + `comgooglemaps://` | #15, inkl. Auto/Fuß/Rad. Kein Google-SDK, kein Key, kein Kontingent |
| Geocoding | `CLGeocoder` / `MKLocalSearch` | manuelle Stadtwahl (#14) – kostenlos in iOS, deshalb kein Nominatim nötig |
| Standort | CoreLocation, `WhenInUse` | #14, nur nach Freigabe |
| Benachrichtigungen | `UserNotifications` **lokal** + `BGAppRefreshTask` | #11/#27 ohne Developer-Programm |
| Fremdbibliotheken | **keine** | siehe Abschnitt 0: senkt das Build-Risiko drastisch, und kostet nichts |

### 4.4 Eine App für iPhone, iPad und Mac

Anforderung: Die App soll auf allen drei Gerätearten laufen. Umgesetzt wird
das als **ein** SwiftUI-Codebestand mit einem Universal-Target
(iPhone + iPad) plus **Mac Catalyst** für den Mac.

Mindestversionen: iOS/iPadOS 17, macOS 14 (Sonoma) — die Kombination, in der
`@Observable`, SwiftData und Swift Charts überall verfügbar sind.

#### Layout-Strategie

Kein Gerät bekommt eine Sonderoberfläche. Stattdessen reagiert dieselbe
Ansicht auf die verfügbare Breite:

| Breite | Navigation | Inhalt |
|---|---|---|
| kompakt (iPhone hochkant) | schwebende Tab-Leiste unten, wie in den Referenzbildern | eine Spalte, Karten volle Breite |
| regulär (iPad, Mac, iPhone Max quer) | `NavigationSplitView` — Seitenleiste statt Tab-Leiste | mehrspaltiges Raster, Detailansicht daneben statt darüber |

Konkrete Regeln, die durchgehend gelten:

- Keine festen Pixelbreiten. Raster über `LazyVGrid` mit
  `GridItem(.adaptive(minimum:))`, damit aus einer Spalte auf dem iPhone von
  selbst drei auf dem iPad werden.
- Der Preisvergleich wird auf breiten Schirmen zur Tabelle mit zusätzlichen
  Spalten (Grundpreis, Entfernung, Aktualität), statt sie zu verstecken.
- Dynamic Type wird respektiert; Karten wachsen mit der Schriftgröße, statt
  Text abzuschneiden.
- Der Hero-Verlauf skaliert relativ zur Bildschirmhöhe, nicht in festen Punkten.

#### Was auf dem Mac nicht geht — und wie die App damit umgeht

Hier gilt dieselbe Regel wie bei den Preisdaten: keine Funktion vortäuschen,
die es nicht gibt.

| Funktion | iPhone | iPad | Mac | Anmerkung |
|---|---|---|---|---|
| Suche, Preisvergleich, Grundpreis | ✅ | ✅ | ✅ | reine Logik, überall gleich |
| Favoriten, Einkaufsliste (SwiftData) | ✅ | ✅ | ✅ | |
| Preisverlauf (Swift Charts) | ✅ | ✅ | ✅ | |
| Karte & Filialen (MapKit) | ✅ | ✅ | ✅ | |
| Route an Apple Karten | ✅ | ✅ | ✅ | |
| Route an Google Maps | ✅ | ✅ | ⚠️ | Für macOS gibt es keine Google-Maps-App. Fällt auf `maps.google.com` im Browser zurück. |
| **Barcode-Scanner** | ✅ | ✅ | ❌ | `VisionKit DataScannerViewController` gibt es auf macOS nicht. Auf dem Mac wird der Scanner-Knopf **gar nicht erst angezeigt** statt eine tote Schaltfläche zu zeigen. |
| Standort | ✅ | ✅ | ⚠️ | Auf dem Mac nur WLAN-basiert und deutlich ungenauer. Die manuelle Ortswahl ist dort der Hauptweg. |
| Preisalarme im Hintergrund | ✅ | ✅ | ⚠️ | `BGAppRefreshTask` ist iOS-only. Auf dem Mac wird beim Öffnen der App geprüft. |

#### Kostenfolge

Keine. Mac Catalyst ist eine Einstellung im Projekt, kein Zusatzprodukt.
Zum Testen genügt der Start aus Xcode heraus. Erst die **Weitergabe** einer
Mac-App außerhalb des App Store bräuchte eine Notarisierung — und die setzt
wieder das Apple Developer Program voraus. Für Entwicklung und eigene Nutzung
fällt nichts an.

### 4.5 Kernlogik als eigenes Swift-Package

`Packages/PriceCore` – enthält reine, seiteneffektfreie Logik und ist der
einzige Teil, den man ohne iOS-Simulator testen kann:

- `UnitPrice` – Grundpreisberechnung (#8/#37: 1,49 € / 1,5 L = 0,993 €/L,
  Rechnung mit `Decimal`, **nie `Double`**, um Rundungsfehler auszuschließen)
- `ProductMatcher` – #21: Barcode = harte Identität; ohne Barcode
  Marke + Menge + Variante mit Normalisierung ("1.5 Liter" ↔ "1,5L"), aber
  **harte Trennung** bei abweichender Gesamtmenge oder Variante (Zero ≠ Original)
- `PriceComparator` – Sortierung, Confidence, Delta zum Vorpreis
- `BasketOptimizer` – #18: günstigste Kombination über n Märkte, mit
  Entfernungs-Strafterm ("nur 10 ct teurer, aber 10,5 km näher")

---

## 5. Feature-Matrix: Was ist mit echten Daten machbar?

| # | Feature | Machbar mit echten Daten? |
|---|---|---|
| 6 | Produktsuche | ✅ voll (Open Food Facts) |
| 19 | Barcode-Scanner | ✅ voll (VisionKit + OFF) |
| 8 | Grundpreis / Preis pro Einheit | ✅ voll, exakt berechenbar |
| 20 | Produktdetailseite | ✅ voll |
| 13 | Filialen + Öffnungszeiten | ✅ voll (OSM) |
| 14 | Standort & Entfernung | ✅ voll |
| 15 | Route (Apple/Google Maps) | ✅ voll |
| 9 | Favoriten | ✅ voll (lokal) |
| 17 | Einkaufsliste | ✅ voll (lokal) |
| 29/30/31 | Filter, Radius, Sortierung | ✅ voll |
| 32/33 | Offline, Fehlerbehandlung | ✅ voll |
| 7 | **Preisvergleich** | ✅ gebaut — ⚠️ zeigt nur, was an Daten existiert |
| 12 | Angebotserkennung | ✅ gebaut — ⚠️ nur wo `price_is_discounted` gesetzt ist |
| 10 | Preisverlauf | ✅ gebaut — erscheint erst ab 4 Beobachtungen |
| 16/18 | Günstigster Markt / Korb-Optimierung | ✅ gebaut — ⚠️ Basis oft unvollständig |
| 25 | Preisänderungen | ⚠️ nur bei vorhandener Historie |
| – | **Preise beitragen** | ✅ gebaut — Preisschild fotografieren, Beleg + Preis an Open Prices |
| 11/27 | Preisalarm + Benachrichtigung | ⚠️ **lokal** (kostenlos, aber von iOS opportunistisch geplant). Echter Push nur mit Developer-Programm 99 €/Jahr – siehe [KOSTEN.md](KOSTEN.md) |
| 41 | Preisprognose | ⚠️ nur bei ausreichender Historie – sonst gar nicht anzeigen |
| – | Echtzeit-Verfügbarkeit im Regal | ❌ **keine legale Quelle. Wird nicht gebaut.** |
| – | Vollständige Preise aller Märkte | ❌ **existiert nicht. Wird nicht vorgetäuscht.** |

---

## 6. Roadmap

**M0 – Fundament** · Xcode-Projekt (baubar), `PriceCore`-Package,
Design-System aus den Referenzbildern (Farben, Cards, Typo, Tab-Bar), Tests
für Grundpreis + Matching.

**M1 – Echte Produkte** · OFF-Client, Suche, Produktdetail, Barcode-Scanner,
Favoriten + Einkaufsliste (SwiftData). *Ab hier ist die App real nutzbar.*

**M2 – Echte Orte** · Overpass-Client, Standort, Filialliste, Entfernung,
Route zu Apple/Google Maps, Radius- und Händlerfilter.

**M3 – Echte Preise** · Open-Prices-Client, Preisvergleich, Confidence-System,
Grundpreis im Vergleich, Angebots-Badge, ehrliche Leerzustände.

**M4 – Intelligenz** · Preisverlauf (Swift Charts), Preisänderungen,
Korb-Optimierung, "Lohnt sich der Umweg?", Deals-Sektion.

**M5 – Beitragen** · Preisschild fotografieren → `POST /proofs` + `/prices`.
Schließt die Datenlücke legal.

**M6 – Alarme** · lokale Preisalarme über `BGAppRefreshTask` +
`UserNotifications`, inklusive ehrlichem Hinweis auf die Zustellgarantie.
Kein Backend, keine Kosten.

**M7 – Store-Reife** · App Icon, Launch Screen, Privacy Manifest,
Permission-Texte, Accessibility-Durchlauf, Fehlerfall-Matrix.

---

## 7. Entscheidungen

### Getroffen

**Mac-Zugang: noch offen (2026-09-10).** Das Projekt wird deshalb so gebaut,
dass alle drei Wege offenbleiben — eigener Mac, Cloud-Mac oder CI. Konkret:
keine Fremdbibliotheken (kein SPM-Auflösen nötig), Rechenlogik in einem
separaten Package (`swift test` genügt, kein Xcode-Projekt), und später ein
Xcode-Projekt mit synchronisierten Ordnergruppen, das ohne Projektdatei-Pflege
auskommt.

**Farbpalette: Verlauf Bordeaux → Türkis, Cyan als funktionale Akzentfarbe.**
Aus den Referenzbildern übernommen:

| Rolle | Verwendung |
|---|---|
| Grund | Near-Black (`#0A0A0C`), Karten minimal aufgehellt |
| Hero-Verlauf | Bordeaux → Türkis, weich, über die obere Bildschirmhälfte |
| Akzent (funktional) | Cyan — Ersparnis, günstigster Preis, aktive Tab-Leiste, FAB |
| Signal Angebot | Rot/Orange — ausschließlich für Aktionspreise, sonst nie |
| Confidence | Cyan = bestätigt, neutral = aktuell, gedämpft = veraltet |

Wichtig für die Farbdisziplin: Rot ist **reserviert** für Angebote. Der
Bordeaux-Anteil erscheint nur im Verlauf, nie als Bedienelement — sonst
konkurriert er mit dem Angebots-Signal.

### Noch offen

**Testregion** — in welcher Stadt testest du? Danach richtet sich, welche
Filial- und Preisdaten wir zuerst gegen die Realität prüfen. Gemessene
Datendichte siehe Abschnitt 2.2; Berlin und München sind am besten versorgt.
