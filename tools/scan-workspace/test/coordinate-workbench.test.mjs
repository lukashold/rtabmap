import test from 'node:test';
import assert from 'node:assert/strict';
import { coordinateStrings, coordinateText, coordinateLanguage } from '../src/coordinate-i18n.js';
import {
  COORDINATE_INPUT_LIMIT, parseCoordinateJSON, parseLandmarkField, parseCoordinateTolerance, parseGeodeticField,
  exportCoordinateAnchors, calculateRegistrationCandidate, calculateGPSCandidate, exportCoordinateCandidate,
} from '../src/coordinate-workbench.js';

const source = [[0,0,0],[2,0,0],[0,0,3],[0,1,0]];
const target = source.map(([x,y,z]) => [x+10,y+1,z+3]);
const sourceText = JSON.stringify(source), targetText = JSON.stringify(target);
const sourceFrame = { kind: 'viewer-centered-y-up', units: 'm', roomId: 'room-1', name: 'Room A', floor: '1',
  modelToFrame: [2,0,0,0,0,2,0,0,0,0,2,0,-4,-2,-6,1] };
const point = { latitude: 0, longitude: 0.00001, height: 2, verticalDatum: 'ellipsoidal' };
const origin = { latitude: 0, longitude: 0, height: 0, verticalDatum: 'ellipsoidal' };
const errorCode = code => error => error.code === code;

test('fifteen complete coordinate dictionaries expose both text APIs and regional language aliases', () => {
  const languages = ['de','en','fr','es','it','zh-Hans','pt','ar','hi','bn','ru','ja','ko','id','tr'];
  assert.deepEqual(Object.keys(coordinateStrings).sort(), languages.sort());
  for (const [language, dictionary] of Object.entries(coordinateStrings)) {
    assert.deepEqual(Object.keys(dictionary), Object.keys(coordinateStrings.en));
    assert.ok(Object.values(dictionary).every(value => typeof value === 'string' && value.trim()));
    assert.equal(coordinateText(language), dictionary);
    assert.equal(coordinateText(language, 'title'), dictionary.title);
    assert.ok(Object.isFrozen(dictionary));
    for (const key of ['anchorHelp','prefillHelp','gpsHelp','resultHelp','exampleNotice','downloadAnchors']) {
      if (language !== 'en') assert.notEqual(dictionary[key], coordinateStrings.en[key], `${language}.${key}`);
    }
    assert.match(dictionary.anchorHelp, /A\/B\/C/);
    assert.match(dictionary.gpsHelp, /ellipsoidal/);
    assert.match(dictionary.gpsHelp, /horizontalMeters/);
    assert.match(dictionary.gpsHelp, /verticalMeters/);
  }
  for (const [input, expected] of [['de-AT','de'],['EN_gb','en'],['zh_TW','zh-Hans'],['ar-EG','ar'],['pt-BR','pt'],['in_ID','id'],['unknown','en']]) assert.equal(coordinateLanguage(input), expected);
});

test('JSON reads reject malformed and byte-oversized inputs before accepting points', () => {
  assert.throws(() => parseCoordinateJSON('{'), errorCode('jsonError'));
  assert.throws(() => parseCoordinateJSON(null), errorCode('jsonError'));
  assert.throws(() => parseCoordinateJSON(' '.repeat(COORDINATE_INPUT_LIMIT+1)), errorCode('sizeError'));
  // UTF-8 bytes, not just JS character count, define the bound.
  assert.throws(() => parseCoordinateJSON(JSON.stringify('界'.repeat(22000))), errorCode('sizeError'));
  for (const value of [[], [[1,2,3],[4,5,6]], [[1,2],[3,4],[5,6]], [[1,2,3],[4,5,6],[7,8,'9']], Array.from({ length: 101 }, () => [1,2,3])]) {
    assert.throws(() => parseLandmarkField(JSON.stringify(value)), errorCode('pairsError'));
  }
  assert.throws(() => parseLandmarkField('[[1e400,0,0],[1,2,3],[4,5,6]]'), errorCode('pairsError'));
});

test('tolerance has no implicit value and accepts a decimal comma without numeric coercion', () => {
  assert.equal(parseCoordinateTolerance(' '), undefined);
  assert.equal(parseCoordinateTolerance('0,025'), .025);
  assert.equal(parseCoordinateTolerance('1e-3'), .001);
  assert.equal(parseCoordinateTolerance('0'), 0);
  for (const invalid of ['-1','NaN','Infinity','0x10','1,2,3','1m','1e400','1e10']) assert.throws(() => parseCoordinateTolerance(invalid), errorCode('toleranceError'));
});

test('registration computes a detached candidate; fitting does not validate measurement accuracy', () => {
  const candidate = calculateRegistrationCandidate({ sourceText, targetText, sourceFrame, sourceLabels: ['A','B','C','D'], inputProvenance: 'provided-project-anchors' });
  assert.equal(candidate.result.accepted, null);
  assert.equal(candidate.result.status, 'needs-review');
  assert.equal(candidate.inputs.toleranceMeters, null);
  assert.ok(candidate.result.rmse < 1e-12);
  assert.deepEqual(candidate.inputs.source.points, source, 'sourceFrame matrix must not be applied a second time');
  assert.deepEqual(candidate.inputs.source.frame, sourceFrame);
  assert.deepEqual(candidate.inputs.target.frame, { kind: 'user-entered-unknown', units: 'm' });
  const decoded = JSON.parse(exportCoordinateCandidate(candidate));
  assert.equal(decoded.source, 'candidate');
  assert.equal(decoded.metricAccuracyValidated, false);
  assert.equal(decoded.physicalAccuracyValidated, false);
  assert.equal(decoded.appliedToModel, false);
  assert.equal(decoded.automaticBuildingMerge, false);
  assert.equal(decoded.inputProvenance, 'provided-project-anchors');
  assert.deepEqual(source, JSON.parse(sourceText));
});

test('explicit tolerance changes only fit acceptance; incorrect count and degenerate points fail', () => {
  const accepted = calculateRegistrationCandidate({ sourceText, targetText, toleranceText: '0,001' });
  assert.equal(accepted.result.accepted, true);
  assert.equal(accepted.metricAccuracyValidated, false);
  const wrongTarget = target.map(row => [...row]); wrongTarget[3][1] += 1;
  const rejected = calculateRegistrationCandidate({ sourceText, targetText: JSON.stringify(wrongTarget), toleranceText: '.01' });
  assert.equal(rejected.result.accepted, false);
  assert.ok(rejected.result.maxResidual > .01);
  assert.throws(() => calculateRegistrationCandidate({ sourceText, targetText: JSON.stringify(target.slice(0,3)) }), errorCode('pairsError'));
  assert.throws(() => calculateRegistrationCandidate({ sourceText: '[[0,0,0],[1,0,0],[2,0,0]]', targetText: '[[0,0,0],[1,0,0],[2,0,0]]' }), errorCode('degenerateLandmarks'));
});

test('anchor transfer preserves named frame and ordering without guessing correspondence', () => {
  const labels = ['C','A','<script>test</script>','B'];
  const text = exportCoordinateAnchors({ sourcePoints: target, sourceFrame, sourceLabels: labels });
  const parsed = parseLandmarkField(text);
  assert.deepEqual(parsed.points, target);
  assert.deepEqual(parsed.labels, labels);
  assert.deepEqual(parsed.frame, sourceFrame);
  const candidate = calculateRegistrationCandidate({ sourceText, targetText: text, sourceLabels: ['A','B','C','D'] });
  assert.deepEqual(candidate.inputs.target.labels, labels, 'labels must not reorder geometric points');
  assert.deepEqual(candidate.inputs.target.frame, sourceFrame);
  assert.equal(candidate.result.accepted, null);
  assert.throws(() => exportCoordinateAnchors({ sourcePoints: source, sourceLabels: ['A'] }), errorCode('pairsError'));
  assert.throws(() => exportCoordinateAnchors({ sourcePoints: source, sourceFrame: { ...sourceFrame, units: 'ft' } }), errorCode('pairsError'));
  assert.throws(() => exportCoordinateAnchors({ sourcePoints: source, sourceFrame: { ...sourceFrame, modelToFrame: [1,2] } }), errorCode('pairsError'));
  assert.throws(() => parseLandmarkField(text.replace('"metricAccuracyValidated": false', '"metricAccuracyValidated": true')), errorCode('pairsError'));
});

test('GPS needs explicit origin and ellipsoidal datum, while unknown uncertainty stays unknown', () => {
  assert.throws(() => parseGeodeticField(JSON.stringify({ latitude: 0, longitude: 0, height: 0 })), errorCode('unsupportedVerticalDatum'));
  assert.throws(() => parseGeodeticField(JSON.stringify({ ...point, verticalDatum: 'MSL' })), errorCode('unsupportedVerticalDatum'));
  assert.throws(() => parseGeodeticField(JSON.stringify({ ...point, uncertainty: { horizontalMeters: -1 } })), errorCode('invalidUncertainty'));
  assert.throws(() => calculateGPSCandidate({ pointText: JSON.stringify(point), originText: '' }), errorCode('jsonError'));
  const result = calculateGPSCandidate({ pointText: JSON.stringify(point), originText: JSON.stringify(origin) });
  assert.equal(result.inputs.origin.uncertainty, undefined);
  assert.equal(result.inputs.point.uncertainty, undefined);
  assert.ok(result.result.position[0] > 1 && result.result.position[0] < 1.2);
  assert.ok(Math.abs(result.result.position[1] - 2) < .001);
  assert.equal(result.result.metricAccuracyValidated, false);
  assert.equal(result.appliedToModel, false);
  const partial = parseGeodeticField(JSON.stringify({ ...point, uncertainty: { horizontalMeters: 4 } }));
  assert.deepEqual(partial.uncertainty, { horizontalMeters: 4 });
  assert.equal(partial.uncertainty.verticalMeters, undefined);
});

test('synthetic provenance survives anchor export, paste, candidate calculation and re-export on either side', () => {
  const syntheticSource = exportCoordinateAnchors({ sourcePoints: source, sourceFrame, sourceLabels: ['A','B','C','D'], inputProvenance: 'synthetic-example' });
  const syntheticTarget = exportCoordinateAnchors({ sourcePoints: target, sourceFrame, inputProvenance: 'synthetic-example' });
  for (const [left, right, syntheticSide] of [[syntheticSource, targetText, 'source'], [sourceText, syntheticTarget, 'target']]) {
    const candidate = calculateRegistrationCandidate({ sourceText: left, targetText: right, inputProvenance: 'provided-project-anchors' });
    assert.equal(candidate.inputProvenance, 'synthetic-example');
    assert.equal(candidate.inputs[syntheticSide].inputProvenance, 'synthetic-example');
    assert.deepEqual(candidate.inputs[syntheticSide].frame, sourceFrame);
    assert.equal(JSON.parse(exportCoordinateCandidate(candidate)).inputProvenance, 'synthetic-example');
  }
  const partlyEdited = calculateRegistrationCandidate({ sourceText, targetText, sourceInputProvenance: 'manual-input', targetInputProvenance: 'synthetic-example' });
  assert.equal(partlyEdited.inputProvenance, 'synthetic-example');
  assert.equal(partlyEdited.inputs.source.inputProvenance, 'manual-input');
  assert.equal(partlyEdited.inputs.target.inputProvenance, 'synthetic-example');
});

test('imported coordinate frames require an affine column-major matrix', () => {
  for (const index of [3,7,11,15]) {
    const perspective = [...sourceFrame.modelToFrame]; perspective[index] = .1;
    assert.throws(() => exportCoordinateAnchors({ sourcePoints: source, sourceFrame: { ...sourceFrame, modelToFrame: perspective } }), errorCode('pairsError'));
  }
  const frameCopy = JSON.parse(exportCoordinateAnchors({ sourcePoints: source, sourceFrame })).frame;
  assert.deepEqual(frameCopy.modelToFrame, sourceFrame.modelToFrame);
});

test('candidate serialization rejects invented certification and nonfinite results', () => {
  const candidate = calculateRegistrationCandidate({ sourceText, targetText, inputProvenance: 'synthetic-example' });
  assert.equal(JSON.parse(exportCoordinateCandidate(candidate)).inputProvenance, 'synthetic-example');
  for (const key of ['metricAccuracyValidated','physicalAccuracyValidated','appliedToModel','automaticBuildingMerge']) {
    assert.throws(() => exportCoordinateCandidate({ ...candidate, [key]: true }), errorCode('geometryError'));
  }
  assert.throws(() => exportCoordinateCandidate({ ...candidate, result: { ...candidate.result, rmse: Infinity } }), errorCode('geometryError'));
  assert.throws(() => calculateRegistrationCandidate({ sourceText, targetText, inputProvenance: 'survey-certified' }), errorCode('pairsError'));
});
