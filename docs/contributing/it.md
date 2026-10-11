# Contribuire a KANTURA

KANTURA è un fork indipendente di RTAB-Map. Sviluppo e pull request usano [`lukashold/rtabmap:kantura/main`](https://github.com/lukashold/rtabmap/tree/kantura/main). La [guida principale in inglese](../../CONTRIBUTING.md) descrive il processo completo.

## Iniziare e sviluppare

Leggi la [guida allo spazio di lavoro](../../tools/scan-workspace/README.md), il [confronto delle funzioni](../KANTURA-FEATURES.md) e le [validazioni](../../tools/scan-workspace/VALIDATION.md). Cerca prima nelle [issue del fork](https://github.com/lukashold/rtabmap/issues). Sono utili bug riproducibili, piccole migliorie, traduzioni e prove su dispositivi reali.

Per il browser servono repository completo, Node.js 24 e pnpm 11.25.0. Crea un ramo da `kantura/main`. In `tools/scan-workspace`:

```sh
pnpm install --frozen-lockfile
pnpm test
pnpm check
pnpm build
pnpm start
```

Apri `http://localhost:4173`. La guida principale spiega Corepack, Docker e archivio server. Verifica modifiche a geometria e persistenza con test pertinenti; per correzioni di testo controlla lingua e layout interessati. Indica le verifiche eseguite e quelle ancora mancanti.

## Tradurre e spiegare

I testi web sono in `src/i18n.js` e `src/experience-i18n.js` nello spazio di lavoro; la guida nativa è in `app/ios/RTABMapApp/MeasurementGuide.json`. I video usano `tools/scan-workspace/public/videos/scripts.json`. Mantieni chiavi, ID delle scene, unità e variabili. Modifica insieme sottotitoli e narrazione. Per testi tagliati allega uno screenshot.

I video sono animazioni sintetiche, non scansioni reali. Conserva questa indicazione e i limiti delle misurazioni e delle stime di trasporto.

## Provare sul dispositivo

iOS richiede un Mac, Xcode compatibile, dipendenze native e la tua firma. Consulta la [guida d’installazione](../APP-STORE-RELEASE.md). Gli script Swift `app/ios/Tests/run-scan-tracking-tests.sh` e `run-measurement-guide-tests.sh` non sostituiscono una scansione su iPhone.

Indica revisione, dispositivo, versione iOS, modalità, passaggi e risultato atteso/effettivo. Confronta le misure con un metro e riporta valori e unità. Segnala dati sintetici. In base alla modifica, prova stanza, cancello, interruzione, salvataggio/riapertura, foto ed esportazione. Non pubblicare ambienti privati, persone o credenziali senza i diritti necessari.

## Inviare una pull request

Crea il tuo fork e un ramo da `kantura/main`, realizza una modifica mirata, verificala e apri la PR verso **`lukashold/rtabmap:kantura/main`**. Descrivi problema, risultato e limiti. Le correzioni generali di RTAB-Map possono essere proposte separatamente al progetto originale; interfaccia e browser KANTURA riguardano prima questo fork. Collabora in modo rispettoso e costruttivo.

## Rispettare le licenze

Il codice del progetto usa [BSD 3-Clause](../../LICENSE). Conserva gli avvisi e contribuisci solo contenuti distribuibili. Le dipendenze native vanno verificate separatamente: ORB-Octree con `WITH_ORB_OCTREE` è GPLv3, OpenCV abilita Nonfree, e occorre controllare i componenti SuiteSparse/g2o e LASzip 2.0.1/libLAS statici effettivamente usati. Documenta versione e licenza delle nuove dipendenze. L’[audit di distribuzione](../APP-STORE-RELEASE.md#native-abhängigkeiten-und-lizenzen) non costituisce una completa approvazione per l’App Store.
