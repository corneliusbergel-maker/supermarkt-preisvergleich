# Preise direkt von den Supermärkten – Prüfung

> Frage vom 2026-09-12: Kann Preisfuchs die Preise und Angebote von Edeka,
> Lidl, REWE & Co. direkt bei den Märkten abholen und stündlich aktualisieren,
> statt nur über Open Prices?
>
> Maßstab ist Anforderung #22: *„Nicht einfach Webseiten scrapen, wenn dies
> gegen deren Nutzungsbedingungen verstößt. Prüfe die technische und
> rechtliche Machbarkeit.“* Und #39: Geht etwas nicht, wird keine Lösung
> erfunden, sondern erklärt, was möglich ist.
>
> Das hier ist eine technische Bestandsaufnahme, **keine Rechtsberatung**.

---

## Ergebnis

**Keine deutsche Supermarktkette bietet eine offizielle Schnittstelle an.**
Geprüft wurde deshalb, ob eine Kette ihre öffentliche Angebotsseite für eine
App zugänglich lässt. Die Kriterien:

1. `robots.txt` erlaubt die Seite,
2. die Seite antwortet einer App, die sich ehrlich als Preisfuchs zu erkennen
   gibt – kein Bot-Schutz, keine Menschen-Prüfung, kein Verstellen als Browser,
3. Nutzungsbedingungen und Impressum verbieten die Nutzung nicht,
4. die Angebote stehen maschinenlesbar im Quelltext der Seite.

**Kaufland, ALDI Nord, ALDI SÜD und Lidl erfüllen alle vier Punkte – ihre
Angebote holt die App direkt und stündlich.** Bei Lidl gilt das nur für die
Artikel, die der Prospekt strukturiert liefert: Getränke und Non-Food. Die
übrigen Ketten scheiden an mindestens einem Punkt aus.

Wichtige Beobachtung: Mehrere Seiten, die zunächst mit HTTP 403 antworteten,
taten das nur, weil der Abruf sich als Browser ausgab. Mit der ehrlichen
Preisfuchs-Kennung antworteten EDEKA, ALDI SÜD und ALDI Nord normal.

---

## Geprüft am 2026-09-12

| Kette | Ergebnis | Grund |
|---|---|---|
| **Kaufland** | ✅ **umgesetzt** | `filiale.kaufland.de/robots.txt` sperrt nur Detailseiten, nicht die Übersicht. Seite antwortet mit HTTP 200. Impressum ohne Nutzungseinschränkung; die „Terms of Use“ betreffen nur Kaufland Card. Angebote strukturiert im Quelltext. |
| **ALDI Nord** | ✅ **umgesetzt** | `robots.txt` sperrt nur einzelne Bereiche, nicht die Angebote. Seite antwortet mit HTTP 200. Impressum (`/kundeninformationen/impressum.html`) ohne Klausel zu Urheberrecht, Vervielfältigung oder automatischem Zugriff. Die 253 Angebote der Woche stehen als JSON in der Seite (Name, Marke, Preis, Grundpreis, Gültigkeit von–bis, Pfand, UVP). Die Seite verweist selbst auf die Vorschau `/angebote-vorschau.html` (282 Angebote der nächsten Woche, gleiches Format) – die lädt die App mit, sonst stünde ALDI Nord sonntags leer da. |
| **ALDI SÜD** | ✅ **umgesetzt** | `robots.txt` sperrt nur `/tools` und Suchanfragen, erlaubt Seitenzahlen (`?page=`) ausdrücklich. Seite antwortet mit HTTP 200. Impressum ohne Einschränkung; die Nutzungsbedingungen gelten für das Kundenkonto. Angebote je Aktionstag (`/angebote/2026-09-11`) im Nuxt-Format der Seite. ALDI SÜD nennt nur „verfügbar seit“, kein Enddatum – die App zeigt es genau so. **Zusätzlich das Dauersortiment mit Regalpreisen** (seit 2026-09-14): 19 Lebensmittel- und Alltagskategorien unter `/produkte/<kategorie>/k/<id>`, zusammen rund 3.000 Artikel, darunter 548 Markenprodukte (Volvic, Haribo, Jacobs, Milka …). Geladen höchstens einmal täglich, Seite für Seite mit 2 Sekunden Pause, gespeichert auf dem Gerät. Beim Zählen am 2026-09-14 blieben nach 19 schnellen Abrufen 14 Anfragen ohne Antwort, ein einzelner Abruf danach kam sofort mit HTTP 200 – deshalb die Pausen. |
| **REWE** | ❌ (erneut geprüft 2026-09-13) | `robots.txt` gibt 17 Kategorieseiten unter `/angebote/nationale-angebote/…` ausdrücklich frei, und sie antworteten der Preisfuchs-Kennung zunächst: 15 Seiten mit zusammen 87 Angeboten samt Preis (weitere 125 Plätze lädt die Seite erst nach). **Aber:** Nach dieser Serie antwortete REWEs Firewall mit HTTP 403 und *„Zeig uns, dass du ein Mensch bist … WAF Challenge Bot protection“* – auch für die Nutzungsbedingungen. REWE stuft solche Abrufe also als Bot ein und sperrt sie. Die App müsste auf jedem Gerät unter dieser Erkennungsschwelle bleiben; das wäre ein Umgehen der Sperre. |
| **EDEKA** | ❌ | `robots.txt` erlaubt die Angebote, das Impressum erlaubt ausdrücklich, Text zu speichern und zu vervielfältigen (nicht Bilder). Die Marktsuche (`/api/marketsearch/markets`) antwortet der Preisfuchs-Kennung. **Aber:** Die Angebote je Markt (`/api/offers?marketId=…`) antworten ihr am 2026-09-13 mit HTTP 403 und der Meldung *„haha! better luck next time 😜“*. EDEKA sperrt Programme dort also absichtlich aus. Durchgekommen wäre nur mit kopierten Browser-Cookies – das hieße, die Sperre zu umgehen. |
| **PENNY** | ❌ | Angebote kommen erst nach Marktauswahl über eine interne Schnittstelle. Die Nutzungsbedingungen der PENNY App verbieten den Zugriff „zum Auslesen oder Speichern von Daten“ – das spricht klar gegen ein Auslesen. |
| **Lidl** | ✅ **teilweise umgesetzt** (geprüft 2026-09-13) | `lidl.de/robots.txt` erlaubt die Prospektübersicht `/c/online-prospekte/…` (gesperrt sind nur `/user-api/` und Such-/ID-Parameter). Der Prospektdienst `endpoints.leaflets.schwarz` hat keine `robots.txt`; beide antworten der Preisfuchs-Kennung. Das Impressum (`/c/impressum/s10005238`) enthält keine Nutzungseinschränkung. Der Prospekt liefert je Woche rund 150–170 Artikel mit Titel, Marke, Preis und Beschreibung – **aber nur Getränke (Wein, Bier, Spirituosen) und Non-Food**. Lebensmittel stehen nur als Bild im Prospekt; die liest die App nicht. |
| **Netto Marken-Discount** | ❌ | Die Angebotsseite antwortet dem Preisfuchs-`User-Agent` mit HTTP 403. |
| **NORMA** | ❌ | Impressum: *„Eine Verwendung von Teilen der Website bedarf einer ausdrücklichen Zustimmung“*. |
| **dm** | ❌ (geprüft 2026-09-13) | `robots.txt` sperrt `/search`. Preise zu einem Produkt ließen sich nur über die Suche finden – die Such-Schnittstelle auf einem anderen Server zu nutzen, hieße, diese Sperre zu umgehen. |
| **tegut** | ❌ (geprüft 2026-09-13) | `robots.txt` erlaubt fast alles, das Impressum schränkt nichts ein, die Angebotsseite antwortet der Preisfuchs-Kennung. **Aber:** Sie enthält keinen einzigen Preis – Angebote gibt es erst nach einer Marktsuche per Formular, und dann als Prospekt. Nichts Maschinenlesbares ohne Nachbau der Seitenlogik. |
| **Globus** | ❌ (geprüft 2026-09-13) | `robots.txt` sperrt nur Shop-Bereiche. Die Prospekte liegen je Markt (`/<markt>/aktuelles-prospekt.php`), ohne Preise im Seitentext. |
| **Rossmann** | ❌ (geprüft 2026-09-13) | `robots.txt` sperrt Suche und alle Adressen mit Parametern und schließt ausdrücklich `ClaudeBot` und `Claude-Web` von der ganzen Seite aus. Nicht weiter abgerufen. |

### Was es sonst gibt – und warum es nicht passt

| Weg | Warum nicht |
|---|---|
| **Kommerzielle Datenanbieter** (z. B. Pepesto) | Kostenpflichtig (widerspricht #51) und nach eigener Aussage selbst aus öffentlichen Shopseiten gewonnen, nicht lizenziert. |
| **Undokumentierte App-Schnittstellen** | Nicht freigegeben, teils per Bot-Schutz gesichert – das zu umgehen kommt nicht in Frage. |
| **Stündlicher Sammel-Server über GitHub Actions** | GitHub erlaubt auf seinen Runnern nur Tätigkeiten für Bau, Test, Bereitstellung und Veröffentlichung des Projekts. Die App lädt deshalb selbst, auf dem Gerät. |
| **supermarktcheck.de** (Nutzer tragen Preise ein, geprüft 2026-09-14) | `robots.txt` erlaubt alles, aber die Nutzungsbedingungen verlangen für jede Vervielfältigung – *„auch auszugsweise“* – die *„vorherige schriftliche Zustimmung“*. Ohne diese Zustimmung nicht nutzbar; Anfrage-Vorlage in `ANFRAGEN-HAENDLER.md`. |
| **supermarktcompare.de** (Preisvergleich, geprüft 2026-09-14) | `robots.txt` sperrt ausdrücklich `ClaudeBot`, `GPTBot` und weitere KI-Crawler; die Startseite antwortet der Preisfuchs-Kennung mit HTTP 410. Die Seite sammelt ihre Preise nach eigener Aussage selbst bei den Ketten. Nicht genutzt. |
| **Apify-Schnittstellen, Daltix** | Kostenpflichtig (je Angebot bzw. Vertrag) und selbst durch Auslesen der Ketten gewonnen. Widerspricht #51. |

**Filialgenaue Preise für alle Produkte, minütlich aktualisiert,** bietet damit
keine frei nutzbare Quelle. Die Ketten veröffentlichen solche Daten nicht, die
Sammelseiten verbieten die Übernahme oder sperren Programme, und die
Datenanbieter kosten Geld. Minütliche Abrufe wären ohnehin nicht sinnvoll:
Regalpreise ändern sich selten, Angebote wöchentlich – und so häufige Abrufe
würden die Schutzsysteme der Seiten auslösen.

---

## So sind die vier Ketten eingebunden

- **Wo:** `Packages/PriceCore/Sources/PriceData/KauflandOffersClient.swift`,
  `AldiOffersClients.swift` und `LidlOffersClient.swift`; angezeigt über `Preisfuchs/Features/MarketOffers/`,
  gesteuert von `Preisfuchs/Services/MarketOffersStore.swift`.
- **Wann:** Beim Öffnen der Startseite, danach stündlich solange die App offen
  ist, beim Zurückkehren in die App und beim Herunterziehen. Kaufland und
  ALDI Nord (je eine Seite) frühestens nach 10 Minuten erneut; ALDI SÜD (bis zu
  rund 20 Seiten) höchstens einmal pro Stunde.
- **Nur eingeschaltete Ketten:** Wer eine Kette in den Einstellungen abwählt,
  lädt ihre Seite auch nicht.
- **Was:** Titel, Marke, Preis, Vergleichspreis (mit Bezeichnung wie „UVP“),
  Rabatt, Einheit, Grundpreis, Pfand, Gültigkeit. Kaufland-Card-Preise werden
  **getrennt** gekennzeichnet und nie als normaler Preis ausgegeben.
- **Zuordnung zu Produkten:** Die Angebote tragen keinen Barcode. Auf der
  Produktseite erscheint ein Angebot deshalb nur, wenn `OfferMatcher` (in
  `PriceCore`) **alle** Punkte bestätigt: gleiche Marke, gleicher Artikelname
  (oder „versch. Sorten“ mit passendem Namen), kein widersprechendes
  Sortenwort, Produktmenge innerhalb der Packungsangabe. Im Zweifel keine
  Zuordnung. Die Zeile nennt Quelle und Gültigkeit und sagt dazu, wenn das
  Angebot nur über „versch. Sorten“ passt.
- **Was nicht:** Keine Produktbilder aus den Prospekten (Rechte bei den
  Ketten). Kein erfundenes Enddatum bei ALDI SÜD.
- **Ehrlichkeit:** Alle drei Seiten zeigen eine Standardauswahl ohne gewählte
  Filiale. Die App sagt dazu, dass einzelne Märkte abweichen können, und nennt
  Quelle und Abrufzeit je Kette.
- **Datenschutz:** An die Ketten geht nur ein gewöhnlicher Seitenabruf mit
  Preisfuchs-Kennung – kein Standort, keine Kennung des Nutzers.
- **Wenn eine Kette ihre Seite ändert:** Der Parser meldet einen Fehler statt
  einer leeren Liste; Tests sichern das ab. Fällt eine Kette aus, bleiben die
  anderen sichtbar.

## Die übrigen Ketten – und was die App stattdessen zeigt

Für REWE, EDEKA, PENNY, Netto und NORMA – und für Lebensmittel bei Lidl – gibt
es keinen erlaubten automatischen Abruf. Die Produktseite zeigt sie trotzdem, im Bereich
**„Preise nach Supermarkt“** – jede eingeschaltete Kette in einer Zeile:

1. **Angebot direkt von der Kette** (Kaufland, ALDI Nord, ALDI SÜD, Lidl), wenn eines
   streng zum Produkt passt;
2. sonst der **günstigste aktuelle Preis aus Open Prices** für diese Kette –
   bevorzugt aus der Umgebung, sonst aus ganz Deutschland, immer mit Ort und
   Alter. Ein Preis aus einer über 25 km entfernten Filiale steht als
   „Preis aus <Ort>“ da, mit dem Zusatz „Preis dort nicht belegt“ an der
   nächsten Filiale – und zählt nie als günstigster Supermarkt;
3. sonst ein älterer Preis, als „möglicherweise veraltet“ gekennzeichnet;
4. sonst „Noch kein Preis bekannt“ und der Link zum offiziellen Prospekt.

Dazu die **nächste Filiale** der Kette (OpenStreetMap) mit Entfernung und
Route. Oben steht der **günstigste Supermarkt** unter allen aktuellen Preisen.
Wer im Markt einen Preis sieht, trägt ihn über „Preis beitragen“ ein – danach
steht er allen zur Verfügung.

Die Startseite verlinkt die offiziellen Angebotsseiten zusätzlich unter
„Prospekte der Märkte“.

Nicht eingebunden: EDEKAs Angebote je Markt (`/api/offers`). Die Schnittstelle
sperrt Programme ausdrücklich aus (HTTP 403, siehe Tabelle); eine Umgehung
kommt nicht in Frage.

Für vollständige, filialgenaue Händlerpreise bräuchte es eine **Vereinbarung
mit den Ketten** (Datenlizenz) – in der Regel nicht kostenlos. Kostenlos wächst
der Datenbestand über **Open Prices**: Jeder Preis, der in der App über „Preis
beitragen“ eingetragen wird, steht danach allen zur Verfügung.

## Quellen

- `robots.txt` von REWE, EDEKA, Lidl, ALDI SÜD, ALDI Nord, PENNY, NORMA und
  `filiale.kaufland.de`; Impressum von Kaufland, EDEKA, Lidl, ALDI SÜD,
  ALDI Nord, PENNY, NORMA; Nutzungsbedingungen von EDEKA und ALDI SÜD;
  Angebotsseiten aller neun Ketten – abgerufen 2026-09-12 mit Preisfuchs-Kennung
- [PENNY App – Nutzungsbedingungen](https://www.penny.de/penny-app-nutzungsbedingungen)
- [NORMA – Impressum](https://www.norma-online.de/de/impressum)
- [EDEKA – Impressum](https://www.edeka.de/impressum/)
- [ALDI Nord – Impressum](https://www.aldi-nord.de/kundeninformationen/impressum.html)
- [ALDI SÜD – Impressum](https://www.aldi-sued.de/unternehmen/impressum)
- [Kaufland – Terms of Use (Kaufland Card)](https://content.kaufland.com/de/de/ssc12/terms_of_use.html)
- [Pepesto – Rewe API](https://www.pepesto.com/supermarkets/rewe/)
- [GitHub – Zusatzbedingungen (Actions)](https://docs.github.com/en/site-policy/github-terms/github-terms-for-additional-products-and-features)
