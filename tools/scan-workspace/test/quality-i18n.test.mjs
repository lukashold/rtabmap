import test from 'node:test';
import assert from 'node:assert/strict';
import { qualityDictionaries } from '../src/quality-i18n.js';
import { supportedLanguages } from '../locales/index.js';
test('capture media and quality descriptions are complete in all fifteen languages',()=>{
  assert.deepEqual(Object.keys(qualityDictionaries).sort(),[...supportedLanguages].sort());
  const expected=Object.keys(qualityDictionaries.en).sort();
  for(const code of supportedLanguages){assert.deepEqual(Object.keys(qualityDictionaries[code]).sort(),expected);assert.ok(Object.values(qualityDictionaries[code]).every(value=>typeof value==='string'&&value.length>0));}
});
