import * as cloudflare from "@pulumi/cloudflare";

export const ACCOUNT_ID = "6a0ba4b767a451c12205ed6cc161b915";

export const bilboAccessPolicy = new cloudflare.ZeroTrustAccessPolicy(
  "bilbo-access-policy",
  {
    accountId: ACCOUNT_ID,
    decision: "allow",
    includes: [{ email: { email: "fausto.nunez@mailbox.org" } }],
    name: "Bilbo Login",
    sessionDuration: "730h",
  },
  {
    protect: true,
  },
);
