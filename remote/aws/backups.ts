import * as aws from "@pulumi/aws";
import * as pulumi from "@pulumi/pulumi";

const NAME = "bilbo-backups";

const bucket = new aws.s3.BucketV2(NAME);
const user = new aws.iam.User(`${NAME}-user`, {});
const keys = new aws.iam.AccessKey(`${NAME}-user-keys`, { user: user.name });

new aws.s3.BucketPublicAccessBlock(`${NAME}-bucket-public-access-block`, {
  bucket: bucket.id,
  blockPublicAcls: true,
  blockPublicPolicy: true,
  ignorePublicAcls: true,
  restrictPublicBuckets: true,
});

new aws.s3.BucketLifecycleConfigurationV2(`${NAME}-lifecycle`, {
  bucket: bucket.id,
  rules: [
    {
      id: "glacier-transition",
      status: "Enabled",
      transitions: [
        {
          days: 0,
          storageClass: "DEEP_ARCHIVE",
        },
      ],
    },
  ],
});

const policy = new aws.iam.Policy(`${NAME}-policy`, {
  policy: bucket.arn.apply((arn) => ({
    Version: "2012-10-17" as const,
    Statement: [
      {
        Effect: "Allow" as const,
        Action: [
          "s3:PutObject",
          "s3:GetObject",
          "s3:ListBucket",
          "s3:DeleteObject",
          "s3:RestoreObject",
        ],
        Resource: [arn, `${arn}/*`],
      },
    ],
  })),
});

new aws.iam.UserPolicyAttachment(`${NAME}-policy-attachment`, {
  user: user.name,
  policyArn: policy.arn,
});

export const bucketName = bucket.id;
export const bucketAccessKeyId = keys.id;
export const bucketSecretAccessKey = keys.secret;
export const bucketRegion = aws.getRegionOutput().name;
export const bucketRcloneConfig = pulumi.interpolate`
[aws-glacier]
access_key_id = ${keys.id}
acl = private
provider = AWS
region = ${pulumi.output(aws.getRegion()).name}
secret_access_key = ${keys.secret}
storage_class = DEEP_ARCHIVE
type = s3
`;
