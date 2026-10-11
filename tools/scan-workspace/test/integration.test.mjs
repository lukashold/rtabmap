import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, writeFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { guide,dictionaries,resolveLanguage } from '../src/i18n.js';
import { createAppServer } from '../server.mjs';
test('five complete tutorials and UI dictionaries share supported languages',()=>{
  assert.deepEqual(Object.keys(guide),['de','fr','es','it','zh-Hans']);
  for(const [lang,g] of Object.entries(guide)){
    assert.equal(g.steps.length,7);assert.ok(g.steps.every(s=>s.title&&s.body&&s.icon));
    assert.equal(Object.keys(dictionaries[lang]).length,Object.keys(dictionaries.de).length);
    assert.ok(Object.values(dictionaries[lang]).every(v=>typeof v==='string'&&v.length));
  }
  assert.equal(resolveLanguage('fr-CA'),'fr');assert.equal(resolveLanguage('zh-TW'),'zh-Hans');assert.equal(resolveLanguage('en'),'de');
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
