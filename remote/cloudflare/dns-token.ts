import * as cloudflare from "@pulumi/cloudflare";
import { ZONE_ID } from "./zone";

const dnsWrite = cloudflare.getApiTokenPermissionGroupsListOutput({
  name: "DNS Write",
  scope: "com.cloudflare.api.account.zone",
});

export const bilboDnsToken = new cloudflare.ApiToken("bilbo-dns-token", {
  name: "bilbo dyndns and ACME",
  status: "active",
  policies: [
    {
      effect: "allow",
      permissionGroups: dnsWrite.results.apply((groups) =>
        groups.map((group) => ({ id: group.id })),
      ),
      resources: JSON.stringify({
        [`com.cloudflare.api.account.zone.${ZONE_ID}`]: "*",
      }),
    },
  ],
});

export const bilboDnsTokenValue = bilboDnsToken.value;
