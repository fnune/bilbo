import * as cloudflare from "@pulumi/cloudflare";
import { ZONE_ID, ZONE_NAME } from "./zone";

// fnune.com sends and receives no mail. These records say so, so no one can
// spoof the domain while it is dormant. Replace them with the real provider's
// MX, SPF and DKIM when mail moves onto the domain. The stale ProtonMail
// records these supersede are deleted out of band; see remote/README.md.

// RFC 7505 null MX: the domain accepts no mail.
export const nullMx = new cloudflare.DnsRecord("fnune-null-mx", {
  zoneId: ZONE_ID,
  name: ZONE_NAME,
  type: "MX",
  content: ".",
  priority: 0,
  ttl: 1,
  comment: "no mail, managed by bilbo-remote",
});

// No host is authorized to send as the domain.
export const spfDeny = new cloudflare.DnsRecord("fnune-spf-deny", {
  zoneId: ZONE_ID,
  name: ZONE_NAME,
  type: "TXT",
  content: '"v=spf1 -all"',
  ttl: 1,
  comment: "no mail, managed by bilbo-remote",
});

// Reject any mail claiming to be from the domain or a subdomain.
export const dmarcReject = new cloudflare.DnsRecord("fnune-dmarc-reject", {
  zoneId: ZONE_ID,
  name: `_dmarc.${ZONE_NAME}`,
  type: "TXT",
  content: '"v=DMARC1; p=reject; sp=reject"',
  ttl: 1,
  comment: "no mail, managed by bilbo-remote",
});
