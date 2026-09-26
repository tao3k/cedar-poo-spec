import CedarPooSpec.PolicyModules
import CedarPooSpec.Soundness
import LeanPoo.Proof.Batch

/-! Connect a C4 policy revision to the authorization proof object's patch. -/

namespace CedarPooSpec.PolicyModules

open LeanPoo.Proof
open CedarPooSpec.Soundness

def Revision.authorizationPatch (revision : Revision) :
    Patch AuthorizationKey AuthorizationValue :=
  if decide (revision.before.policies.map CompiledPolicy.policy =
      revision.after.policies.map CompiledPolicy.policy) then Patch.empty
  else Patch.set .policies (revision.after.policies.map CompiledPolicy.policy)

end CedarPooSpec.PolicyModules
