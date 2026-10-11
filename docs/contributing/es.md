# Colaborar con KANTURA

KANTURA es un fork independiente de RTAB-Map. El desarrollo y las pull requests se dirigen a [`lukashold/rtabmap:kantura/main`](https://github.com/lukashold/rtabmap/tree/kantura/main). La [guía principal en inglés](../../CONTRIBUTING.md) explica el proceso completo.

## Empezar y desarrollar

Lee la [guía del espacio de trabajo](../../tools/scan-workspace/README.md), la [comparación de funciones](../KANTURA-FEATURES.md) y las [validaciones](../../tools/scan-workspace/VALIDATION.md). Busca primero en los [issues del fork](https://github.com/lukashold/rtabmap/issues). Puedes aportar errores reproducibles, mejoras pequeñas, traducciones o pruebas con un dispositivo real.

Para el navegador necesitas el repositorio completo, Node.js 24 y pnpm 11.25.0. Crea una rama desde `kantura/main`. En `tools/scan-workspace`:

```sh
pnpm install --frozen-lockfile
pnpm test
pnpm check
pnpm build
pnpm start
```

Abre `http://localhost:4173`. La guía principal describe Corepack, Docker y el almacenamiento del servidor. Comprueba cambios de geometría y persistencia con pruebas relevantes; para una corrección de texto, revisa el idioma y el diseño afectados. Indica qué comprobaste y qué sigue pendiente.

## Traducir y explicar

Los textos web están en `src/i18n.js` y `src/experience-i18n.js` del espacio de trabajo; la guía nativa, en `app/ios/RTABMapApp/MeasurementGuide.json`. Los vídeos usan `tools/scan-workspace/public/videos/scripts.json`. Conserva claves, identificadores de escena, unidades y variables. Modifica juntos subtítulos y narración. Adjunta una captura si se corta el texto.

Los vídeos son animaciones sintéticas, no escaneos reales. Mantén esa indicación y los límites de las mediciones y estimaciones de transporte.

## Probar en un dispositivo

iOS requiere un Mac, Xcode compatible, bibliotecas nativas y tu propia firma. Consulta la [guía de instalación](../APP-STORE-RELEASE.md). Los scripts Swift `app/ios/Tests/run-scan-tracking-tests.sh` y `run-measurement-guide-tests.sh` no sustituyen una captura en el iPhone.

Indica revisión, dispositivo, versión de iOS, modo, pasos y resultado esperado/real. Compara mediciones con una cinta métrica e incluye valores y unidades. Identifica los datos sintéticos. Según el cambio, prueba habitación, puerta exterior, interrupción, guardado/reapertura, fotos y exportación. No publiques interiores privados, personas o credenciales sin los derechos correspondientes.

## Enviar una pull request

Crea tu fork y una rama desde `kantura/main`, implementa una mejora concreta, compruébala y abre la PR contra **`lukashold/rtabmap:kantura/main`**. Explica problema, resultado y límites. Las correcciones generales de RTAB-Map pueden proponerse por separado al proyecto original; la interfaz y el navegador KANTURA corresponden primero a este fork. Mantén una colaboración respetuosa y constructiva.

## Respetar licencias

El código del proyecto usa [BSD 3-Clause](../../LICENSE). Conserva los avisos y aporta solo contenido que puedas distribuir. Las dependencias nativas necesitan revisión separada: ORB-Octree con `WITH_ORB_OCTREE` está bajo GPLv3, OpenCV activa Nonfree, y deben auditarse los componentes concretos de SuiteSparse/g2o y LASzip 2.0.1/libLAS estáticos. Documenta versión y licencia de las dependencias nuevas. La [auditoría de publicación](../APP-STORE-RELEASE.md#native-abhängigkeiten-und-lizenzen) no representa una autorización completa para el App Store.
