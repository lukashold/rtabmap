# KANTURA unabhängig im App Store veröffentlichen

Stand der Recherche: 11. Oktober 2026. **KANTURA** wird im Fork [lukashold/rtabmap, Zweig kantura/main](https://github.com/lukashold/rtabmap/tree/kantura/main) eigenständig weiterentwickelt. Eine Übernahme von PRs durch RTAB-Map ist dafür nicht nötig. Eine separate App-Store-Veröffentlichung braucht eine eigene App-Identität, ein Apple-Entwicklerkonto, einen korrekt lizenzierten und signierten Build sowie Apples Prüfung. Der jetzige Entwicklungszweig ist noch keine freigegebene Store-Version. Der neue Produktname ist eine Arbeitsmarke; Verfügbarkeit und Markenrechte sind vor der Store-Anmeldung abschließend zu prüfen.

## Zuerst auf das eigene iPhone

Die [offizielle RTAB-Map-App](https://apps.apple.com/app/rtab-map-3d-lidar-scanner/id1564774365) lässt sich sofort aus dem Store installieren. Sie enthält Änderungen dieses Forks erst, wenn das Upstream-Projekt sie veröffentlicht.

Für den Fork am MacBook mit Apple-Chip:

1. Xcode installieren, dessen SDK und Geräteunterstützung zur iOS-Version des iPhones passen. Die [RTAB-Map-iOS-Bauanleitung](https://github.com/introlab/rtabmap/wiki/Installation#ios) verwenden. Prebuilt-Bibliotheken müssen zur verwendeten Xcode-/SDK-Version und zum Mindest-iOS-Ziel passen; ein erfolgreicher Link mit Versionswarnungen belegt diese Kompatibilität nicht.
2. Den Fork auschecken, die nativen Abhängigkeiten und den RTAB-Map-Kern bauen und `app/ios/RTABMapApp.xcodeproj` öffnen. Der KANTURA-Zweig heißt `kantura/main`; der bisherige Upstream-PR bleibt separat auf `ios/scan-recovery-guidance`.
3. Unter **Xcode → Settings → Apple Accounts** anmelden. Im Target unter **Signing & Capabilities** das eigene Team und **Automatically manage signing** auswählen. Die vorgesehene eigene Bundle-ID ist `io.github.lukashold.kantura`. Diese muss im eigenen Apple-Team noch registriert beziehungsweise bei einer Kollision geändert werden; eine Quellcode-Einstellung ist keine Apple-Registrierung.
4. iPhone per Kabel verbinden, dem Mac vertrauen und als Zielgerät auswählen. Falls Xcode dazu auffordert, auf dem iPhone **Einstellungen → Datenschutz & Sicherheit → Entwicklermodus** aktivieren und den Neustart bestätigen. Dann mit **Run** installieren. Apples [Geräteanleitung](https://developer.apple.com/documentation/xcode/running-your-app-on-simulated-or-physical-devices) und [Entwicklermodus-Anleitung](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device) beschreiben die Schritte.

Ein kostenloses **Personal Team** reicht für begrenzte Tests auf eigenen Geräten. Die zugehörigen Provisioning-Profile laufen nach sieben Tagen ab; anschließend muss die App erneut über Xcode installiert werden. Es ersetzt keine TestFlight- oder Store-Veröffentlichung. Siehe [Apple Developer Account](https://developer.apple.com/help/account/basics/about-your-developer-account).

Ein unsigniertes IPA aus GitHub Actions ist ein Build-Artefakt. Es ist weder ein TestFlight-Link noch eine durch Antippen installierbare iPhone-App. Docker dient hier dem Desktop-Arbeitsbereich, nicht dem Signieren oder Installieren der iOS-App.

## TestFlight und App Store über dein Konto

1. **Apple Developer Program beitreten.** Apple nennt 99 USD pro Mitgliedschaftsjahr; der tatsächliche regionale Preis wird bei der Anmeldung angezeigt. Einzelperson oder Organisation bewusst wählen: Davon hängt die öffentlich angezeigte Verkäuferidentität ab. Siehe [Enrollment](https://developer.apple.com/programs/enroll/).
2. **Eigene Produktidentität festlegen.** Neuer Name, eigenes Icon und eigene Store-Texte; RTAB-Map als technische Grundlage mit Attribution nennen. Metarooms einfache Schrittfolge ist ein Vorbild, seine Marke, Screenshots, Texte und konkrete Oberfläche sind keine Veröffentlichungsassets. Apple prüft eigenständigen Nutzen und untersagt irreführende Nachahmung. Siehe [App Review 4.1](https://developer.apple.com/help/app-review/guideline-reference/4-1-prevent-copycat-rejection).
3. **App-ID und App-Store-Eintrag anlegen.** Die eigene Bundle-ID in Xcode und App Store Connect muss übereinstimmen. Unter **Apps → + → New App** Name, Sprache, Bundle-ID und SKU eintragen. Erforderliche Verträge muss der Account Holder selbst akzeptieren. Siehe [App-Eintrag anlegen](https://developer.apple.com/help/app-store-connect/create-an-app-record/add-a-new-app).
4. **Release-Kandidat signieren und hochladen.** Nach Behebung der unten aufgeführten Release-Punkte in Xcode **Product → Archive** und im Organizer **Distribute App → App Store Connect** verwenden. Versions- und Buildnummer erhöhen. Der Upload allein veröffentlicht nichts. Siehe [Apple Distributionsablauf](https://developer.apple.com/documentation/xcode/distributing-your-app-for-beta-testing-and-releases).
5. **TestFlight durchführen.** Zunächst intern am iPhone testen, dann bei Bedarf externe Tester einladen. Der erste extern verteilte Build braucht eine TestFlight-Prüfung. Tester installieren über Apples TestFlight-App; Upstream muss dafür nichts übernehmen. Siehe [TestFlight](https://developer.apple.com/testflight/).
6. **Store-Fassung einreichen.** Echte Screenshots, Beschreibung, Support-URL, öffentlich erreichbare Datenschutzerklärung, Altersfreigabe und Export-Compliance-Angaben hinterlegen. Den getesteten Build auswählen, Review-Hinweise zum LiDAR-Gerät und zum Messablauf ergänzen und einreichen. Keine garantierte Freigabezeit oder Zustimmung voraussetzen.

## Konkrete Release-Punkte in diesem Repository

### Native Abhängigkeiten und Lizenzen

RTAB-Map selbst verwendet eine BSD-Lizenz: geänderter Quellcode und Binärdateien dürfen unter den Bedingungen der [LICENSE](../LICENSE) weitergegeben werden. Das beseitigt nicht die Bedingungen der tatsächlich eingebundenen Bibliotheken.

Die Durchsicht von [install_deps.sh](../app/ios/RTABMapApp/install_deps.sh), [CMakeLists.txt](../CMakeLists.txt) und [License.plist](../app/ios/Settings.bundle/License.plist) zeigt vor der Veröffentlichung zu klärende Punkte:

| Fund | Konsequenz für den Release-Build |
| --- | --- |
| `WITH_ORB_OCTREE=ON`; die CMake-Zusammenfassung nennt GPLv3 | Für ein möglichst einfach verteilbares Profil deaktivieren oder die Lizenz- und Distributionsbedingungen ausdrücklich klären. Den Kern danach neu bauen. |
| OpenCV mit `OPENCV_ENABLE_NONFREE=ON` | Auf `OFF` umstellen und neu bauen, sofern keine ausdrücklich benötigten und geklärten Nonfree-Funktionen vorgesehen sind. Der Schalter ist keine Lizenzfreigabe. |
| SuiteSparse mit `cholmod;cxsparse;spqr` und statisch gebaute g2o-Abhängigkeiten | Lizenzen der konkreten eingebundenen Komponenten und Versionen prüfen; ein permissives Solver-Profil wählen oder erforderliche Rechte und Pflichten erfüllen. |
| LASzip 2.0.1 statisch und libLAS | Tatsächlich gelinkte Bestandteile und deren Weitergabebedingungen inventarisieren; nicht benötigten LAS/LAZ-Export gegebenenfalls aus dem Release-Profil entfernen. |
| Vorhandene iOS-Lizenzseite nennt nur einen Teil der installierten Bibliotheken | Vollständige Hinweise aus den tatsächlich verwendeten Versionen ergänzen, einschließlich Web-Abhängigkeiten für separat verteilte Web-Pakete. |

Die konkrete ORB-Implementierung trägt ihren GPLv3-Hinweis in [ORBextractor.cc](../corelib/src/opencv/ORBextractor.cc). SuiteSparse 7.6.1 dokumentiert unterschiedliche Lizenzen pro Komponente in seiner [Lizenzsammlung](https://github.com/DrTimothyAldenDavis/SuiteSparse/blob/v7.6.1/LICENSE.txt); für LASzip ist die [Lizenz der eingebauten Version 2.0.1](https://github.com/LASzip/LASzip/blob/2.0.1/COPYING) relevant. Die Lizenz einer späteren Version ist dafür kein Ersatz.

Dies ist eine Quellcode-Bestandsaufnahme, keine abgeschlossene juristische Freigabe. Insbesondere ist nicht geprüft, welche Symbole jedes statischen Archivs im finalen Executable verbleiben. Das Upstream-Prebuilt-Archiv deshalb nicht ungeprüft als eigenes Store-Release ausliefern. Ein neuer Build mit überprüftem Abhängigkeitsprofil, archiviertem CMake-Cache und vollständigen Lizenztexten macht die Entscheidung nachvollziehbar. Die vorhandene Upstream-Store-App belegt keine Lizenzfreigabe für unseren konkreten Fork-Build.

### Datenschutz und Cloud

Kamera und Tiefendaten können private Innenräume, Personen und Ortsdetails enthalten. Die Datenschutzerklärung muss den tatsächlichen Release erklären: lokale Speicherung, expliziter Export über iOS Dateien, direkte Web-Uploads zu Google/Microsoft sowie optionale selbst gehostete Speicherung. Die Betreiberidentität, Kontaktmöglichkeit, Aufbewahrung und Löschung müssen zu der realen Bereitstellung passen. Keine pauschale Angabe „keine Daten erhoben“ übernehmen, bevor App, Bibliotheken und Serververhalten geprüft sind. App-Store-Datenschutzangaben müssen auch relevante Drittanbieter berücksichtigen. Siehe [App Privacy](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy/).

Vor dem Upload die tatsächlichen Required-Reason-APIs und SDKs prüfen, gültige `PrivacyInfo.xcprivacy`-Dateien in die richtigen Bundles aufnehmen und Xcodes Datenschutzbericht kontrollieren. Ein erfundener pauschaler Manifest-Grund genügt nicht. Siehe [Required Reason APIs](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api) und [SDK-Anforderungen](https://developer.apple.com/support/third-party-SDK-requirements/).

Die Web-OAuth-Client-IDs sind öffentlich; sie sind keine Geheimnisse und keine Apple-Signierschlüssel. Die [Cloud-Einrichtung](../tools/scan-workspace/README.md) beschreibt getrennte Microsoft- und Google-Registrierungen. Die native iOS-Dateiauswahl verwendet zunächst die bereits angemeldeten File-Provider-Apps. Eine Registrierung und echte Anmelde-/Uploadtests mit den vorgesehenen Konten stehen vor einer Freigabe noch aus.

### Gerät und Produktqualität

Am iPhone 17 Pro mindestens einen ganzen Raum und ein Tor aufnehmen, Texturen und Geometrie prüfen, mehrere Abstände mit dem Maßband vergleichen, speichern/öffnen/exportieren und Hintergrundwechsel, Trackingverlust, Speicherknappheit sowie lange Scans prüfen. Messungen und Flächen nach einem Projekt-Roundtrip am Computer vergleichen. Die fünf Übersetzungen, große Schrift und VoiceOver auf echtem Gerät testen. Marketing darf derzeit weder garantierte Millimetergenauigkeit noch automatische Grundrisse oder vollständige Polycam/Metaroom-Funktionsgleichheit behaupten.

Der Fork kann währenddessen unabhängig weiterentwickelt und getestet werden. Der nächste konkrete Vertriebsschritt ist ein korrekt signierter, getesteter TestFlight-Kandidat unter dem eigenen Konto. Die noch ausstehenden Kontoentscheidungen, Verträge, Gebühren, Markenwahl und abschließende Einreichung bleiben beim Kontoinhaber.
