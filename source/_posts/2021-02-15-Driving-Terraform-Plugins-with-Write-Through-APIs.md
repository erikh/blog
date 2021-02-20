---
title: Driving Terraform Plugins with Write-Through APIs
date: 2021-02-15 17:42:56
tags:
  - Golang
  - Programming
  - Terraform
---

Terraform has a great ecosystem of [providers](https://registry.terraform.io/browse/providers), which work in many ways analogous to Chef, Puppet, or Kubernetes' resource ecosystems. The providers allow you to interact with third party tooling that is less desired in the core of the product and preferred to be maintained outside of it.

To interoperate with the terraform plugin ecosystem, this article can help you understand what is involved, but just goes into a specific technique you can use to integrate your APIs with providers. [Here](https://learn.hashicorp.com/collections/terraform/providers) is where you can befriend even more wonderful documentation by the Hashicorp folks that can get you on your way to making your own provider. Go there first!

Terraform/Hashicorp keeps a [registry](https://registry.terraform.io) of major third party integrations, so be sure to check that out before diving off into third party purgatory. :)

# An Introduction to Terraform's Providers

Terraform talks to it's providers through an application protocol called [GRPC](https://grpc.io) which then leverages a serialized format called [protocol buffers](https://developers.google.com/protocol-buffers) to turn your messages into really tiny ones for the purposes of sending over the network, typically at least. Terraform however, uses GRPC to talk inter-process on a single system instead of across the network. Since protobuf (as it is frequently called) is also strongly typed as a serialization format, terraform can map a lot of your Golang types directly to protobuf ones. This is what the terraform schema accomplishes for you; we'll see some of those definitions in a minute.

But fundamentally, your process is independent of terraform and is for all intents and purposes a really limited webserver that runs for a short period of time. It's important to know this for the purposes of debugging it later.

## What a (small) provider looks like

Each terraform provider consists of a few scaffolding files and the following types:

- Provider: There is typically only one of these for a given binary. It defines the provider information as well as its outer schema.
- Resource: This has a lot of overlap with a Schema, but ultimately provides the top-tier resources and data sources via callbacks that you write that fill in the rest of the schema. However, resources are also used to populate schema elements in some dynamic and complex scenarios.
- Schema: Schemas are basically type definitions, and are frequently represented as a `map[string]*Schema` to associate the types with their key names.

### Using the provider

If you'd like to review the complete code as a repository, try [erikh/terraurl on GitHub](https://github.com/erikh/terraurl). If you'd like to follow along with the examples, try a `make install` after cloning the repo. You'll need terraform 0.14 to work with this plugin.

Here's a small provider you can make: one that fetches a URL with a customizable `User-Agent` and stuffs the result at the `target_path`, and doesn't fetch again as long as the modified time and file size are the same. Here's an example:

```terraform
terraform {
  required_providers {
    terraurl = {
      source  = "github.com/erikh/terraurl"
      version = "0.0.1"
    }
  }
}

provider "terraurl" {
  user_agent = "Hello my baby, hello my honey, hello my ragtime gal"
}

resource "terraurl_fetch" "golang" {
  url         = "https://storage.googleapis.com/golang/go1.16.linux-amd64.tar.gz"
  target_path = "/tmp/golang.tar.gz"
}
```

#### What this does is

First, import our custom provider at the source and version and also _operating system_ and _architecture_. Because Golang builds to native binaries, we cannot rely on an interpreter to keep us from having to build a version for every select architecture. I strongly recommend looking at investing into go tooling like [GoReleaser](https://goreleaser.com/) to solve this problem for you. You may have noticed that `make install` in the repository does this for you by detecting your architecture with `go env`.

Boot the provider with the supplied parameters; in this case, `user_agent` will be changed to something sillier and more amphibian for all client requests.

Finally, it fetches the latest (at the time of this writing) stable version of Golang, and stuffs it under `/tmp`. State changes are expected to alter the local content, that is, a changed file on disk, or remotely, should synchronize the remote to local.

#### A deeper dive into the provider

I'm going to do this section a little differently since there is more code than normal. [Follow along on Github](https://github.com/erikh/terraurl). See `main.go` for the majority of the effort.

##### Types

First, let's examine the typed/typeless hybrid nature of terraform. You will see a ton of code that works like this:

```go
d.Get("some_key").(string)
d.Get("other_key").(int64)
```

Most Go programmers know what a type assertion is, the act of making sure an `interface{}` type is a specific type, used as a type-safe cast, _with the penalty being a panicked goroutine for mistakes_. When reading the code, keep in mind that almost all type assertions are controlled operations and that the chances of them panicking are low to nil at worst. The schema enforces our types as a part of the I/O process, so we can safely assert them during `Get()` calls. Note that there is also `GetOk()` to see if things are modified or exist already, in the event you need to more delicately control this behavior.

In other instances, there is an agreed on protocol -- for example the handle to `*TerraURLClient`, that can be safely asserted into a new variable because it's configured that way as a part of a standard process. More of these standard processes will be tacked onto the terraform schema later on in this article.

Types will be a thing you battle. We implement some patterns later on in this article to assist with this.

##### Changed Attributes

You will see calls to `d.HasChanged` in the provider as well; these are terraform hooks into the metadata system to see if the plan or computed (read) values have deviated from the state; this call allows us to determine if there are any changes to initiate as a result.

This call is used in `UpdateContext` hooks regularly.

##### SetId and the ID attribute

`SetId("")` removes the state for the ID you're processing. It is frequently used in `DeleteContext` calls and situations (like our local file deletion) that require state to be re-created.

Note, likewise, you must set an ID to record state at all for the resource you're processing.

# Problems with the current tooling that need solving

So we used a lot of words getting to this point, so this part should be a little shorter and sweeter, now that you know how to make a terraform plugin.

Here are some challenges you will run into.

## Many packages are in alpha/beta state

Sorry to call this out at all, but critical things like the package that generates documentation and the schema libraries itself are in beta and alpha states at present. If you want to avoid this by using older tools, you can, but you're in for a world of pain only the _Coen Brothers_ could describe.

This will fade with time, but you should be aware of it.

## Easy propagation of I/O

I/O, specifically around types of all kinds, is kind of a mess of schlepping from one struct to `d.Set()` calls and back again through `d.Get()`, probably 95% of the time. It would be nicer if this was easier to do, like `flag.StringVar()` can work with pointers, I would like to see bound variables for terraform schemas so I can just quite literally point a whole struct at it one member at a time. I think in general this would make terraform plugins much much much simpler to write for the easy cases.

## Better support for type conversions

Type conversion beyond the basic types is non-existent, and hard to achieve with just the schema, leading to more boilerplate code. A simple "this is the i/o of the type" set of hooks would help here, I think.

## Better support for state auditing (testing)

There might be better tools for this, but what I amounted to was:

```go
state := map[string]interface{}{}

f, _ := os.Open("terraform.tfstate")
json.NewDecoder(f).Decode(&state)
```

And about 8 type assertion functions with short names. I don't like it at all and have made some strides on the automated testing front, but hope to make a dent in this problem soon too. What I would prefer is to find a solution that already works, naturally. :) It really feels like this is missing and/or poorly documented tooling in Terraform's arsenal. State auditing after something has changed in terraform seems just incredibly hard to do, and I wish I knew why.

## Common Types

I think some canned types would help solve a lot of basic issues with type conversion, too.

Examples of types I'd like to see directly represented in the schema:

- Files, Dirs, and Paths
- Networks (IP, CIDR, etc)

# Solutions

Below are some solutions to the above gripes. I am really enjoying my terraform journey and should be clear about that; all things equal, Hashicorp has really done a bang-up job making a solid API that works as it's intended to, with minimum opportunity for accidentally being stupid about it.

## Terraform testing library

When tasked to write a terraform plugin, I was concerned with how to test it. I didn't find much that addressed the following question:

_When I run terraform, how do I determine what happened?_

So I wrote something, you can find it here at [erikh/tftest](https://github.com/erikh/tftest). `tftest` is ultra-alpha and I recommend you stare at it twice before trying to use it. That said, what it accomplishes are:

- Managing terraform runs in an automated fashion
  - `init`, `apply`, `refresh`, and `destroy` are covered
- Automated examination of tfstate, easy to get from a single call (as a `map[string]interface{}`)
- Signal handling is covered, with automated cleanup/destroy on all failures/cancellations
- Integrating with golang's `testing` library is also covered; it will automatically schedule a `Destroy` after you apply in the `*testing.T.Cleanup()` system.

It is a spiritual companion to [erikh/duct](https://github.com/erikh/duct), if you need something like that for docker.

## A Schema Wrapper package

The schema wrapper (SchemaWrap and ValidatedSchema) is printed below. Summarily, it manages the conversion of types, the validation of types before they ever reach terraform or the API hit, and generally treats terraform as a write-through cache, keeping all operations a few lines of code away from synchronization in your logic at all times. The goal of the schema wrapper is to remove as much boilerplate as possible when dealing with properties of a resource.

### Source

```go
// This is printed from the ZeroTier provider linked below, and licensed under a BSD 3-Clause license.
package schemawrap

import (
	"errors"

	"github.com/hashicorp/terraform-plugin-sdk/v2/diag"
	"github.com/hashicorp/terraform-plugin-sdk/v2/helper/schema"
)

// ValidatedSchema is an internal schema for validating and managing lots of
// schema parameters. It is intended to be a more-or-less write-through cache
// of terraform information with validation and conversion along the way.
type ValidatedSchema struct {
	// Schema is our schema. The key is the name. See SchemaWrap for more information.
	Schema map[string]*SchemaWrap
	// Should be programmed to yield the type at Yield time.
	YieldFunc func(ValidatedSchema) interface{}
	// Should be programmed to populate the validated schema with Set calls.
	CollectFunc func(ValidatedSchema, *schema.ResourceData, interface{}) diag.Diagnostics
}

// SchemaWrap wraps the terraform schema with validators and converters.
type SchemaWrap struct {
	// Schema is the terraform schema.
	Schema *schema.Schema
	// ValidatorFunc is a function, that if supplied, validates the data and
	// yields an error if the function returns one.
	ValidatorFunc func(interface{}) diag.Diagnostics
	// FromTerraformFunc converts data from terraform plans to the Value (see
	// below). It returns an error if it had trouble.
	FromTerraformFunc func(interface{}) (interface{}, diag.Diagnostics)
	// ToTerraformFunc converts data from the Value to the terraform
	// representation. This must *always* succeed (in practice, this has not been
	// an issue at this time)
	ToTerraformFunc func(interface{}) interface{}
	// EqualFunc is used in comparisons, which are used in determining if changes
	// need to be pushed to our API.
	EqualFunc func(interface{}, interface{}) bool
	// Value is the internal value; this is a representation suitable for using
	// in both ValidatedSchema.YieldFunc() and ValidatedSchema.CollectFunc
	// interchangeably, as in, they can be type asserted without panicking.
	Value interface{}
}

func (sw *SchemaWrap) Clone() *SchemaWrap {
	val, err := sw.Schema.DefaultValue()
	if err != nil {
		panic(err)
	}

	return &SchemaWrap{
		Value:             val,
		Schema:            sw.Schema,
		ValidatorFunc:     sw.ValidatorFunc,
		FromTerraformFunc: sw.FromTerraformFunc,
		ToTerraformFunc:   sw.ToTerraformFunc,
		EqualFunc:         sw.EqualFunc,
	}
}

func (vs ValidatedSchema) Clone() ValidatedSchema {
	vs2 := ValidatedSchema{
		Schema:      map[string]*SchemaWrap{},
		YieldFunc:   vs.YieldFunc,
		CollectFunc: vs.CollectFunc,
	}

	for key, sw := range vs.Schema {
		vs2.Schema[key] = sw.Clone()
	}

	return vs2
}

// TerraformSchema returns the unadulterated schema for use by terraform.
func (vs ValidatedSchema) TerraformSchema() map[string]*schema.Schema {
	res := map[string]*schema.Schema{}

	for k, v := range vs.Schema {
		res[k] = v.Schema
	}

	return res
}

// CollectFromTerraform collects all the properties listed in the validated schema, converts
// & validates them, and makes this object available for further use. Failure
// to call this method before others on the same transaction may result in
// undefined behavior.
func (vs ValidatedSchema) CollectFromTerraform(d *schema.ResourceData) diag.Diagnostics {
	for key, sw := range vs.Schema {
		var (
			res interface{}
			err diag.Diagnostics
		)

		if sw.FromTerraformFunc != nil {
			if res, err = sw.FromTerraformFunc(d.Get(key)); err != nil {
				return err
			}
		} else {
			res = d.Get(key)
		}

		if sw.ValidatorFunc != nil {
			if err := sw.ValidatorFunc(res); err != nil {
				return err
			}
		}

		sw.Value = res
	}

	return nil
}

// CollectFromObject is a pre-programmed call on the struct which accepts the
// known object and sets all the values appropriately.
func (vs ValidatedSchema) CollectFromObject(d *schema.ResourceData, i interface{}) diag.Diagnostics {
	return vs.CollectFunc(vs, d, i)
}

// Get retrieves the set value inside the schema.
func (vs ValidatedSchema) Get(key string) interface{} {
	return vs.Schema[key].Value
}

// Set a value in terraform. This goes through our validation & conversion
// first.
func (vs ValidatedSchema) Set(d *schema.ResourceData, key string, value interface{}) diag.Diagnostics {
	sw := vs.Schema[key]
	if sw == nil {
		return diag.FromErr(errors.New("invalid key, plugin error"))
	}

	if sw.ValidatorFunc != nil {
		if err := sw.ValidatorFunc(value); err != nil {
			return err
		}
	}

	if sw.ToTerraformFunc != nil {
		value = sw.ToTerraformFunc(value)
		if err := d.Set(key, value); err != nil {
			return diag.FromErr(err)
		}
	} else {
		if err := d.Set(key, value); err != nil {
			return diag.FromErr(err)
		}
	}

	sw.Value = value

	return nil
}

// Yield yields the type on request.
func (vs ValidatedSchema) Yield() interface{} {
	return vs.YieldFunc(vs)
}
```

### Usage

The [ZeroTier Terraform Provider](https://github.com/zerotier/terraform-provider-zerotier) makes use of this code as well as implementing several resources atop it. Let's take a look at the `zerotier_network` resource which makes heavy usage of the pattern.

An example of its use, taken from the README:

```terraform
resource "zerotier_network" "occams_router" {
  name        = "occams_router"
  description = "The prefix with largest number of bits is usually correct"
  assignment_pool {
    cidr = "10.1.0.0/24"
  }
  route {
    target = "10.1.0.0/24"
  }
  flow_rules = "accept;"
}
```

We can see that several properties are set; some of these are scalars, and some complex types. Let's take a brief look at how they're implemented:

- [SchemaWrap implementation](https://github.com/zerotier/terraform-provider-zerotier/blob/master/pkg/zerotier/ztnetwork.go)
- [Standard Resource Code](https://github.com/zerotier/terraform-provider-zerotier/blob/master/pkg/zerotier/resource_network.go)

Quickly we should notice that we are constructing global singletons and cloning them. Each time the struct is referred to in the resource code, it is cloned with the `Clone()` method to avoid corruption. This is not the best part of this design, and if you don't like it, replacing with a constructor + static return is easy, at a minor if at all noticeable cost to perf in almost all situations.

Let's take a look at our resource definition for the `zerotier_network` resource. This function is called during provider definition, and yields the schema to it. The notable thing here is the reference to `TerraformSchema()`, which is a convenience method to return the pre-defined schema.

```go
func resourceNetwork() *schema.Resource {
	return &schema.Resource{
		Description:   "Network provider for ZeroTier, allows you to create ZeroTier networks.",
		CreateContext: resourceNetworkCreate,
		ReadContext:   resourceNetworkRead,
		UpdateContext: resourceNetworkRead, // schemawrap makes these equivalent
		DeleteContext: resourceNetworkDelete,
		Schema:        ZTNetwork.TerraformSchema(),
	}
}
```

If we look in the create function, we can see the integration of SchemaWrap through the `ZTNetwork` definition:

```go
func resourceNetworkCreate(ctx context.Context, d *schema.ResourceData, m interface{}) diag.Diagnostics {
	ztn := ZTNetwork.Clone()
	if err := ztn.CollectFromTerraform(d); err != nil {
		return err
	}

	c := m.(*ztcentral.Client)
	net := ztn.Yield().(*ztcentral.Network)
	rules := net.RulesSource

	n, err := c.NewNetwork(ctx, net.Config.Name, net)
	if err != nil {
		return []diag.Diagnostic{{
			Severity: diag.Error,
			Summary:  "Unable to create ZeroTier Network",
			Detail:   fmt.Sprintf("CreateNetwork returned error: %v", err),
		}}
	}

	if _, err := c.UpdateNetworkRules(ctx, n.ID, rules); err != nil {
		return diag.FromErr(err)
	}

	d.SetId(n.ID)
	d.Set("tf_last_updated", time.Now().Unix())

	return resourceNetworkRead(ctx, d, m)
}
```

This:

1. Copies everything from terraform into the schemawrap ingester
2. Returns a `ztcentral.Network` via the yield function in schemawrap (we'll discuss this in a minute)
3. Manipulates the remote resource with the `Network` struct to the ZeroTier API

After that, the Read function takes over:

```go
func resourceNetworkRead(ctx context.Context, d *schema.ResourceData, m interface{}) diag.Diagnostics {
	c := m.(*ztcentral.Client)
	var diags diag.Diagnostics

	ztNetworkID := d.Id()
	ztNetwork, err := c.GetNetwork(ctx, ztNetworkID)
	if err != nil {
		diags = append(diags, diag.Diagnostic{
			Severity: diag.Error,
			Summary:  "Unable to read ZeroTier Network",
			Detail:   fmt.Sprintf("GetNetwork returned error: %v", err),
		})
		return diags
	}

	return ZTNetwork.Clone().CollectFromObject(d, ztNetwork)
}
```

This calls another important method called `CollectFromObject`, which is the inverse of `CollectFromTerraform`, but with a synchronization heuristic; it will apply everything to terraform, and let terraform sort out what changed, allowing it to do what it's good at!

#### Yielding and Collecting

Subsequently, if we go to `ztnetwork.go`, we can see that there are several methods in it, and a type definition previously mentioned called `ZTNetwork` at the bottom. While also containing value checking and type conversion, there are two very critical methods near the top called `ztNetworkYield` and `ztNetworkCollect`. You may also see them referred to in the `ZTNetwork` struct.

Basically, the rules are as thus:

You always _yield_ the _native type_, or the non-terraform type you wish to incorporate to "define" your resource and distinguish it from others. Yielding must always succeed; if you are panicking while yielding, something is probably not defaulted correctly.

```go
func ztNetworkYield(vs ValidatedSchema) interface{} {
	return &ztcentral.Network{
		ID:          vs.Get("id").(string),
		RulesSource: vs.Get("flow_rules").(string),
		Config: ztcentral.NetworkConfig{
			Name:             vs.Get("name").(string),
			IPAssignmentPool: vs.Get("assignment_pool").([]ztcentral.IPRange),
			Routes:           vs.Get("route").([]ztcentral.Route),
			IPV4AssignMode:   vs.Get("assign_ipv4").(*ztcentral.IPV4AssignMode),
			IPV6AssignMode:   vs.Get("assign_ipv6").(*ztcentral.IPV6AssignMode),
			EnableBroadcast:  boolPtr(vs.Get("enable_broadcast").(bool)),
			MTU:              vs.Get("mtu").(int),
			MulticastLimit:   vs.Get("multicast_limit").(int),
			Private:          boolPtr(vs.Get("private").(bool)),
		},
	}
}
```

You _collect_ from two data sources: the _native type_ and _terraform_. The two "Collect" calls above define the two directions collections can go in; both have an intrinsic write-through cache: the native type. The collect hook in `ztnetwork.go` does the rest of it. Note that unlike Yield, collections can error out. This is because validations and conversions happen at this time.

```go
func ztNetworkCollect(vs ValidatedSchema, d *schema.ResourceData, i interface{}) diag.Diagnostics {
	ztNetwork := i.(*ztcentral.Network)

	var diags diag.Diagnostics

	diags = append(diags, vs.Set(d, "id", ztNetwork.ID)...)
	diags = append(diags, vs.Set(d, "flow_rules", ztNetwork.RulesSource)...)
	diags = append(diags, vs.Set(d, "name", ztNetwork.Config.Name)...)
	diags = append(diags, vs.Set(d, "mtu", ztNetwork.Config.MTU)...)
	diags = append(diags, vs.Set(d, "creation_time", ztNetwork.Config.CreationTime)...)
	diags = append(diags, vs.Set(d, "route", ztNetwork.Config.Routes)...)
	diags = append(diags, vs.Set(d, "assignment_pool", ztNetwork.Config.IPAssignmentPool)...)
	diags = append(diags, vs.Set(d, "enable_broadcast", ptrBool(ztNetwork.Config.EnableBroadcast))...)
	diags = append(diags, vs.Set(d, "multicast_limit", ztNetwork.Config.MulticastLimit)...)
	diags = append(diags, vs.Set(d, "private", ptrBool(ztNetwork.Config.Private))...)
	diags = append(diags, vs.Set(d, "assign_ipv4", ztNetwork.Config.IPV4AssignMode)...)
	diags = append(diags, vs.Set(d, "assign_ipv6", ztNetwork.Config.IPV6AssignMode)...)

	return diags
}
```

This implementation could probably be golfed around populating `diags` a bit, but otherwise feels very simple and compact to me. The `ValidatedSchema` implementation manages the write-through properties.

#### Validations and Conversions

I think most people reading this article know what these are, so I won't spend too much time on it, but fundamentally we slightly extend the schema with Validations that happen earlier than Terraform's do, as well as conversions that always result in the _native type_ being stored; this way we can always _yield_ without fear of the assertions ever panicking. It also means we can spend less time worrying about how to store complicated data, because the API is already doing that job for us. The conversions are in [converters.go](https://github.com/zerotier/terraform-provider-zerotier/blob/master/pkg/zerotier/converters.go), if you want to see how they work.

# Impressions

The Terraform ecosystem is arguably still young, but the tooling is solid in lieu of some rougher edges around release cadence.

I would like to see a better solution to types, but Golang is only so capable for this case and honestly, this isn't too bad, just exceptionally wordy.

I would _really_ like to see more tooling come out of Hashicorp that can do 95% of ingesting an API directly into terraform. There's a great opportunity for someone to do something exciting between terraform and openapi, I think; which would open zillions of doors for terraform users. A lot of the back/forth between terraform and API calls doesn't seem as necessary as it might be. I think this is more a reflection on the maturity of the libraries (which again, is really pretty great) than any myopia on the part of the creators. Or Maybe, I'm just terrible at Google. Also possible.

Anyway, thank you for reading. I hope you found this helpful!
