# Die App aufs iPhone bringen — ohne Mac, ohne Kosten

Es geht. Der Weg ist: **CI baut, Windows signiert, iPhone installiert.**

Ich hatte in einer früheren Antwort gesagt, dafür brauche es zwingend einen
Mac oder 99 €/Jahr. Das war zu eng gedacht — es stimmt nur für eine
**dauerhafte** Installation. Für Testen reicht die kostenlose Apple-ID.

---

## Was du brauchst

| | |
|---|---|
| iPhone + USB-Kabel | |
| Apple-ID | kostenlos, siehe Sicherheitshinweis unten |
| **Apple Devices** oder iTunes | für die USB-Treiber unter Windows |
| Signier-Werkzeug | 3uTools **oder** Sideloadly, beide kostenlos |

Kein Mac. Kein Developer-Programm. Keine Gebühr.

---

## Schritt 1 — Die IPA herunterladen

Die CI baut sie bei jedem Push automatisch.

1. [Actions im Repository öffnen](https://github.com/corneliusbergel-maker/supermarkt-preisvergleich/actions)
2. Den obersten grünen Lauf anklicken
3. Ganz unten unter **Artifacts**: `Preisfuchs-unsigned-ipa` herunterladen
4. Das ZIP entpacken — darin liegt `Preisfuchs-unsigned.ipa`

> Diese Datei ist **unsigniert**. So lässt sie sich nicht installieren — das
> ist kein Fehler, sondern der Zwischenstand. Die Signatur kommt im nächsten
> Schritt und muss von *deiner* Apple-ID stammen.

---

## Schritt 2 — Signieren und installieren

### Variante A: Sideloadly

1. [sideloadly.io](https://sideloadly.io) herunterladen und installieren
2. iPhone per Kabel anschließen, am iPhone „Vertrauen" bestätigen
3. Sideloadly öffnen, die IPA hineinziehen
4. Apple-ID eintragen, **Start** drücken
5. Bei aktivierter Zwei-Faktor-Anmeldung wird ein Code abgefragt

Sideloadly vergibt automatisch eine eindeutige Bundle-Kennung, falls
`de.preisfuchs.app` schon vergeben ist.

### Variante B: 3uTools

1. [3u.com](https://www.3u.com) herunterladen und installieren
2. iPhone anschließen
3. **Toolbox → IPA signature → Sign with Apple ID**
4. IPA wählen, Apple-ID eintragen, Gerät auswählen
5. Signieren, dann installieren

Beide binden die Signatur an die **Gerätekennung** deines iPhones. Eine so
signierte Datei lässt sich auf keinem anderen Gerät installieren.

---

## Schritt 3 — Entwickler vertrauen

Beim ersten Start meldet iOS „Nicht vertrauenswürdiger Entwickler".

**Einstellungen → Allgemein → VPN & Geräteverwaltung → deine Apple-ID →
Vertrauen**

Danach startet die App.

---

## Die Grenzen — ehrlich

**Nach 7 Tagen läuft die Signatur ab.** Die App startet dann nicht mehr. Neu
signieren mit demselben Werkzeug, dieselbe Apple-ID — die Daten auf dem Gerät
(Favoriten, Einkaufsliste) bleiben dabei erhalten, solange du die App nicht
löschst.

Weitere Grenzen kostenloser Apple-IDs:

| Grenze | Wert |
|---|---|
| Gültigkeit der Signatur | 7 Tage |
| Gleichzeitig sideloadbare Apps | 3 |
| Neue App-Kennungen | 10 pro 7 Tage |
| Geräte | 3 pro 7 Tage |

Für eine App, die du selbst testest, reicht das bequem.

---

## Sicherheitshinweis — bitte lesen

Beide Werkzeuge brauchen deine **Apple-ID samt Kennwort**. Sie melden sich
damit bei Apples Entwicklerdienst an und holen ein Signaturzertifikat. Das ist
technisch notwendig — ohne Apple-Anmeldung gibt es keine gültige Signatur.

**Meine Empfehlung: Leg dir dafür eine eigene, kostenlose Apple-ID an.**

Nicht weil die Werkzeuge zwingend unseriös wären, sondern weil das Prinzip
gilt: Zugangsdaten zum Hauptkonto — mit Fotos, Käufen, iCloud, „Wo ist?" —
gibt man keinem Drittwerkzeug. Eine separate Apple-ID kostet nichts, ist in
zwei Minuten angelegt, und im schlimmsten Fall ist nichts daran verloren.

Zum Signieren reicht sie vollständig aus.

> Ich richte diese Apple-ID **nicht** für dich ein und trage auch keine
> Zugangsdaten ein. Kontoanmeldungen machst du selbst — das ist eine feste
> Grenze bei mir, unabhängig davon, wie umständlich es ist.

---

## Was auf dem Gerät funktionieren sollte

Die App braucht **keine besonderen Berechtigungen**, die kostenlosen Konten
verwehrt wären. Es gibt keine Entitlement-Datei, kein iCloud, keine App
Groups, keinen Remote-Push.

| Funktion | Mit kostenloser Signatur |
|---|---|
| Suche, Preisvergleich, Grundpreis | ✅ |
| Barcode-Scanner (Kamera) | ✅ |
| Standort, Filialen, Routen | ✅ |
| Favoriten, Einkaufsliste (SwiftData) | ✅ |
| Lokale Benachrichtigungen | ✅ |
| Preisalarm im Hintergrund | ✅ sollte laufen (nur Info.plist, kein Entitlement) |
| Preise beitragen | ✅ braucht ein Open-Food-Facts-Konto, ebenfalls kostenlos |

Das ist der Stand nach Aktenlage — **auf echter Hardware getestet hat es
niemand**. Genau dafür ist dieser Weg da. Wenn etwas klemmt, schick mir die
Fehlermeldung.

---

## Wenn es hakt

| Symptom | Ursache |
|---|---|
| „Unable to install" | Bundle-Kennung schon vergeben → im Werkzeug eine andere setzen |
| App stürzt sofort ab | Meist die Hintergrundaufgaben-Kennung; siehe [INSTALLATION.md](INSTALLATION.md) |
| Gerät wird nicht erkannt | Apple Devices oder iTunes fehlt → USB-Treiber |
| „Could not find Developer Disk Image" | iOS neuer als das Werkzeug → Werkzeug aktualisieren |
| Nach 7 Tagen tot | Normal. Neu signieren. |
