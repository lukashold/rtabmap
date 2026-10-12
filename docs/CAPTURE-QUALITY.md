# Aufnahme und Qualität nachvollziehbar prüfen

Stand: 0.6.0 Preview, 12. Oktober 2026. Ein scharf aussehendes Bild, eine
vollständige Oberfläche und ein richtiges Maß sind verschiedene Ergebnisse.
Kantura kennzeichnet Foto-Rekonstruktionen mit ungeprüftem Maßstab. Ein Panorama
hat keine Tiefe; Gaussian Splats sind kein geschlossenes Messmesh. Ein erfolgreicher
Verarbeitungslauf belegt geprüfte Ergebnisdateien, nicht richtige Geometrie oder
Maße. Ein Foto als Eingang macht KI-erzeugte unsichtbare Flächen nicht zu einer
beobachteten Oberfläche.

## Den passenden Pfad verwenden

- **Räume und Öffnungen:** RoomPlan erkennt Wände, Türen, Fenster und Raummaße; RTAB-Map/LiDAR liefert eine texturierte räumliche Aufnahme. Die getrennten Aufnahmen sind nicht automatisch registriert. Gebäude und Etagen organisieren Räume, richten sie aber nicht geometrisch aus. Erkennungssicherheit beschreibt die Kategorie, keine Maßtoleranz.
- **Tor und Außenobjekt:** LiDAR/Texturaufnahme mit überprüfbaren Breiten, Höhen und Detailfotos. Dünne Stäbe, Glas, glänzende Teile und verdeckte Flächen einzeln prüfen. Eine fehlende Oberfläche nicht als „kein Hindernis“ behandeln.
- **Foto-Mesh:** Viele scharfe, überlappende Ansichten eines unveränderten Motivs. Die Kamera bewegt sich um das Objekt beziehungsweise durch die Szene. Der Worker ermittelt daraus Kameras und Oberfläche; reine Drehung am selben Ort liefert keine verlässliche Tiefe. Die native Foto-Führung erhält Originale und gibt Bildhinweise, keinen 3D-Qualitätsnachweis.
- **Gaussian Splat:** Eine sorgfältige Fotoserie oder geeignete Videoframes speisen die tatsächliche Splat-Verarbeitung. Interessierende Blickrichtungen aufnehmen und im Viewer kontrollieren. Eine optisch überzeugende Ansicht ersetzt weder Messoberfläche noch Referenz.
- **Panorama:** Für einen Rundumblick um möglichst denselben Kameramittelpunkt drehen. Die native Panorama-Führung sammelt Originalfotos; erst der explizite Serverauftrag setzt sie zusammen. Der [Stitcher](../tools/panorama/README.md) erzeugt ein echtes 2:1-Kugelbild mit Abdeckungsmaske. Unbekannte Richtungen bleiben transparent; kein AI-Fill und keine Tiefe. Ein gewöhnlicher schmaler Handy-Panoramastreifen ist nicht automatisch ein vollständiges Kugelbild.
- **Einzelbild-KI:** Ein freigestelltes Motiv oder ausdrücklich bestätigter neutraler Hintergrund. Das native Kamerabild bleibt ein Original; [TripoSR](../tools/generation/README.md) schätzt daraus ein neues Modell einschließlich unsichtbarer Seiten. Dieses Ergebnis dient der Ansicht, nicht der Vermessung, Passungs- oder Transportentscheidung. Auch eine bekannte Länge macht seine Form nicht verlässlich.

## Vor dem Rechnen

Einige Originalbilder groß öffnen: Ist das Motiv scharf, ausreichend strukturiert
und ohne starke Helligkeitssprünge? Decken benachbarte Bilder gemeinsame sichtbare
Stellen ab? Bewegte Personen, Spiegelungen und ein gedrehtes Objekt vor einem
unveränderten Hintergrund können widersprüchliche Zuordnungen erzeugen. Auch
symmetrische Gegenstände und wiederholte Boden-/Wandmuster können falsche
Zuordnungen ermöglichen. Mehr Trainingsiterationen beseitigen weder fehlende
Ansichten noch falsche Kameras. Diese Voraussetzungen beschreibt die
[offizielle COLMAP-Anleitung](https://colmap.github.io/tutorial.html).

Die Videoeingabe ist implementiert: FFmpeg dekodiert begrenzte MP4/MOV-Dateien;
Auswahlregeln berücksichtigen Zeitabdeckung, Bilddetail, Belichtung und ähnliche
Bilder. Mindestens acht geeignete Frames müssen übrig bleiben. Auswahlgründe und
exportierte Bilder bleiben nachvollziehbar. Diese Regeln sind keine Garantie
für genügend Bewegung oder richtige Kamerapositionen. Die echte synthetische
Video-zu-Mesh-Probe und die gepinnte FFmpeg-Prüfung bestanden in Lauf 38208881350.
Der Gesamt-Lauf scheiterte damals an der Python-Umgebungserkennung der anderen
Aufnahmearten; der Fix bestand anschließend alle sieben gemeinsamen API-Aufträge
in Lauf 38210549928. Das ist keine Handyvideo-Abnahme.

Das UAV-Profil akzeptiert passende Drohnenfotos/-videos über dieselbe Pipeline.
GPS-/Höhenmetadaten werden in Originalen erhalten, jedoch nicht automatisch in
geografische Kameraposen oder verlässliche Maße umgewandelt. Georeferenzierung,
Kontrollpunkte und Orthomosaik bleiben offen. Polycam dokumentiert einen
[gesonderten Drohnen-/GPS-Ablauf](https://learn.poly.cam/hc/en-us/articles/30549134403860-How-to-Create-Drone-3D-Models-in-Polycam);
dieser Vergleich ist kein Nachweis dieser Kantura-Funktionen.

## Warnungen ernst nehmen

Der aktuelle Web-Code erhält Qualitätswarnungen beim Import und im gespeicherten
Projekt. Bei **möglicherweise falschen Kamerapositionen** oder **zu wenig Bewegung
zwischen Blickpunkten** sind Messung und Kalibrierung gesperrt. Das Modell kann
angesehen und mit Notizen versehen werden; für Messzwecke neu aufnehmen.
Eine Referenzlänge ändert nur den Maßstab und repariert keine falsche Form.

**Viele wiederholte Blickpunkte** ist eine eigene Warnung. Sie allein sperrt
Kalibrierung/Messung nicht, verlangt aber mehr unterschiedliche Ansichten und
unabhängige Kontrollmaße. Eine Foto-Rekonstruktion ohne blockierende Warnung
benötigt weiterhin eine bekannte Referenz, bevor Maße aktiviert werden.
Generierte Modelle, Panoramen und Splats bleiben unabhängig davon ohne metrische
Messwerkzeuge. Das Ausbleiben einer Warnung ist keine Qualitätsfreigabe.

Die Kamerahinweise sind Diagnosehilfen. Ein geringer Pixel-Reprojektionsfehler
kann trotz falscher räumlicher Zuordnung entstehen. Verluste/PSNR der
Splat-Ansicht beschreiben Bildwiedergabe, keine physische Maßgenauigkeit. Die
Oberfläche erklärt den nötigen nächsten Schritt; technische Zahlen bleiben im
Ergebnismanifest nachvollziehbar.

## Ergebnis kontrollieren

1. Originaldaten und Einstellungen sichern. Aufnahmegerät, Datum, Modus, Engineversion, Verarbeitungseinstellungen, Dauer und Hardware notieren.
2. Modell aus mehreren Richtungen öffnen. Löcher, doppelte Konturen, schwebende Fragmente, verschmierte Texturen und abgeschnittene Bauteile erfassen. Bei Panorama zusätzlich Naht, Horizont und Abdeckungsmaske ansehen.
3. Für ein geeignetes Messmesh mindestens drei unabhängige reale Referenzstrecken verwenden, etwa Raumbreite, Raumhöhe und Türöffnung. Eine Kalibrierstrecke allein ist keine unabhängige Bestätigung. Abweichungen vor/nach ausdrücklich vorgenommener Skalierung getrennt festhalten. Eine blockierende Kamerawarnung nicht durch Skalierung umgehen.
4. Dieselbe Szene nochmals neu aufnehmen. Wiederholbarkeit und problematische Stellen dokumentieren, auch wenn ein Durchlauf besser aussieht. Für einen Vergleich mit einer anderen App dieselbe Szene und dieselben Referenzen verwenden.
5. Archiv speichern, schließen und auf dem Zielgerät wieder öffnen. Maße, Fotos, Etagenzuordnung, Herkunft und Qualitätswarnungen müssen erhalten bleiben. Ein heruntergeladenes Archiv ist eine lokale Datei, keine automatisch bestätigte Cloud-Sicherung.

## Was die synthetischen Prüfungen bisher zeigen

Die echte CPU-Pipeline hat aus einer periodisch texturierten Testszene Dateien
erzeugt, aber falsche Kamerageometrie: 15 von 16 bekannten gegenüberliegenden
Ansichtspaaren lagen fast zusammen. Diese Szene ist **nicht qualitätsfreigegeben**.
Die unveränderten Ausgangswerte und Kriterien stehen in
[QUALITY-FIXTURES.md](../tools/validation/QUALITY-FIXTURES.md). Ein Mesh ohne genug
Punkte in der erwarteten Würfelregion erhält ein ausdrücklich ungültiges
Geometrieergebnis; die Kameraauswertung bleibt dabei erhalten.

Eine zweite, deterministische Szene verwendet dieselbe Geometrie und dieselben
Kameras mit eindeutigen, nicht periodischen Texturen. Ihre Ground-Truth-Datei
liegt außerhalb des Foto-ZIPs und wird nicht in die Rekonstruktionsengine
gegeben. Ihre tatsächliche Rekonstruktion bestand die vorab dokumentierten
synthetischen Kriterien in Lauf 38208881350: alle 32 Kameras, keine zusammengefallenen
Gegenansichten und ausreichende Nähe/Abdeckung der sichtbaren Würfelflächen.
Die lokale Auswertung der heruntergeladenen echten Dateien bestand anschließend
auch mit `--require-quality`. Die Kameras des Splat-Laufs bestanden ebenfalls;
das prüft seine Positionen, nicht die Bildqualität. Dieses Ergebnis löscht den
schwierigen Fall nicht und beweist keine Verbesserung an realen Räumen oder Toren.

Die echten Offline-Docker-Proben für Panorama und TripoSR sind Funktionsnachweise
der jeweiligen Engines. Ein unsignierter iOS-Build und Webtests ersetzen keine
reale Aufnahme. Signierter iPhone-17-Pro-Durchlauf, native WKWebView/GPU,
Cloud-Anmeldung, Kalibrierung mit physischen Referenzen, ausgerichtete Etagen und
Drohnen-Georeferenzierung sind damit nicht bestätigt. Maßgenauigkeit benötigt
reale Szenen, benannte Referenzen und eine vorab festgelegte Toleranz.
Der [Validierungsstand](../tools/scan-workspace/VALIDATION.md) führt tatsächliche
Prüfungen; die [Roadmap](POLYCAM-ROADMAP.md) die noch offenen Abnahmen.
