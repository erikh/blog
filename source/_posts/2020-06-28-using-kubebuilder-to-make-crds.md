---
layout: post
title: Using kubebuilder to make CRDs and clients
tags:
  - Programming
  - Kubernetes
  - Golang
---

[kubebuilder](https://github.com/kubernetes-sigs/kubebuilder) is a front-end for a variety of code generators for Kubernetes resources, primarily for the use of creating [Custom Resource Definitions](https://kubernetes.io/docs/concepts/extend-kubernetes/api-extension/custom-resources/#customresourcedefinitions) and implementing the [Operator pattern](https://kubernetes.io/docs/concepts/extend-kubernetes/operator/). It's a newer, fancier version of the [generate-groups.sh](https://github.com/kubernetes/code-generator/blob/master/generate-groups.sh) script (with about 100% less cut and pasting, too).

It's a great way to get started with programming in a Kubernetes environment. It incorporates all the tooling and architecture you need to make code generate properly in Kubernetes into your repository, taking over your `Makefile`, `Dockerfile`, etc to provide you with useful defaults.

# Setup

First and foremost, kubebuilder will work, **by default** _with the kubernetes cluster configured in `~/.kube/config`_. It is advisable to install something like <https://k3s.io> to bootstrap something to play with, if you don't already have a preferred method. We will be working with Kubernetes **1.18** in this post.

Second, the release of kubebuilder you fetch is important as well; we are using kubebuilder **2.3.1**. You can find this release [here](https://github.com/kubernetes-sigs/kubebuilder/releases/tag/v2.3.1). [Kustomize](https://github.com/kubernetes-sigs/kustomize) is also necessary, we fetched **[3.6.1](https://github.com/kubernetes-sigs/kustomize/releases/tag/kustomize%2Fv3.6.1)**.

`kubebuilder` likes to be unpacked into `/usr/local/kubebuilder` for the tests, specifically. You can accomplish this like so:

```bash
$ sudo tar vxz --strip-components=1 -C /usr/local/kubebuilder -f kubebuilder.tar.gz
```

This will unpack other binaries like a `kube-apiserver` and `etcd` as well. Put `kustomize` somewhere in `$PATH`.

# The Plan

The plan is to update a CRD with a client we create; this client will simply insert a UUID (if possible) with some basic data. We will then explore this data from the kubectl command-line.

All examples will be in golang and use all the traditional `k8s.io` libraries. You should not need to, but could paste a lot of this code if necssary.

## Let's Initialize Our Repository

First things first, understand that `kubebuilder` wants to own every detail your repository from the build system, down to the license of the code it generates under. If you don't want this behavior, creating outside of the standard tree is probably advisable, or outside of the repository entirely, and depending on it instead.

This example removes the license to avoid forcing you to license your own code a specific way, but there are a few options. Every `kubebuilder` sub-command has a `--help` option.

```bash
# yes, you should run under $GOPATH.
$ mkdir $GOPATH/src/github.com/<your user>/k8s-api
$ cd $GOPATH/src/github.com/<your user>/k8s-api
# this kubebuilder command will spew a bunch of files into your repository.
$ kubebuilder init --domain example.org --license none
```

You will see some output like this:

```
erikh/k8s-api% kubebuilder init --domain example.org --license none
Writing scaffold for you to edit...
Get controller runtime:
$ go get sigs.k8s.io/controller-runtime@v0.5.0
Update go.mod:
$ go mod tidy
Running make:
$ make
/home/erikh/bin/controller-gen object:headerFile="hack/boilerplate.go.txt" paths="./..."
go fmt ./...
go vet ./...
go build -o bin/manager main.go
Next: define a resource with:
$ kubebuilder create api
```

This sets up a domain (you will get a default if you don't specify it) for your API which is encoded into the code generation.

If we look at the repository now, quite a bit has changed. We can see a `Makefile` as well as a bunch of directories:

```
drwxrwxr-x 2 erikh erikh  4096 Jun 28 11:15 bin/
drwx------ 8 erikh erikh  4096 Jun 28 11:15 config/
-rw------- 1 erikh erikh   795 Jun 28 11:15 Dockerfile
-rw------- 1 erikh erikh   357 Jun 28 11:15 .gitignore
-rw------- 1 erikh erikh   148 Jun 28 11:15 go.mod
-rw-rw-r-- 1 erikh erikh 44135 Jun 28 11:15 go.sum
drwx------ 2 erikh erikh  4096 Jun 28 11:15 hack/
-rw------- 1 erikh erikh  1444 Jun 28 11:15 main.go
-rw------- 1 erikh erikh  2069 Jun 28 11:15 Makefile
-rw------- 1 erikh erikh    64 Jun 28 11:15 PROJECT
```

## Creating the API

This is the build system for your API; it hasn't even arrived yet! We need to run another `kubebuilder` command to create it. We need to pick an API group and kind first; we'll use "apis" and "UUID" respectively.

We'll need both the resource and the controller for publishing our resource changes in the client; if we don't provide these options, you will be prompted for them.

```
erikh/k8s-api% kubebuilder create api --version v1 --group apis --kind UUID --resource --controller
Writing scaffold for you to edit...
api/v1/uuid_types.go
controllers/uuid_controller.go
Running make:
$ make
/home/erikh/bin/controller-gen object:headerFile="hack/boilerplate.go.txt" paths="./..."
go fmt ./...
go vet ./...
go build -o bin/manager main.go
```

## Making the API do what we want

Our task is fairly simple here; we're going to edit some struct properties, and move on to making our client.

Let's first look at our above-noted `api/v1/uuid_types.go`:

```go
package v1

import (
        metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
)

// EDIT THIS FILE!  THIS IS SCAFFOLDING FOR YOU TO OWN!
// NOTE: json tags are required.  Any new fields you add must have json tags for the fields to be serialized.

// UUIDSpec defines the desired state of UUID
type UUIDSpec struct {
        // INSERT ADDITIONAL SPEC FIELDS - desired state of cluster
        // Important: Run "make" to regenerate code after modifying this file

        // Foo is an example field of UUID. Edit UUID_types.go to remove/update
        Foo string `json:"foo,omitempty"`
}

// UUIDStatus defines the observed state of UUID
type UUIDStatus struct {
        // INSERT ADDITIONAL STATUS FIELD - define observed state of cluster
        // Important: Run "make" to regenerate code after modifying this file
}

// +kubebuilder:object:root=true

// UUID is the Schema for the uuids API
type UUID struct {
        metav1.TypeMeta   `json:",inline"`
        metav1.ObjectMeta `json:"metadata,omitempty"`

        Spec   UUIDSpec   `json:"spec,omitempty"`
        Status UUIDStatus `json:"status,omitempty"`
}

// +kubebuilder:object:root=true

// UUIDList contains a list of UUID
type UUIDList struct {
        metav1.TypeMeta `json:",inline"`
        metav1.ListMeta `json:"metadata,omitempty"`
        Items           []UUID `json:"items"`
}

func init() {
        SchemeBuilder.Register(&UUID{}, &UUIDList{})
}
```

This is what it should look like (roughly) when you view it. We're going to make a slight modification to `UUIDSpec` and leave the rest alone.

Let's change the inner struct body to look something more resembling this:

```go
// UUIDSpec defines the desired state of UUID
type UUIDSpec struct {
  UUID      string  `json:"uuid,omitempty"`
  RandomInt int     `json:"random_int,omitempty"`
}
```

Once this is done, type `make` at the root of the repository. Try `make test`, too. This will generate your code and keep everything up to date.

To install your CRD on to the cluster, type `make install`. Do this now, as it will help with the next step.

## Finally, the Client

The client leverages the controller-runtime client to interact with your types in a way that makes Golang happy. The code has no idea about your type until the point they're compiled together; this abstraction allows them to import and work with nearly any type and the same client.

```go
package main

import (
        "context"
        "math/rand"
        "os"
        "time"

        v1 "github.com/erikh/k8s-api/api/v1"
        "github.com/google/uuid"
        "k8s.io/apimachinery/pkg/runtime"
        "k8s.io/client-go/tools/clientcmd"
        "sigs.k8s.io/controller-runtime/pkg/client"
)

func init() {
        // don't take your crypto advice from me
        rand.Seed(time.Now().Unix())
}

func main() {
        k8s, err := clientcmd.BuildConfigFromFlags("", os.Getenv("HOME")+"/.kube/config")
        if err != nil {
                panic(err)
        }

        u := uuid.New()

        ur := &v1.UUID{
                Spec: v1.UUIDSpec{
                        UUID:      u.String(),
                        RandomInt: rand.Int(),
                },
        }

        ur.SetNamespace(os.Getenv("KUBE_NAMESPACE"))
        ur.SetName(u.String())

        s := runtime.NewScheme()
        v1.AddToScheme(s)
        k8sClient, err := client.New(k8s, client.Options{Scheme: s})
        if err != nil {
                panic(err)
        }

        if err := k8sClient.Create(context.Background(), ur); err != nil {
                panic(err)
        }
}
```

Walking through what's happening here:

- We first get our Kubernetes configuration from `~/.kube/config`. If you don't like this path, change it here, as credentials will be loaded and servers will be used from this configuration. However, if you have followed the steps so far, this is what you have already been using.
- We generate a UUID. There are numerous packages for this; we are using `github.com/google/uuid` for our generation.
- We construct our object with the UUID represented as string and a random integer because we can. It's not very random.
- Next we set the namespace and name, two required arguments for any namespaced object in the Kubernetes ecosystem.
- We now take a `runtime.Scheme`, and append our API to it. We then use the `runtime.Scheme` in our controller-runtime client.
- Finally, we tell the client to create the object. Any error about the name of the object or contents will appear in this step.

### Building and Running the Client

Try this:

```bash
$ mkdir /tmp/k8s-client
## copy in the contents to /tmp/k8s-client/main.go
$ cd /tmp/k8s-client
$ KUBE_NAMESPACE='my-namespace' go run .
```

On success, no output is returned.

### Validating we got our data in

To validate our data has indeed arrived, let's check it out with the standard tools instead of building our own orchestration. CRDs have the added benefit of being integrated and controllable directly from the standard API, making them accessible with tools like `kubectl`.

Let's try that (I ran it a few times, you should see one for each time you ran it successfully):

```
$ kubectl get uuid -n runs
NAME                                   AGE
b97e07ab-2399-4100-879f-0e3049971552   19m
f213c804-3a8a-4e80-804a-368ff9d5a8d8   18m
```

Let's describe one to see if we got our random integer:

```
$ kubectl describe uuid -n runs b97e07ab-2399-4100-879f-0e3049971552
```

```yaml
Name: b97e07ab-2399-4100-879f-0e3049971552
Namespace: runs
Labels: <none>
Annotations: <none>
API Version: apis.example.org/v1
Kind: UUID
Metadata:
  Creation Timestamp: 2020-06-28T11:40:46Z
  Generation: 1
  Managed Fields:
    API Version: apis.example.org/v1
    Fields Type: FieldsV1
    fieldsV1:
      f:spec:
        .:
        f:random_int:
        f:uuid:
      f:status:
    Manager: main
    Operation: Update
    Time: 2020-06-28T11:40:46Z
  Resource Version: 1430134
  Self Link: /apis/apis.example.org/v1/namespaces/runs/uuids/b97e07ab-2399-4100-879f-0e3049971552
  UID: ccaf1f8a-3215-4a8b-8d31-697c87a01eb2
Spec:
  random_int: 4186180082803320644
  Uuid: b97e07ab-2399-4100-879f-0e3049971552
Status:
Events: <none>
```

We can see that indeed, not only is our random integer there, but it is quite large too. What's also important is that we can see the update manifest of the item, this would be useful for auditing a badly behaving application or user.

# kubebuilder == rails new

kubebuilder, as we saw, is basically `rails new` for Kubernetes. Those of you familiar with the ruby/rails ecosystem may be familiar with this being a single command to generate giant swaths of code to edit later. I imagine it's scope will expand to handling other patterns in Kubernetes and I look forward to using it for future projects.

I've put the code I generated [here](https://github.com/erikh/k8s-api), if you want to pull it down to play around. Enjoy!
