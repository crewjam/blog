+++
date = "2015-03-06T00:00:00"
title = "Ephemeral Encryption in AWS"
description = "in which we throw away our private keys"
image = "/images/Padlocks_sign_nseoultower.jpg"
layout = "post"
slug = "aws-ephemeral-crypto"
+++

How we use volume encryption in our AWS ephemeral disks

<!--more-->

> You should encrypt data at rest. 

That's like the 8th commandment or something. Why? I can think of a few reasons:

1. You are worried about a malicious insider. 
2. You are worried about carelessness.
3. Someone (a regulator, probably) made you do it.

There's lots of snake oil out there about data encryption, particularly in the cloud. In this post I'll share our solution for data-at-rest encryption in AWS. (Most of this is general to cloud compute providers, just in case you are one of the 38 people that use something other than AWS.)

# throw away the key

Key management is super tricky to do correctly and I'm super lazy. So when we needed to do volume encryption in AWS, I looked for a way to avoid having to manage the keys.

Our app is hosted entirely in AWS. We receive data there, store it there and display it to the users there. Every single one of our EC2 instances uses the ephemeral store, including those for data storage. We keep the data available by using a distributed data store that replicates our data across instances (we use [Elastic Search](http://www.elasticsearch.org/)). [^ebs] 

[^ebs]: Part of this is an artifact of the time when EBS latency was unpredictable. Part of this is that we just don't need to use EBS because we are replicated at the database layer.

To protect the data at rest at on these instances, we create an encrypted volume and discard the key. This is from the code that runs when one of our instances first boots:

~~~python
from Crypto.PublicKey import RSA
from Crypto import Random

# ...

passphrase = Random.new().read(64).encode("hex")

# Encrypt the passphrase to the escrow key and store the encrypted
# passphrase on the server. This is for emergencies, since we don't
# really have any further need for the key.
if FULL_DISK_ENCRYPTION_KEY_ESCOW_PUBLIC_KEY:
  print "encrypted escrowed key at /root/.ephemeral_escrowed_key"
  key = RSA.importKey(FULL_DISK_ENCRYPTION_KEY_ESCOW_PUBLIC_KEY)
  data = key.encrypt(passphrase, None)[0].encode("base64")
  file("/root/.ephemeral_escrowed_key", "w").write(data)
  os.chmod("/root/.ephemeral_escrowed_key", 0400)

print "creating encrypted volume on", raid_device
subprocess.check_call("echo {passphrase} | cryptsetup luksFormat "
  "-c twofish-xts-plain64 -s 512 --key-file=- "
  "{raid_device}".format(**locals()), shell=True)

subprocess.check_call("echo {passphrase} | cryptsetup luksOpen "
  "--key-file=- {raid_device} ephemeral-encrypted".format(**locals()),
  shell=True)

print "creating filesystem on /dev/mapper/ephemeral-encrypted"
subprocess.check_call(["mkfs", "-t", "ext4", "-T", "largefile4",
  "-F", "/dev/mapper/ephemeral-encrypted"])
~~~

When we first started doing this I was nervous about cases where we'd need the key again, so I generated an RSA key-pair to escrow the volume key and kept the private part in a safe. These days we are confident enough in our approach that we don't need to escrow the volume key any more.

Even though we've discarded our copy of the key, the kernel still has a copy. And the kernel copy is [discoverable if you have access to memory](http://events.ccc.de/camp/2007/Fahrplan/attachments/1300-Cryptokey_forensics_A.pdf). The guest kernel keeps these keys in non-paged memory, but I wonder if the hypervisor respects that? If not and the hypervisor pages guest memory then the encryption key could end up on a disk somewhere.[^future_work]

[^future_work]: I'd be interested to hear from you if you know or find out how this works...

It is probably a good idea to disable commands like `reboot` and `shutdown` so you don't accidentally do something you'll regret. We haven't bothered to do that because we live in a world where we are (almost) never sad if we lose a machine. (Perhaps I'll write more about that someday)

Some days we are sad, like when [AWS needs to reboot loads of instances](http://aws.amazon.com/blogs/aws/ec2-maintenance-update/) all at once. We have to make sure we stay on top of maintenance events so we don't get too many instances needing to restart, since we have to replace rather than restart.

So why isn't this crazy? Let's go through our (admittedly informal) threat model a bit.

# A malicious insider

Consider the risk that a malicious employee of Amazon steals your data.

Insider threat exists in all networks. The important question to consider is not "am I vulnerable to an insider?" -- that answer always "yes." A better question is "am I *more* vulnerable to insider threat in AWS than in my datacenter?" The answer to that is a little more interesting...

<img style="float: right; width: 400px; padding-left: 20px;" src="/images/299px-RFControlPanel2.jpg" />

If you are using AWS for data processing, the CPUs will need access to unencrypted data (setting aside boring use cases like blind storage, or fancy impractical things like [homomorphic encryption](http://www.wired.com/2014/11/hacker-lexicon-homomorphic-encryption/)). So however you organize it, the key or key-equivalent to decrypt your data must be accessible to the CPUs doing the work.

Services like [CloudHSM](http://aws.amazon.com/cloudhsm/), [KMS](http://aws.amazon.com/kms/), or even [on-premise key management](http://www.safenet-inc.com/data-encryption/hardware-security-modules-hsms/) don't fundamentally change this issue. If you move encryption keys (or encryption operations themselves) into a separate device, the credentials used to access that device become equivalent to the keys themselves.[^cloudhsm]

[^cloudhsm]: That isn't to say that these devices don't provide security value. The value is in post-incident investigation, auditing, key rotation, access control and so on. These are all super important, it's just that they don't fundamentally change the threat model.

Fortunately, AWS are somewhat transparent about [how they mitigate insider threat](http://d0.awsstatic.com/whitepapers/Security/AWS%20Security%20Whitepaper.pdf). And they seem to be doing a fairly good job. Better, perhaps than [you are doing in your data center](http://www.datacenterknowledge.com/archives/2007/12/08/oceans-11-data-center-robbery-in-london/).

A malicious insider at AWS faces another challenge that an on-premise attacker doesn't: she doesn't understand your business. The folks whose badges open the doors to your datacenter probably understand your business pretty well. They sit in company meetings, they participate in projects, etc. When they become disgruntled, they know exactly where the most important assets are to snatch. An insider at AWS, although having access to your data, might not know which data matters. Point Amazon.

Bottom line we can't really mitigate insider threat with volume encryption. But at least Amazon doesn't make the situation any worse, and it might even make it better.

**Protecting data from a malicious insider is an explicit non-goal.** Which is lucky because it's impossible.

# A careless insider at AWS

<img style="float: right; width: 400px; padding-left: 20px;" src="/images/88b5821e80b3b19f9813bd0c5d9919d9_623x412.jpg" />

What about the risk of carelessness by AWS? They say disks don't leave their datacenters, but what if that is more aspirational than descriptive? [^caveat]

[^caveat]: I have no reason to suspect that AWS are doing anything wrong, we just want to understand the consequences if they are.

Data-at-rest encryption helps here. Imagine the case where the underlying disk containing your data walks out into the open. If the disk does not also include the encryption key, then it presents little risk.

Another not-so-crazy case to consider is multi-tenancy. Imagine a disk used to hold your data is re-provisioned to another customer. AWS claims your data will not be accessible. But what if they are wrong? Again, if the disk does not also include the encryption key, then it presents little risk.

# Compliance

This is the easiest. You have to do it, even if it doesn't significantly affect your security posture. Information Security is about mitigating mission risk -- including the risk that your mission gets shut down because of non-compliance. So there are times when you may need to add data-at-rest encryption even when you think if presents little security value.

# TL;DR

Key management is hard. When possible, skip it. In a fault tolerant system, it should be possible. It was for us.

Image: [buenosaurus](http://commons.wikimedia.org/wiki/User:Optx)

