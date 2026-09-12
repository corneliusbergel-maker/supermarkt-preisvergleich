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
   gibt (kein Bot-Schutz, kein Verstellen als Browser),
3. Nutzungsbedingungen und Impressum verbieten die Nutzung nicht,
4. die Angebote stehen maschinenlesbar im Quelltext.

**Nur Kaufland erfüllt alle vier Punkte – die Kaufland-Wochenangebote holt die
App deshalb direkt und stündlich.** Alle anderen Ketten scheiden an mindestens
einem Punkt aus.

---

## Geprüft am 2026-09-12

| Kette | Ergebnis | Grund |
|---|---|---|
| **Kaufland** | ✅ **umgesetzt** | `filiale.kaufland.de/robots.txt` sperrt nur Detailseiten, nicht die Übersicht `/angebote/uebersicht.html`. Die Seite antwortet dem Preisfuchs-`User-Agent` mit HTTP 200. Das Impressum enthält keine Nutzungseinschränkung; die gefundenen „Terms of Use“ betreffen nur das Kundenprogramm Kaufland Card. Die Angebote stehen als strukturierte Daten im Quelltext (Titel, Preis, alter Preis, Rabatt, Einheit, Grundpreis, Gültigkeit, Kartenpreis). |
| **REWE** | ❌ | Die Nutzungsbedingungen-Seite antwortet automatischen Abrufen mit einer „WAF Challenge Bot protection“. `robots.txt` sperrt die interne Schnittstelle `/restservices/`. |
| **EDEKA** | ❌ | Das Impressum erlaubt, Text zu speichern und zu vervielfältigen, verbietet es aber für Bilder. Die Angebote lädt die Seite erst nachträglich über eine eigene Schnittstelle je Markt; `robots.txt` und Nutzungsbedingungen sind per Bot-Schutz gesperrt (HTTP 403), sodass die Erlaubnis nicht prüfbar ist. |
| **Lidl** | ❌ | Die Angebote gibt es als Prospekt (Bilder), nicht als Einzelpreise. `robots.txt` sperrt `/user-api/` und Such-/ID-Parameter. |
| **ALDI SÜD** | ❌ | `robots.txt` per Bot-Schutz gesperrt (HTTP 403); die „Nutzungsbedingungen“ gelten nur für das Kundenkonto. Erlaubnis nicht prüfbar. |
| **ALDI Nord** | ❌ | Preise stehen nicht im Quelltext, sondern werden per JavaScript nachgeladen. |
| **PENNY** | ❌ | Preise werden per JavaScript nachgeladen. Die Nutzungsbedingungen der PENNY App verbieten den Zugriff „zum Auslesen oder Speichern von Daten“. |
| **Netto Marken-Discount** | ❌ | Die Angebotsseite antwortet dem Preisfuchs-`User-Agent` mit HTTP 403. |
| **NORMA** | ❌ | Impressum: *„Eine Verwendung von Teilen der Website bedarf einer ausdrücklichen Zustimmung“*. |

### Was es sonst gibt – und warum es nicht passt

| Weg | Warum nicht |
|---|---|
| **Kommerzielle Datenanbieter** (z. B. Pepesto) | Kostenpflichtig (widerspricht #51) und nach eigener Aussage selbst aus öffentlichen Shopseiten gewonnen, nicht lizenziert. |
| **Undokumentierte App-Schnittstellen** | Nicht freigegeben, teils per Bot-Schutz gesichert – das zu umgehen kommt nicht in Frage. |
| **Stündlicher Sammel-Server über GitHub Actions** | GitHub erlaubt auf seinen Runnern nur Tätigkeiten für Bau, Test, Bereitstellung und Veröffentlichung des Projekts. Die App lädt deshalb selbst, auf dem Gerät. |

---

## So ist Kaufland eingebunden

- **Wo:** `Packages/PriceCore/Sources/PriceData/KauflandOffersClient.swift`,
  angezeigt über `Preisfuchs/Features/MarketOffers/`.
- **Wann:** Beim Öffnen der Startseite und danach stündlich, solange die App
  offen ist; beim Zurückkehren, wenn der Stand älter als eine Stunde ist; beim
  Herunterziehen. Nie öfter als alle 10 Minuten.
- **Was:** Titel, Preis, alter Preis, Rabatt, Einheit, Grundpreis,
  Gültigkeitszeitraum. Kaufland-Card-Preise werden **getrennt** gekennzeichnet
  („Mit Kaufland Card …“, „nur mit Kaufland Card“) und nie als normaler Preis
  ausgegeben.
- **Was nicht:** Keine Produktbilder aus dem Prospekt (Rechte bei Kaufland).
  Keine Verknüpfung mit Produkten aus Open Food Facts – die Angebote tragen
  keinen Barcode, eine Zuordnung über den Namen wäre geraten.
- **Ehrlichkeit:** Die Seite zeigt die Standardauswahl von kaufland.de ohne
  gewählte Filiale. Die App sagt dazu, dass einzelne Märkte abweichen können,
  und nennt Quelle und Abrufzeit.
- **Datenschutz:** An Kaufland geht nur ein gewöhnlicher Seitenabruf mit
  Preisfuchs-Kennung – kein Standort, keine Kennung des Nutzers.
- **Wenn Kaufland die Seite ändert:** Der Parser meldet einen Fehler statt
  einer leeren Liste; ein Test sichert das ab.

## Die übrigen Ketten

Für REWE, EDEKA, Lidl, ALDI SÜD, ALDI Nord, PENNY, Netto und NORMA verlinkt die
Startseite unter „Prospekte der Märkte“ die offizielle Angebotsseite. Die
Angebote sind dort einen Tipp entfernt und immer so aktuell, wie die Kette sie
veröffentlicht.

Für echte, vollständige Händlerpreise bräuchte es eine **Vereinbarung mit den
Ketten** (Datenlizenz) – in der Regel nicht kostenlos. Kostenlos wächst der
Datenbestand über **Open Prices**: Jeder Preis, der in der App über „Preis
beitragen“ eingetragen wird, steht danach allen zur Verfügung.

## Quellen

- `robots.txt` von REWE, Lidl, ALDI Nord, PENNY, NORMA und
  `filiale.kaufland.de`; Impressum von Kaufland, EDEKA, Lidl, PENNY, NORMA;
  Angebotsseiten aller neun Ketten – abgerufen 2026-09-12
- [PENNY App – Nutzungsbedingungen](https://www.penny.de/penny-app-nutzungsbedingungen)
- [NORMA – Impressum](https://www.norma-online.de/de/impressum)
- [EDEKA – Impressum](https://www.edeka.de/impressum/)
- [Kaufland – Terms of Use (Kaufland Card)](https://content.kaufland.com/de/de/ssc12/terms_of_use.html)
- [Pepesto – Rewe API](https://www.pepesto.com/supermarkets/rewe/)
- [GitHub – Zusatzbedingungen (Actions)](https://docs.github.com/en/site-policy/github-terms/github-terms-for-additional-products-and-features)
