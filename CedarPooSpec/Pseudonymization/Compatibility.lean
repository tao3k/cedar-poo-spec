import CedarPooSpec.Data.Relation

/-!
The token-recipe comparison is expressed directly in Cedar's expression AST.
Tenant admission, grant provenance, and actual cryptographic key possession
remain independent controls.
-/

namespace CedarPooSpec.Pseudonymization

open Cedar.Spec

structure TokenRelation where
  source : Expr
  target : Expr

def TokenRelation.sameRecipe (relation : TokenRelation) : Expr :=
  .and (CedarPooSpec.Data.sameAttribute relation.source relation.target "mode")
    (.and (CedarPooSpec.Data.sameAttribute relation.source relation.target "scope")
      (.and (CedarPooSpec.Data.sameAttribute relation.source relation.target "keyDomain")
        (.and (CedarPooSpec.Data.sameAttribute relation.source relation.target "tokenKeyVersion")
          (CedarPooSpec.Data.sameAttribute relation.source relation.target "transformVersion"))))

end CedarPooSpec.Pseudonymization
