"""Freeze/replay domain-only constraint observations; no wire admission claim."""
import argparse
import hashlib
import json
from pathlib import Path
from run import load_sdk, REVISION, SOURCE_DIGEST

FIXTURE = Path(__file__).resolve().parents[2] / 'Tests/Conformance/ap2-checkout-constraints-v1.json'
CORPUS_DIGEST = 'b761e39a03245704ad07ce12552f540cb9646506f4a33616623f4ec3780bc908'

def cases():
    def item(sku, qty, line=None):
        return {'id': line or 'line-'+sku, 'item': {'id':sku,'title':sku,'price':100}, 'quantity':qty,'totals':[]}
    def req(name, skus, qty):
        return {'id':name,'acceptable_items':[{'id':s,'title':s} for s in skus],'quantity':qty}
    def constraints(requirements):
        return [{'type':'checkout.allowed_merchants','allowed':[{'id':'merchant-1','name':'Shop'}]}, {'type':'checkout.line_items','items':requirements}]
    def checkout(items):
        return {'id':'checkout-constraints','merchant':{'id':'merchant-1','name':'Shop'},'line_items':items,'status':'ready_for_complete','currency':'USD','totals':[],'links':[]}
    rows=[]
    def add(name, items, requirements, expect='reject', mutate=None):
        row={'id':name,'checkout':checkout(items),'constraints':constraints(requirements),'contract_expectation':expect}
        if mutate: mutate(row)
        rows.append(row)
    add('exact-quantity', [item('A',2)], [req('r1',['A'],2)], 'accept')
    add('wrong-merchant', [item('A',2)], [req('r1',['A'],2)], mutate=lambda r:r['constraints'][0]['allowed'][0].update(id='other'))
    add('underfilled-requirement', [item('A',1)], [req('r1',['A'],2)])
    add('excess-units', [item('A',3)], [req('r1',['A'],2)])
    add('extra-sku', [item('A',2),item('B',1)], [req('r1',['A'],2)])
    add('mixed-alternatives', [item('A',1),item('B',1)], [req('r1',['A','B'],2)])
    add('overlap-needs-backtracking', [item('A',1),item('B',1)], [req('r1',['A','B'],1),req('r2',['A'],1)], 'accept')
    add('empty-alternatives', [item('A',2)], [req('r1',[],2)])
    add('unknown-constraint', [item('A',2)], [req('r1',['A'],2)], mutate=lambda r:r['constraints'].append({'type':'unknown.constraint'}))
    add('zero-quantity', [item('A',0)], [req('r1',['A'],2)])
    add('duplicate-requirement-id', [item('A',2)], [req('same',['A'],1),req('same',['A'],1)])
    add('missing-line-items-constraint', [item('A',2)], [req('r1',['A'],2)], mutate=lambda r:r['constraints'].pop())
    add('all-constraints-conjoined', [item('A',2)], [req('r1',['A'],2)], mutate=lambda r:r['constraints'].append({'type':'checkout.line_items','items':[req('r2',['B'],2)]}))
    add('duplicate-cart-line-id', [item('A',1,'same'),item('A',1,'same')], [req('r1',['A'],2)])
    add('aggregate-same-sku', [item('A',1,'one'),item('A',1,'two')], [req('r1',['A'],2)], 'accept')
    return rows

def observe(row):
    from ap2.sdk.constraints import check_checkout_constraints
    from ap2.sdk.generated.open_checkout_mandate import OpenCheckoutMandate
    from ap2.sdk.generated.types.checkout import Checkout
    try:
        mandate=OpenCheckoutMandate(constraints=row['constraints'],cnf={'jwk':{}})
        violations=check_checkout_constraints(mandate,Checkout.model_validate(row['checkout']))
        return {'domain':'rejected' if violations else 'accepted'}
    except Exception as error:
        return {'domain':'rejected','error_type':type(error).__name__}

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--sdk-root',type=Path,required=True)
    parser.add_argument('--generate',action='store_true')
    args=parser.parse_args()
    load_sdk(args.sdk_root.resolve())
    if args.generate:
        if FIXTURE.exists(): raise ValueError('Frozen corpus already exists')
        rows=cases()
        for row in rows: row['sdk_observation']=observe(row)
        FIXTURE.write_text(json.dumps({'schema':'cedar-poo.ap2.checkout-constraints.v1','ap2_revision':REVISION,'sdk_source_sha256':SOURCE_DIGEST,'cases':rows},indent=2,sort_keys=True)+'\n')
    if hashlib.sha256(FIXTURE.read_bytes()).hexdigest()!=CORPUS_DIGEST: raise ValueError('Frozen constraint bytes changed')
    corpus=json.loads(FIXTURE.read_text())
    if corpus['ap2_revision']!=REVISION or corpus['sdk_source_sha256']!=SOURCE_DIGEST: raise ValueError('Provenance mismatch')
    for row in corpus['cases']:
        actual=observe(row)
        if actual!=row['sdk_observation']: raise ValueError('SDK observation changed: '+row['id'])
        print('PASS',row['id'],'SDK='+actual['domain'],'contract='+row['contract_expectation'],flush=True)
    print('AP2-CONSTRAINT-SDK-OK',len(corpus['cases']),'domain-only cases')
    print('fixture sha256',hashlib.sha256(FIXTURE.read_bytes()).hexdigest())

if __name__=='__main__': main()
