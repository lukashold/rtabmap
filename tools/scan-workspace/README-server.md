# KANTURA selbst hosten

Der Docker-Server liefert die Weboberfläche und speichert auf Wunsch private
Scan-Projekte: `.rtabmeasure.zip` für einzelne Räume oder
`.kantura-building.zip` für mehrere getrennte Räume und Etagen. Die Archive
enthalten Modelle, Texturen, Maße und Fotonotizen. Der optionale separate Worker
verarbeitet Fotos/Video zu Mesh oder Gaussian Splat, Panorama-Fotos zu einer
sphärischen Ansicht und ein Einzelbild zu ausdrücklich generiertem 3D. Er
rekonstruiert keine RTAB-Map-`.db`-Dateien und verbindet keine RoomPlan-Räume
automatisch zu einem Gebäude.

## Start mit Docker Compose

Im Verzeichnis `tools/scan-workspace`:

```sh
cp .env.example .env
docker compose up -d --build
```

Unter PowerShell heißt der Kopierbefehl `Copy-Item .env.example .env`. Anschließend `http://localhost:8090` öffnen. Der Standard bindet nur an den eigenen Computer. Für die reine Modellansicht sind keine Konten und keine OAuth-Registrierungen nötig.

Für die Server-Bibliothek einen zufälligen Zugangsschlüssel erzeugen:

```sh
docker run --rm node:24-alpine node -e "console.log(require('node:crypto').randomBytes(32).toString('hex'))"
```

Den ausgegebenen Wert in `.env` hinter `SERVER_TOKEN=` eintragen. Danach `docker compose up -d` ausführen und denselben Schlüssel im Browser bei der Server-Bibliothek eingeben. Der Schlüssel wird nur im Arbeitsspeicher der Browserseite gehalten; nach einem Neuladen erneut eingeben. Leerer Schlüssel deaktiviert die Bibliothek. Ein aktivierter Server lehnt Schlüssel mit weniger als 32 Zeichen ab.

Die Bibliothek ist ein gemeinsamer privater Projektspeicher für alle Personen mit diesem Schlüssel. Sie hat keine getrennten Benutzerkonten, Rollen oder öffentlichen Freigabelinks. Modellansicht und Tutorials bleiben ohne Schlüssel zugänglich. Ein Export in Google Drive oder OneDrive braucht zusätzlich die jeweiligen öffentlichen OAuth-Client-IDs; siehe die Hauptanleitung.

## Optionale Rekonstruktion: vier Modi

Zuerst `SERVER_TOKEN` wie oben setzen. Docker Compose ab 2.17 und BuildKit werden
für die zusätzlichen Build-Kontexte benötigt. Im Verzeichnis `tools/scan-workspace`:

```sh
docker compose -f compose.yaml -f compose.reconstruction.yaml up -d --build
```

Der zusätzliche Dienst bleibt ohne eigenen öffentlichen Port im Compose-Netz.
Der Webserver leitet ausschließlich erlaubte `/api/reconstruction`-Routen nach
Authentifizierung weiter. Seine interne `RECONSTRUCTION_URL` wird vom Override
gesetzt und darf nur durch den Betreiber konfiguriert werden. Der Browser nutzt
denselben `SERVER_TOKEN`; dieser gewährt allen Berechtigten Zugriff auf sämtliche
Aufträge und ihre freigegebenen Dateien, einschließlich Panorama-Originalen.

| Modus | Eingabe | Ergebnis |
| --- | --- | --- |
| Mesh | Foto-ZIP mit 8–250 Bildern oder unterstütztes MP4/MOV | Echtes COLMAP/OpenMVS-Texturmodell, Maßstab ungeprüft |
| Gaussian Splat | Dieselben Foto-/Videoeingaben | OpenSplat-Ansicht ohne metrische Messoberfläche |
| Panorama | ZIP mit 2–40 überlappenden Drehaufnahmen | 2:1-PNG, Abdeckungsmaske und unverändertes Originalarchiv; keine Tiefe |
| Generiertes 3D | Ein JPEG/PNG bis 20 MiB, freigestelltes Motiv | Optionales TripoSR-Modell mit geschätzten unsichtbaren Flächen; keine Vermessung |

Die letzten beiden Modi sind in der gemeinsamen Warteschlange implementiert.
Die Standardinstallation enthält Panorama, aber **kein KI-Modell**. Für die
bewusste Aktivierung von TripoSR in `.env` setzen:

```text
RECONSTRUCTION_ENABLE_GENERATION=1
```

Danach denselben Compose-Befehl mit `--build` erneut ausführen. Dies setzt das
Build-Argument `ENABLE_GENERATION` (Standard `0`). Der Build lädt etwa 1,68 GB
geprüfte Modellgewichte und installiert zusätzlich eine getrennte CPU-Torch-
Laufzeit. Für die Laufzeit mit etwa 12 GiB Arbeitsspeicher planen; der tatsächliche
Bedarf hängt von Modell und Einstellungen ab. Keine Anfrage lädt Gewichte oder
Code nach. Die Verarbeitung läuft mit den installierten Engines lokal; Uploads
vom Browser an den eigenen Server bleiben ausdrücklich erforderlich.

Das initiale Worker-Image ist **linux/amd64 mit CPU**. Auf einem Apple-Chip läuft
es gegebenenfalls unter Emulation; Linux-Docker nutzt nicht Apples Metal-GPU.
NVIDIA/OpenSplat und natives MPS sind gesonderte, noch hardwareabhängig zu prüfende
Wege. Große C++-/Torch-Builds benötigen erheblich mehr Platz und Zeit als der
reine Webserver. Details: [Worker](../reconstruction/README.md),
[Panorama](../panorama/README.md), [TripoSR](../generation/README.md).

Aufträge durchlaufen `queued`, `running` und `complete`, `failed` oder `cancelled`.
Abbruch beendet den Worker-Prozessbaum. Nur geprüfte vollständige Artefakte aus
einer festen Namensliste werden veröffentlicht; jeder Download ist auf 200 MiB
begrenzt. Eine fertige Datei belegt weder richtige Kamerapositionen noch genaue
Maße. API-Vertrag, modusspezifische Grenzen, Neustartverhalten und Fehlercodes:
[API.md](../reconstruction/API.md).

Das eigene Volume `reconstruction-projects` enthält Originale, Auftragsstände,
Logs und Ergebnisse. Temporäre Arbeitsdaten werden nach beendetem Worker
aufgeräumt; Originale und Auftragsdaten werden nicht automatisch gelöscht.
Sicherung und Aufbewahrung getrennt vom Volume `scan-projects` planen. Es gibt
keine individuellen Konten oder automatische Löschfrist. Die erweiterten
Routen liefern keine beliebigen privaten Logs oder Dateipfade aus.

**Nachweisstand 0.6:** Webtests/Docker-Build und eigenständige echte Offline-Läufe
für Panorama und TripoSR sind bestanden. Der [gemeinsame API-Lauf](https://github.com/lukashold/rtabmap/actions/runs/38210549928)
bestand anschließend alle sieben echten synthetischen Aufträge und 88 Linux-Tests.
Die korrigierte Video-/FFmpeg-Abfrage und getrennte Python-Umgebungen sind enthalten.
Details stehen in [VALIDATION.md](VALIDATION.md). Das ist kein interaktiver
Browser-/iPhone- oder Genauigkeitsnachweis.
Die periodische synthetische Foto-Fixture ergab fehlerhafte Kamerageometrie und
ist trotz erzeugter Dateien nicht für Messungen freigegeben.

Die Abhängigkeiten haben verschiedene Lizenzen. Insbesondere AGPL-Engines und
mitgelieferte HEIC-Codecs machen das Gesamtimage nicht zu einem reinen BSD-Paket.
Vor eigener Verteilung die jeweiligen [Drittlizenzen](../reconstruction/THIRD-PARTY.md)
sowie die verlinkten Panorama-/Generierungsbedingungen prüfen. Daraus folgt keine
Freigabe der nativen App für den App Store.

## Projekte und Datensicherung

Jedes Speichern legt eine neue unveränderliche Version mit eigener zufälliger ID an. Vorhandene Versionen werden nicht überschrieben. Pro Archiv sind maximal 200 MiB erlaubt; die Browseransicht begrenzt zusätzlich die entpackte Größe. Große Scans vor dem Export in RTAB-Map verkleinern. Jeweils ein Upload pro Server wird angenommen. Ein zweiter gleichzeitiger Upload meldet `busy`; anschließend erneut speichern.

Compose speichert alle Archive und Metadaten im benannten Volume `scan-projects`, unter `/data` im Container. `docker compose down` behält dieses Volume. `docker compose down -v` löscht es einschließlich aller Projekte. Das Volume regelmäßig mit den Sicherungswerkzeugen des Docker-Hosts sichern. Es gibt keine automatische Aufbewahrungsfrist oder Gesamtspeicherquote; den verfügbaren Speicher auf dem Host überwachen.

Der Prozess läuft als unprivilegierter Benutzer `node` (UID 1000). Das Container-Dateisystem ist schreibgeschützt, nur das Datenvolume ist beschreibbar. Docker initialisiert ein neues benanntes Volume mit den passenden Besitzrechten. Wer statt des benannten Volumes einen Hostordner bindet, muss ihn für UID 1000 lesbar und beschreibbar einrichten. Bei fehlenden Schreibrechten startet der Server nicht.

## Auf anderen Geräten oder im Internet öffnen

Für einen Heimserver die Seite hinter einem HTTPS-Reverse-Proxy mit eigenem Domainnamen betreiben. Den Proxy auf Port 8090 des Hosts weiterleiten und die Uploadgrenze auf mindestens 210 MiB einstellen. Für langsame Verbindungen passende Proxy-Zeitlimits setzen; der Node-Server begrenzt eine Anfrage auf zwei Minuten. Die private Bibliothek nutzt einen Bearer-Schlüssel und sollte außerhalb des eigenen Computers ausschließlich über HTTPS aufgerufen werden. Keine Schlüssel in URLs, Links oder öffentlich sichtbaren Konfigurationsdateien verwenden.

Der Proxy braucht WebSocket-Unterstützung nicht. Die OAuth-Rücksprungadresse für Microsoft ist `https://deine-domain.example/auth.html`, bei Google wird die genaue HTTPS-Origin registriert. Für einen lokalen Test gelten stattdessen `http://localhost:8090/auth.html` bzw. `http://localhost:8090`. Der integrierte Server setzt eine mit Google Identity Services auf localhost kompatible Referrer-Policy.

## Ohne Docker

Nach dem Bauen der Weboberfläche genügt Node.js 24:

```sh
DATA_DIR=/srv/kantura-projects SERVER_TOKEN=<zufälliger-schlüssel> node server.mjs
```

PowerShell:

```powershell
$env:DATA_DIR = 'C:\Kantura\projects'
$env:SERVER_TOKEN = '<zufälliger-schlüssel>'
node server.mjs
```

`DATA_DIR` muss außerhalb des öffentlichen `dist`-Verzeichnisses liegen. Ohne `DATA_DIR` und `SERVER_TOKEN` liefert der Server nur die Weboberfläche aus. Der Standard ist `127.0.0.1:4173`; `HOST` und `PORT` können angepasst werden. Die produktive Webserver-Stufe braucht weder npm-Abhängigkeiten noch externe Datenbanken; der optionale Rekonstruktionsdienst hat eigene Engine-/Python-Abhängigkeiten.

## HTTP-Schnittstelle

Alle `/api/projects`-Anfragen benötigen `Authorization: Bearer <SERVER_TOKEN>`. Es werden keine Cookies gesetzt und keine Cross-Origin-Anfragen freigegeben.

| Anfrage | Ergebnis |
| --- | --- |
| `GET /config.json` | Öffentliche OAuth-Client-IDs, `serverEnabled` und `reconstructionEnabled`; niemals Server-Schlüssel, interne Worker-URL oder Datenpfad |
| `GET /api/projects` | `{ "projects": [{ "id", "name", "createdAt", "size" }] }`, neueste zuerst |
| `POST /api/projects?name=Mein%20Raum` | Raw ZIP, `Content-Type: application/zip`; Status 201 und `{ "project": { ... } }` |
| `GET /api/projects/<id>` | ZIP-Download des gespeicherten Projekts |
| `GET /health` | `ok`, für Container-Gesundheitsprüfungen |

Projektnamen dürfen maximal 120 Zeichen haben und keine Schrägstriche oder Steuerzeichen enthalten. Archive werden gestreamt und in einem privaten Zwischenverzeichnis geschrieben. Erst nach Abschluss wird die vollständige Version atomar sichtbar. Fehlerhafte oder abgebrochene Uploads werden aufgeräumt. Bei einem harten Prozessabbruch kann ein unsichtbares `.upload-*`-Verzeichnis zurückbleiben; es darf nach Stoppen des Containers aus dem Datenvolume entfernt werden.

Der Server prüft das ZIP-Dateiformat am Anfang und Ende, entpackt das Archiv jedoch nicht. Die Browseransicht prüft beim Öffnen Manifest, Dateipfade, Formate und entpackte Größe. Die Server-Bibliothek ist kein Virenscanner. Fehlerantworten haben die Form `{ "error": "unauthorized" }`; relevante Codes sind `disabled`, `unauthorized`, `invalid_name`, `invalid_archive`, `too_large`, `busy`, `not_found`, `method_not_allowed` und `storage_error`.

Die Tests in `test/server.test.mjs` prüfen mit echten HTTP-Anfragen Berechtigungen, Speicher-Roundtrip, Neustart, ungültige Archive, Größenlimit einschließlich gestreamter Anfragen, Traversal und die Trennung privater Daten vom öffentlichen Verzeichnis.
