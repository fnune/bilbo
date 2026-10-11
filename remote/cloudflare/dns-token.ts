import * as cloudflare from "@pulumi/cloudflare";

const ZONE_ID = "ae60391afa829b4b5f0e664484989d6b";

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
      resources: {
        [`com.cloudflare.api.account.zone.${ZONE_ID}`]: "*",
      },
    },
  ],
});

export const bilboDnsTokenValue = bilboDnsToken.value;
