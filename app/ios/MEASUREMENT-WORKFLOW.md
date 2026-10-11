# KANTURA: Räume und Tore vermessen

KANTURA ist ein eigenständiger Entwicklungszweig auf Basis von RTAB-Map. Der Messablauf ist **Scannen → Prüfen → Messen → Speichern**. Ein geführter Einstieg erklärt die wichtigsten Handgriffe, der Desktop-Arbeitsbereich zeigt Modell und Messungen gemeinsam. Deutsch, Französisch, Spanisch, Italienisch und vereinfachtes Chinesisch sind im neuen Tutorial und im Desktop-Arbeitsbereich enthalten. Die übrigen, bereits vorhandenen RTAB-Map-Menüs sind dadurch nicht vollständig übersetzt.

Die einfache Reihenfolge orientiert sich am [geführten Raumscan von Metaroom](https://help.amrax.ai/sample-page/scanning-with-metaroom-app/how-to-scan-a-single-room-with-the-metaroom-app/). Oberfläche, Texte und Symbole sind eigene Umsetzungen. Dieses Projekt gehört weder zu Metaroom noch zu Polycam.

## Was du brauchst

- Ein iPhone mit LiDAR, beispielsweise dein iPhone 17 Pro, und etwas gleichmäßiges Licht.
- Ein Maßband für mehrere Kontrollmaße. Ein sauberes 3D-Bild allein bestätigt keine Messgenauigkeit.
- Für die unveränderte veröffentlichte App: [RTAB-Map im App Store](https://apps.apple.com/app/rtab-map-3d-lidar-scanner/id1564774365).
- Für diese Entwicklungsversion: ein Mac mit passendem Xcode, dein Apple-Konto und das iPhone zum Signieren und Testen. Windows kann den Desktop-Arbeitsbereich ausführen; die native App wird mit Xcode gebaut. Details: [eigene Veröffentlichung und Installation](../../docs/APP-STORE-RELEASE.md).

Der App-Store-Link installiert die offizielle Upstream-App. Unsere Ergänzungen erscheinen dort erst nach einer Übernahme und einer neuen Veröffentlichung. Ein unsigniertes CI-IPA lässt sich nicht direkt installieren.

## 1. Scan aufnehmen

1. Eine markante Referenzstrecke mit dem Maßband messen und notieren, zum Beispiel den Abstand zwischen zwei Torpfosten.
2. Eine neue Aufnahme starten. **LiDAR Mode** aktivieren, normales **Mapping** verwenden, auf die Kamera warten und **Record** drücken.
3. Boden, Ecken und Wände langsam mit überlappenden Ansichten erfassen. Zum Startpunkt zurückkehren. Bei einem Tor nach Möglichkeit beide Seiten durch einen zusammenhängenden Weg aufnehmen.
4. Stoppen und die `.db` als Original speichern. Die Datenbank ermöglicht eine spätere Rekonstruktion; der Browser liest sie nicht direkt.

LiDAR liefert räumliche Tiefe, die Kamera liefert Bilder und hilft bei der Orientierung. Ein texturiertes Modell verbindet beides. Es handelt sich nicht um zwei unabhängig zu startende Scans. Bewegte Tore, spiegelnde Flächen, dünne Stäbe und starkes Sonnenlicht können problematisch bleiben.

## 2. Modell prüfen und exportieren

**Assemble → Optimized mesh → Textured Mesh** wählen. Auf doppelte Wände, Lücken, überbrückte Öffnungen und fehlende schmale Teile achten. Das Modell als **OBJ-ZIP mit MTL und Bildern** exportieren; alle Dateien zusammen lassen, damit die Texturen erhalten bleiben.

Über **In Dateien / Cloud sichern** kannst du den iOS-Dateiauswahldialog verwenden. OneDrive beziehungsweise Google Drive müssen installiert, angemeldet und in **Dateien → Durchsuchen → … → Bearbeiten** aktiviert sein. Den gewünschten Ordner auswählen und anschließend beim Anbieter prüfen, ob die Übertragung abgeschlossen ist. Ein geschlossener Dateidialog bestätigt noch keinen abgeschlossenen Cloud-Upload.

## 3. Strecken auf dem iPhone oder Computer messen

Auf dem iPhone den Messmodus starten, unter **Measuring → Point to Point Mode** die Punktmessung wählen und zwei Punkte nacheinander mit **+** bestätigen.

Am Computer den [Arbeitsbereich](../../tools/scan-workspace/README.md) starten und die exportierte oder synchronisierte ZIP öffnen. **Strecke** wählen und zwei Punkte auf der Modelloberfläche anklicken. Die Anzeige unterscheidet direkte Länge, horizontalen Abstand und Höhenunterschied. Bei Punktwolken wird ein tatsächlich vorhandener Punkt gewählt. Für eine Torbreite möglichst die gegenüberliegenden Innenkanten auf gleicher Höhe erfassen.

## 4. Grundfläche und ebene Flächen messen

**Grundfläche** wählen, bei Bedarf **Draufsicht** und **Dach ausblenden** aktivieren. Die Bodenecken der Reihe nach markieren, danach **Fläche abschließen**. Auch L-förmige Konturen sind möglich. Überkreuzende Kanten oder praktisch identische Punkte werden abgewiesen.

Das Ergebnis ist die manuell markierte, horizontale Bodenkontur. Es gibt hier keine automatische RoomPlan-Raumerkennung, keine automatisch zugeschnittenen Wandflächen und keinen fertigen Bauplan. Räume getrennt markieren, wenn du getrennte Flächenwerte möchtest. Für eine ebene Tor- oder Wandfläche **Oberflächenfläche** verwenden. Punkte müssen annähernd in einer Ebene liegen.

## 5. Maßstab prüfen und sichern

RTAB-Map exportiert normalerweise in Metern. Bei fremden Modellen die Import-Einheit und die Hochachse prüfen. Mehrere bekannte Abstände vergleichen. **Referenz kalibrieren** übernimmt eine bekannte Länge und skaliert sämtliche Ergebnisse. Dadurch werden örtliche Verzerrungen nicht repariert. Nach der Kalibrierung weitere Kontrollmaße prüfen.

**Projekt sichern** lädt ein `.rtabmeasure.zip` mit Modell, Texturen und Messungen herunter. CSV enthält die Messwerte; SVG enthält die von dir markierten Grundrisse. Cloud-Upload und die optionale Serverablage werden ausdrücklich ausgelöst. Ein nur im Browser geöffnetes Modell ist noch nicht gespeichert.

Die direkte Web-Integration für OneDrive und Google Drive braucht einmalig die OAuth-Registrierung des Betreibers. Sie verwaltet Projektpakete in begrenztem Umfang, keinen vollständigen Cloud-Dateimanager. Für einen vorhandenen Scan aus einem beliebigen Cloud-Ordner zunächst herunterladen oder synchronisieren, dann **Datei öffnen** verwenden.

## Tutorial und Prüfstand

Die gemeinsame Quelle für die fünf Sprachen ist [MeasurementGuide.json](RTABMapApp/MeasurementGuide.json). Die Anleitung ist im nativen Messleitfaden und im Desktop-Tutorial verfügbar. Die Textübersetzungen sollten vor einer öffentlichen Veröffentlichung zusätzlich von Muttersprachlern im tatsächlichen Ablauf geprüft werden.

Die Entwicklung ergänzt Bedienung, Export und Messauswertung. Ein kompletter Raumscan und ein Torscan auf dem iPhone 17 Pro, reale Genauigkeitsvergleiche sowie echte OAuth-Anmeldungen mit den Betreiber-Client-IDs bleiben erforderliche Freigabetests. Automatisierte Tests und ein erfolgreicher Build ersetzen diese Tests nicht.
