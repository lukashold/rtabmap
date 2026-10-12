# KANTURA: Funktionsvergleich und nächste Ausbaustufen

Historischer Metaroom-Vergleich vom 11. Oktober 2026: Die Formulierungen „in dieser Runde“ und die Ist-Angaben unten gehören zur damaligen Ausbauplanung. Für die aktuelle 0.6-Fassung gelten die [Aufnahmearten-Roadmap](POLYCAM-ROADMAP.md), [Qualitätsprüfung](CAPTURE-QUALITY.md) und [tatsächlichen Prüfergebnisse](../tools/scan-workspace/VALIDATION.md). Insbesondere unterstützt die geführte Oberfläche inzwischen 15 Sprachen; mehrere damals geplante Raum-/Berichtsfunktionen sind implementiert. Dieser Vergleich ist keine aktuelle Abnahme aller Funktionen.

Recherche: **11. Oktober 2026**, anhand der offiziellen Metaroom-Produktseiten, des Help Centers und des Changelogs. Dies ist ein Vergleich dokumentierter Funktionen und unseres Quellcode-Stands, kein eigener Genauigkeitstest von Metaroom. Preise und Paketgrenzen sind nicht Teil des Vergleichs. „In dieser Runde“ bezeichnet den Entwicklungsumfang; die Freigabe einzelner Funktionen hängt weiterhin von Build-, Browser- und Gerätetests ab.

Das Ziel für KANTURA ist konkret: **Räume und Tore aufnehmen, das Aussehen nachvollziehen, Breiten/Höhen/Abstände und Flächen bestimmen und das Ergebnis auf dem eigenen Computer weiterverwenden.** Hinzu kommt die Vorprüfung, ob ein Gerät durch einen angegebenen Durchgang und über ein Treppenpodest bewegt werden könnte. Metaroom dient als Vorbild für einen verständlichen Ablauf. Name, Gestaltung, Texte und technische Umsetzung bleiben eigenständig.

## Was wir vom Bedienablauf übernehmen

Metaroom führt von einer kurzen Vorbereitung über die laufende 3D-Vorschau zu einer Prüfung des Scanabschnitts. Erst danach wird abgeschlossen oder erneut aufgenommen. Bei mehreren Räumen werden weitere Abschnitte ergänzt. Die Anleitung beschreibt auch den anschließenden Upload und das Öffnen im Workspace. [Offizielle Anleitung für einen Raum](https://help.amrax.ai/sample-page/scanning-with-metaroom-app/how-to-scan-a-single-room-with-the-metaroom-app/)

Für KANTURA ergibt sich daraus dieser eigene Ablauf:

1. **Aufnahme wählen:** „Raum“ für die Erkennung von Innenräumen, „Tor / Objekt“ für den bestehenden LiDAR-Modellscan.
2. **Vorbereiten:** Linse, Licht, unbewegte Umgebung und ein mit Maßband gemessenes Kontrollmaß. Die nächste Handlung muss eindeutig erkennbar sein.
3. **Aufnehmen:** Kamerabild und Modellfortschritt, verständliche Hinweise bei Trackingproblemen und eine gut erreichbare Stopptaste.
4. **Prüfen:** Fehlstellen, falsche Kanten und fehlende Objekte ansehen, bevor man den Ort verlässt. Eine erfolgreiche Rekonstruktion ist keine Bestätigung aller Maße.
5. **Messen und ergänzen:** Punktmessung, Flächenkontur, Kontrollmaß sowie Notiz mit Foto an einer ausgewählten Stelle.
6. **Mitnehmen:** Projektdatei, CAD-Kontur oder verständlicher Messbericht; bei Bedarf explizit im Cloud-Konto oder auf dem eigenen Server speichern.

Die beiden Aufnahmearten sind wichtig: Metaroom beschreibt seine Scan-App ausdrücklich als für Innenräume ausgelegt und unterstützt laut Help Center keine Außenaufnahmen. Ein Tor im Freien bleibt in KANTURA daher ein Anwendungsfall für den RTAB-Map-Modellscan, dessen Eignung am konkreten Objekt geprüft werden muss. [Metaroom zu Außenaufnahmen](https://help.amrax.ai/sample-page/more-questions/outdoor-scanning/)

## Vergleich für Räume, Tore und Maße

**Vorhanden** bedeutet im KANTURA-Entwicklungszweig implementiert, nicht als eigene App im Store veröffentlicht. **In dieser Runde** ist der aktuelle Ausbau. **Offen** ist noch kein zugesagtes oder fertiggestelltes Feature.

| Bereich | Offiziell dokumentiertes Metaroom-Verhalten | KANTURA und verbleibende Arbeit |
| --- | --- | --- |
| Geführter Einstieg | Vorbereitung, Hinweise während des Scans, Vorschau und Abschnittsprüfung. [Anleitung](https://help.amrax.ai/sample-page/scanning-with-metaroom-app/how-to-scan-a-single-room-with-the-metaroom-app/) | **Vorhanden:** Messleitfaden, Scan-Hinweise und fünfsprachiger Desktop-Arbeitsbereich. **In dieser Runde:** deutliche Wahl zwischen Raum- und Objektaufnahme. Die komplette ältere RTAB-Map-Oberfläche ist noch nicht neu gestaltet oder übersetzt. |
| Raumstruktur | Raum- und Objektelemente werden erkannt und strukturiert dargestellt. [Objekterkennung](https://amrax.ai/3d-room-scan/room-object-recognition/) | **In dieser Runde:** nativer Apple-RoomPlan-Modus für Wände, Türen, Fenster und Öffnungen; Export als USDZ und KANTURA-JSON für den Browser. Daraus folgt noch keine automatische, baureife BIM-Dokumentation. |
| Anschauliches Modell | Fototexturen in den Scanergebnissen sind im Changelog für Q1 2026 dokumentiert. [Changelog](https://amrax.ai/changelog/) | **Vorhanden:** texturierte OBJ-Modelle aus RTAB-Map und Umschalten zwischen Textur und Geometrie im Browser. Das vereinfachte RoomPlan-Modell hat keine eigene Fototextur. Eine automatische Kombination beider Aufnahmearten in einem gemeinsamen Koordinatensystem ist **offen**. |
| Strecken und Höhen | Punktmessungen und Außenmaße ausgewählter Elemente. [Messwerkzeuge](https://help.amrax.ai/sample-page/metaroom-studio-features/basic-measurements/) | **Vorhanden:** freie Punktmessung mit direkter Länge, horizontalem Abstand und Höhenunterschied. **Offen:** komfortables Fangen an erkannten Kanten, Achsensperren und Winkelwerkzeug. |
| Grund- und Wandflächen | Manuelle Flächen sowie Elementflächen; bei Öffnungen werden Gesamt-, Öffnungs- und Nettofläche unterschieden. [Messwerkzeuge](https://help.amrax.ai/sample-page/metaroom-studio-features/basic-measurements/) | **Vorhanden:** manuelle horizontale Grundflächen und ebene Oberflächen, auch mit konkaver Kontur. **In dieser Runde:** strukturierte Raumdaten als zusätzliche Grundlage. **Offen:** nachvollziehbarer automatischer Abzug von Tür-/Fensterflächen einschließlich Korrekturmöglichkeit. |
| Foto und räumlicher Bezug | Snapshots werden während der Aufnahme gesetzt und sind im 3D-Modell lokalisierbar. [Snapshots](https://help.amrax.ai/sample-page/scanning-with-metaroom-app/how-to-set-points-of-interest-during-scanning-with-the-metaroom-app/) | **In dieser Runde:** eigene Fotoanhänge an manuell gesetzten 3D-Notizen. Das ist eine Ortsmarkierung mit Anhang. Es fehlen noch Kamera-Posen und die automatische Einpassung eines Fotos als echte Scanansicht. |
| Notizen | Notizen an Snapshots und Raumelementen; Snapshot-Notizen erscheinen im PDF-Projektbericht. [Notizen](https://help.amrax.ai/sample-page/metaroom-studio-features/notes-in-scanned-spaces/) | **In dieser Runde:** Titel, Beschreibung, Art wie Tür/Fenster/Tor/Wand und optionales Foto an einem 3D-Punkt; im Projektpaket erhalten und im Bericht nutzbar. Team-Kommentare mit Autoren und Verlauf sind **offen**. |
| Messbericht und CAD | Unter anderem 2D-DXF, PDF-Grundriss, PDF-Projektbericht und IFC sind dokumentiert. [Exportübersicht, aktualisiert 6. Oktober 2026](https://help.amrax.ai/sample-page/export-integrations/what-export-formats-does-metaroom-studio-support/) | **Vorhanden:** CSV und SVG. **In dieser Runde:** DXF für die Grundrisskonturen und ein druckbarer Bericht mit PDF-Ausgabe über den Browser. Kein vollständiger IFC-Export, keine Revit-/ArchiCAD-Zertifizierung und keine automatische Übernahme aller Gebäudesemantik. |
| Räume und Etagen zusammenführen | Mehrraum-Scans sind dokumentiert; das Changelog Q2 2026 nennt die Kombination separater Etagen. [Mehrraum-Scan](https://amrax.ai/3d-room-scan/multi-room-scanning/), [Changelog](https://amrax.ai/changelog/) | **In dieser Runde:** Gebäude, Etagen und Räume manuell benennen und getrennte Raummodelle verwalten. **Offen:** räumliche Ausrichtung mit Vorschau, Zusammenführung und belastbare Kontrolle der Übergänge. Die Zuordnung zu derselben Etage richtet Modelle nicht automatisch aneinander aus. |
| Große und komplexe Gebäude | Das Help Center führt eigene Abläufe für große Räume, Treppen und komplexe Decken. [Funktionsübersicht](https://help.amrax.ai/docs/) | **Offen:** geführte Abschnitte, Rekonstruktion von Treppen und Dachschrägen, Kapazitätsplanung und belastbare Tests langer Sitzungen. Keine unbelegte maximale Gebäudegröße versprechen. |
| Teilen und Zusammenarbeit | Gemeinsamer Projektzugriff ist im Help Center beschrieben. [Projektfreigabe](https://help.amrax.ai/sample-page/metaroom-studio-features/project-sharing/) | **Vorhanden:** transportable Projekt-ZIPs, direkte Cloud-Adapter und optionale eigene Serverablage. Die Serverablage ist noch kein Mehrbenutzersystem mit Rollen, Revisionen und konfliktfreiem gemeinsamem Bearbeiten. |
| Aufnahmezuverlässigkeit | Das Changelog Q2 2026 nennt eine Akkuwarnung und verbesserte Uploadzuverlässigkeit. [Changelog](https://amrax.ai/changelog/) | **Vorhanden:** Hinweise bei Trackingverlust. **Offen:** durchgängige Speicher-/Akku-/Temperaturhinweise, wartende Uploadaufträge und Wiederaufnahme nach Netzunterbrechungen. |

## Schwerpunkt dieses Entwicklungsschritts

### P0: Der erste Raum und das erste Tor müssen verständlich funktionieren

- **Innenraumaufnahme:** RoomPlan liefert einen strukturierten Ausgangspunkt. Die Kameraerfassung und Erkennung laufen nativ auf einem unterstützten Apple-Gerät. [Apple beschreibt RoomPlan](https://developer.apple.com/augmented-reality/roomplan/) als API für parametrische Innenraummodelle mit Dimensionen und USD/USDZ-Ausgabe. KANTURA-JSON ist unser zusätzlicher Austauschweg zum Browser, kein von Apple standardisiertes CAD-Format.
- **Browserimport:** Ein Raumexport muss anhand einer Versionskennung validiert werden. Achsen und Metermaßstab müssen erhalten bleiben. Nicht erkannte oder mehrdeutige Elemente dürfen nicht unbemerkt zu vermeintlich sicheren Maßen werden.
- **Foto-Notiz:** Ein Punkt, ein verständlicher Titel, eine Art, Beschreibung und optional ein eigenes Foto. Foto und Text müssen beim Speichern, erneuten Öffnen und Berichterstellen erhalten bleiben. Eine angehängte Fotografie wird nicht automatisch metrisch messbar.
- **Kontrollmaß:** Eine Modellstrecke mit einer unabhängig gemessenen Referenz vergleichen und die Abweichung ausweisen. Das ist eine Prüfung, keine stillschweigende Skalierung. Kalibrierung bleibt eine gesonderte Aktion; mehrere andere Referenzstrecken dienen anschließend zur Kontrolle.
- **Weitergabe:** Ein DXF mit dokumentierter Einheit und ein lesbarer Bericht mit Modellbezug, Messwerten, Notizen, Fotos und Kontrollmaßen. Der Browserdruck kann eine PDF-Datei erzeugen; das ist keine fest zugesicherte maßstäbliche Planzeichnung auf jedem Drucker.

### P1: Weniger manuelle Arbeit beim Messen

Kantenfang mit abschaltbarer Hilfe, horizontale/vertikale Achsensperre und gut sichtbare ausgewählte Endpunkte kommen als Nächstes. Danach folgen editierbare Raumkonturen, kontrollierbarer Abzug von Öffnungen und die Auswahl eines erkannten Elements mit seinen Dimensionen. Ein Änderungsverlauf muss später erklären können, ob ein Wert aus der Erkennung, einer freien Messung oder einer manuellen Korrektur stammt.

Für den Torablauf ist das Ziel eine eigene verständliche Vorlage: lichte Breite zwischen Pfosten, Höhe links/rechts, Flügelbreite, Bodenabstand und mehrere Detailfotos. Dies sind zunächst benannte Messungen des Nutzers; weder Scharniere noch Torflügel werden derzeit automatisch erkannt.

### P2: Größere Projekte und professionelle Übergabe

Die räumliche Mehrraum- und Etagenzusammenführung, gemeinsam registrierte Fotos und Geometrie, Treppen/Dachschrägen, IFC, fachliche Raumkategorien, vollständige Geräte-/Assetlisten und ein echtes Mehrbenutzersystem bleiben gesonderte Vorhaben. Sie brauchen eigene Dateiformate, fachliche Regeln und Interoperabilitätstests. Sie lassen sich nicht durch zusätzliche Export-Schaltflächen als fertig darstellen.

## Gerät durch das Stiegenhaus: Was die neue Vorprüfung leistet

Die Transportprüfung verwendet die **manuell eingegebenen** Geräte- und Wegmaße: Breite, Tiefe, Höhe, lichte Durchgangsbreite und -höhe, Podestbreite und -tiefe, Treppenanstieg, horizontaler Treppenlauf und Drehwinkel. Alle Längen sind in Metern. Anstieg und Lauf müssen dieselbe Treppenstrecke beschreiben; beispielsweise eine einzelne Stufe oder den gesamten geraden Lauf. Die Neigung ergibt sich aus dem Verhältnis beider Werte. Der gewählte Abstand gilt pro Seite, auch oben und unten.

Das Gerät wird als starrer Quader behandelt. Die Berechnung prüft aufrechte und seitlich ausgerichtete Tragpositionen. Wenn Kippen aktiviert ist, werden außerdem die zur Treppenneigung passende Lage und die Kippübergänge betrachtet. Beim Drehen wird ein mittig im rechteckigen Podest liegender Hüllraum geprüft. Analytische Maxima berücksichtigen die größten Abmessungen auch zwischen den sichtbaren Animationsschritten.

Die Ergebnisse bedeuten:

- **Im geprüften Hüllraum möglich:** Eine der geprüften Bewegungen hat unter diesen vereinfachten Annahmen ausreichend Platz. Das bestätigt weder den gesamten realen Weg noch die Tragbarkeit.
- **Weitere Prüfung nötig:** Die untersuchten Hüllräume reichen nicht aus. Eine versetzte Drehung, ein anderer Kippwinkel oder ein anderer Weg könnte dennoch funktionieren. Ein misslungener mittiger Podesttest wird deshalb nicht als endgültiges „passt nicht“ ausgegeben.
- **Durchgang zu klein:** Die kleinste physische Gerätekante einschließlich beidseitigem Abstand ist größer als eine zwingende Durchgangsbreite oder -höhe. Innerhalb des starren Quader-Modells hilft dagegen keine andere Orientierung.

Dies ist **keine Kollisionssimulation gegen den eingescannten 3D-Treppenlauf**. Einzelne Stufen, Geländer, schräge Decken, Vorsprünge, tragende Personen, Sackkarre und Handgriffe werden nicht als separate Hindernisse berechnet. Eine automatisch berechnete durchgängige Bewegungsbahn, die sich am Scan entlangschieben lässt, ist noch offen. Kippen ist außerdem nur dann praktisch zulässig, wenn die Anleitung des konkreten Geräts es erlaubt. Verpackung, Griffe und sonstige Anbauteile müssen in den tatsächlich transportierten Außenmaßen enthalten sein.

Die gleichmäßig angenommene lichte Höhe und die mitgeprüften Kippübergänge sind absichtlich konservativ. Ein bereits außerhalb des geprüften Bereichs gekipptes Gerät kann einen anderen Platzbedarf haben; diese zusätzliche Rangierfläche ist hier nicht separat beschrieben. Die Ausgabe der Kippkandidaten macht den Platzbedarf sichtbar, ohne eine Freigabe zu erzwingen.

### Modellnummern: kleiner belegter Katalog

Die Modellsuche durchsucht zunächst einen **eingebauten Offline-Katalog**. Sie führt keine beliebige Online-Suche aus und leitet keine Maße aus ähnlich klingenden Modellnummern ab. Unbekannte Modelle werden anhand ihres eigenen Herstellerdatenblatts manuell eingetragen. Herstellerquelle und Prüfdatum bleiben sichtbar; die regionalen Modellzusätze zählen zur Zuordnung.

| Modell | Herstellermaße ohne Verpackung, B × T × H | Quelle und Besonderheit |
| --- | --- | --- |
| Bosch KGN39VLEA | 0,600 × 0,660 × 2,030 m | [Bosch Deutschland](https://www.bosch-home.com/de/de/product/KGN39VLEA); als nicht mehr verfügbar geführt, als Bestandsgerät weiterhin identifizierbar. |
| Samsung RB34C600ESA/EF | 0,595 × 0,658 × 1,853 m | [Samsung Österreich](https://www.samsung.com/at/refrigerators/bottom-mount-freezer/rb7300t-344l-silver-rb34c600esa-ef/); die Tiefe ist ausdrücklich **ohne Türgriff** angegeben. Tatsächliche Transporttiefe prüfen. |
| LG GBP62PZNAC | 0,595 × 0,675 × 2,030 m | [LG Österreich](https://www.lg.com/at/kuhlschranke/kuhl-gefrierkombinationen/gbp62pznac/); mit Verpackung nennt die Quelle 0,634 × 0,745 × 2,135 m (B × T × H). |

Die drei Einträge wurden am 11. Oktober 2026 mit den verlinkten Herstellerangaben abgeglichen. Sie sind keine Kaufempfehlung, Lieferbarkeitszusage oder Bestätigung, dass das konkrete Gerät ohne Nachmessen transportiert werden kann.

## Wo KANTURA für diesen Einsatz besonders nützlich werden kann

Die Priorität liegt auf frei weiterentwickelbarem Quellcode, lokalen Projektdateien und selbst betriebener Ablage, einem gesonderten Torablauf und sichtbaren Kontrollmaßen. Das sind konkrete Produktziele und Architekturentscheidungen. Eine allgemein höhere Scanqualität, geringere Abweichung oder bessere Vollständigkeit gegenüber Metaroom ist damit nicht nachgewiesen.

Auch Metaroom grenzt seine Eignung gegenüber amtlicher Vermessung, Statik und abschließender Bauabnahme ab. KANTURA übernimmt daher keine pauschalen Millimeter-, Vermessungs- oder BIM-Versprechen. Für die gewünschte Planung zählt die dokumentierte Abweichung am tatsächlichen Raum oder Tor. [Offiziell beschriebene Metaroom-Grenzen](https://help.amrax.ai/sample-page/more-questions/what-is-metaroom-not-suitable-for/)

## Nachweis vor einer Freigabe

Der Geräteversuch muss mindestens einen normalen Raum, einen nicht rechteckigen Raum mit Öffnungen und ein Tor im Freien umfassen. Jeweils Originale sichern, mehrere unabhängige Referenzen aufnehmen und Modellgeometrie sowie Endpunktwahl ansehen. Eine Raumfläche mit fehlender Ecke darf nicht als korrekt abgeschlossen gelten. Reflexionen, dünne Stäbe und verdeckte Kanten müssen am Ergebnis erkennbar bleiben.

Für die neue Runde sind außerdem folgende Ergebnisse überprüfbar: Ein bekannter Raumexport behält seine Dimensionen beim Browserimport; Projekt-ZIPs erhalten Notizen, Bilder und Referenzwerte; ein bearbeitetes oder kalibriertes Modell erhält passende aktualisierte Abweichungen; DXF-Konturen haben dieselben Maße wie das Modell; der PDF-Druck enthält alle erfassten Messungen und gut lesbare Fotos. iOS-Geräteprüfung, Muttersprachlerprüfung der Texte und Live-Tests der Cloud-Anmeldung bleiben von automatisierten Tests getrennt auszuweisen.

Die eigenständige App-Veröffentlichung ist in [APP-STORE-RELEASE.md](APP-STORE-RELEASE.md) beschrieben. Bedienung und Installation des Desktop-Arbeitsbereichs stehen in der [Workspace-Anleitung](../tools/scan-workspace/README.md).
