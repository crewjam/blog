+++
date = "2016-03-18T09:38:19-04:00"
title = "Building a Robust etcd cluster in AWS"
slug = "etcd-aws"
layout = "post"
image = "/images/2011_Library_of_Congress_USA_5466788868_card_catalog.jpg"
+++

Consensus based directories are the core of many distributed systems. People use tools like [zookeeper](https://zookeeper.apache.org/), [etcd](https://coreos.com/etcd/docs/latest/) and [consul](https://www.consul.io/) to manage distributed state, elect leaders, and discover services. Building a robust cluster of these services in a [chaotic environment](http://techblog.netflix.com/2012/07/chaos-monkey-released-into-wild.html) was trickier than I thought, so I'm documenting what I figured out here.

The source for all this is [available on github](https://github.com/crewjam/etcd-aws).

## Goals

1. Use cloudformation to establish a three node autoscaling group of etcd instances.
2. In case of the failure of a single node, we want the cluster to remain available and the replacement node to integrate into the cluster.
3. **Cycling**. If each node in the cluster is replaced by a new node, one at a time, the cluster should remain available.
4. We want to configure cloudformation such that updates to the launch configuration affect the rolling update described in #3.
5. In the event of failure of all nodes simultaneously, the cluster recovers, albiet with interruption in service. The state is restored from a previous backup.

## Cloudformation

We're using [go-cloudformation](https://godoc.org/github.com/crewjam/go-cloudformation) to produce our cloudformation templates. The template consists of:

- A VPC containing three subnets across three availability zones.
- An autoscaling group of CoreOS instances running etcd with an initial size of 3.
- An internal load balancer that routes etcd client requests to the autoscaling group.
- A lifecycle hook that monitors the autoscaling group and sends termination events to an SQS queue.
- An S3 bucket that stores the backup
- CloudWatch alarms that monitor the health of the cluster and that the backup is happening.

![](/images/aws-etcd-diagram.jpg)

## Wrapping etcd

To implement the various features that we need on top of etcd we'll write a program `etcd-aws` that discovers the correct configuration and invokes `etcd`. It will also handle the backups and cluster state monitoring that I'll describe later.

Because we're using CoreOS we'll need to replace the systemd unit file that replaces `etcd` with a wrapper. [Quoting](https://www.digitalocean.com/community/tutorials/understanding-systemd-units-and-unit-files):

> If you wish to modify the way that a unit functions, the best location to do so is within the `/etc/systemd/system` directory. Unit files found in this directory location take precedence over any of the other locations on the filesystem. If you need to modify the system's copy of a unit file, putting a replacement in this directory is the safest and most flexible way to do this.

So we replace the built-in `etcd2.service` with our own in `/etc/systemd/system/etcd2.service`:

~~~systemd
[Unit]
Description=etcd2
Conflicts=etcd.service

[Service]
Restart=always
EnvironmentFile=/etc/etcd_aws.env
ExecStart=/usr/bin/docker run --name etcd-aws \
  -p 2379:2379 -p 2380:2380 \
  -v /var/lib/etcd2:/var/lib/etcd2 \
  -e ETCD_BACKUP_BUCKET -e ETCD_BACKUP_KEY \
  --rm crewjam/etcd-aws
ExecStop=-/usr/bin/docker rm -f etcd-aws

[Install]
WantedBy=multi-user.target
~~~

The full source of `etcd-aws` is in [the github repo](https://github.com/crewjam/etcd-aws/).

## The Bootstrap Problem

Etcd provides three ways of bootstrapping, via the [discovery service](https://coreos.com/etcd/docs/latest/clustering.html#etcd-discovery) they operate, via [DNS SRV records](https://coreos.com/etcd/docs/latest/clustering.html#dns-discovery), and via [static configuration](https://coreos.com/etcd/docs/latest/clustering.html#static). 

### Bootstrapping via the discovery service

To use the discovery service you register your cluster specifying the initial cluster size and get back a random cluster ID. You provide that cluster cluster ID to each node you create. Using discovery requires that we bake the registration step into the CloudFormation template. This is possible with custom resources and lambda, but in the end it is annoying.

After the discovery service is aware of *n* nodes, subsequent nodes that check in are assumed to be ["proxies"](https://coreos.com/etcd/docs/latest/proxy.html), i.e. not full-fledged members of the cluster. This breaks cycling because any nodes launched after the first three will auto-discover as proxies, and as the initial nodes drop off, eventually all the nodes will be proxies and the cluster will break.

But the most important issue is that we introduce a dependence on a third-party service. We could run our own discovery service, but that requires a robust etcd--which is what we are trying to achieve in the first place!

### Bootstrapping via DNS SRV

We didn't look too hard at using DNS SRV records because it would introduce complexity that we're not super keen on having to manage.

### Bootstrapping via static

The only approach that remains is bootstraping via a static initial configuration. In this mode you specify some environment variables to etcd and it uses that to create the initial cluster. For example:

~~~bash
ETCD_NAME=i-cb94f313
ETCD_INITIAL_CLUSTER=i-19e3b3de=http://10.0.121.237:2380,i-cb94f313=http://10.0.50.67:2380,i-c8ccfa12=http://10.0.133.146:2380
ETCD_INITIAL_CLUSTER_STATE=new
ETCD_INITIAL_CLUSTER_TOKEN=arn:aws:autoscaling:us-west-2:012345678901:autoScalingGroup:8aa26c96-903f-481d-a43c-64bed19e9a58:autoScalingGroupName/etcdtest-MasterAutoscale-D0LX5CJYWRWY
~~~

This looks easy and simple, but there are a bunch of non-obvious contraints.

- The value in `ETCD_NAME` must be present in `ETCD_INITIAL_CLUSTER`.
- etcd derives the cluster ID from `ETCD_INITIAL_CLUSTER` when `ETCD_INITIAL_CLUSTER_STATE` is `new`, by hashing it or something. This means that `ETCD_INITIAL_CLUSTER` must be **identical** on all the nodes where `new` is specified. Same order. Same names. Identical.
- You might think that the cluster ID would be derived from `ETCD_INITIAL_CLUSTER_TOKEN`, but it isn't. `ETCD_INITIAL_CLUSTER_TOKEN` is a safety feature to keep clusters from getting mixed up, but it is not used to seed the cluster ID. 
- Nodes will not elect a leader until *n* / 2 + 1 of the nodes defined in `ETCD_INITIAL_CLUSTER` are present. It appears that you cannot join a cluster with `ETCD_INITIAL_CLUSTER_STATE=existing` until this has happend.

## The Bootstrap Solution

To make this work we need to get at least two nodes to invoke `etcd` with the exact same `ETCD_INITIAL_CLUSTER` and `ETCD_INITIAL_CLUSTER_STATE=new`. After that we only need to get `ETCD_INITIAL_CLUSTER` mostly correct and can use `ETCD_INITIAL_CLUSTER_STATE=existing`.

When `etcd-aws` starts it determines the current members of the cluster using [ec2cluster](https://github.com/crewjam/etcd-aws/) which introspects the current instance's metadata and EC2 for the configuration of other instances. For our purposes, a cluster member is any instance in the same autoscaling group.

Next we attempt to contact each node in the cluster to determine if the cluster currently has a leader. If any node can be contacted and reports a leader then we assume the cluster is in the `existing` state, otherwise we assume the cluster is `new`. (Remember: we have to have at least two nodes that join as `new` in order to bootstrap the cluster and elect our first leader.)

We construct the `ETCD_INITIAL_CLUSTER` value using the EC2 instance ID for the node name and the node's private IP address.

We're almost there, but not quite. I've observed cases where new nodes fail to join existing clusters with a message like this:

    etcdmain: error validating peerURLs {ClusterID:500f903265bef4ea Members:[&{ID:7452025f0b7cee3e RaftAttributes:{PeerURLs:[http://10.0.133.146:2380]} Attributes:{Name:i-c8ccfa12 ClientURLs:[http://10.0.133.146:2379]}}] RemovedMemberIDs:[]}: member count is unequal

This can be resolved by telling an existing node of the cluster about the new node just before starting the new etcd. We can do this by manually joining the node to the cluster by making a `POST` request to the `/v2/members` endpoint on one of the existing nodes.

## The Cycling Problem

So now we can launch a cluster from nothing -- nifty. But because it's 2016 and all the cool kids are doing [immutable infrastructure](https://www.google.com/search?q=immutable%20infrastructure) we have to as well. Here is where things get tricky.

Etcd uses the [Raft consensus algorithm](https://speakerdeck.com/benbjohnson/raft-the-understandable-distributed-consensus-protocol) to maintain consistency. The algorithm requires that a quorum of nodes be in-sync to make a decision. If you have an *n*-node cluster, you'll need *n* / 2 + 1 nodes for a quorum.

So what happens when we replace each node one at a time?

| State                    | Total Nodes | Alive Nodes | Dead Nodes | Quorum |
|--------------------------|-------------|-------------|------------|--------|
| Initial                  | 3           | 3           | 0          | 2      |
| After first replacement  | 4           | 3           | 1          | 3      |
| After second replacement | 5           | 3           | 2          | 3      |
| After third replacement  | 6           | 3           | 3          | 4      |

1. In the initial state we have three nodes. Two are required for quorum.
2. We create a node and destroy a node. Now the cluster thinks there are *n*=4 nodes, one of which is unreachable. Three are required for quorum.
3. We create a node and destroy a node. Now *n*=5, with two nodes unreachable and three required for quorum. 
4. We create a node and destroy a node. Now *n*=6, with three nodes unreachable and four required for quorum.  

**Boom!** Cluster broken. At this point it is impossible for the cluster to elect a leader. The missing nodes will never rejoin, but the cluster doesn't know that, so they still count against the count required for quorum.

Crap.

The documentation describes how a node can be gracefully shut down, removing it from the cluster. For robustness, we don't want to rely on, or even expect that we'll be able to shut a node down cleanly -- remember [it's chaotic out there](http://techblog.netflix.com/2012/07/chaos-monkey-released-into-wild.html).

## The Cycling Solution

Whever an instance is terminated we want to tell the remaining nodes about it so that our terminated instance doesn't count against *n* for the purposes of determining if there is a quorum. We don't want to interfere too much with the failure detection built in to etcd, just give it a hint when autoscaling takes a node away. 

[Auto Scaling lifecycle hooks](http://docs.aws.amazon.com/AutoScaling/latest/DeveloperGuide/lifecycle-hooks.html) are just the ticket.

We create a lifecycle hook that notifies us whenever an instance is terminated. Experimentally, this works no matter if autoscaling kills your instance or if you kill an instance by hand.

~~~go
t.AddResource("MasterAutoscaleLifecycleHookQueue", cfn.SQSQueue{})
t.AddResource("MasterAutoscaleLifecycleHookTerminating", cfn.AutoScalingLifecycleHook{
    AutoScalingGroupName:  cfn.Ref("MasterAutoscale").String(),
    NotificationTargetARN: cfn.GetAtt("MasterAutoscaleLifecycleHookQueue", "Arn"),
    RoleARN:               cfn.GetAtt("MasterAutoscaleLifecycleHookRole", "Arn"),
    LifecycleTransition:   cfn.String("autoscaling:EC2_INSTANCE_TERMINATING"),
    HeartbeatTimeout:      cfn.Integer(30),
})
~~~

Next we create a service that will read from the queue and will tell etcd that the node is deleted whenever that happens.

~~~go
// handleLifecycleEvent is invoked whenever we get a lifecycle terminate message. It removes
// terminated instances from the etcd cluster.
func handleLifecycleEvent(m *ec2cluster.LifecycleMessage) (shouldContinue bool, err error) {
    if m.LifecycleTransition != "autoscaling:EC2_INSTANCE_TERMINATING" {
        return true, nil
    }

    // look for the instance in the cluster
    resp, err := http.Get(fmt.Sprintf("%s/v2/members", etcdLocalURL))
    if err != nil {
        return false, err
    }
    members := etcdMembers{}
    if err := json.NewDecoder(resp.Body).Decode(&members); err != nil {
        return false, err
    }
    memberID := ""
    for _, member := range members.Members {
        if member.Name == m.EC2InstanceID {
            memberID = member.ID
        }
    }

    req, _ := http.NewRequest("DELETE", fmt.Sprintf("%s/v2/members/%s", etcdLocalURL, memberID), nil)
    _, err = http.DefaultClient.Do(req)
    if err != nil {
        return false, err
    }

    return false, nil
}
~~~

This code runs whenever the `etcd-aws` wrapper is running.

## Rolling Updates

In AWS AutoScaling, launch configurations define how your instances get created. Normally when we make changes to a launch configuration in CloudFormation, it does not effect already running instances. 

To be buzzword compliant with "immutable infrastructure", we have to tell CloudFormation to perform rolling updates across our cluster whenever we make a change to the launch configuration. To affect this, we add an `UpdatePolicy` and `CreationPolicy` to the template. We're telling CloudFormation to do rolling updates and to wait for a signal that each node is alive before proceeding to the next.

~~~go
t.Resources["MasterAutoscale"] = &cfn.Resource{
    UpdatePolicy: &cfn.UpdatePolicy{
        AutoScalingRollingUpdate: &cfn.UpdatePolicyAutoScalingRollingUpdate{
            MinInstancesInService: cfn.Integer(3),
            PauseTime:             cfn.String("PT5M"),
            WaitOnResourceSignals: cfn.Bool(true),
        },
    },
    CreationPolicy: &cfn.CreationPolicy{
        ResourceSignal: &cfn.CreationPolicyResourceSignal{
            Count:   cfn.Integer(3),
            Timeout: cfn.String("PT5M"),
        },
    },
    Properties: cfn.AutoScalingAutoScalingGroup{
        DesiredCapacity:         cfn.String("3"),
        MaxSize:                 cfn.String("5"),
        MinSize:                 cfn.String("3"),
        // ...
    },
}
~~~

Now we need to send the signal that we are ready whenever systemd reports that etcd is running. For that we use a `oneshot` service:

~~~systemd
[Unit]
Description=Cloudformation Signal Ready
After=docker.service
Requires=docker.service
After=etcd2.service
Requires=etcd2.service

[Install]
WantedBy=multi-user.target

[Service]
Type=oneshot
EnvironmentFile=/etc/environment
ExecStart=/bin/bash -c '\
eval $(docker run crewjam/ec2cluster); \
docker run --rm crewjam/awscli cfn-signal \
    --resource MasterAutoscale --stack $TAG_AWS_CLOUDFORMATION_STACK_ID \
    --region $REGION; \
'
~~~

With this configured we get the kind of rolling updates that we want. Here is an excerpt of the CloudFormation events that are emitted when performing a rolling upgrade.

~~~console
Temporarily setting autoscaling group MinSize and DesiredCapacity to 4.
Rolling update initiated. Terminating 3 obsolete instance(s) in batches of 1, while keeping at least 3 instance(s) in service. Waiting on resource signals with a timeout of PT15M when new instances are added to the autoscaling group.
New instance(s) added to autoscaling group - Waiting on 1 resource signal(s) with a timeout of PT15M.
Received SUCCESS signal with UniqueId i-81c6a159
Terminating instance(s) [i-48fa9d90]; replacing with 1 new instance(s).
New instance(s) added to autoscaling group - Waiting on 1 resource signal(s) with a timeout of PT15M.
Successfully terminated instance(s) [i-48fa9d90] (Progress 33%).
Received SUCCESS signal with UniqueId i-0dc4a3d5
Terminating instance(s) [i-b2095a75]; replacing with 1 new instance(s).
Successfully terminated instance(s) [i-b2095a75] (Progress 67%).
New instance(s) added to autoscaling group - Waiting on 1 resource signal(s) with a timeout of PT15M.
Successfully terminated instance(s) [i-7aa294a0] (Progress 100%).
Terminating instance(s) [i-7aa294a0]; replacing with 0 new instance(s).
Received SUCCESS signal with UniqueId i-203360e7
UPDATE_COMPLETE
~~~

## Load Balancer for Service Discovery

The CloudFormation template specifies an elastic load balancer for the etcd nodes. The purpose of this load balancer is to be suitable as a value of `ETCD_PEERS` for etcd clients. The etcd client negotiates the list of peers on initial contact, so the load balancer just serves as a way to avoid having to keep an up-to-date list of peers for consumers of the service. After the initial sync, consumers communicate directly with the servers, so we still need tcp/2379 open from the rest of the VPC.

~~~go
t.AddResource("MasterLoadBalancer", cfn.ElasticLoadBalancingLoadBalancer{
    Scheme:  cfn.String("internal"),
    Subnets: cfn.StringList(parameters.VpcSubnets...),
    Listeners: &cfn.ElasticLoadBalancingListenerList{
        cfn.ElasticLoadBalancingListener{
            LoadBalancerPort: cfn.String("2379"),
            InstancePort:     cfn.String("2379"),
            Protocol:         cfn.String("HTTP"),
        },
    },
    HealthCheck: &cfn.ElasticLoadBalancingHealthCheck{
        Target:             cfn.String("HTTP:2379/health"),
        HealthyThreshold:   cfn.String("2"),
        UnhealthyThreshold: cfn.String("10"),
        Interval:           cfn.String("10"),
        Timeout:            cfn.String("5"),
    },
    SecurityGroups: cfn.StringList(
        cfn.Ref("MasterLoadBalancerSecurityGroup")),
})
~~~

## Backup

We need a persistent copy of the database in order to facilitate recovery in case all nodes fail. 

To do this, I initially tried invoking `etcdctl backup` which creates a
consistent copy of the state, tarring up the results and storing them in S3. 
This approach didn't work for me. Both the actual objects being stored **and** information about the cluster state are captured in the backup. When restoring to a new cluster after complete node failure, the cluster state was broken and nothing worked. Ugh.

Instead it turned out to be pretty simple to capture each value directly using the etcd client, write them to a big JSON document and store *that* in S3.

~~~go
// dumpEtcdNode writes a JSON representation of the nodes to w
func dumpEtcdNode(key string, etcdClient *etcd.Client, w io.Writer) {
    response, _ := etcdClient.Get(key, false, false)
    json.NewEncoder(w).Encode(response.Node)
    for _, childNode := range childNodes {
        if childNode.Dir {
            dumpEtcdNode(childNode.Key, etcdClient, w)
        } else {
            json.NewEncoder(w).Encode(childNode)
        }
    }
}
~~~

We want the backup to run on exactly one node very few minutes. We could hold a leader election using etcd itself, but it seemed easier to just run the backup on the current leader of the cluster.

~~~go
// if the cluster has a leader other than the current node, then skip backup.
if nodeState.LeaderInfo.Leader != "" || nodeState.ID != nodeState.LeaderInfo.Leader {
    log.Printf("%s: http://%s:2379/v2/stats/self: not the leader", *instance.InstanceId,
        *instance.PrivateIpAddress)
    continue
}
~~~

### Restoring

We want the cluster to automatically recover from failure of all nodes. This should happen when:

1. The cluster does not yet have a leader, i.e. `ETCD_INITIAL_CLUSTER_STATE` is `new`.
2. The local node does not have any files in the data directory.
3. The backup exists in S3.

Note that there is a race condition here -- For a three node cluster, it is possible that the restore process could take place on two nodes. Since they are restoring the same thing, this seems to me like it doesn't matter much.

## Health Checking

To monitor the health of the cluster, we create a CloudWatch alarm that checks the state of the Elastic Load Balancer:

~~~go
t.AddResource("MasterLoadBalancerHealthAlarm", cfn.CloudWatchAlarm{
    ActionsEnabled:     cfn.Bool(true),
    AlarmActions:       cfn.StringList(cfn.Ref("HealthTopic").String()),
    OKActions:          cfn.StringList(cfn.Ref("HealthTopic").String()),
    AlarmDescription:   cfn.String("master instance health"),
    AlarmName:          cfn.String("MasterInstanceHealth"),
    ComparisonOperator: cfn.String("LessThanThreshold"),
    EvaluationPeriods:  cfn.String("1"),
    Dimensions: &cfn.CloudWatchMetricDimensionList{
        cfn.CloudWatchMetricDimension{
            Name:  cfn.String("LoadBalancerName"),
            Value: cfn.Ref("MasterLoadBalancer").String(),
        },
    },
    MetricName: cfn.String("HealthyHostCount"),
    Namespace:  cfn.String("AWS/ELB"),
    Period:     cfn.String("60"),
    Statistic:  cfn.String("Minimum"),
    Unit:       cfn.String("Count"),

    // Note: for scale=3 we should have no fewer than 1 healthy instance
    // *PER AVAILABILITY ZONE*. This is confusing, I know.
    Threshold: cfn.String("1"),
}) 
~~~

The load balancer, in turn, determines the health of each instance by querying each etcd instance's self reported health url:

~~~go
HealthCheck: &cfn.ElasticLoadBalancingHealthCheck{
    Target:             cfn.String("HTTP:2379/health"),
    HealthyThreshold:   cfn.String("2"),
    UnhealthyThreshold: cfn.String("10"),
    Interval:           cfn.String("10"),
    Timeout:            cfn.String("5"),
}
~~~

### Backup Health

We also want to make sure that the backup keeps running. We want to get alerted if the backup file gets old. To make this happen, we create a custom CloudWatch metric and emit it every time the backup completes:

~~~go
cloudwatch.New(s.AwsSession).PutMetricData(&cloudwatch.PutMetricDataInput{
    Namespace: aws.String("Local/etcd"),
    MetricData: []*cloudwatch.MetricDatum{
        &cloudwatch.MetricDatum{
            MetricName: aws.String("BackupKeyCount"),
            Dimensions: []*cloudwatch.Dimension{
                &cloudwatch.Dimension{
                    Name:  aws.String("AutoScalingGroupName"),
                    Value: aws.String(getInstanceTag(instance, "aws:autoscaling:groupName")),
                },
            },
            Unit:  aws.String(cloudwatch.StandardUnitCount),
            Value: aws.Float64(float64(valueCount)),
        },
    },
})
~~~

This metric tells us how many values are present in the backup. We care about that a little, but mostly we care that `PutMetricData` gets invoked every once in a while to provide these data. In other words, we care most about the `INSUFFICIENT_DATA` case.

~~~go
// this alarm is triggered (mostly) by the requirement that data be present.
// if it isn't for 300 seconds, then the backups are failing and the check goes
// into the INSUFFICIENT_DATA state and we are alerted.
t.AddResource("MasterBackupHealthAlarm", cfn.CloudWatchAlarm{
    ActionsEnabled:          cfn.Bool(true),
    AlarmActions:            cfn.StringList(cfn.Ref("HealthTopic").String()),
    InsufficientDataActions: cfn.StringList(cfn.Ref("HealthTopic").String()),
    OKActions:               cfn.StringList(cfn.Ref("HealthTopic").String()),
    AlarmDescription:        cfn.String("key backup count"),
    AlarmName:               cfn.String("MasterBackupKeyCount"),
    ComparisonOperator:      cfn.String("LessThanThreshold"),
    EvaluationPeriods:       cfn.String("1"),
    Dimensions: &cfn.CloudWatchMetricDimensionList{
        cfn.CloudWatchMetricDimension{
            Name:  cfn.String("AutoScalingGroupName"),
            Value: cfn.Ref("MasterAutoscale").String(),
        },
    },
    MetricName: cfn.String("BackupKeyCount"),
    Namespace:  cfn.String("Local/etcd"),
    Period:     cfn.String("300"),
    Statistic:  cfn.String("Minimum"),
    Unit:       cfn.String("Count"),
    Threshold:  cfn.String("1"),
})
~~~

## Oh. em. geez.

That seems like it was harder than it needed to be, eh? But, we now have a cloudformation template where we can: 

- Generate a working *etcd* cluster from scratch.
- Terminate arbitrary instances and watch the cluster recover.
- Perform a rolling replacement of each node.
- Backup and automatic restore in S3 to handle failure of all nodes
- Health check for the service and the backup.

Pfew! That was a *lot* more work that I thought it would be. 

I'd be grateful for questions, comments, or suggestions -- I'm [@crewjam](https://twitter.com/crewjam) on twitter.

Image Credit: [tedeytan](http://flickr.com/photos/22526649@N03/5466788868)
