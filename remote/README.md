# Bilbo Remote

Pulumi project for what Bilbo needs outside itself: the S3 bucket for off-site
backups, the DNS records and the API token at Cloudflare.

You need `direnv`, an `.envrc` file with `use flake`, and a Pulumi login to the `fnune` org.

AWS credentials come from the `production` ESC environment the stack imports: it assumes the `bilbo-esc` role over OIDC (`aws/esc-oidc.ts`) and hands each deploy one-hour credentials, so no AWS key is stored anywhere. The role can only manage the backup bucket, user and policy. Changing the role itself, its OIDC provider or the backup user's permissions boundary needs an admin login to the AWS account.

The Cloudflare credential needs "API Tokens: Edit" in addition to its DNS
permissions, because this project creates the DNS token that bilbo uses.

Two outputs go into `../secrets/bilbo.yaml` with `sops`:

```sh
pulumi stack output bilboDnsTokenValue --show-secrets | sops set ../secrets/bilbo.yaml '["cloudflare-dns-token"]' "\"$(cat)\""
pulumi stack output bucketRcloneConfig --show-secrets | sops set ../secrets/bilbo.yaml '["rclone-conf"]' "\"$(cat)\""
```

Run `pulumi up` before `nixos-rebuild` when both change. The private DNS records
point at bilbo's WireGuard address; the `dyndns` service on bilbo owns the public
ones and must not manage the same names.

## Accessing the output

To access the output and transfer it to Bilbo:

```sh
pulumi up
pulumi stack output
pulumi stack output --show-secrets
```

## Bootstrapping

If state were lost, it could be recovered by running:

```sh
pulumi import '<type>'                 '<name>'      '<id>'

# Cloudflare
pulumi import "cloudflare:index/apiToken:ApiToken" "bilbo-dns-token" "<TOKEN_ID>"
pulumi import "cloudflare:index/dnsRecord:DnsRecord" "home-vpn-record" "<ZONE_ID>/<RECORD_ID>"   # and bilbo, immich, frigate, docs

# AWS S3
pulumi import "aws:s3/bucketV2:BucketV2" "bilbo-backups" "<BUCKET_NAME>"
pulumi import "aws:s3/bucketPublicAccessBlock:BucketPublicAccessBlock" "bilbo-backups-bucket-public-access-block" "<BUCKET_NAME>"
pulumi import "aws:s3/bucketVersioningV2:BucketVersioningV2" "bilbo-backups-versioning" "<BUCKET_NAME>"
pulumi import "aws:s3/bucketLifecycleConfigurationV2:BucketLifecycleConfigurationV2" "bilbo-backups-lifecycle" "<BUCKET_NAME>"

# AWS IAM
pulumi import "aws:iam/user:User" "bilbo-backups-user" "<USER_NAME>"
pulumi import "aws:iam/accessKey:AccessKey" "bilbo-backups-user-keys" "<ACCESS_KEY_ID>"
pulumi import "aws:iam/policy:Policy" "bilbo-backups-policy" "<POLICY_ARN>"
pulumi import "aws:iam/userPolicyAttachment:UserPolicyAttachment" "bilbo-backups-policy-attachment" "<USER_NAME>/<POLICY_ARN>"
```

There is [more documentation on the Pulumi website](https://www.pulumi.com/docs/iac/adopting-pulumi/import/). Find [the Pulumi stack on Pulumi Cloud](https://app.pulumi.com/fnune/bilbo-remote/production).

## Restoring from backups

The [`restore.sh`](./restore.sh) script automates restoring Borg backups from
AWS S3 Glacier Deep Archive. It uses Pulumi stack outputs to retrieve bucket
configuration.

1. Initiate restoration with `./restore.sh initiate`
2. Check status with `./restore.sh status`
3. Download files once available with `./restore.sh download [destination]`

> Restoring should cost about ~90€ per 1TB.

Once the download is finished, you'll need to restore it using `borg`, because
it's a `borg` archive. Note that the archive is passphrase-protected. Look for
_Bilbo Borg + S3 + Pulumi Credentials -> Borg Repository Password_ in
Bitwarden.

To start, list the available archives:

```sh
borg list ./borg-restore

Enter passphrase for key /home/fausto/Development/bilbo/remote/borg-restore:
bilbo-mirrored-2025-03-15T17:10:29   Sat, 2025-03-15 17:10:32 [57d057f03ea932d3448e8f1892ff19dce7b7af3ebc6db28f3fd49a15f16fbe53]
bilbo-mirrored-2025-03-15T17:46:14   Sat, 2025-03-15 17:46:16 [8a65ed0026069d11200e2f021707c77d5c5389598972b0fb024485f53c866418]
```

Then, you can choose to mount a repository, e.g.:

```sh
mkdir ./borg-mount
borg mount ./borg-restore::bilbo-mirrored-2025-03-15T17:10:29 ./borg-mount
umount ./borg-mount
```

Or extract it:

```sh
borg extract ./borg-restore::bilbo-mirrored-2025-03-15T17:10:29 ./borg-out
```

SQLite databases are in the archive as snapshots under
`var/lib/backup-sqlite-snapshots/<original path>`, not at their original path.
See [Backups](../README.md#backups) for how to put one back.
