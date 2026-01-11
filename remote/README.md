# Bilbo Remote

This is an infrastructure project that uses Pulumi to e.g. maintain an S3
bucket for off-site backups of critical data within Bilbo.

To use it, you'll need `direnv` and an `.envrc` file:

```sh
use flake

export AWS_ACCESS_KEY_ID='<access_key>'
export AWS_SECRET_ACCESS_KEY='<secret_key>'
export AWS_REGION='eu-central-1'

export PULUMI_CONFIG_PASSPHRASE='<pulumi_passphrase>'
```

> Look for `Bilbo Borg + S3 + Pulumi Credentials` on Bitwarden.

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
pulumi import "cloudflare:index/zeroTrustAccessPolicy:ZeroTrustAccessPolicy" "bilbo-access-policy" "accounts/<ACCOUNT_ID>/<POLICY_ID>"
pulumi import "cloudflare:index/zeroTrustAccessApplication:ZeroTrustAccessApplication" "bilbo-access-app" "accounts/<ACCOUNT_ID>/<APP_ID>"

# AWS S3
pulumi import "aws:s3/bucketV2:BucketV2" "bilbo-backups" "<BUCKET_NAME>"
pulumi import "aws:s3/bucketPublicAccessBlock:BucketPublicAccessBlock" "bilbo-backups-bucket-public-access-block" "<BUCKET_NAME>"
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
