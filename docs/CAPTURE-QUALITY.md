# Aufnahme und Qualität nachvollziehbar prüfen

Ein scharf aussehendes Bild, eine vollständige Oberfläche und ein richtiges Maß sind verschiedene Ergebnisse. Kantura zeigt deshalb bei Foto-Rekonstruktionen zunächst einen ungeprüften Maßstab. Ein Panorama hat hier keine Tiefe; Gaussian Splats sind kein geschlossenes Messmesh. Ein erfolgreicher Verarbeitungslauf sagt aus, dass Dateien entstanden sind, nicht dass ihre Geometrie oder Maße stimmen.

## Den passenden Pfad verwenden

- **Räume und Öffnungen:** RoomPlan für erkannte Wände, Türen, Fenster und Raummaße; RTAB-Map/LiDAR für eine texturierte räumliche Aufnahme. Die getrennten Aufnahmen sind nicht automatisch registriert. Gebäude und Etagen organisieren Räume, richten sie aber noch nicht geometrisch aus.
- **Tor und Außenobjekt:** LiDAR/Texturaufnahme mit überprüfbaren Breiten, Höhen und Detailfotos. Dünne Stäbe, Glas, glänzende Teile und verdeckte Flächen einzeln prüfen. Eine fehlende Oberfläche nicht als „kein Hindernis“ behandeln.
- **Foto-Mesh:** Viele scharfe, überlappende Ansichten eines unveränderten Motivs. Die Kamera bewegt sich um das Objekt bzw. durch die Szene, damit unterschiedliche Blickrichtungen entstehen. Der Foto-Worker ermittelt daraus Kameras und Oberfläche.
- **Gaussian Splat:** Derselbe sorgfältige Fotodatensatz kann die Ansicht verbessern. Alle interessierenden Blickrichtungen aufnehmen und später tatsächlich im Viewer ansehen. Eine optisch überzeugende Ansicht ersetzt keine metrische Referenz.
- **Panorama:** Für einen Rundumblick um einen festen Aufnahmeort drehen. Ein gewöhnlicher schmaler Handy-Panoramastreifen ist nicht automatisch ein vollständiges equirektangulares 2:1-Bild. Der [optionale Stitcher](../tools/panorama/README.md) erhält unbekannte Richtungen als Transparenz und Abdeckungsmaske. Seine Drehbewegung unterscheidet sich von der Foto-Mesh-Aufnahme.

## Vor dem Rechnen

Einige Originalbilder groß öffnen: Ist das Motiv scharf, ausreichend strukturiert und ohne starke Helligkeitssprünge? Decken benachbarte Bilder gemeinsame sichtbare Stellen ab? Bewegte Personen, spiegelnde Flächen und ein gedrehtes Objekt vor gleichbleibendem Hintergrund können widersprüchliche Zuordnungen erzeugen. Mehr Trainingsiterationen beseitigen keine fehlenden Ansichten. Die Bildgrundlage zuerst verbessern; bei komplexen Szenen zunächst einen kleinen Ausschnitt verarbeiten. Diese Anforderungen entsprechen den grundlegenden Voraussetzungen der [COLMAP-Fotogrammetrie](https://colmap.github.io/tutorial.html).

Bei Video zählen geeignete Einzelbilder, nicht nur Laufzeit. Gleichmäßige Zeitabstände allein erkennen weder Unschärfe noch redundante Ansichten. Drohnenbilder können dieselbe Rekonstruktion speisen; ein brauchbares geografisches Modell erfordert darüber hinaus überprüfte Koordinaten, Maßstab und gegebenenfalls Kontrollpunkte. Der aktuelle Foto-Worker behauptet keine automatische GPS-Georeferenzierung. Polycam dokumentiert [Video-Frames und Qualitätsauswahl](https://learn.poly.cam/hc/en-us/articles/30549121659412-How-to-Create-Photogrammetry-Models-From-Images-and-Videos-on-Polycam-Web) sowie einen gesonderten [Drohnen-/GPS-Ablauf](https://learn.poly.cam/hc/en-us/articles/30549134403860-How-to-Create-Drone-3D-Models-in-Polycam); diese sind Vergleichsanforderungen, keine nachgewiesenen Kantura-Funktionen.

## Ergebnis kontrollieren

1. Originaldaten und Einstellungen sichern. Aufnahmegerät, Datum, Modus, Engineversion, Verarbeitungseinstellungen, Dauer und Hardware notieren.
2. Modell aus mehreren Richtungen öffnen. Löcher, doppelte Konturen, schwebende Fragmente, verschmierte Texturen und abgeschnittene Bauteile erfassen. Bei Panorama zusätzlich Naht, Horizont und Abdeckungsmaske ansehen.
3. Für Messzwecke mindestens drei unabhängige reale Referenzstrecken verwenden, etwa Raumbreite, Raumhöhe und Türöffnung. Eine Kalibrierstrecke allein ist keine unabhängige Bestätigung. Abweichungen vor und nach einer ausdrücklich vorgenommenen Skalierung getrennt festhalten.
4. Dieselbe Szene nochmals neu aufnehmen. Wiederholbarkeit und problematische Stellen dokumentieren, auch wenn ein Durchlauf besser aussieht. Für einen Vergleich mit einer anderen App dieselbe Szene und dieselben Referenzen verwenden.
5. Archiv speichern, schließen und auf dem Zielgerät wieder öffnen. Maße, Fotos, Etagenzuordnung und ungeprüfte Werte müssen verständlich erhalten bleiben.

Die synthetischen Engine-Tests prüfen Rechenpfade und bekannte Testgeometrie. Erst reale Aufnahmen mit benannter Referenz und vorab festgelegter Toleranz können eine passende Messfreigabe begründen. Der [Validierungsstand](../tools/scan-workspace/VALIDATION.md) enthält die tatsächlich ausgeführten Prüfungen; die [Roadmap](POLYCAM-ROADMAP.md) benennt offene Abnahmen.
