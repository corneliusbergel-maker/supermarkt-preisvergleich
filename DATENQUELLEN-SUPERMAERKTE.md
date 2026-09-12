# Preise direkt von den Supermärkten – Prüfung

> Frage vom 2026-09-12: Kann Preisfuchs die Preise und Angebote von Edeka,
> Lidl, REWE & Co. direkt bei den Märkten abholen und stündlich aktualisieren,
> statt über Open Prices?
>
> Maßstab ist Anforderung #22: *„Nicht einfach Webseiten scrapen, wenn dies
> gegen deren Nutzungsbedingungen verstößt. Prüfe die technische und
> rechtliche Machbarkeit.“* Und #39: Geht etwas nicht, wird keine Lösung
> erfunden, sondern erklärt, was möglich ist.
>
> Das hier ist eine technische Bestandsaufnahme, **keine Rechtsberatung**.

---

## Ergebnis in einem Satz

**Keine deutsche Supermarktkette bietet eine offizielle Schnittstelle für
Preise oder Angebote an. Mehrere untersagen oder blockieren automatische
Abrufe.** Ein automatischer Abgleich direkt bei den Märkten ist deshalb im
Rahmen dieses Projekts nicht zulässig umsetzbar – weder stündlich noch
täglich.

---

## Geprüft am 2026-09-12

| Kette | Offizielle API | Beobachtung | Einschätzung |
|---|---|---|---|
| **REWE** | keine | `robots.txt` sperrt `/restservices/` (die interne Schnittstelle der Website); die öffentlichen Seiten unter `/angebote/nationale-angebote/…` sind freigegeben. Die Nutzungsbedingungen-Seite blockt automatische Abrufe mit HTTP 403. Laut Drittanbieter Pepesto: „Rewe does not offer a public developer API.“ | Interne API gesperrt; Seiten auslesen hieße HTML-Scraping gegen einen Bot-Schutz. **Nicht umgesetzt.** |
| **EDEKA** | keine | `robots.txt` und Nutzungsbedingungen antworten automatischen Abrufen mit HTTP 403 (Bot-Schutz). Die Nutzungsbedingungen nennen laut Suchauszug den Schutz vor „missbräuchlicher automatisierter Ausspähung“. Ein inoffizielles „Edeka-API“-Projekt auf GitHub ist nachgebaut, ohne Erlaubnis. | **Nicht umgesetzt.** |
| **Lidl** | keine | `robots.txt` sperrt `/user-api/` und Such-/ID-Parameter. Registrierung und Login sind per reCAPTCHA gegen Bots geschützt. | **Nicht umgesetzt.** |
| **Kaufland** | keine | `www.kaufland.de/robots.txt` → HTTP 403. `filiale.kaufland.de/robots.txt` sperrt die Angebots-Detailseiten (`/angebote/aktuell/uebersicht/detail`, `/angebote/naechste-woche/detail`). | Angebotsdetails ausdrücklich gesperrt. **Nicht umgesetzt.** |
| **ALDI SÜD** | keine | `robots.txt` → HTTP 403 (Bot-Schutz). | **Nicht umgesetzt.** |
| **ALDI Nord** | keine | `robots.txt` sperrt einzelne Bereiche; keine Schnittstelle. | Nur HTML-Scraping möglich. **Nicht umgesetzt.** |
| **PENNY** | keine | `robots.txt` erlaubt alles. Die Nutzungsbedingungen der PENNY App verbieten aber gewerbliche Nutzung der Inhalte und den Zugriff „zum Auslesen oder Speichern von Daten“. | **Nicht umgesetzt.** |
| **Netto Marken-Discount** | keine | `robots.txt` → HTTP 403 (Bot-Schutz). | **Nicht umgesetzt.** |
| **NORMA** | keine | `robots.txt` sperrt `/ws/` (Webservice). | **Nicht umgesetzt.** |

### Was es sonst gibt – und warum es nicht passt

| Weg | Warum nicht |
|---|---|
| **Kommerzielle Datenanbieter** (z. B. Pepesto) | Kostenpflichtig (widerspricht #51) und nach eigener Aussage selbst aus öffentlichen Shopseiten gewonnen, nicht lizenziert. |
| **Undokumentierte App-Schnittstellen** (per Reverse Engineering) | Nicht freigegeben, teils gegen Nutzungsbedingungen, können jederzeit abgeschaltet werden. |
| **Stündlicher Abruf über GitHub Actions** | GitHub erlaubt Actions nur für Bau, Test und Veröffentlichung des Projekts – nicht als Dauerbetrieb eines Datensammlers. Das Problem der Nutzungsbedingungen der Märkte bliebe ohnehin. |
| **„Heisse Preise“** | Open-Source-Vorbild, erfasst laut README aber nur österreichische Ketten. |

---

## Was stattdessen umgesetzt ist

1. **Prospekte der Märkte (Startseite):** Für jede eingeschaltete Kette ein Link
   auf ihre offizielle Angebotsseite. Alle neun Adressen wurden am 2026-09-12
   im Browser geöffnet (siehe `Preisfuchs/Services/RetailerOffersPages.swift`).
   Die Angebote sind damit einen Tipp entfernt und immer so aktuell, wie die
   Kette sie veröffentlicht – ohne dass Preisfuchs etwas ausliest.
2. **Stündliche Aktualisierung:** Startseite (Favoriten, Deals) und Favoriten
   laden stündlich neu, solange die App offen ist, und beim Zurückkehren in die
   App, wenn der letzte Stand älter als eine Stunde ist. Die Hintergrundprüfung
   der Preisalarme wünscht sich ebenfalls einen Stundentakt; wann sie wirklich
   läuft, entscheidet iOS.
3. **Aktionspreise aus Open Prices** stehen weiter unter „Deine besten Deals“ –
   mit Beleg, ohne Erfindungen.

## Was es für echte Händlerpreise bräuchte

- **Eine Vereinbarung mit den Ketten** (Datenlizenz oder Partnerprogramm). Das
  ist der einzige saubere Weg zu vollständigen, aktuellen Preisen – und in der
  Regel nicht kostenlos.
- **Mehr Beiträge zu Open Prices:** Jeder Preis, der in der App über „Preis
  beitragen“ mit Foto eingetragen wird, steht danach allen zur Verfügung.

## Quellen

- REWE `robots.txt`, Lidl `robots.txt`, ALDI Nord `robots.txt`,
  PENNY `robots.txt`, NORMA `robots.txt`, `filiale.kaufland.de/robots.txt` –
  abgerufen 2026-09-12
- [Pepesto – Rewe API](https://www.pepesto.com/supermarkets/rewe/)
- [PENNY App – Nutzungsbedingungen](https://www.penny.de/penny-app-nutzungsbedingungen)
- [EDEKA – Nutzungsbedingungen](https://www.edeka.de/services/nutzungsbedingungen/)
- [Lidl – Datenschutz (reCAPTCHA)](https://www.lidl.de/c/datenschutz/s10007528)
- [VinceDerPrince/Edeka-API](https://github.com/VinceDerPrince/Edeka-API)
- [badlogic/heissepreise](https://github.com/badlogic/heissepreise)
- [GitHub – Zusatzbedingungen für Actions](https://docs.github.com/en/site-policy/github-terms/github-terms-for-additional-products-and-features#actions)
