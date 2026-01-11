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
    protect: true,
  },
);
