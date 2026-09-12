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

**Kaufland, ALDI Nord und ALDI SÜD erfüllen alle vier Punkte – ihre Angebote
holt die App direkt und stündlich.** Die übrigen Ketten scheiden an mindestens
einem Punkt aus.

Wichtige Beobachtung: Mehrere Seiten, die zunächst mit HTTP 403 antworteten,
taten das nur, weil der Abruf sich als Browser ausgab. Mit der ehrlichen
Preisfuchs-Kennung antworteten EDEKA, ALDI SÜD und ALDI Nord normal.

---

## Geprüft am 2026-09-12

| Kette | Ergebnis | Grund |
|---|---|---|
| **Kaufland** | ✅ **umgesetzt** | `filiale.kaufland.de/robots.txt` sperrt nur Detailseiten, nicht die Übersicht. Seite antwortet mit HTTP 200. Impressum ohne Nutzungseinschränkung; die „Terms of Use“ betreffen nur Kaufland Card. Angebote strukturiert im Quelltext. |
| **ALDI Nord** | ✅ **umgesetzt** | `robots.txt` sperrt nur einzelne Bereiche, nicht die Angebote. Seite antwortet mit HTTP 200. Impressum (`/kundeninformationen/impressum.html`) ohne Klausel zu Urheberrecht, Vervielfältigung oder automatischem Zugriff. Die 253 Angebote der Woche stehen als JSON in der Seite (Name, Marke, Preis, Grundpreis, Gültigkeit von–bis, Pfand, UVP). Die Seite verweist selbst auf die Vorschau `/angebote-vorschau.html` (282 Angebote der nächsten Woche, gleiches Format) – die lädt die App mit, sonst stünde ALDI Nord sonntags leer da. |
| **ALDI SÜD** | ✅ **umgesetzt** | `robots.txt` sperrt nur `/tools` und Suchanfragen, erlaubt Seitenzahlen (`?page=`) ausdrücklich. Seite antwortet mit HTTP 200. Impressum ohne Einschränkung; die Nutzungsbedingungen gelten für das Kundenkonto. Angebote je Aktionstag (`/angebote/2026-09-11`) im Nuxt-Format der Seite. ALDI SÜD nennt nur „verfügbar seit“, kein Enddatum – die App zeigt es genau so. |
| **REWE** | ❌ | Die Nutzungsbedingungen lassen sich nur nach einer Menschen-Prüfung („Zeig uns, dass du ein Mensch bist“) lesen – die wird nicht umgangen. Die Angebotsseite liefert ohne gewählten Markt nur 10 Angebote; der Rest kommt erst nach Marktauswahl. |
| **EDEKA** | ❌ | `robots.txt` erlaubt die Angebote, das Impressum erlaubt ausdrücklich, Text zu speichern und zu vervielfältigen (nicht Bilder), die Nutzungsbedingungen betreffen App, PAYBACK und Bezahlen. **Aber:** Die Angebotsseite enthält keine Angebotsdaten; sie kommen über eine Live-Verbindung je Markt. Die nachzubauen wäre Reverse Engineering und bräche bei jeder Änderung. |
| **PENNY** | ❌ | Angebote kommen erst nach Marktauswahl über eine interne Schnittstelle. Die Nutzungsbedingungen der PENNY App verbieten den Zugriff „zum Auslesen oder Speichern von Daten“ – das spricht klar gegen ein Auslesen. |
| **Lidl** | ❌ | Lebensmittel-Angebote gibt es nur als Prospekt (Bilder). `robots.txt` sperrt `/user-api/` und Such-/ID-Parameter. |
| **Netto Marken-Discount** | ❌ | Die Angebotsseite antwortet dem Preisfuchs-`User-Agent` mit HTTP 403. |
| **NORMA** | ❌ | Impressum: *„Eine Verwendung von Teilen der Website bedarf einer ausdrücklichen Zustimmung“*. |

### Was es sonst gibt – und warum es nicht passt

| Weg | Warum nicht |
|---|---|
| **Kommerzielle Datenanbieter** (z. B. Pepesto) | Kostenpflichtig (widerspricht #51) und nach eigener Aussage selbst aus öffentlichen Shopseiten gewonnen, nicht lizenziert. |
| **Undokumentierte App-Schnittstellen** | Nicht freigegeben, teils per Bot-Schutz gesichert – das zu umgehen kommt nicht in Frage. |
| **Stündlicher Sammel-Server über GitHub Actions** | GitHub erlaubt auf seinen Runnern nur Tätigkeiten für Bau, Test, Bereitstellung und Veröffentlichung des Projekts. Die App lädt deshalb selbst, auf dem Gerät. |

---

## So sind die drei Ketten eingebunden

- **Wo:** `Packages/PriceCore/Sources/PriceData/KauflandOffersClient.swift`
  und `AldiOffersClients.swift`; angezeigt über `Preisfuchs/Features/MarketOffers/`,
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
- **Was nicht:** Keine Produktbilder aus den Prospekten (Rechte bei den
  Ketten). Keine Verknüpfung mit Produkten aus Open Food Facts – die Angebote
  tragen keinen Barcode, eine Zuordnung über den Namen wäre geraten. Kein
  erfundenes Enddatum bei ALDI SÜD.
- **Ehrlichkeit:** Alle drei Seiten zeigen eine Standardauswahl ohne gewählte
  Filiale. Die App sagt dazu, dass einzelne Märkte abweichen können, und nennt
  Quelle und Abrufzeit je Kette.
- **Datenschutz:** An die Ketten geht nur ein gewöhnlicher Seitenabruf mit
  Preisfuchs-Kennung – kein Standort, keine Kennung des Nutzers.
- **Wenn eine Kette ihre Seite ändert:** Der Parser meldet einen Fehler statt
  einer leeren Liste; Tests sichern das ab. Fällt eine Kette aus, bleiben die
  anderen sichtbar.

## Die übrigen Ketten

Für REWE, EDEKA, Lidl, PENNY, Netto und NORMA verlinkt die Startseite unter
„Prospekte der Märkte“ die offizielle Angebotsseite.

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
