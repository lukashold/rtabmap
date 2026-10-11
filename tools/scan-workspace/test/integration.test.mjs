import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, writeFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { guide,dictionaries,resolveLanguage } from '../src/i18n.js';
import { experienceDictionaries, experienceText } from '../src/experience-i18n.js';
import { designDictionaries } from '../src/design-i18n.js';
import { extraLocales, supportedLanguages, directionFor } from '../locales/index.js';
import { createAppServer } from '../server.mjs';
test('fifteen complete tutorials and UI dictionaries share supported languages',()=>{
  assert.equal(supportedLanguages.length,15);
  const languages=[...supportedLanguages].sort();
  for(const collection of [guide,dictionaries,experienceDictionaries,designDictionaries])assert.deepEqual(Object.keys(collection).sort(),languages);
  for(const [lang,g] of Object.entries(guide)){
    assert.equal(g.steps.length,7);assert.ok(g.steps.every(s=>s.title&&s.body&&s.icon));
    assert.deepEqual(g.steps.map(s=>s.icon),guide.de.steps.map(s=>s.icon));
    assert.deepEqual(Object.keys(dictionaries[lang]).sort(),Object.keys(dictionaries.de).sort());
    assert.ok(Object.values(dictionaries[lang]).every(v=>typeof v==='string'&&v.length));
    assert.deepEqual(Object.keys(experienceDictionaries[lang]).sort(),Object.keys(experienceDictionaries.de).sort());
    assert.ok(Object.values(experienceDictionaries[lang]).every(v=>typeof v==='string'&&v.length));
    assert.deepEqual(Object.keys(designDictionaries[lang]).sort(),Object.keys(designDictionaries.de).sort());
    assert.ok(Object.values(designDictionaries[lang]).every(v=>typeof v==='string'&&v.length));
    assert.deepEqual(Object.keys(g).sort(),Object.keys(guide.de).sort());
    assert.deepEqual(Object.keys(g.workflow).sort(),Object.keys(guide.de.workflow).sort());
    assert.equal(g.workflow.stages.length,4);assert.ok(g.workflow.stages.every(s=>s.title&&s.detail));
    assert.equal(Object.keys(g.roomPlan).length,56);
    assert.deepEqual(Object.keys(g.roomPlan).sort(),Object.keys(guide.de.roomPlan).sort());
    assert.ok(Object.values(g.roomPlan).every(v=>typeof v==='string'&&v.length));
  }
  assert.equal(Object.keys(extraLocales).length,9);
  for(const [language,pack]of Object.entries(extraLocales))assert.deepEqual(guide[language],pack.guide,`${language}: native guide is synchronized with its locale pack`);
  assert.equal(resolveLanguage('fr-CA'),'fr');assert.equal(resolveLanguage('zh-TW'),'zh-Hans');assert.equal(resolveLanguage('en'),'en');
  assert.equal(resolveLanguage('en-US'),'en');assert.equal(resolveLanguage('EN_gb'),'en');assert.equal(resolveLanguage('nl-NL'),'de');
  assert.equal(experienceText('en-US','remainingClearance'),'Remaining clearance');
  assert.equal(experienceText('EN_gb','kindDoor'),'Door');
  assert.equal(experienceText('nl-NL','kindDoor'),experienceDictionaries.de.kindDoor);
});
test('regional and legacy locale aliases resolve consistently with Arabic RTL and other languages LTR',()=>{
  const aliases={'pt-BR':'pt','ar-EG':'ar','hi-IN':'hi','bn-BD':'bn','ru-RU':'ru','ja-JP':'ja','ko-KR':'ko','id-ID':'id','tr-TR':'tr','in_ID':'id'};
  for(const [alias,language]of Object.entries(aliases)){
    assert.equal(resolveLanguage(alias),language,alias);
    assert.equal(experienceText(alias,'kindDoor'),experienceDictionaries[language].kindDoor,alias);
    assert.equal(directionFor(alias),language==='ar'?'rtl':'ltr',alias);
  }
  for(const language of supportedLanguages)assert.equal(directionFor(language),language==='ar'?'rtl':'ltr',language);
});
test('static server exposes public configuration, rejects writes and traversal',async()=>{
  const root=await mkdtemp(join(tmpdir(),'rtab-web-'));await writeFile(join(root,'index.html'),'<h1>test</h1>');
  const server=createAppServer(root);await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));const url=`http://127.0.0.1:${server.address().port}`;
  try{
    assert.equal(await(await fetch(url)).text(),'<h1>test</h1>');
    assert.equal(await(await fetch(url+'/health')).text(),'ok');
    assert.deepEqual(Object.keys(await(await fetch(url+'/config.json')).json()),['googleClientId','microsoftClientId','serverEnabled']);
    assert.equal((await fetch(url,{method:'POST',body:'scan data'})).status,405);
    assert.equal((await fetch(url+'/%2e%2e%2fpackage.json')).status,404);
    assert.equal((await fetch(url+'/%zz')).status,404);
    assert.equal(await(await fetch(url,{method:'HEAD'})).text(),'');
  }finally{await new Promise(resolve=>server.close(resolve));await rm(root,{recursive:true,force:true});}
});
