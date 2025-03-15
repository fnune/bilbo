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

This project uses local state, and if state were lost, it could be recovered by
gathering some information on AWS and importing it like so:

```sh
pulumi import '<type>'                 '<name>'      '<id>'
pulumi import aws:s3/bucketV2:BucketV2 bilbo-backups bilbo-backups-123456
```

There is [more documentation on the Pulumi website](https://www.pulumi.com/docs/iac/adopting-pulumi/import/).
