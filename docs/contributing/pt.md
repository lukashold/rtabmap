# Contribuir para o KANTURA

O KANTURA é uma derivação independente do RTAB-Map. O desenvolvimento e os pedidos de integração usam [`lukashold/rtabmap:kantura/main`](https://github.com/lukashold/rtabmap/tree/kantura/main). O [guia principal em inglês](../../CONTRIBUTING.md) descreve o processo completo.

## Começar e desenvolver

Consulte o [guia do espaço de trabalho](../../tools/scan-workspace/README.md), a [comparação de funcionalidades](../KANTURA-FEATURES.md) e o [registo de validação](../../tools/scan-workspace/VALIDATION.md). Pesquise primeiro nos [problemas do projeto](https://github.com/lukashold/rtabmap/issues). Um erro reproduzível, uma melhoria específica, uma tradução ou um teste num dispositivo real são bons primeiros contributos.

Para desenvolver a versão para navegador, use o repositório completo, Node.js 24 e pnpm 11.25.0. Crie uma ramificação a partir de `kantura/main`. Em `tools/scan-workspace`, execute:

```sh
pnpm install --frozen-lockfile
pnpm test
pnpm check
pnpm build
pnpm start
```

Abra `http://localhost:4173`. O guia principal explica Corepack, Docker e armazenamento no servidor. Teste as alterações à geometria e à persistência dos dados. Para corrigir texto, verifique o idioma e a apresentação. Registe as verificações realmente executadas e as que não conseguiu executar.

## Traduzir e explicar

O pacote português está em `tools/scan-workspace/locales/pt.json`. Preserve as chaves, os identificadores de cenas e ícones, as unidades e os campos variáveis. Mantenha as legendas e a narração coerentes. Verifique também a integração no guia nativo e na interface; uma tradução do guia não prova que todos os ecrãs nativos estejam traduzidos. Inclua uma captura de ecrã quando o texto ficar cortado.

Os vídeos são animações sintéticas, não digitalizações reais. Preserve essa indicação, a distinção entre RoomPlan e LiDAR e as limitações das medições e das estimativas de transporte. As divisões têm origens independentes e não são alinhadas automaticamente.

## Testar num dispositivo

O iOS exige um Mac, Xcode compatível, dependências nativas e assinatura própria. Consulte o [guia de instalação](../APP-STORE-RELEASE.md). Os testes Swift em `app/ios/Tests/run-scan-tracking-tests.sh` e `run-measurement-guide-tests.sh` não substituem uma captura num iPhone.

Indique a revisão, o dispositivo, a versão do iOS, o modo, os passos e os resultados esperado e observado. Compare as medições com fita métrica e indique valores e unidades. Identifique os dados sintéticos. Conforme a alteração, teste divisão, portão, interrupção, guardar/reabrir, fotografias e exportação. Partilhe apenas exemplos autorizados, sem interiores privados, pessoas ou credenciais expostos indevidamente.

## Propor alterações e respeitar licenças

Crie a sua derivação e uma ramificação a partir de `kantura/main`, faça uma alteração focada, teste e abra um pedido de integração para **`lukashold/rtabmap:kantura/main`**. Explique o problema, o resultado e as limitações. As correções gerais do RTAB-Map podem ser propostas separadamente ao projeto original; as funcionalidades específicas do KANTURA pertencem primeiro a esta derivação.

O código do projeto usa a licença [BSD 3-Clause](../../LICENSE). Preserve as atribuições e contribua apenas com conteúdo que possa distribuir. As dependências nativas têm condições próprias: ORB-Octree ativado por `WITH_ORB_OCTREE` usa GPLv3; OpenCV ativa Nonfree; os componentes SuiteSparse/g2o e LASzip 2.0.1/libLAS ligados estaticamente continuam sujeitos a auditoria. Documente a versão e a licença de novas dependências. A [auditoria de publicação](../APP-STORE-RELEASE.md#native-abhängigkeiten-und-lizenzen) não constitui uma aprovação concluída para a App Store.
