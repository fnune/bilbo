import * as cloudflare from "@pulumi/cloudflare";
import { ACCOUNT_ID, ZONE_ID, bilboAccessPolicy } from "./shared";

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

export const bilboDnsRecord = new cloudflare.DnsRecord(
  "bilbo-dns",
  {
    zoneId: ZONE_ID,
    name: "bilbo.fnune.com",
    type: "A",
    content: "91.41.230.203",
    proxied: true,
    ttl: 1,
  },
  {
    protect: true,
  },
);

export const immichDnsRecord = new cloudflare.DnsRecord(
  "immich-dns",
  {
    zoneId: ZONE_ID,
    name: "immich.fnune.com",
    type: "A",
    content: "91.41.230.203",
    proxied: true,
    ttl: 1,
  },
  {
    protect: true,
  },
);
