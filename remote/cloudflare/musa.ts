import * as cloudflare from "@pulumi/cloudflare";
import { ACCOUNT_ID, bilboAccessPolicy } from "./shared";

export const musaPhoneToken = new cloudflare.ZeroTrustAccessServiceToken(
  "musa-phone-token",
  {
    accountId: ACCOUNT_ID,
    name: "Musa phone",
    duration: "8760h",
  },
);

const musaServiceAuthPolicy = new cloudflare.ZeroTrustAccessPolicy(
  "musa-service-auth-policy",
  {
    accountId: ACCOUNT_ID,
    decision: "non_identity",
    includes: [{ serviceToken: { tokenId: musaPhoneToken.id } }],
    name: "Musa phone",
  },
);

export const musaAccessApplication = new cloudflare.ZeroTrustAccessApplication(
  "musa-access-app",
  {
    accountId: ACCOUNT_ID,
    appLauncherVisible: false,
    domain: "musa.fnune.com",
    name: "Musa API",
    policies: [
      { id: musaServiceAuthPolicy.id, precedence: 1 },
      { id: bilboAccessPolicy.id, precedence: 2 },
    ],
    selfHostedDomains: ["musa.fnune.com"],
    sessionDuration: "730h",
    type: "self_hosted",
  },
);

export const musaPhoneTokenClientId = musaPhoneToken.clientId;
export const musaPhoneTokenClientSecret = musaPhoneToken.clientSecret;
