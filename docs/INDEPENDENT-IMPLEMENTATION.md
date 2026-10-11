# Independent implementation and source provenance

Kantura is an independently developed fork of the open-source RTAB-Map project.
Polycam and MetaRoom are references for publicly described user workflows and
capabilities. Kantura is not a fork of either product and does not include their
implementation, assets, application packages or private services.

## Meaning of "clean room" in this project

Our current work uses public product documentation to write requirements, then
implements those requirements in Kantura with our own code and tests. This is
independent implementation. It is not a claim that a formally separated,
audited clean-room engineering process has been completed: the contributors
writing requirements and implementation are not two isolated teams.

Nor is Kantura an implementation from an empty codebase. RTAB-Map provides the
existing scanner, mapping and reconstruction foundation. Apple RoomPlan provides
native indoor recognition. The browser uses Three.js and other declared packages.
Their origins, licenses and attribution must remain visible. Existing notices
and the repository's [release dependency review](APP-STORE-RELEASE.md) still apply.

## Contribution rules

1. Describe a user-visible capability from a public source or a user request.
   Link the source and record the observation date. Do not treat marketing
   accuracy statements as our own measured performance.
2. Write an observable requirement independently of another product's internals.
   For example: "A user can choose a model corner within a screen-space radius,
   see the proposed point and turn assistance off."
3. Implement with original project code, documented platform APIs or explicitly
   identified open-source dependencies. Identify new dependency licenses.
4. Use synthetic geometry and our own captures for tests. Do not copy proprietary
   scan datasets, product illustrations, tutorial recordings or interface assets.
5. Keep algorithms, expected inputs, coordinate conventions and limits reviewable.
   Save real selected geometry, not a display-only corrected number.
6. Record automated checks separately from real-device, account and beginner tests.
   A button, roadmap entry or successful compile is not evidence of a working
   capture/reconstruction pipeline.

Do not submit decompiled application code, recovered private APIs, extracted
models/weights or proprietary implementation material as contributions. A new
publicly licensed component needs its own provenance and dependency review.

## Initial implementation trace

| Requirement | Source of requirement | Kantura implementation and acceptance |
| --- | --- | --- |
| Indoor wall width and height are understandable | User's request to measure walls; Apple's public RoomPlan surface dimensions | Existing native RoomPlan export/import. The next UI revision labels the dimensions; actual capture still requires a signed iPhone test. |
| Point selection can assist with corners and edges | Public [Polycam measurement guide](https://learn.poly.cam/hc/en-us/articles/29647317758100-How-to-Measure-Your-Captures), plus our measurement usability review | Optional browser assistance using mesh boundaries/sharp edges, explicit selected-point feedback and synthetic geometry tests. It is not Polycam's algorithm. |
| Rooms and outdoor objects have distinct capture guidance | User's room/gate requirements and public platform capabilities | Indoor RoomPlan capture and RTAB-Map textured capture are separate workflows. No shared camera poses or merged model are implied. |
| Multi-floor projects preserve each room | User's apartment/house requirement | Existing room archive and library; individual room origins remain separate. Connected building geometry needs explicit transforms and new acceptance tests. |

The [Polycam capability roadmap](POLYCAM-ROADMAP.md) records the broader scope and
unfinished functions. Its entries must not be presented as released capabilities.
