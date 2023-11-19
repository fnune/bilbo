let
  fausto = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIiM6VWz2s3rUff+r3x8w/KOWli7sWcTIM0l70yQjIuu";
  bilbo = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMnuvKYsmZgijFlt2TlM5JPsT/rCkZT37GBpcb5Oa372";
in {
  "cloudflare-api-token.age".publicKeys = [fausto bilbo];
}
