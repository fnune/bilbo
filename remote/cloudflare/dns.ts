import * as cloudflare from "@pulumi/cloudflare";
import { ZONE_ID, ZONE_NAME } from "./zone";

const VPN_ONLY_HOSTNAMES = ["bilbo", "immich", "frigate", "home", "docs", "health", "notify", "requests"];
const BILBO_VPN_ADDRESS = "10.100.0.1";

export const vpnOnlyRecords = VPN_ONLY_HOSTNAMES.map(
  (name) =>
    new cloudflare.DnsRecord(`${name}-vpn-record`, {
      zoneId: ZONE_ID,
      name: `${name}.${ZONE_NAME}`,
      type: "A",
      content: BILBO_VPN_ADDRESS,
      proxied: false,
      ttl: 1,
      comment: "VPN only, managed by bilbo-remote",
    }),
);
