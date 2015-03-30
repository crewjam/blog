---
layout: post
title: Using Google Apps to log in to AWS
description: In which we point that maintaining user accounts sucks, avoiding it is hard, and share a tool to make it a tiny bit easier
modified: 2015-03-29
tags: []
image:
  feature: Herakles_Kerberos_Eurystheus_Louvre_E701.jpg

---

In which we point that maintaining user accounts sucks, avoiding it is hard, and share [a tool to make it a tiny bit easier](https://github.com/crewjam/awsconsoleauth) (I hope).

As your fledgling AWS infrastructure grows, it is tempting to start creating IAM users in your account. 

<img style="float: right; width: 400px; padding-left: 20px;" src="{{site.baseurl}}/images/15493266328_98f9224f60_z.jpg">

> "Hey Bob, can I get access to your cool app?

click click

> "Sure, Alice, your initial password is `hunter2`, make sure to change it right away."

A few moments pass and then:

> "Bob, my password doesn't work."

click click google google click click

> "Try it now"

silence

> "Wait, what's my username again?"

Sound familiar? 

Non-federated user accounts seem easy but they are usually wrong in the long run. First, it is a massive time sink--people need to be added and removed, they forget their passwords, they lose their 2FA tokens, stuff breaks and they ask you for help, and on and on...

Second, when your non-federated accounts get out of sync with HR (say because somebody quits or gets fired), then you have a security problem if the account isn't killed straightaway.
 
# Federation

Instead of creating accounts for each user in AWS we want to federate with existing mechanisms. ("federate" is auth nerd jargon, really we just mean "link".) The AWS API supports [lots](http://blogs.aws.amazon.com/security/post/Tx71TWXXJ3UI14/Enabling-Federation-to-AWS-using-Windows-Active-Directory-ADFS-and-SAML-2-0) [of](http://blogs.aws.amazon.com/security/post/Tx3LP54JOGBE0AY/Building-an-App-using-Amazon-Cognito-and-an-OpenID-Connect-Identity-Provider) [different](http://aws.amazon.com/about-aws/whats-new/2014/10/14/easier-role-selection-for-saml-based-single-sign-on/) federation mechanisms. 
Here's what we want:

1. Use Google OAuth to identify users
2. Use membership in a particular Google Groups to determine the AWS access policy we apply.
3. Provide direct, easy access to the AWS console.
4. Expose appropriate API credentials to the users so they can use the libraries and CLI.

I sifted through the APIs a bit and came to the conclusion that we needed to host a service to handle the authorization. The example tool didn't really seem to do this (and runs only on Windows, I think) and I wanted to get some OAuth experience, so I wrote a tool to do it, [available here](https://github.com/crewjam/awsconsoleauth).

# How It Works

- Your users navigate to this service.
- We redirect them through the Google login process.
- We check their group membership in the Google directory service to determine 
  which access policy to apply.
- We generate credentials using the AWS Token service and the GetFederationToken API.
- We build a URL to the AWS console that contains their temporary credentials 
  and redirect them there. 
 - Alternatively we pass their temporary credentials to
  them directly for use with the AWS API.

![]({{site.baseurl}}/images/DSC_1379.JPG)

A request for `https://aws.example.com/` eventually redirects to the root of the console. A request for `https://aws.example.com/?uri=/ec2/v2/home?region=us-east-1%23Instances:sort=desc:launchTime` redirects to the EC2 console view.

If you want the credentials directly, you can request `https://aws.example.com/?view=sh` which displays access keys suitable for pasting into a bash-style shell:

        # expires 2015-03-14 01:01:04 +0000 UTC
        export AWS_ACCESS_KEY_ID="ASIAJXXXXXXXXXXXXXXX"
        export AWS_SECRET_ACCESS_KEY="uS1aP/AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
        export AWS_SESSION_TOKEN="AQoD...i6gF"

You can also try `view=csh` and `view=fish`.

# Deployment

The included [CloudFormation](http://aws.amazon.com/cloudformation/) document creates a load balancer that listens for HTTPS connections on TCP/443 and proxies them via HTTP to instances in an autoscaling group of size 1. At boot, the instances run a the `awsauthproxy` docker image which runs `awsauthd`.

The configuration generates an AWS user whose credentials are used to call GetFederationToken(). These credentials have the maximum access that any of our federated users can have.

# Holy credentials, batman!

The various credentials and secrets we need to make this work get a little hairy. We have:

<img style="float: left; width: 200px; margin-right: 40px; margin-bottom: 20px" src="{{site.baseurl}}/images/Let_me_tell_you_a_secret.jpg" title="cc ed yurdon https://www.flickr.com/photos/72098626@N00/3741906651">
	
1. A Google OAuth client id and secret. This is used by the web application to authorize users.
2. A Google Service account. This is used by the web application to determine which groups an authorized user is in.
3. An AWS key and secret that serve as the root for the [GetFederationToken](http://docs.aws.amazon.com/STS/latest/APIReference/API_GetFederationToken.html) API call. These must be long-term credentials, not the kind of temporary, token-based credentials that you get from an instance profile.

So how do we protect these secrets from authorized non-root users of our AWS account? The Google secrets are parameters to the CloudFormation document while the AWS secret is known only at the time the CloudFormation stack is created.

For starters, anyone with SSH access to any of the EC2 instances would also have access to the keys. We protect that by carefully selecting the initial SSH key pair (or omit it entirely once everything is working -- that is what we do).

Anyone with access to the AWS resources that control the instance would also have access to the keys. We use the [CloudFormation metadata attributes](http://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/aws-attribute-metadata.html) to pass the secrets to the instance and restrict access to the CloudFormation document using an IAM policy.

Using metadata (attached to the launch config, but I think you can attach 'em anywhere you like):

    "LaunchConfig": {
      "Type": "AWS::AutoScaling::LaunchConfiguration",
      "Metadata": {
        "SecretAccessKey": {"Fn::GetAtt": ["FederationUserAccessKey", "SecretAccessKey"]},
        "GoogleClientSecret": {"Ref": "GoogleClientSecret"},
        "GoogleServicePrivateKey": {"Ref": "GoogleServicePrivateKey"}
      }

From within the instance we can snag the secret with [cfn-get-metadata](http://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/cfn-get-metadata.html):

	cfn-get-metadata -v -s authproxy -r LaunchConfig -k SecretAccessKey

*n.b.:* There seems to be special magic that allows the requests that *cfn-get-metadata* makes to succeed even when the instance has no credentials at all. Anyone know what that magic is?

This is the policy we attach to the user account we create. It prohibits access to our CloudFormation stack.

        {
          "PolicyName" : "MaxAllowedAccessOfFederatedUsers",
          "PolicyDocument" : {
            "Version": "2012-10-17",
            "Statement": [
              {
                "Effect": "Allow",
                "NotAction": "iam:*",
                "Resource": "*"
              },
              {
                "Action": ["cloudformation:*"],
                "Effect": "Deny",
                "Resource": {"Fn::Join": ["", ["arn:aws:iam",
                  {"Ref": "AWS::Region"}, ":", {"Ref": "AWS::AccountId"}, ":stack/",
                  {"Ref": "AWS::StackName"}, "/*"]]}
              }
            ]
          }
        }

Here is what happened when I logged in as a federated user to check that I couldn't inspect the stack:

![]({{site.baseurl}}/images/cfn_access_denied_1.png)

# Aside: some things that didn't work

## Fail #1: Specifying a C.F. Stack exactly

My first attempt at writing the policy document I used ``{"Ref": "AWS:StackId"}`` which emits an ARN like ``arn:aws:cloudformation:us-east-1:123456789012:stack/authproxy/daB6cc49-9510-4747-9378-94da915f7fb3``. **This didn't work to prevent access, although I expected it would.** (!!!) Through some trial and error I discovered that I had to specify the resource as ``arn:aws:cloudformation:us-east-1:123456789012:stack/authproxy/*``. Perhaps the UUID refers to the version of the document or something?

## Fail #2: Secrets in user data

Passing the secrets in the user data didn't work because we would have had to restrict access to the the CF stack, the autoscaling launch configuration and the EC2 instance. This was too tricky for me to get working. You might think you could write something this:

        {
            "Condition": {
                "StringEquals": {
                    "ec2:ResourceTag/aws:cloudformation:stack-id": {"Ref": "AWS::StackId"}
                }
            },
            "Resource": [
                "arn:aws:ec2:us-east-1:123456789012:instance/*"
            ],
            "Action": [
                "ec2:*"
            ],
            "Effect": "Deny"
        }

This is an invalid policy because apparently the colons in *aws:cloudformation:stack-id* are not allowed. Ugh!

## Fail #3: Secrets in S3

I considered putting the secrets in an S3 key and restricting access to the key. The problem is that there is no practical way to get the secret key (i.e. the result of invoking ``{"Fn::GetAtt": ["FederationUserAccessKey", "SecretAccessKey"]}``) into an S3 bucket using CloudFormation. We could use an *output* and some kind of follow-up script. But then we'd still have to protect the document in order to protect the output. So, using metadata is cleaner.

# Limitations

- The mapping from Google groups to AWS policies is currently hard coded. It would be nice to express the policy mappings as AWS IAM users, or groups or something. (This hack works for us but if you fix it, please shoot me a pull request)

- The size of policy document passed to GetFederationToken() is fairly limited.
  I had to remove stuff from the default ReadOnlyAccess policy to make it fit. (This works for us but if you fix it, please shoot me a pull request)

- All errors are reported to users in exactly the same way, by returning 
  *400 Bad Request*. This has the benefit of preventing any state leakage to 
  unauthorized users but is a little unfriendly. After carefully considering the
  implications, we might want errors that are a little friendlier.

- There is a public key to decrypt a part of response to the Google OAuth flow. We fetch the public key at startup, but Google rotates it with some regularity so we should fetch it periodically. (This is an honest-to-God bug which I intend to fix soon)

# Parting thoughts (mini-rant)

As hosted services go, IAM and CloudFormation are both extremely powerful. The folks that designed IAM obviously understood the need for a flexible and granular policy framework. What they built was a flexible, granular, and **very complicated** policy framework. 

When the complexity exceeds my ability to understand, it becomes increasingly difficult to ensure that the policy reflects my actual intentions.

For sure, this is a tough tradeoff to make, but it is an important one with security consequences on both sides. Too granular and the users can't reason about it; too simple and the users can't get the control they want. 

In this tradeoff, I think AWS have leaned a little too far towards complexity, but reasonable people can and do differ.
