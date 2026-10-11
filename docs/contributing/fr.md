# Contribuer à KANTURA

KANTURA est un fork indépendant de RTAB-Map. Le développement et les pull requests ciblent [`lukashold/rtabmap:kantura/main`](https://github.com/lukashold/rtabmap/tree/kantura/main). Le [guide principal en anglais](../../CONTRIBUTING.md) décrit le processus complet.

## Commencer et développer

Consultez le [guide de l’espace de travail](../../tools/scan-workspace/README.md), le [comparatif fonctionnel](../KANTURA-FEATURES.md) et les [validations](../../tools/scan-workspace/VALIDATION.md). Recherchez d’abord dans les [issues du fork](https://github.com/lukashold/rtabmap/issues). Un bug reproductible, une amélioration ciblée, une traduction ou un essai sur appareil constituent de bons premiers apports.

Pour le navigateur, utilisez le dépôt complet, Node.js 24 et pnpm 11.25.0. Créez une branche depuis `kantura/main`. Dans `tools/scan-workspace` :

```sh
pnpm install --frozen-lockfile
pnpm test
pnpm check
pnpm build
pnpm start
```

Ouvrez `http://localhost:4173`. Le guide principal explique Corepack, Docker et le stockage serveur. Testez les changements de géométrie et de persistance ; pour une correction de texte, vérifiez la langue et la mise en page concernées. Indiquez les contrôles réellement exécutés et ceux encore impossibles.

## Traduire et expliquer

Les textes web sont dans `src/i18n.js` et `src/experience-i18n.js` de l’espace de travail ; le guide natif est dans `app/ios/RTABMapApp/MeasurementGuide.json`. Les vidéos utilisent `tools/scan-workspace/public/videos/scripts.json`. Préservez clés, identifiants de scènes, unités et variables. Modifiez sous-titres et narration ensemble. Joignez une capture si un texte est coupé.

Les vidéos sont des animations synthétiques, pas des scans réels. Conservez cette mention ainsi que les limites des mesures et des estimations de transport.

## Tester sur appareil

iOS nécessite un Mac, un Xcode compatible, les dépendances natives et votre signature. Consultez le [guide d’installation](../APP-STORE-RELEASE.md). Les scripts Swift `app/ios/Tests/run-scan-tracking-tests.sh` et `run-measurement-guide-tests.sh` ne remplacent pas une capture sur iPhone.

Indiquez révision, appareil, version iOS, mode, étapes et résultats attendu/observé. Comparez les mesures à un mètre ruban et fournissez valeurs et unités. Signalez les données synthétiques. Selon le changement, testez pièce, portail, interruption, sauvegarde/réouverture, photos et export. Ne publiez pas d’intérieurs privés, de personnes ou d’identifiants sans les droits nécessaires.

## Proposer une pull request

Créez votre fork et une branche issue de `kantura/main`, réalisez une modification ciblée, testez, puis ouvrez une PR vers **`lukashold/rtabmap:kantura/main`**. Décrivez problème, résultat et limites. Les correctifs RTAB-Map généraux peuvent être proposés séparément en amont ; l’interface et le navigateur KANTURA relèvent d’abord de ce fork. Échangez de façon constructive.

## Respecter les licences

Le code du projet utilise [BSD 3-Clause](../../LICENSE). Conservez les mentions et contribuez uniquement du contenu distribuable. Les dépendances natives ont leurs propres conditions : ORB-Octree activé par `WITH_ORB_OCTREE` est GPLv3, OpenCV active Nonfree, et les composants SuiteSparse/g2o ainsi que LASzip 2.0.1/libLAS statiques restent à auditer. Documentez version et licence des nouvelles dépendances. L’[audit de publication](../APP-STORE-RELEASE.md#native-abhängigkeiten-und-lizenzen) n’est pas une autorisation App Store achevée.
