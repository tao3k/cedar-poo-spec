// SPDX-FileCopyrightText: 2026 hardenedlinux Linux Team and Contributors
// SPDX-License-Identifier: Apache-2.0
import {test,expect} from 'bun:test';
import {readFile} from 'node:fs/promises';
import {connectWasm} from '@openmbee/opensysml';
const root=new URL('../../',import.meta.url);
test('proof cards bind actual SDK declarations to Lean theorem kinds, not display labels',async()=>{
 const source='dev/sysml/zero-trust-proofs.sysml',raw=await readFile(new URL(source,root),'utf8');
 const parts=[...raw.matchAll(/part (\w+) : (\w+);\s*attribute \w+Symbol : String = "([A-Za-z0-9_.]+)";\s*attribute \w+Source : String = "([A-Za-z0-9_/.]+)";/g)];
 expect(parts).toHaveLength(14);
 const connection=await connectWasm();
 const laws:string[]=[],declarations:string[]=[],origins:Array<[string,string]>=[];
 try{
  const model=(await connection.parseSources([[source,raw]])).raiseForErrors();
  for(const[,id,role,symbol,file]of parts){
   const value=await model.eval(`ZeroTrustProofs::${id}Symbol`),origin=await model.eval(`ZeroTrustProofs::${id}Source`);
   expect(value.kind).toBe('string');expect(origin.kind).toBe('string');
   if(value.kind!=='string'||origin.kind!=='string')throw new Error('Proof source metadata is not a string');
   expect(value.value).toBe(symbol!);expect(origin.value).toBe(file!);
   expect((await readFile(new URL(file!,root),'utf8')).length).toBeGreaterThan(0);
   declarations.push(symbol!);origins.push([symbol!,file!.replace(/\.lean$/,'').replaceAll('/','.')]);if(role==='KernelLaw'||role==='KernelCounterexample')laws.push(symbol!);
  }
 }finally{await connection.close();}
 expect(laws.length).toBeGreaterThanOrEqual(8);
 const names=(items:string[])=>items.map(name=>'`'+name).join(', ');
 const uses=[
  ['CedarPooSpec.ZeroTrust.usage_retains_core','CedarPooSpec.ZeroTrust.usage_rechecks_after_recovery'],
  ['CedarPooSpec.ZeroTrust.ProfileObject.composed_preserves_actual_parent_and_original','CedarPooSpec.Gateway.ZeroTrust.continuing_objects_preserve_parent_and_consumption'],
 ];
 const script=`import Lean
import CedarPooSpec.ZeroTrust
import CedarPooSpec.Gateway.ZeroTrust
import Tests.ZeroTrust.ProfileObject
run_cmd do
  let env ← Lean.getEnv
  for name in [${names(declarations)}] do
    unless (env.find? name).isSome do throwError "missing diagram declaration: {name}"
  for (name, moduleName) in [${origins.map(([name,module])=>'(`'+name+', `'+module+')').join(', ')}] do
    let some actual ← pure (env.getModuleIdxFor? name) | throwError "missing declaration origin: {name}"
    let some expected ← pure (env.getModuleIdx? moduleName) | throwError "missing source module: {moduleName}"
    unless actual == expected do throwError "diagram declaration/source mismatch: {name}"
  for name in [${names(laws)}] do
    match env.find? name with
    | some (.thmInfo _) => pure ()
    | _ => throwError "diagram law is not a theorem: {name}"
  for (dependency, name) in [${uses.map(([dependency,name])=>'(`'+dependency+', `'+name+')').join(', ')}] do
    match env.find? name with
    | some (.thmInfo info) =>
      unless info.value.getUsedConstants.contains dependency do
        throwError "diagram lemma edge absent from proof term: {dependency} -> {name}"
    | _ => throwError "diagram target is not a theorem: {name}"
  Lean.logInfo "ZERO-TRUST-PROOF-FIGURES-LEAN-OK"
`;
 const checked=Bun.spawnSync(['lake','env','lean','-M','2048','-T','10000000','--stdin'],{cwd:root.pathname,stdin:Buffer.from(script)});
 expect(new TextDecoder().decode(checked.stderr)).toBe('');
 expect(checked.exitCode).toBe(0);
 expect(new TextDecoder().decode(checked.stdout)).toContain('ZERO-TRUST-PROOF-FIGURES-LEAN-OK');
},30000);
