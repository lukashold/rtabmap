# Bei KANTURA mitarbeiten

KANTURA ist ein eigenständiger RTAB-Map-Fork. Entwicklung und Pull Requests gehören zum Zweig [`lukashold/rtabmap:kantura/main`](https://github.com/lukashold/rtabmap/tree/kantura/main). Die [englische Hauptanleitung](../../CONTRIBUTING.md) beschreibt den vollständigen Ablauf.

## Einsteigen und entwickeln

Lies [Arbeitsbereich](../../tools/scan-workspace/README.md), [Funktionsvergleich](../KANTURA-FEATURES.md) und [Teststand](../../tools/scan-workspace/VALIDATION.md). Suche zuerst in den [Issues des Forks](https://github.com/lukashold/rtabmap/issues). Geeignete Beiträge sind nachvollziehbare Fehlerberichte, kleine Bedienverbesserungen, Übersetzungen oder echte Gerätetests.

Für den Browser brauchst du das vollständige Repository, Node.js 24 und pnpm 11.25.0. Erstelle einen eigenen Branch von `kantura/main`. In `tools/scan-workspace`:

```sh
pnpm install --frozen-lockfile
pnpm test
pnpm check
pnpm build
pnpm start
```

Öffne `http://localhost:4173`. Einrichtung von Corepack, Docker und Serverablage steht in der Hauptanleitung. Prüfe geänderte Geometrie und Speicherung mit passenden Tests; bei reinen Textkorrekturen genügt eine gezielte Sprach-/Layoutprüfung. Nenne tatsächlich ausgeführte und noch fehlende Prüfungen.

## Übersetzen und erklären

UI-Texte stehen in `src/i18n.js` und `src/experience-i18n.js` unter dem Browser-Arbeitsbereich; die native Anleitung in `app/ios/RTABMapApp/MeasurementGuide.json`. Videos verwenden `tools/scan-workspace/public/videos/scripts.json`. Schlüssel, Szenen-IDs, Einheiten und Platzhalter erhalten; Untertitel und Sprechertext zusammen ändern. Bei abgeschnittenen Texten hilft ein Screenshot.

Die Erklärvideos sind synthetische Animationen, keine echten Scanaufnahmen. Diese Kennzeichnung und die Grenzen von Messungen und Transportprüfungen müssen erhalten bleiben.

## Auf dem Gerät testen

iOS benötigt einen Mac mit passendem Xcode, nativen Bibliotheken und eigener Signierung. Die [Installationsanleitung](../APP-STORE-RELEASE.md) erklärt den Weg. Swift-Prüfungen stehen in `app/ios/Tests/run-scan-tracking-tests.sh` und `run-measurement-guide-tests.sh`; sie ersetzen keine Aufnahme auf dem iPhone.

Melde Revision, Gerät, iOS-Version, Scanmodus, Schritte und erwartetes/tatsächliches Ergebnis. Vergleiche Messungen mit einem Maßband und nenne beide Werte samt Einheit. Kennzeichne synthetische Daten. Prüfe bei passenden Änderungen Raum, Tor, Unterbrechung, Speichern/Öffnen, Fotos und Export. Veröffentliche keine privaten Räume, Personen oder Zugangsdaten ohne entsprechende Rechte.

## Einen PR einreichen

Fork erstellen, Branch von `kantura/main` anlegen, kleine Änderung umsetzen, prüfen und einen PR gegen **`lukashold/rtabmap:kantura/main`** öffnen. Beschreibe Problem, Ergebnis und Grenzen. Allgemeine RTAB-Map-Korrekturen können separat zu Upstream; KANTURA-Markenoberfläche und Browser gehören zunächst hierher. Bleibe sachlich und konstruktiv.

## Lizenzen beachten

Eigener Projektcode steht unter [BSD 3-Clause](../../LICENSE); Hinweise erhalten und nur Inhalte mit passenden Rechten beitragen. Native Abhängigkeiten sind gesondert zu prüfen: ORB-Octree ist bei aktiviertem `WITH_ORB_OCTREE` GPLv3, OpenCV aktiviert Nonfree, hinzu kommen konkrete SuiteSparse/g2o-Komponenten sowie statisches LASzip 2.0.1/libLAS. Neue Abhängigkeiten mit Version und Lizenz dokumentieren. Der [Release-Audit](../APP-STORE-RELEASE.md#native-abhängigkeiten-und-lizenzen) ist noch keine abgeschlossene App-Store-Freigabe.
