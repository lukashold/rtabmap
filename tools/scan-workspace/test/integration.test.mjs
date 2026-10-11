import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, writeFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { guide,dictionaries,resolveLanguage } from '../src/i18n.js';
import { experienceDictionaries, experienceText } from '../src/experience-i18n.js';
import { createAppServer } from '../server.mjs';
test('six complete tutorials and UI dictionaries share supported languages',()=>{
  assert.deepEqual(Object.keys(guide),['de','fr','es','it','zh-Hans','en']);
  assert.deepEqual(Object.keys(dictionaries).sort(),Object.keys(guide).sort());
  assert.deepEqual(Object.keys(experienceDictionaries).sort(),Object.keys(guide).sort());
  for(const [lang,g] of Object.entries(guide)){
    assert.equal(g.steps.length,7);assert.ok(g.steps.every(s=>s.title&&s.body&&s.icon));
    assert.deepEqual(Object.keys(dictionaries[lang]),Object.keys(dictionaries.de));
    assert.ok(Object.values(dictionaries[lang]).every(v=>typeof v==='string'&&v.length));
    assert.deepEqual(Object.keys(experienceDictionaries[lang]),Object.keys(experienceDictionaries.de));
    assert.ok(Object.values(experienceDictionaries[lang]).every(v=>typeof v==='string'&&v.length));
    assert.deepEqual(Object.keys(g),Object.keys(guide.de));
    assert.deepEqual(Object.keys(g.workflow),Object.keys(guide.de.workflow));
    assert.equal(g.workflow.stages.length,4);assert.ok(g.workflow.stages.every(s=>s.title&&s.detail));
    assert.equal(Object.keys(g.roomPlan).length,56);
    assert.deepEqual(Object.keys(g.roomPlan),Object.keys(guide.de.roomPlan));
    assert.ok(Object.values(g.roomPlan).every(v=>typeof v==='string'&&v.length));
  }
  assert.equal(resolveLanguage('fr-CA'),'fr');assert.equal(resolveLanguage('zh-TW'),'zh-Hans');assert.equal(resolveLanguage('en'),'en');
  assert.equal(resolveLanguage('en-US'),'en');assert.equal(resolveLanguage('EN_gb'),'en');assert.equal(resolveLanguage('nl-NL'),'de');
  assert.equal(experienceText('en-US','remainingClearance'),'Remaining clearance');
  assert.equal(experienceText('EN_gb','kindDoor'),'Door');
  assert.equal(experienceText('nl-NL','kindDoor'),experienceDictionaries.de.kindDoor);
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
