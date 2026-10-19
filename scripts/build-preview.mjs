#!/usr/bin/env node
// Rebuild the offline demo from its maintained HTML/CSS/JS sources. No packages or credentials.
import {readFile,writeFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {fileURLToPath} from 'node:url';
import path from 'node:path';
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const preview=path.join(root,'preview');
const read=name=>readFile(path.join(preview,name),'utf8');
const [template,css,model,app]=await Promise.all(['index.html','style.css','model.mjs','app.mjs'].map(read));
const importLine="import {layouts,titles,createState,selectWindow,setDisplays,setCycling,applyAction} from './model.mjs';";
if(!app.startsWith(importLine))throw new Error('Update the offline bundler for the changed app imports.');
const js='\n(function(){\n"use strict";\n'+model.replace(/^export /gm,'')+'\n'+app.slice(importLine.length)+'\n})();\n';
if(/<\/script/i.test(js)||/<\/style/i.test(css))throw new Error('Unexpected closing tag in bundled source.');
const hash=createHash('sha256').update(js).digest('base64');
let html=template.replace('<link rel="stylesheet" href="style.css">','<style>\n'+css+'\n</style>')
 .replace('<script type="module" src="app.mjs"></script>','<script>'+js+'</script>')
 .replace(/<meta http-equiv="Content-Security-Policy"[^>]+>/,`<meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'sha256-${hash}'; style-src 'unsafe-inline'; img-src data:; connect-src 'none'; object-src 'none'; base-uri 'none'; form-action 'none'">`);
const assetRefs=[...html.matchAll(/(?:src|href)="(assets\/[^\"]+)"/g)].map(m=>m[1]);
for(const asset of new Set(assetRefs)){
 const bytes=await readFile(path.join(preview,asset));
 const mime=asset.endsWith('.svg')?'image/svg+xml':asset.endsWith('.png')?'image/png':null;
 if(!mime)throw new Error('Unsupported embedded asset: '+asset);
 html=html.replaceAll('"'+asset+'"','"data:'+mime+';base64,'+bytes.toString('base64')+'"');
}
if(/<(?:script|link)[^>]+(?:src|href)="(?!data:)/i.test(html)||/<img[^>]+src="(?!data:)/i.test(html))throw new Error('Offline HTML still has an external runtime dependency.');
const output=path.join(preview,'standalone.html');
if(process.argv.includes('--check')){
 if(await readFile(output,'utf8')!==html)throw new Error('Offline HTML is stale. Run node scripts/build-preview.mjs and commit it.');
 console.log('Offline preview matches source; script hash and embedded assets verified.');
}else{
 await writeFile(output,html);console.log('Built preview/standalone.html — open directly in your browser, no server or login.');
}
