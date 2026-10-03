"""Freeze/replay pinned SDK wire observations; this tool grants no admission."""
from __future__ import annotations

import argparse
import base64
import copy
import hashlib
import importlib.metadata
import json
import sys
from pathlib import Path
from unittest.mock import patch

REVISION = 'e1ea56db72a6385bce3e5c1112b3a56ce60acb43'
SOURCE_DIGEST = '5a2eedaa96d7cd962c7baa75161b9f376b2ba37eafcb9fbea551a2573a50698d'
CORPUS_DIGEST = 'b841dceaf97b6b78907b095bd6bfbb9e7dc43bf1bc37e8d8b0a9959b11acee9a'
REPO = Path(__file__).resolve().parents[2]
FIXTURE = REPO / 'Tests/Conformance/ap2-mandate-wire-v1.json'
PACKAGES = {'cryptography': '46.0.5', 'jwcrypto': '1.5.6', 'pydantic': '2.12.5', 'sd-jwt': '0.10.4'}
NOW = 1800000000


def encoded(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).decode().rstrip('=')


def decoded(value: str) -> bytes:
    return base64.urlsafe_b64decode(value + '=' * (-len(value) % 4))


def digest(value: str) -> str:
    return encoded(hashlib.sha256(value.encode('ascii')).digest())


def load_sdk(root: Path) -> dict[str, str]:
    files = sorted(root.glob('code/sdk/python/ap2/sdk/**/*.py')) + [root / 'pyproject.toml']
    manifest = {str(p.relative_to(root)): hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(files)}
    actual = hashlib.sha256(json.dumps(manifest, sort_keys=True, separators=(',', ':')).encode()).hexdigest()
    if actual != SOURCE_DIGEST:
        raise ValueError(f'Pinned SDK source mismatch: {actual}')
    for name, expected in PACKAGES.items():
        if importlib.metadata.version(name) != expected:
            raise ValueError(f'Dependency version mismatch: {name}')
    sys.path.insert(0, str(root / 'code/sdk/python'))
    return manifest


def sign_payload(payload: dict, key, header: dict | None = None) -> str:
    from jwcrypto import jws
    token = jws.JWS(json.dumps(payload, separators=(',', ':')).encode())
    token.add_signature(key, protected=json.dumps(header or {'alg': 'ES256', 'typ': 'JWT'}))
    return token.serialize(compact=True)


def resign(token: str, key, change) -> str:
    issuer, *suffix = token.split('~')
    header, payload, _ = issuer.split('.')
    claims = json.loads(decoded(payload))
    change(claims)
    return '~'.join([sign_payload(claims, key, json.loads(decoded(header))), *suffix])


def observe(vector: dict) -> dict:
    from ap2.sdk.checkout_mandate_chain import CheckoutMandateChain
    from ap2.sdk.sdjwt import common, chain
    from jwcrypto import jwk, jws
    context = vector['context']
    try:
        payloads = chain.verify_chain(
            [common.parse_token(t) for t in vector['tokens']],
            lambda _token: jwk.JWK(**vector['root_jwk']),
            clock_skew_seconds=0, current_time=context['now'],
            expected_aud=context['aud'], expected_nonce=context['nonce'],
        )
    except Exception as error:
        return {'wire': 'rejected', 'error_type': type(error).__name__}
    result = {'wire': 'accepted', 'payloads': payloads}
    try:
        typed = CheckoutMandateChain.parse(payloads)
        violations = typed.verify(
            expected_checkout_hash=context['checkout_hash'],
            checkout_jwt=payloads[-1].get('checkout_jwt'),
        )
        result['domain'] = 'rejected' if violations else 'accepted'
    except Exception as error:
        result.update(domain='rejected', domain_error_type=type(error).__name__)
    # Independent merchant-signature observation. The SDK domain helper above
    # extracts checkout content; it is not itself this signature verifier.
    try:
        merchant = jws.JWS()
        merchant.deserialize(payloads[-1]['checkout_jwt'])
        merchant.verify(jwk.JWK(**vector['merchant_jwk']), alg='ES256')
        result['merchant_signature'] = 'accepted'
    except Exception:
        result['merchant_signature'] = 'rejected'
    return result


def generate() -> list[dict]:
    from ap2.sdk.disclosure_metadata import DisclosureMetadata
    from ap2.sdk.generated.open_checkout_mandate import OpenCheckoutMandate
    from ap2.sdk.generated.checkout_mandate import CheckoutMandate
    from ap2.sdk.sdjwt import common, sd_jwt, kb_sd_jwt
    from jwcrypto.jwk import JWK
    root_key, agent_key, merchant_key, wrong_key = [JWK.generate(kty='EC', crv='P-256') for _ in range(4)]
    checkout = sign_payload({
        'id': 'checkout-1', 'merchant': {'id': 'merchant-1', 'name': 'Shop'},
        'line_items': [], 'status': 'ready_for_complete', 'currency': 'USD',
        'totals': [{'type': 'subtotal', 'amount': 0}, {'type': 'total', 'amount': 0}],
        'links': [],
    }, merchant_key)
    context = {'aud': 'https://merchant.example', 'nonce': 'server-nonce-1', 'now': NOW,
               'checkout_hash': digest(checkout)}
    open_claims = OpenCheckoutMandate(constraints=[], cnf={'jwk': json.loads(agent_key.export_public())}, iat=NOW, exp=NOW+600)
    root = sd_jwt.create(open_claims, root_key, sd=DisclosureMetadata()).sd_jwt_issuance
    closed = CheckoutMandate(checkout_jwt=checkout, checkout_hash=digest(checkout), iat=NOW, exp=NOW+600)
    def leaf(parent=root, signer=agent_key, mode='sd_hash', payload=closed, sd=None):
        with patch('ap2.sdk.sdjwt.kb_sd_jwt.time.time', return_value=NOW):
            return kb_sd_jwt.create(common.parse_token(parent), signer, payload,
                                    context['aud'], context['nonce'], hash_mode=mode,
                                    sd=sd if sd is not None else DisclosureMetadata()).sd_jwt_issuance
    terminal = leaf()
    base = {'tokens': [root, terminal], 'context': context,
            'root_jwk': json.loads(root_key.export_public()),
            'merchant_jwk': json.loads(merchant_key.export_public())}
    vectors = []
    def add(name, reason, contract='reject', edit=None, wire='rejected'):
        v = copy.deepcopy(base)
        if edit:
            edit(v)
        v.update(id=name, contract_expectation=contract, purpose=reason)
        v['sdk_observation'] = observe(v)
        if v['sdk_observation']['wire'] != wire:
            raise ValueError(f'Unexpected SDK wire outcome: {name}: {v["sdk_observation"]}')
        vectors.append(v)
        print(f'{name}: {v["sdk_observation"]["wire"]}', flush=True)
    add('valid-sd-hash', 'Two-hop chain and independently signed merchant checkout', 'accept', wire='accepted')
    add('valid-issuer-jwt-hash', 'Alternate pinned delegation hash mode', 'accept',
        lambda v: v['tokens'].__setitem__(1, leaf(mode='issuer_jwt_hash')), wire='accepted')
    add('wrong-root-key', 'Independently enrolled root trust mismatch', edit=lambda v: v.__setitem__('root_jwk', json.loads(wrong_key.export_public())))
    add('wrong-holder-key', 'Terminal signature does not match verified parent cnf', edit=lambda v: v['tokens'].__setitem__(1, leaf(signer=wrong_key)))
    add('wrong-parent-hash', 'Valid holder signature over substituted parent hash', edit=lambda v: v['tokens'].__setitem__(1, resign(terminal, agent_key, lambda p: p.__setitem__('sd_hash', 'wrong'))))
    add('both-parent-hashes', 'Ambiguous delegation hash modes', edit=lambda v: v['tokens'].__setitem__(1, resign(terminal, agent_key, lambda p: p.__setitem__('issuer_jwt_hash', digest(common.parse_token(root).issuer_jwt)))))
    add('wrong-audience', 'Authenticated verifier audience differs', edit=lambda v: v['context'].__setitem__('aud', 'https://other.example'))
    add('wrong-nonce', 'Authenticated server nonce differs', edit=lambda v: v['context'].__setitem__('nonce', 'server-nonce-2'))
    expired_root = sd_jwt.create(open_claims.model_copy(update={'exp': NOW-1}), root_key, sd=DisclosureMetadata()).sd_jwt_issuance
    add('expired-root', 'Expired parent with otherwise correctly rebound child', edit=lambda v: v.__setitem__('tokens', [expired_root, leaf(parent=expired_root)]))
    add('future-hop', 'Validly signed future terminal issuance time', edit=lambda v: v['tokens'].__setitem__(1, resign(terminal, agent_key, lambda p: p.__setitem__('iat', NOW+1))))
    disclosed = leaf(sd=DisclosureMetadata(sd_keys=['checkout_jwt']))
    add('valid-disclosure', 'Required checkout claim reconstructed from its digest', 'accept', lambda v: v['tokens'].__setitem__(1, disclosed), wire='accepted')
    def alter(v):
        parts = disclosed.split('~')
        data = json.loads(decoded(parts[1]))
        data[-1] = 'changed-checkout'
        parts[1] = encoded(json.dumps(data).encode())
        v['tokens'][1] = '~'.join(parts)
    add('altered-disclosure', 'Altered disclosure is ignored by pinned SDK; required checkout claim remains absent', edit=alter, wire='accepted')
    add('duplicate-disclosure', 'One disclosure supplied twice', edit=lambda v: v['tokens'].__setitem__(1, disclosed + disclosed.split('~')[1] + '~'))
    add('missing-checkout-disclosure', 'Wire validity alone cannot supply required domain claim', edit=lambda v: v['tokens'].__setitem__(1, disclosed.split('~')[0]+'~'), wire='accepted')
    add('missing-verifier-context', 'Optional SDK defaults cannot stand for authenticated transaction inputs', edit=lambda v: v['context'].update(aud=None, nonce=None), wire='accepted')
    def wrong_vct(v):
        v['tokens'][1] = resign(terminal, agent_key, lambda p: p['delegate_payload'][0].__setitem__('vct', 'mandate.checkout.2'))
    add('unsupported-vct', 'Cryptographically valid unsupported closed mandate schema', edit=wrong_vct, wire='accepted')
    bad_checkout = sign_payload(json.loads(decoded(checkout.split('.')[1])), wrong_key)
    bad_closed = closed.model_copy(update={'checkout_jwt': bad_checkout, 'checkout_hash': digest(bad_checkout)})
    def merchant_substitution(v):
        v['tokens'][1] = leaf(payload=bad_closed)
        v['context']['checkout_hash'] = digest(bad_checkout)
    add('wrong-merchant-signature', 'Domain extraction and constraints do not authenticate merchant signing authority', edit=merchant_substitution, wire='accepted')
    return vectors


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--sdk-root', type=Path)
    parser.add_argument('--check-frozen', action='store_true', help='Offline byte-integrity check only; does not replay SDK crypto')
    parser.add_argument('--generate', action='store_true', help='Generate new random test-only keys/signatures; refuses to replace a frozen corpus')
    args = parser.parse_args()
    if args.check_frozen:
        if args.generate:
            parser.error('--check-frozen cannot generate a corpus')
        if hashlib.sha256(FIXTURE.read_bytes()).hexdigest() != CORPUS_DIGEST:
            raise ValueError('Frozen wire corpus bytes changed')
        constraints = REPO / 'Tests/Conformance/ap2-checkout-constraints-v1.json'
        if hashlib.sha256(constraints.read_bytes()).hexdigest() != 'b761e39a03245704ad07ce12552f540cb9646506f4a33616623f4ec3780bc908':
            raise ValueError('Frozen constraint corpus bytes changed')
        print('AP2-CORPUS-INTEGRITY-OK 17 vectors; SDK replay not performed')
        print('AP2-CONSTRAINT-CORPUS-INTEGRITY-OK 15 domain cases; SDK replay not performed')
        return
    if args.sdk_root is None:
        parser.error('--sdk-root is required for generation or cryptographic SDK replay')
    manifest = load_sdk(args.sdk_root.resolve())
    if args.generate:
        if FIXTURE.exists():
            raise ValueError('Frozen corpus already exists; generation requires an explicitly reviewed new corpus version')
        corpus = {'schema': 'cedar-poo.ap2.mandate-wire.v1', 'ap2_revision': REVISION,
                  'sdk_source_sha256': SOURCE_DIGEST, 'sdk_files': manifest,
                  'dependencies': PACKAGES, 'vectors': generate()}
        FIXTURE.write_text(json.dumps(corpus, indent=2, sort_keys=True)+'\n')
    corpus = json.loads(FIXTURE.read_text())
    if hashlib.sha256(FIXTURE.read_bytes()).hexdigest() != CORPUS_DIGEST:
        raise ValueError('Frozen wire corpus bytes changed')
    if (corpus['ap2_revision'], corpus['sdk_source_sha256'], corpus['sdk_files'], corpus['dependencies']) != (REVISION, SOURCE_DIGEST, manifest, PACKAGES):
        raise ValueError('Corpus provenance mismatch')
    ids = set()
    for vector in corpus['vectors']:
        if vector['id'] in ids:
            raise ValueError('Duplicate vector ID')
        ids.add(vector['id'])
        actual = observe(vector)
        if actual != vector['sdk_observation']:
            raise ValueError(f'SDK observation changed: {vector["id"]}: {actual}')
        print(f'PASS {vector["id"]}: wire={actual["wire"]} contract={vector["contract_expectation"]}', flush=True)
    print(f'AP2-WIRE-OK {len(ids)} frozen vectors; SDK replay only, Rust verification is a separate gate')


if __name__ == '__main__':
    main()
