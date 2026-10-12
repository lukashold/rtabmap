# KANTURA: Räume und Tore vermessen

KANTURA ist ein eigenständiger Entwicklungszweig auf Basis von RTAB-Map; der Quellstand ist **0.6.0, Build 4**. Der Messablauf ist **Scannen → Prüfen → Messen → Speichern**. Für einfache Innenraummaße beginnst du mit **Raumplan**. Für ein texturiertes Modell oder ein Tor verwendest du den **LiDAR-Ablauf**. Weitere Foto-, Video- und Panorama-Modi sammeln Originale für die Serververarbeitung; ein KI-Modell aus einem Einzelbild ist kein vermessbarer Scan.

Die geführte Oberfläche, Textanleitungen und der Desktop-Arbeitsbereich unterstützen 15 Sprachen: Deutsch, Englisch, Französisch, Spanisch, Italienisch, vereinfachtes Chinesisch, Portugiesisch, Arabisch, Hindi, Bengalisch, Russisch, Japanisch, Koreanisch, Indonesisch und Türkisch. Die geerbten RTAB-Map-Expertenmenüs bleiben überwiegend Englisch. Das siebenteilige Texttutorial erklärt ausdrücklich den LiDAR-Ablauf; RoomPlan hat einen eigenen geführten Ablauf.

Die einfache Reihenfolge orientiert sich am [geführten Raumscan von Metaroom](https://help.amrax.ai/sample-page/scanning-with-metaroom-app/how-to-scan-a-single-room-with-the-metaroom-app/). Oberfläche, Texte und Symbole sind eigene Umsetzungen. Dieses Projekt gehört weder zu Metaroom noch zu Polycam.

## Was du brauchst

- Ein iPhone mit LiDAR, beispielsweise dein iPhone 17 Pro, und etwas gleichmäßiges Licht.
- Ein Maßband für mehrere Kontrollmaße. Ein sauberes 3D-Bild allein bestätigt keine Messgenauigkeit.
- Für die unveränderte veröffentlichte App: [RTAB-Map im App Store](https://apps.apple.com/app/rtab-map-3d-lidar-scanner/id1564774365).
- Für diese Entwicklungsversion: ein Mac mit passendem Xcode, dein Apple-Konto und das iPhone zum Signieren und Testen. Windows kann den Desktop-Arbeitsbereich ausführen; die native App wird mit Xcode gebaut. Details: [eigene Veröffentlichung und Installation](../../docs/APP-STORE-RELEASE.md).

Der App-Store-Link installiert die offizielle Upstream-App. Unsere Ergänzungen erscheinen dort erst nach einer Übernahme und einer neuen Veröffentlichung. Ein unsigniertes CI-IPA lässt sich nicht direkt installieren.

## Raumplan: Innenräume und mehrere Etagen

1. **Raumplan** öffnen und Haus/Projekt, Etage und Raum benennen. Dieser Ablauf setzt iOS 17 oder neuer und ein von Apple unterstütztes LiDAR-Gerät voraus; die App prüft die Unterstützung.
2. Den Hinweisen der Raumaufnahme folgen und Wände, Türen, Fenster und Öffnungen aus passenden Blickwinkeln erfassen. Mit **Fertig** beenden und das Ergebnis prüfen.
3. Bei Wänden und Öffnungen sind **Breite** und **Höhe** beschriftet. Eine Bodenfläche wird nur aus einer vorhandenen erkannten Kontur berechnet; eine fehlende Kontur wird nicht durch ein umschließendes Rechteck ersetzt. Die Erkennungssicherheit ist keine bestätigte Messgenauigkeit. Mehrere Strecken mit einem Maßband kontrollieren.
4. Raum lokal speichern und USDZ sowie `.kantura-room.json` über Dateien exportieren. Die JSON lässt sich im Desktop-Arbeitsbereich als schematischer Raumplan öffnen. In **Meine Räume** sind gespeicherte Räume nach ihren Haus-/Etagen-/Raumnamen wieder auffindbar und erneut exportierbar.

Weitere Räume nacheinander aufnehmen. Die Etagenangabe organisiert unabhängige Räume; sie verbindet weder Treppenhäuser noch Raumkoordinaten automatisch. Ein RoomPlan-Raum und ein texturierter LiDAR-Scan sind getrennte Aufnahmen. Ihre Texturen und Positionen werden nicht automatisch aufeinander ausgerichtet.

## LiDAR 1: Scan aufnehmen

1. Eine markante Referenzstrecke mit dem Maßband messen und notieren, zum Beispiel den Abstand zwischen zwei Torpfosten.
2. Eine neue Aufnahme starten. **LiDAR Mode** aktivieren, normales **Mapping** verwenden, auf die Kamera warten und **Record** drücken.
3. Boden, Ecken und Wände langsam mit überlappenden Ansichten erfassen. Zum Startpunkt zurückkehren. Bei einem Tor nach Möglichkeit beide Seiten durch einen zusammenhängenden Weg aufnehmen.
4. Stoppen und die `.db` als Original speichern. Die Datenbank ermöglicht eine spätere Rekonstruktion; der Browser liest sie nicht direkt.

LiDAR liefert räumliche Tiefe, die Kamera liefert Bilder und hilft bei der Orientierung. Ein texturiertes Modell verbindet beides. Es handelt sich nicht um zwei unabhängig zu startende Scans. Bewegte Tore, spiegelnde Flächen, dünne Stäbe und starkes Sonnenlicht können problematisch bleiben.

## LiDAR 2: Modell prüfen und exportieren

**Assemble → Optimized mesh → Textured Mesh** wählen. Auf doppelte Wände, Lücken, überbrückte Öffnungen und fehlende schmale Teile achten. Das Modell als **OBJ-ZIP mit MTL und Bildern** exportieren; alle Dateien zusammen lassen, damit die Texturen erhalten bleiben.

Über **In Dateien / Cloud sichern** kannst du den iOS-Dateiauswahldialog verwenden. OneDrive beziehungsweise Google Drive müssen installiert, angemeldet und in **Dateien → Durchsuchen → … → Bearbeiten** aktiviert sein. Den gewünschten Ordner auswählen und anschließend beim Anbieter prüfen, ob die Übertragung abgeschlossen ist. Ein geschlossener Dateidialog bestätigt noch keinen abgeschlossenen Cloud-Upload.

## LiDAR 3: Strecken auf dem iPhone oder Computer messen

Auf dem iPhone den Messmodus starten, unter **Measuring → Point to Point Mode** die Punktmessung wählen und zwei Punkte nacheinander mit **+** bestätigen.

Am Computer den [Arbeitsbereich](../../tools/scan-workspace/README.md) starten und die exportierte oder synchronisierte ZIP öffnen. **Strecke** wählen und zwei Punkte auf der Modelloberfläche anklicken. Die Anzeige unterscheidet direkte Länge, horizontalen Abstand und Höhenunterschied. Bei Punktwolken wird ein tatsächlich vorhandener Punkt gewählt. Für eine Torbreite möglichst die gegenüberliegenden Innenkanten auf gleicher Höhe erfassen.

## LiDAR 4: Grundfläche und ebene Flächen messen

**Grundfläche** wählen, bei Bedarf **Draufsicht** und **Dach ausblenden** aktivieren. Die Bodenecken der Reihe nach markieren, danach **Fläche abschließen**. Auch L-förmige Konturen sind möglich. Überkreuzende Kanten oder praktisch identische Punkte werden abgewiesen.

Das Ergebnis dieses Werkzeugs ist die manuell markierte, horizontale Bodenkontur. Es führt keine zusätzliche RoomPlan-Erkennung auf dem importierten LiDAR-Modell aus. Die automatische Erkennung gehört zum getrennten Raumplan-Modus oben. Räume getrennt markieren, wenn du getrennte Flächenwerte möchtest. Für eine ebene Tor- oder Wandfläche **Oberflächenfläche** verwenden. Punkte müssen annähernd in einer Ebene liegen.

## LiDAR 5: Maßstab prüfen und sichern

RTAB-Map exportiert normalerweise in Metern. Bei fremden Modellen die Import-Einheit und die Hochachse prüfen. Mehrere bekannte Abstände vergleichen. **Referenz kalibrieren** übernimmt eine bekannte Länge und skaliert sämtliche Ergebnisse. Dadurch werden örtliche Verzerrungen nicht repariert. Nach der Kalibrierung weitere Kontrollmaße prüfen.

**Projekt sichern** lädt ein `.rtabmeasure.zip` mit Modell, Texturen und Messungen herunter. CSV enthält die Messwerte; SVG enthält die von dir markierten Grundrisse. Cloud-Upload und die optionale Serverablage werden ausdrücklich ausgelöst. Ein nur im Browser geöffnetes Modell ist noch nicht gespeichert.

Die direkte Web-Integration für OneDrive und Google Drive braucht einmalig die OAuth-Registrierung des Betreibers. Sie verwaltet Projektpakete in begrenztem Umfang, keinen vollständigen Cloud-Dateimanager. Für einen vorhandenen Scan aus einem beliebigen Cloud-Ordner zunächst herunterladen oder synchronisieren, dann **Datei öffnen** verwenden.

## Fotoobjekt, Raumfotos und Gaussian Splats

**Fotoobjekt** führt auf einem unterstützten Gerät ab iOS 17 durch Apples Object Capture. Wenn das Gerät auch die lokale Photogrammetrie unterstützt, kann es aus dem Datensatz ein USDZ erzeugen. Die iOS-Verarbeitung verwendet immer Apples Detailstufe `.reduced`; eine höhere Stufe ist hier nicht auswählbar. Originalfotos bleiben privat gespeichert und exportierbar. Für den OBJ-/GLB-Import des Browsers muss ein lokales USDZ separat konvertiert werden.

Unter **Raum, Außenbereich & Video** stehen **Raum fotografieren**, **Außenbereich fotografieren** und **Fotos für Gaussian Splat** ohne die Begrenzungsbox des Objektmodus bereit. Mindestens 20 überlappende Bilder sind ein sinnvoller Einstieg: langsam seitwärts gehen, mehrere Höhen zeigen, beim Auslösen stillhalten und ungefähr 70–80 % Überlappung zwischen Nachbarbildern anstreben. Die App prüft die Überlappung nicht automatisch. Ein unterbrochener Datensatz bleibt in **Meine Originalaufnahmen** erhalten und kann fortgesetzt werden.

Die Kamera verwendet eine feste physische Rück-Weitwinkellinse mit **Zoom 1×**. Fokus und Belichtung passen sich weiter automatisch an. Nach dem Speichern prüft die App ein Graustufen-Vorschaubild von höchstens 128 Pixeln je Seite auf sehr dunkle/helle Anteile, wenig Kontrast und schwache Bildkanten. Hinweise helfen beim Nachfotografieren, bestätigen aber weder Schärfe noch Bewegung, Überlappung oder Maßhaltigkeit. Kein Original wird dafür neu kodiert oder automatisch gelöscht.

Den Fotodatensatz als ZIP exportieren und im Browser ausdrücklich an den optionalen [Rekonstruktionsserver](../../tools/reconstruction/README.md) übergeben. Dort **Mesh** oder **Gaussian Splat** wählen. Der Maßstab ist ohne Prüfung nicht verlässlich. Ein Splat dient der Ansicht und ist keine metrische Oberfläche. Über **Splat öffnen** lassen sich unterstützte `.splat`- und Gaussian-`.ply`-Dateien bis 32 MiB auf dem iPhone offline ansehen; die App trainiert selbst keine Splats.

## Video, Panorama und KI-Einzelbild

| Auswahl im Originalaufnahme-Bereich | Vorgehen und Grenze |
| --- | --- |
| Video aufnehmen | Kamera und Mikrofon erlauben. Bis zu drei Minuten mit Ton filmen, langsam seitwärts gehen und verschiedene Blickwinkel zeigen. Die unveränderte Originaldatei bleibt lokal. |
| Video aus Dateien importieren | MOV/MP4/M4V bis 2 GiB archivieren. Für den Server das Original ausdrücklich exportieren; dort werden Bilder ausgewählt und Mesh oder Splat berechnet. Der Server akzeptiert höchstens 200 MiB pro Upload und hat eigene Codec-/Dauergrenzen. Größere Videos als Kopie kürzen oder verkleinern. |
| Panorama-Fotoreihe aufnehmen | 20–36 überlappende Fotos aufnehmen, maximal 36 pro Reihe. Möglichst um dieselbe Kameraposition drehen, statt wie bei der 3D-Aufnahme seitwärts zu gehen. Rundum sowie nach oben/unten ergänzen. Original-ZIP exportieren und im Browser **Panorama** wählen. Erst der Server fügt Bilder zusammen; eine geschlossene 360°-Ansicht ist nicht garantiert. |
| Panorama importieren | Ein bereits fertiges equirektanguläres 2:1-Bild als JPEG/PNG importieren, höchstens 32 MiB und 8192 × 4096 Pixel. Das Original exportieren und im Browser als Panorama öffnen. Panoramen enthalten keine rekonstruierte Tiefe. |
| Einzelfoto für KI-Modell | Ein vollständig sichtbares einzelnes Objekt vor schlichtem Hintergrund fotografieren oder JPEG/PNG aus Dateien importieren, höchstens 20 MiB und 16 Megapixel. Ein transparenter, freigestellter Hintergrund ist geeignet. Bei einem zu großen Kamerabild bleibt das Original erhalten; eine kleinere Kopie ist für die Verarbeitung nötig. |

Für das KI-Modell **Originaldatei exportieren**, im Browser **KI-Modell** wählen und den freigestellten Vordergrund bestätigen. Der optionale TripoSR-Server erzeugt Geometrie auch für nicht sichtbare Flächen. Das Ergebnis ist ausdrücklich **kein Scan und nicht zum Vermessen geeignet**, auch nicht durch Eingabe einer Referenzlänge. Die native App lädt kein Bild automatisch hoch und führt TripoSR nicht lokal aus.

Die Originalbibliothek ist vom automatischen Geräte-Backup ausgeschlossen. Erst ein ausdrücklicher Dateien-/ZIP-Export gibt Aufnahmen weiter. Fotos können Standortmetadaten, Videos zusätzlich Ton enthalten. Auch Foto-ZIPs dürfen beim Server-Upload höchstens 200 MiB groß sein. Automatische Georeferenzierung, ein ausgerichtetes Gesamtgebäude über mehrere Etagen und die automatische Verbindung von RoomPlan mit Fototexturen bleiben eigenständige offene Arbeiten.

## Tutorial und Prüfstand

Die gemeinsame native Quelle für alle 15 Sprachen ist [MeasurementGuide.json](RTABMapApp/MeasurementGuide.json); neun zusätzliche Sprachpakete werden mit dem Desktop synchronisiert. Der Einstieg bietet außerdem lokalisierte Erklärvideos. Die Videos ersetzen nicht die jeweils aktuellen Modushinweise. Die Textübersetzungen sollten vor einer öffentlichen Veröffentlichung zusätzlich von Muttersprachlern im tatsächlichen Ablauf geprüft werden.

Der vollständige unsignierte iOS-Build samt IPA und Foundation-Prüfungen bestand für den 0.6-Snapshot in [Lauf 38207033828](https://github.com/lukashold/rtabmap/actions/runs/38207033828). Echte Offline-Docker-Ausführungen für Panorama und TripoSR bestanden in [Lauf 38207033832](https://github.com/lukashold/rtabmap/actions/runs/38207033832). Das belegt diese konkreten Builds und Verarbeitungsläufe, keinen Kameratest. Die durchgängigen Routen des gemeinsamen HTTP-Jobdienstes werden separat geprüft; ein erfolgreicher Einzelprozess belegt sie noch nicht.

Ein kompletter Raumscan und ein Torscan auf dem iPhone 17 Pro, reale Genauigkeitsvergleiche, Splat-GPU-/Touch-Bedienung sowie echte OAuth-Anmeldungen mit den Betreiber-Client-IDs bleiben erforderliche Freigabetests. Automatisierte Tests und ein erfolgreicher Build ersetzen sie nicht. Kantura behauptet keine vollständige Funktions- oder Qualitätsgleichheit mit Polycam.
