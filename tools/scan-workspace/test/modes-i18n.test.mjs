import test from 'node:test';
import assert from 'node:assert/strict';
import { modesStrings, modesText } from '../src/modes-i18n.js';

test('all fifteen capture-mode dictionaries include translated warnings and provenance', () => {
  const languages = ['de', 'en', 'fr', 'es', 'it', 'zh-Hans', 'pt', 'ar', 'hi', 'bn', 'ru', 'ja', 'ko', 'id', 'tr'];
  const keys = ['panoramaJob', 'generatedJob', 'imageInputHelp', 'foregroundReady', 'generatedWarning', 'panoramaPhotosHelp', 'generatedSource'];
  assert.deepEqual(Object.keys(modesStrings).sort(), languages.sort());
  for (const [language, dictionary] of Object.entries(modesStrings)) {
    assert.deepEqual(Object.keys(dictionary), keys);
    assert.ok(Object.values(dictionary).every(value => typeof value === 'string' && value.trim()));
    assert.match(dictionary.imageInputHelp, /JPEG/);
    assert.match(dictionary.imageInputHelp, /PNG/);
    assert.match(dictionary.imageInputHelp, /20/);
    if (language !== 'en') for (const key of keys) assert.notEqual(dictionary[key], modesStrings.en[key], `${language}.${key} must not be an English fallback`);
    assert.equal(modesText(language), dictionary);
    assert.ok(Object.isFrozen(dictionary));
  }
  assert.equal(modesText('unsupported'), modesStrings.en);
});
