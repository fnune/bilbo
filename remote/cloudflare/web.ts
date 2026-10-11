import * as cloudflare from "@pulumi/cloudflare";
import { ACCOUNT_ID, bilboAccessPolicy } from "./shared";

export const bilboAccessApplication = new cloudflare.ZeroTrustAccessApplication(
  "bilbo-access-app",
  {
    accountId: ACCOUNT_ID,
    appLauncherVisible: true,
    domain: "bilbo.fnune.com",
    name: "Bilbo",
    policies: [
      {
        id: bilboAccessPolicy.id,
        precedence: 1,
      },
    ],
    selfHostedDomains: ["bilbo.fnune.com"],
    sessionDuration: "730h",
    type: "self_hosted",
  },
  {
    protect: false,
  },
);

export const papraAccessApplication = new cloudflare.ZeroTrustAccessApplication(
  "papra-access-app",
  {
    accountId: ACCOUNT_ID,
    appLauncherVisible: true,
    domain: "docs.fnune.com",
    name: "Papra",
    policies: [
      {
        id: bilboAccessPolicy.id,
        precedence: 1,
      },
    ],
    selfHostedDomains: ["docs.fnune.com"],
    sessionDuration: "730h",
    type: "self_hosted",
  },
  {
    protect: false,
  },
);
