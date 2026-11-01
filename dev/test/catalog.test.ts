// SPDX-FileCopyrightText: 2026 hardenedlinux Linux Team and Contributors
// SPDX-License-Identifier: Apache-2.0

import {test,expect} from 'bun:test';
import {readFile} from 'node:fs/promises';
import {connectWasm} from '@openmbee/opensysml';
import {observeCatalog,catalogSysML,categories} from '../catalog';
const input=()=>({format_version:2,sources:{policies:[{}],entities:[[]],schemas:[{}]},entries:{example:{manifest_kind:'schema-bound',schema_ref:0,revision_sources:{r:0},cases:[{name:'case',revision:'r',policy_ref:0,entities_ref:0,expected:'deny'}]}}});
test('display observations retain source references and never promote expected decisions',()=>{
 const result=observeCatalog(JSON.stringify(input()));expect(result.entries[0]!.expectedDeny).toBe(1);expect(result.entries[0]!.expectedAllow).toBe(0);expect(result.entries[0]!.category).toBe('schema-bound');
 const malformed=input();malformed.entries.example.cases[0]!.policy_ref=4;expect(()=>observeCatalog(JSON.stringify(malformed))).toThrow('source reference');
 const drift=input();drift.entries.example.revision_sources.r=1;expect(()=>observeCatalog(JSON.stringify(drift))).toThrow('Revision');
 const missing=input();delete(missing.entries.example as {schema_ref?:number}).schema_ref;expect(()=>observeCatalog(JSON.stringify(missing))).toThrow('schema reference');
 expect(()=>observeCatalog(JSON.stringify({...input(),format_version:999}))).toThrow();
 expect(()=>observeCatalog(JSON.stringify({...input(),entries:{artifact:[{root:'broken',policy_ref:-1}]}}))).toThrow();
 expect(()=>observeCatalog(JSON.stringify({...input(),entries:{artifact:[{root:'broken',policy_ref:4}]}}))).toThrow('source reference');
 const data=observeCatalog(JSON.stringify({...input(),entries:{domain:[{business:'uninterpreted'}]}}));expect(data.entries[0]!.category).toBe('data');
});
test('actual Lean catalog becomes a parsed SDK model and category values round-trip',async()=>{
 const raw=await readFile(new URL('../.generated/lean-catalog.json',import.meta.url),'utf8'),summary=observeCatalog(raw),source=catalogSysML(summary),connection=await connectWasm();
 try{
  const model=(await connection.parseSources([['dev/sysml/lean-catalog.sysml',source]])).raiseForErrors();
  const count=await model.eval('LeanCatalog::entryCount');expect(count.kind).toBe('int');if(count.kind==='int')expect(count.value).toBe(BigInt(summary.entries.length));
  for(const[order,category]of categories.entries()){const value=await model.eval(`LeanCatalog::group${order}Count`);expect(value.kind).toBe('int');if(value.kind==='int')expect(value.value).toBe(BigInt(summary.entries.filter(entry=>entry.category===category).length));}
  const view=await connection.renderView(model.hash,'LeanCatalog::overview',{depth:1});expect(view.nodes).toHaveLength(5);
  const broken=await connection.loads('package Broken { part ;');expect(broken.ok).toBe(false);expect(()=>broken.raiseForErrors()).toThrow();
 }finally{await connection.close();}
},30000);
