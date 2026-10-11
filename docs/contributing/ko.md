# KANTURA에 기여하기

KANTURA는 RTAB-Map의 독립 포크입니다. 개발과 풀 리퀘스트는 [`lukashold/rtabmap:kantura/main`](https://github.com/lukashold/rtabmap/tree/kantura/main)을 대상으로 합니다. 전체 절차는 [영문 기여 안내](../../CONTRIBUTING.md)를 참고하세요.

## 시작하기

[작업 공간 안내](../../tools/scan-workspace/README.md), [기능 비교](../KANTURA-FEATURES.md), [검증 기록](../../tools/scan-workspace/VALIDATION.md)을 읽어 보세요. 보고하기 전에 [기존 이슈](https://github.com/lukashold/rtabmap/issues)를 검색하세요. 재현 가능한 오류, 작은 사용성 개선, 번역, 실제 기기 테스트 모두 도움이 됩니다.

브라우저 개발에는 전체 저장소, Node.js 24, pnpm 11.25.0이 필요합니다. `kantura/main`에서 작업 브랜치를 만들고 `tools/scan-workspace`에서 실행하세요.

```sh
pnpm install --frozen-lockfile
pnpm test
pnpm check
pnpm build
pnpm start
```

`http://localhost:4173`을 여세요. Corepack, Docker, 서버 저장 설정은 기본 안내에 있습니다. 형상 계산, 아카이브, 데이터 저장 변경에는 의미 있는 검증을 추가하세요. 문구 수정은 해당 언어와 화면 배치를 확인하세요. 실제로 실행한 검증과 아직 실행하지 못한 검증을 구분해 기록하세요.

## 번역과 사용 안내

한국어 팩은 `tools/scan-workspace/locales/ko.json`에 있습니다. 네이티브 안내인 `app/ios/RTABMapApp/MeasurementGuide.json`, 영상 대본인 `tools/scan-workspace/public/videos/scripts.json`과도 내용이 일치하는지 확인하세요. 키, 장면 ID, 아이콘 ID, 단위, 치환 기호를 유지하세요. 자막과 음성 내용을 함께 수정하고 글자가 잘리면 화면 캡처를 첨부하세요.

영상은 실제 스캔이 아닌 합성 애니메이션입니다. 이 설명을 유지하세요. RoomPlan은 실내용이며 대문과 야외 물체에는 LiDAR 스캔을 사용합니다. 별도로 촬영한 방은 자동으로 정렬되지 않습니다. 기준 비교가 스캔 전체의 정확도를 보증하지 않으며, 운반 추정도 실제 경로의 모든 충돌을 검사하지 않습니다.

## iPhone에서 확인하기

iOS 빌드와 서명에는 Mac, 호환되는 Xcode, 네이티브 의존성이 필요합니다. [설치 및 출시 안내](../APP-STORE-RELEASE.md)를 참고하세요. `app/ios/Tests/run-scan-tracking-tests.sh`와 `run-measurement-guide-tests.sh`는 실제 기기 촬영을 대신하지 않습니다.

보고서에는 리비전, 기기, iOS 버전, 모드, 재현 단계, 기대한 결과와 실제 결과를 기록하세요. 줄자와 비교할 때는 양쪽 값, 측정 방법, 단위를 적고 합성 자료인지 실측 자료인지 명시하세요. 변경에 따라 방, 대문, 중단, 저장과 다시 열기, 사진, 내보내기를 확인하세요. 필요한 권한 없이 사적인 실내, 사람, 주소, 키, 계정 정보를 공개하지 마세요.

## 풀 리퀘스트와 라이선스

포크와 `kantura/main` 기반 브랜치를 만들고 범위를 좁힌 변경을 **`lukashold/rtabmap:kantura/main`**에 제안하세요. 문제, 최종 동작, 검증, 제한 사항을 설명하세요. 일반적인 RTAB-Map 수정은 원본 프로젝트에 별도로 제안할 수 있습니다. KANTURA 화면과 작업 공간은 이 포크에서 다룹니다. 건설적으로 의견을 나누세요.

저작권 고지와 [BSD 3-Clause 라이선스](../../LICENSE)를 유지하세요. 네이티브 의존성에는 별도 조건이 있으므로 [출시 감사 내용](../APP-STORE-RELEASE.md#native-abhängigkeiten-und-lizenzen)을 확인하세요. 새 의존성의 버전, 라이선스, 목적을 기록하세요. 비밀 정보, 서명 인증서, 배포 권한 없는 자료를 추가하지 마세요. 저장소와 테스트 통과만으로 App Store 출시 준비가 끝난 것은 아닙니다.
