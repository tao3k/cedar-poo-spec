/-!
Capability declarations for the three transformations exercised by the
reference scenario. They describe what a mode can support, not possession of
a key or authorization to perform an operation.
-/

namespace CedarPooSpec.Pseudonymization

inductive Mode where
  | aesSiv | aesGcm | hmacSha256
  deriving DecidableEq

def Mode.label : Mode → String
  | .aesSiv => "aes-siv"
  | .aesGcm => "aes-gcm"
  | .hmacSha256 => "hmac-sha256"

def Mode.reversible : Mode → Bool
  | .aesSiv | .aesGcm => true
  | .hmacSha256 => false

def Mode.linkable : Mode → Bool
  | .aesSiv | .hmacSha256 => true
  | .aesGcm => false

end CedarPooSpec.Pseudonymization
