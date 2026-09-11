# Vom Quellcode auf dein iPhone

Diese Anleitung beantwortet die sieben Fragen aus Anforderung 46 — konkret und
ohne Auslassungen. Die unbequemen Stellen sind ausdrücklich markiert.

---

## Kurzfassung: Was kostet was

| Was du willst | Mac nötig? | Kosten |
|---|---|---|
| Code bauen und Tests laufen lassen | nein (GitHub Actions) | **0 €** |
| Im Simulator ansehen | nein (CI-Screenshots) | **0 €** |
| Im Simulator selbst bedienen | ja | 0 € (bzw. ca. 0,10 €/h Cloud-Mac) |
| **Auf dein iPhone laden, 7 Tage gültig** | **ja** | **0 €** |
| Auf dein iPhone, dauerhaft / TestFlight | nein (CI) | **99 €/Jahr** |
| Im App Store veröffentlichen | nein (CI) | **99 €/Jahr** |

Die 99 €/Jahr sind das Apple Developer Program. **Es gibt keinen legalen Weg
daran vorbei**, wenn die App dauerhaft auf einem Gerät bleiben soll. Alles
andere in diesem Projekt ist kostenlos — siehe [KOSTEN.md](KOSTEN.md).

---

## 1. Projekt in Xcode öffnen

Voraussetzung: **macOS mit Xcode 16 oder neuer.** Die CI baut mit Xcode 26.6.

```
Preisfuchs.xcodeproj   ← diese Datei per Doppelklick öffnen
```

Im Schema-Auswahlfeld oben `Preisfuchs` wählen, daneben ein Zielgerät. Dann
`⌘R`.

**Falls sich das Projekt nicht öffnen lässt:** Die Projektdatei nutzt
synchronisierte Ordnergruppen (`objectVersion 77`), die es erst ab Xcode 16
gibt. Mit einer älteren Version bleibt sie unlesbar.

---

## 2. Abhängigkeiten

**Keine.** Es ist nichts zu installieren, nichts zu holen, kein CocoaPods,
kein Carthage, kein Swift-Package aus dem Netz.

Verwendet werden ausschließlich Apple-Frameworks — SwiftUI, SwiftData,
MapKit, CoreLocation, VisionKit, Vision, Charts, UserNotifications,
BackgroundTasks, PhotosUI, Security — und das lokale Paket
`Packages/PriceCore`, das im Projektordner liegt.

Das war eine bewusste Entscheidung: Ich kann auf diesem Windows-Rechner nicht
kompilieren, und jede Fremdbibliothek wäre eine weitere Fehlerquelle, die ich
nicht prüfen kann.

---

## 3. API-Schlüssel

**Keine.** Die App braucht keinen einzigen.

| Dienst | Schlüssel nötig? |
|---|---|
| Open Food Facts (Produkte) | nein |
| Open Prices (Preise lesen) | nein |
| Overpass / OpenStreetMap (Filialen) | nein |
| Apple Karten, Ortssuche | nein — in iOS enthalten |
| Google Maps (Route) | nein — nur URL-Schema, kein SDK |

Die einzige Anmeldung im ganzen Projekt betrifft das **Beitragen** eigener
Preise. Dafür braucht es ein kostenloses Open-Food-Facts-Konto, und der
Nutzer meldet sich in der App selbst an. Es gibt nichts im Quellcode
einzutragen — genau deshalb steht dort auch kein Geheimnis, das man versehentlich
veröffentlichen könnte.

---

## 4. Wo Schlüssel einzutragen wären

Entfällt (siehe 3.). Der Zugangstoken fürs Beitragen entsteht zur Laufzeit und
liegt im **Schlüsselbund** des Geräts — nicht im Code, nicht in `UserDefaults`,
nicht im Repository.

---

## 5. Signing einrichten

In Xcode: Projekt anwählen → Target `Preisfuchs` → Reiter **Signing &
Capabilities**.

1. **Automatically manage signing** ankreuzen.
2. Bei **Team** deine Apple-ID wählen. Steht dort nichts:
   Xcode → Settings → Accounts → `+` → Apple-ID hinzufügen.
   Eine kostenlose Apple-ID genügt.
3. **Bundle Identifier** ändern. Der eingetragene Wert
   `de.preisfuchs.app` gehört mir nicht und dir auch nicht — er muss weltweit
   eindeutig sein. Nimm etwas wie `de.deinname.preisfuchs`.

> **Den Bundle Identifier zu ändern reicht aus** — die Kennung der
> Hintergrundaufgabe muss ihm *nicht* folgen. iOS verlangt nur, dass sie in
> der Info.plist aufgeführt ist.
>
> Solltest du sie trotzdem umbenennen wollen: Sie steht an **zwei** Stellen
> und muss dort identisch sein, sonst stürzt die App beim Start ab.
>
> - `Config/Info.plist`, Schlüssel `BGTaskSchedulerPermittedIdentifiers`
> - `Preisfuchs/Services/PriceAlertService.swift`, `taskIdentifier`
>
> Beide stehen aktuell auf `de.preisfuchs.priceCheck` — geprüft.

---

## 6. Auf dein iPhone installieren

### Weg A — mit Mac, kostenlos

1. iPhone per Kabel anschließen, am Gerät „Diesem Computer vertrauen" bestätigen.
2. In Xcode oben dein iPhone als Ziel wählen.
3. `⌘R`.
4. Beim ersten Mal meldet iOS „Nicht vertrauenswürdiger Entwickler":
   Einstellungen → Allgemein → VPN & Geräteverwaltung → deine Apple-ID →
   **Vertrauen**.

**Die Einschränkung:** Mit einer kostenlosen Apple-ID läuft die Signatur nach
**7 Tagen** ab. Danach startet die App nicht mehr und muss neu installiert
werden. Das ist Apples Regel, kein Fehler im Projekt.

### Weg B — ohne Mac, über TestFlight

Braucht das Apple Developer Program (99 €/Jahr).

1. Im Apple Developer Portal eine App-ID mit deinem Bundle Identifier anlegen.
2. In App Store Connect die App anlegen.
3. Einen API-Schlüssel für App Store Connect erzeugen (`.p8`).
4. Diesen Schlüssel als **GitHub-Secret** hinterlegen — **niemals** ins
   Repository legen. Die `.gitignore` blockt `*.p8` bereits.
5. Die CI um einen Archivierungs- und Upload-Schritt erweitern.

Schritt 5 ist noch nicht gebaut. Er lohnt sich erst, wenn das
Developer-Programm tatsächlich vorhanden ist — vorher ließe er sich nicht
einmal testen.

---

## 7. Schritte zur Veröffentlichung im App Store

Was **schon erledigt** ist:

- [x] App-Icon (1024 px, erzeugt von `Tools/make-icon.mjs`)
- [x] Launch Screen (über `UILaunchScreen` in der Info.plist)
- [x] Privacy Manifest (`Preisfuchs/PrivacyInfo.xcprivacy`)
- [x] Berechtigungstexte für Standort, Kamera und Fotos — auf Deutsch und
      konkret begründet
- [x] `ITSAppUsesNonExemptEncryption = false` (keine eigene Verschlüsselung)
- [x] Namensnennung der ODbL-Datenquellen in den Einstellungen — das ist
      Lizenzpflicht, nicht Höflichkeit
- [x] Keine Geheimnisse im Client
- [x] Dark Mode, Dynamic Type, VoiceOver-Beschriftungen

Was **noch fehlt**:

- [ ] Apple Developer Program (99 €/Jahr)
- [ ] App-Store-Eintrag: Name, Untertitel, Beschreibung, Schlüsselwörter
- [ ] Screenshots in den geforderten Größen (die CI erzeugt bereits welche —
      Apple verlangt aber bestimmte Geräteklassen)
- [ ] Datenschutzerklärung unter einer öffentlichen Adresse — für Apps mit
      Standortzugriff Pflicht
- [ ] Altersfreigabe ausfüllen
- [ ] App Privacy in App Store Connect — muss zum Privacy Manifest passen
- [ ] Test auf einem echten Gerät: Kamera, Standort, Hintergrundaufgaben.
      **Nichts davon lässt sich im Simulator abschließend prüfen.**

---

## Was ich nicht prüfen konnte

Ehrlichkeitshalber, weil dieses Projekt auf Windows entstanden ist:

| Geprüft durch CI auf echtem macOS | Nicht geprüft |
|---|---|
| Kompiliert für iOS und Mac Catalyst | Verhalten auf echter Hardware |
| 170+ Tests der Rechenlogik | Kamera und Barcode-Erkennung |
| App startet im Simulator | Hintergrundaufgaben (iOS plant sie selbst) |
| Suche, Preisvergleich, Verlauf mit echten Daten | Standortgenauigkeit im Feld |
| Bildschirmfotos von iPhone und iPad | Route-Übergabe an Apple/Google Maps |
| | Beitragen eines Preises (braucht ein echtes Konto) |

Die rechte Spalte ist nicht „vermutlich in Ordnung" — sie ist **ungeprüft**.
Beim ersten Lauf auf einem echten Gerät ist damit zu rechnen, dass dort etwas
klemmt.
