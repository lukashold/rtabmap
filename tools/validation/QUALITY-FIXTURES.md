# Two independent synthetic reconstruction fixtures

Keep both cases. A successful easier/distinct-texture run does not replace the difficult periodic fixture or establish real scan accuracy.

```sh
# Existing difficult case: unchanged generator and outputs.
python tools/validation/procedural-capture.py --output periodic.zip --truth periodic-truth.json --size 384 --count 32
# Additional distinct-texture case: same geometry, cameras and image size.
python tools/validation/procedural-distinct.py --output distinct.zip --truth distinct-truth.json --size 384 --count 32
```

Feed only the photo ZIP into the reconstruction engine. The ground-truth JSON stays outside the archive and is used only afterwards by `reconstruction-quality.py`. Run the same engine revision and settings for both inputs. Identify each fixture explicitly in the resulting report; never average them into a single improved score.

The new fixture uses deterministic original geometric marks with independent layouts on all six cube faces, plus a static world-coordinate noise texture on the ground. It has no shared white square-border grid and no repeated checkerboard floor. The camera centres, rotations, cube bounds, floor height and focal length match the old 32-view/384-pixel reference exactly. JPEG bytes and ZIP metadata are deterministic for the pinned Pillow/NumPy environment. No external assets, learned generator or truth camera input is used by the reconstruction engine.

Tests verify distinct opposing-face layouts, nonrepetition of the ground under the old half-/one-/two-/four-unit shifts, actual rendered opposing-view JPEG differences, repeatable archive bytes and absence of camera truth in the input manifest. These are **fixture checks, not reconstruction success**. Retain actual reconstruction failures and quality metrics after running each dataset.

## Legacy baseline remains unchanged

The previously evaluated 32-camera result has these four values in synthetic scene units (cube side 2):

| Metric | Existing value |
| --- | --- |
| `cameraPositionRMSE` | `3.7868876970054273` |
| `cameraPositionP95` | `4.2006735602448275` |
| `cameraRotationMedianDegrees` | `86.06900374959443` |
| `cameraRotationP95Degrees` | `179.59316083666428` |

Adding the diagnostic below leaves all four values exactly unchanged. The old generator and stored baseline JSON have not been modified. This large error is retained as a failed quality case; it is not made acceptable by a successful engine exit or by producing downloadable files.

## Camera coincidence diagnostic

The evaluator now also reports `cameraCoincidence`. It compares exact known opposing synthetic-view names. The new truth file declares those pairs explicitly; the unchanged legacy orbit uses its original ordered `Images/view-NNN.jpg` → `frame_NNNNN.jpg` names. Engine image IDs and output order do not determine correspondence.

Each pair's estimated camera separation is divided by the median nonzero pairwise separation across registered camera centres. `coincidentPairs` lists opposing viewpoints whose normalized distance is below `0.01`; `coincidentPairCount` and `opposingPairsChecked` make missing/partial registration visible. This dimensionless collapse threshold is invariant to the arbitrary SfM scale and is **not a physical accuracy tolerance**. The old result contains 15 flagged pairs out of 16 known opposing pairs.

Run fixture/evaluator tests with:

```sh
python -m unittest discover -s tools/validation/test -v
```

On 12 October 2026, eight local tests passed. A separate read-only review roundtripped the real 32 ground-truth poses through a known similarity transform and synthetic COLMAP binary poses, recovering camera centres within floating-point precision. It confirmed that the old large residual is not caused by a camera convention or alignment calculation error. Docker reconstruction and any measured improvement on the new fixture must be recorded separately after they actually run.
