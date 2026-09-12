# Kosten & Limits jeder Abhängigkeit

> Anforderung #51: Das Projekt muss kostenlos betreibbar sein — ohne
> monatliche Gebühren und ohne versteckte Kosten.
>
> Diese Datei listet **jede** externe Abhängigkeit mit Kosten, Limits,
> Nutzungsbedingungen und dem Risiko zukünftiger Kosten. Stand: 2026-09-10.

---

## Kurzfassung

**Die App kostet im Betrieb 0 € — dauerhaft.** Kein Backend, kein Hosting,
keine kostenpflichtige API, kein Abo, kein API-Key.

Es gibt **genau eine** unvermeidbare Kostenstelle, und die betrifft nicht die
App selbst, sondern Apples Vertriebsweg:

| Was du willst | Kosten |
|---|---|
| App auf dein iPhone laden (mit Zugang zu einem Mac) | **0 €** (Sideload mit kostenloser Apple-ID, alle 7 Tage neu signieren) |
| App dauerhaft auf dem iPhone / TestFlight / App Store | **99 €/Jahr** (Apple Developer Program) |
| **Echte Push-Benachrichtigungen** | **99 €/Jahr** — technisch nicht umgehbar, siehe unten |

---

## 1. Datenquellen

### Open Food Facts (Produktdaten)

| | |
|---|---|
| **Kosten** | 0 € — gemeinnütziges Projekt, spendenfinanziert |
| **API-Key** | nicht erforderlich |
| **Lizenz** | ODbL (Daten), frei nutzbar auch kommerziell, Namensnennung nötig |
| **Limits** | Keine Rate-Limit-Header im Response gefunden (geprüft 2026-09-10). Die Betreiber erwarten einen aussagekräftigen `User-Agent` und faire Nutzung. |
| **Kostenrisiko** | Sehr gering. Nonprofit ohne kommerzielles Interesse an API-Monetarisierung. |
| **Unsere Maßnahme** | Eigener `User-Agent`, lokaler Cache, keine Massenabfragen. |

### Open Prices (Preisdaten)

| | |
|---|---|
| **Kosten** | 0 € — Teil desselben Projekts |
| **API-Key** | Lesen: nein. **Schreiben**: Bearer-Token aus kostenlosem Open-Food-Facts-Konto — siehe „Preise beitragen" unten |
| **Lizenz** | ODbL |
| **Limits** | Keine Rate-Limit-Header gefunden (geprüft 2026-09-10). Pagination über `size`/`page`. |
| **Kostenrisiko** | Sehr gering, siehe oben. |
| **Unsere Maßnahme** | Ergebnisse cachen, `size` begrenzen. Aktualisiert wird höchstens stündlich und nur Startseite und Favoriten, solange die App offen ist (seit 2026-09-12). |

### Kaufland-Wochenangebote — 0 €

| | |
|---|---|
| **Kosten** | 0 € — öffentliche Angebotsseite `filiale.kaufland.de/angebote/uebersicht.html` |
| **API-Key** | nicht erforderlich |
| **Nutzung** | `robots.txt` erlaubt die Übersicht; Impressum und Website schränken die Nutzung nicht ein (geprüft 2026-09-12). Keine Bilder, nur Titel, Preise und Gültigkeit, mit Quellenangabe. |
| **Limits** | Keine veröffentlicht. Die Seite ist komprimiert rund 500 KB groß. |
| **Unsere Maßnahme** | Ehrlicher `User-Agent`, höchstens stündlich und nur bei geöffneter App, frühestens nach 10 Minuten erneut, zwei Versuche. Kein Standort wird mitgeschickt. |
| **Risiko** | Kaufland kann die Seite jederzeit ändern oder sperren. Dann zeigt die App einen Fehler statt veralteter Angebote. |

### ALDI Nord und ALDI SÜD — 0 €

| | ALDI Nord | ALDI SÜD |
|---|---|---|
| **Seite** | `aldi-nord.de/angebote.html` und die Vorschau `/angebote-vorschau.html` | `aldi-sued.de/angebote` und Tagesseiten `/angebote/JJJJ-MM-TT` |
| **Kosten / Key** | 0 €, kein Key | 0 €, kein Key |
| **Nutzung** | `robots.txt` erlaubt die Seite; Impressum ohne Nutzungseinschränkung (geprüft 2026-09-12) | `robots.txt` erlaubt Angebots- und Unterseiten (`?page=`); Impressum ohne Einschränkung, Nutzungsbedingungen betreffen nur das Kundenkonto (geprüft 2026-09-12) |
| **Umfang je Abruf** | 2 Seiten (laufende und nächste Woche), komprimiert je rund 100 KB | Übersicht plus je Aktionstag 1–3 Seiten, zusammen bis zu rund 20 Abrufe à ~125 KB |
| **Unsere Maßnahme** | Ehrlicher `User-Agent`, frühestens nach 10 Minuten erneut | Ehrlicher `User-Agent`, höchstens einmal pro Stunde, nur Aktionstage ±7 Tage, höchstens 6 Seiten je Tag |

### Angebotsseiten der übrigen Märkte — reine Links, 0 €

Die Startseite verlinkt die offiziellen Angebotsseiten von REWE, EDEKA,
Lidl, PENNY, Netto Marken-Discount und NORMA. Dort wird **nichts
ausgelesen** — diese Ketten erlauben es nicht oder geben ihre Angebote nur
nach Marktauswahl heraus. Begründung und Belege:
[DATENQUELLEN-SUPERMAERKTE.md](DATENQUELLEN-SUPERMAERKTE.md).

### Preise beitragen — ebenfalls 0 €

Wer selbst Preise einträgt, braucht ein **kostenloses Konto bei Open Food
Facts**. Keine Zahlungsdaten, kein Abo, keine Gebühr — das Konto dient nur
dazu, dass die Datenbank nachvollziehen kann, woher ein Preis stammt.

Technisch: Benutzername und Kennwort holen einmalig einen Zugangstoken
(`POST /api/v1/auth`). Das Kennwort wird **nicht gespeichert**, der Token
liegt im Schlüsselbund des Geräts. Beiträge stehen anschließend unter ODbL
allen zur Verfügung — das ist der Grund, warum die Daten in dieser App nichts
kosten.

### Overpass API / OpenStreetMap (Filialen)

| | |
|---|---|
| **Kosten** | 0 € — von der OSM-Community betrieben |
| **API-Key** | nicht erforderlich |
| **Lizenz** | ODbL, Namensnennung „© OpenStreetMap-Mitwirkende" **Pflicht** |
| **Limits** | **Live gemessen 2026-09-10:** `Rate limit: 2` — nur **2 gleichzeitige Abfragen pro IP**. Zusätzlich Zeit- und Speicherkontingente pro Query. |
| **Kostenrisiko** | Keines. Aber: Bei Überlastung antwortet der Server mit HTTP 429 — die App muss das sauber abfangen. |
| **Unsere Maßnahme** | Anfragen **serialisieren** (nie parallel), Ergebnisse pro Kachel **7 Tage lokal cachen**, kleiner Radius, `[out:json][timeout:25]`, Backoff bei 429, Attributionshinweis in den Einstellungen. |

---

## 2. iOS-Frameworks — alle kostenlos in iOS enthalten

| Framework | Wofür | Kosten |
|---|---|---|
| SwiftUI | gesamte Oberfläche | 0 € |
| SwiftData | Favoriten, Einkaufsliste, Alarme, Cache | 0 € |
| MapKit | Kartenanzeige **und** Routenübergabe via `MKMapItem.openMaps` | 0 € |
| CoreLocation | Standort, Entfernung | 0 € |
| VisionKit | Barcode-Scanner (`DataScannerViewController`) | 0 € |
| Vision | Produktfotos freistellen (`VNGenerateForegroundInstanceMaskRequest`), vollständig auf dem Gerät | 0 € |
| Swift Charts | Preisverlauf-Diagramm | 0 € |
| UserNotifications | lokale Benachrichtigungen | 0 € |
| BackgroundTasks | `BGAppRefreshTask` für Preisprüfung | 0 € |

**Wichtig zu MapKit:** Auf Apple-Plattformen ist MapKit in iOS enthalten und
kostenlos — anders als *MapKit JS* im Web, das Kontingente hat. Wir nutzen
ausschließlich das native MapKit. Kein Google-Maps-SDK, kein Mapbox, kein
Kartenkontingent.

**Geocoding** (manuelle Stadteingabe, Anforderung #14) über Apples
`CLGeocoder` bzw. `MKLocalSearch` — ebenfalls kostenlos in iOS. Deshalb
brauchen wir **kein** Nominatim und keinen externen Geocoding-Dienst.

---

## 3. Google Maps — kostenlos, weil wir kein SDK verwenden

Anforderung #15 nennt Google Maps als Routenziel. Das lösen wir **ohne**
Google-Maps-Platform-Account und **ohne** API-Key:

```
comgooglemaps://?daddr=<lat>,<lng>&directionsmode=driving
```

Das ist ein URL-Schema, das die **bereits installierte** Google-Maps-App
öffnet. Es findet kein API-Aufruf statt, es gibt keinen Key und keine
Abrechnung. Ist die App nicht installiert, fällt die Route auf Apple Karten
zurück — auch das kostenlos.

> Das Google-Maps-**SDK** oder die Directions-API wären kostenpflichtig
> (Kontingent + Kreditkarte). Beides bauen wir bewusst **nicht** ein.

---

## 4. Backend & Hosting — gestrichen

Die ursprüngliche Architektur sah für Push-Benachrichtigungen ein kleines
Backend vor (~5–10 €/Monat). **Das ist mit Anforderung #51 unvereinbar und
entfällt ersatzlos.**

Die App spricht direkt mit den drei öffentlichen APIs. Damit gilt:

- kein Server, keine Datenbank, kein Hosting
- keine Secrets, die geschützt werden müssten
- keine DSGVO-Auftragsverarbeitung
- **0 € Betriebskosten, dauerhaft**

### Warum es dafür keine kostenlose Backend-Alternative gibt

Ich habe die üblichen Gratis-Tarife geprüft. Das Problem liegt nicht am
Hosting, sondern an Apple:

> **Remote Push auf iOS läuft ausschließlich über Apples Push-Dienst APNs.
> Ein APNs-Schlüssel setzt eine Mitgliedschaft im Apple Developer Program
> (99 €/Jahr) voraus. Kostenlose Entwickler-Profile enthalten die
> Push-Berechtigung nicht.**

Es ist also gleichgültig, wie günstig der Server wäre — **echter Push ist auf
iOS grundsätzlich nicht kostenlos.** Ein Gratis-Hoster würde daran nichts
ändern.

### Was wir stattdessen tun — kostenlos

Preisalarme (#11) laufen **auf dem Gerät**:

`BGAppRefreshTask` weckt die App gelegentlich im Hintergrund, prüft die
abonnierten Produkte gegen die Open-Prices-API und löst bei Treffer eine
**lokale** Benachrichtigung aus. Das kostet nichts und braucht kein
Developer-Programm.

**Die ehrliche Einschränkung, die in der App auch so benannt wird:**
iOS entscheidet selbst, wann und ob ein `BGAppRefreshTask` läuft — abhängig
von Akku, Netz und Nutzungsgewohnheiten. Ein Preisalarm kann deshalb
**verspätet oder gar nicht** ausgelöst werden. Er ist eine Bequemlichkeit,
keine Garantie. Die App wird das im Alarm-Dialog so sagen und nicht so tun,
als sei es Echtzeit-Push.

---

## 5. Entwicklung & Verteilung

| Posten | Kosten | Anmerkung |
|---|---|---|
| Xcode | 0 € | nur macOS |
| Swift, alle Frameworks | 0 € | |
| Fremdbibliotheken | 0 € | **wir verwenden keine** |
| Simulator-Tests | 0 € | Mac nötig |
| Sideload aufs eigene iPhone | **0 €** | kostenlose Apple-ID, Signatur läuft nach 7 Tagen ab, dann neu bauen |
| Apple Developer Program | **99 €/Jahr** | nur nötig für: TestFlight, App Store, Push, Signatur ohne 7-Tage-Ablauf |
| Cloud-Mac (falls kein Mac vorhanden) | ~0,10 €/h | vermeidbar, wenn du an einen Mac kommst |
| GitHub Actions macOS-Runner | 0 € bei öffentlichem Repo | Build ja — Verteilung aufs iPhone braucht trotzdem das Developer-Programm |

---

## 6. Kostenrisiko-Bewertung

| Risiko | Bewertung |
|---|---|
| Eine der drei APIs führt Gebühren ein | **Sehr gering.** Alle drei sind gemeinnützig/community-betrieben mit offener Lizenz. Die Daten sind zusätzlich als ODbL-Dump frei herunterladbar — im Ernstfall bliebe der Datenzugang bestehen. |
| Eine API schaltet ab oder drosselt | **Möglich.** Deshalb: Cache, sauberes Fehlerverhalten, und die App bleibt mit gecachten Daten nutzbar (klar als veraltet markiert). |
| Versteckte Kontingente | **Keine gefunden.** Kein Dienst verlangt Kreditkarte, Konto oder Key (außer dem kostenlosen OFF-Konto zum Beitragen von Preisen). |
| Wachsende Nutzerzahl treibt Kosten | **Nicht möglich.** Es gibt keine Komponente, die wir bezahlen — jedes Gerät spricht direkt mit den APIs. |

---

## 7. Regel für die weitere Entwicklung

Bevor eine neue externe Abhängigkeit eingebaut wird, muss sie hier mit
Kosten, Limits und Lizenz eingetragen werden. Kommt etwas mit Kreditkarte,
Kontingent oder Abo — wird es nicht eingebaut, sondern dir vorgelegt.
