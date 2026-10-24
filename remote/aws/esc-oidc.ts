import * as aws from "@pulumi/aws";
import * as pulumi from "@pulumi/pulumi";
import { keepsBackupUserOnItsBucket } from "./backups";

const NAME = "bilbo-esc";
const ORG = pulumi.getOrganization();
const AUDIENCE_OF_DEFAULT_PROJECT_ESC_ENVIRONMENTS = ORG;
const account = aws.getCallerIdentityOutput().accountId;

const oidc = new aws.iam.OpenIdConnectProvider("pulumi-esc-oidc", {
  url: "https://api.pulumi.com/oidc",
  clientIdLists: [AUDIENCE_OF_DEFAULT_PROJECT_ESC_ENVIRONMENTS],
});

const role = new aws.iam.Role(NAME, {
  name: NAME,
  assumeRolePolicy: oidc.arn.apply((arn) =>
    JSON.stringify({
      Version: "2012-10-17",
      Statement: [
        {
          Effect: "Allow",
          Principal: { Federated: arn },
          Action: "sts:AssumeRoleWithWebIdentity",
          Condition: {
            StringEquals: {
              "api.pulumi.com/oidc:aud": AUDIENCE_OF_DEFAULT_PROJECT_ESC_ENVIRONMENTS,
            },
            StringLike: { "api.pulumi.com/oidc:sub": `pulumi:environments:org:${ORG}:env:*` },
          },
        },
      ],
    }),
  ),
});

new aws.iam.RolePolicy(`${NAME}-manages-backups-and-only-reads-its-guardrails`, {
  role: role.name,
  policy: pulumi
    .all([account, oidc.arn, keepsBackupUserOnItsBucket.arn])
    .apply(([account, oidcArn, boundaryArn]) => {
      const backupUsers = `arn:aws:iam::${account}:user/bilbo-backups-user-*`;
      return JSON.stringify({
        Version: "2012-10-17",
        Statement: [
          {
            Sid: "BackupBucket",
            Effect: "Allow",
            Action: "s3:*",
            Resource: ["arn:aws:s3:::bilbo-backups-*", "arn:aws:s3:::bilbo-backups-*/*"],
          },
          {
            Sid: "BackupUser",
            Effect: "Allow",
            Action: [
              "iam:GetUser",
              "iam:DeleteUser",
              "iam:TagUser",
              "iam:UntagUser",
              "iam:ListUserTags",
              "iam:CreateAccessKey",
              "iam:DeleteAccessKey",
              "iam:UpdateAccessKey",
              "iam:ListAccessKeys",
              "iam:AttachUserPolicy",
              "iam:DetachUserPolicy",
              "iam:ListAttachedUserPolicies",
              "iam:ListUserPolicies",
              "iam:ListGroupsForUser",
              "iam:ListSigningCertificates",
              "iam:ListSSHPublicKeys",
              "iam:ListServiceSpecificCredentials",
              "iam:ListMFADevices",
              "iam:GetLoginProfile",
            ],
            Resource: backupUsers,
          },
          {
            Sid: "BackupUserOnlyWithBoundary",
            Effect: "Allow",
            Action: "iam:CreateUser",
            Resource: backupUsers,
            Condition: { StringEquals: { "iam:PermissionsBoundary": boundaryArn } },
          },
          {
            Sid: "BackupPolicy",
            Effect: "Allow",
            Action: [
              "iam:CreatePolicy",
              "iam:DeletePolicy",
              "iam:CreatePolicyVersion",
              "iam:DeletePolicyVersion",
              "iam:GetPolicy",
              "iam:GetPolicyVersion",
              "iam:ListPolicyVersions",
              "iam:ListEntitiesForPolicy",
              "iam:TagPolicy",
              "iam:UntagPolicy",
              "iam:ListPolicyTags",
            ],
            Resource: `arn:aws:iam::${account}:policy/bilbo-backups-policy-*`,
          },
          {
            Sid: "ReadOnlyGuardrails",
            Effect: "Allow",
            Action: ["iam:Get*", "iam:List*"],
            Resource: [`arn:aws:iam::${account}:role/${NAME}`, oidcArn, boundaryArn],
          },
        ],
      });
    }),
});

export const escRoleArn = role.arn;
