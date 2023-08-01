---
title: Writing a DNS Server with trust-dns
date: 2023-05-31 20:40:01
tags:
    - dns
    - rust
---

Hi friends! Today I will be offering an article on how to write your own, specialized DNS server with the rust `trust-dns` toolkit.

## Why write a DNS server?

It's not necessary in a lot of situations. Mostly, this article will be targeting situations like:

-   You have a very specialized need for a DNS server, and want the minimum impact possible for an environment.
-   You have very dynamic/ever-changing needs, and wish to sync your DNS server with the source of truth to avoid a configuration management / de-sync problem.
-   You want better control over the performance of your DNS solution.

## Why trust-dns? Why not BIND or ldns or?

Services like BIND, CoreDNS, ldns, and even kubedns provide configuration-driven solutions to solving your problem. This is not a always a great solution when your configuration can change out-of-band, meaning that the change originated in a source that is not the configuration of the service. For example, a PostgreSQL database, an API you're querying for more information about your hosts, or even a git repository. Something has to synchronize this configuration to the DNS service, and while continuous delivery pipelines are very nice these days, sometimes the amount of time they take to run is too slow, or simply impossible to do at a rate that matches the rate of change you want.

`trust-dns` provides its own server, a `named`-alike that has quite a numerous set of features and I strongly suggest you look at it. It is asynchronous, relying on the [tokio](https://crates.io/crates/tokio) toolkit, and multi-core aware as well. My simpler DNS servers based on the libraries yield upwards of 300,000 resolves/sec on a Ryzen 5900X with zero failures; something that none of the above servers get close to boasting.

Aside from all that, `trust-dns` has thankfully divided its components into numerous parts as independent rust crates, which you can import independently to get different bits of functionality. For example, the [trust-dns-server](https://crates.io/crates/trust-dns-server) package provides the server components, while [trust-dns-resolver](https://crates.io/crates/trust-dns-resolver) implements DNS resolver bits. To make a cache-free forwarder, one imports both, and bolts the resolver into the server. Very elegant and easy to use.

## What have you done with trust-dns?

-   [zeronsd](https://github.com/zerotier/zeronsd), which is a DNS server that stays in sync with your [ZeroTier](https://www.zerotier.com) LAN configuration, providing names for your IP addresses of residents on the network. ZeroNSD is used by a lot of ZeroTier users.
-   [polyresolver](https://github.com/erikh/polyresolver) which is a forwarding plane for multiple DNS servers based on the domain you're trying to resolve, providing a sort-of "split horizon" DNS at the resolver level.
-   [border](https://github.com/erikh/border.rs), which is an experimental load balancer and DNS service with automated health checking and consensus. This is not ready for production.
-   [nsbench](https://github.com/erikh/nsbench) is a DNS flooder / benchmarker that uses the `trust-dns-resolver` toolkit.
-   Internal projects at companies that needed a DNS server.

## Ok, I'm sold. How do I get started?

This article will start from no repository to a fully-fledged one. We will use a very specific version of `trust-dns` and a `Cargo.toml` to reflect that, hopefully ensuring that even though the dependencies may drift later, this code will still work. Upgrading your dependencies (and covering any API mismatch) should be a priority concern if you take the concepts used here into production.

### The repository

It wouldn't be very nice of me if I just made you cut and paste a bunch of crap into a file, so I created [this repository](https://github.com/erikh/examplens.rs) for your perusal. If you'd like to avoid the rest of the words and get right into the meat, that's also up to you! It builds a binary called `examplens` that takes an `examplens.yaml` in the current directory for its configuration, which is parsed with [serde](https://crates.io/crates/serde) and [serde_yaml](https://crates.io/crates/serde_yaml). `examplens` just overwrites DNS entries provided in domain root -> A record format, for example:

```yaml
example.com:
    foo.example.com: 127.0.0.2
```

Will resolve `foo.example.com` at `127.0.0.2`.

### Cargo setup

The rest of this tutorial assumes you are starting from scratch. If you'd rather follow along by cloning the repository and opening files, you're welcome to do that, too!

First off, to create the repository, we use `cargo new --bin examplens`.

To fill `Cargo.toml`'s dependencies, we're going to be quite prescriptive in our dependency settings, so this project works without me having to maintain this blog article. :) A nice feature of cargo is that it's really, really good at doing stuff like this.

The `dependencies` section should look like this:

```toml
[dependencies]
serde = "^1"
serde_yaml = "^0.9"
anyhow = "^1.0.0"
trust-dns-server = { version = "^0.22.0", features = [ "trust-dns-resolver" ] }
trust-dns-resolver = { version = "^0.22.0", features = [ "tokio-runtime" ] }
tokio = { version = "^1.28.0", features = [ "full" ] }
```

To cover issues we've not discussed yet, We use [anyhow](https://crates.io/crates/anyhow) as a general error handler. This is much simpler than having to write error types for things we, well, don't care too much about. `anyhow` will just make it easy to get the string error out of it, while still providing the error handling functionality we desire.

We also add some features to `trust-dns-server`, namely integrated support for the resolver. This will pull it in automatically, but we need to pull it in manually to add deliberate [tokio](https://crates.io/crates/tokio) support, as we want to stay within the tokio runtime. If we did not do this, the resolver would resort to the synchronous version of the resolver, which would potentially block our resolves while it was out trying to forward queries.

### Parsing the configuration

I'm going to gloss over this fairly fast, as I don't want this article to be a treatise on `serde`. Functionally, we define a tuple struct called `DNSName` which encapsulates the trust-dns `Name` type, which manages DNS names. Then, we write a simple serializer and deserializer for it which calls `Name::parse`, which is a RFC-compliant DNS name parser. This allows us to embed the names as strings in our YAML, and ensure that by the time they get to `trust-dns`, they are valid DNS names, as the program will complain and abort long before then if they aren't. Code follows.

```rust
#[derive(Clone, Ord, PartialOrd, Eq, PartialEq)]
pub struct DNSName(Name);

impl Serialize for DNSName {
    fn serialize<S>(&self, serializer: S) -> Result<S::Ok, S::Error>
    where
        S: serde::Serializer,
    {
        serializer.serialize_str(&self.0.to_string())
    }
}

struct DNSNameVisitor;

impl Visitor<'_> for DNSNameVisitor {
    type Value = DNSName;

    fn expecting(&self, formatter: &mut std::fmt::Formatter) -> std::fmt::Result {
        formatter.write_str("expecting a DNS name")
    }

    fn visit_str<E>(self, v: &str) -> Result<Self::Value, E>
    where
        E: serde::de::Error,
    {
        Ok(DNSName(match Name::parse(v, None) {
            Ok(res) => res,
            Err(e) => return Err(serde::de::Error::custom(e)),
        }))
    }
}

impl<'de> Deserialize<'de> for DNSName {
    fn deserialize<D>(deserializer: D) -> Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        deserializer.deserialize_str(DNSNameVisitor)
    }
}
```

In our `main` function, we add just enough code to parse our YAML and present it as a `std::collections::BTreeMap` of data, starting with the domain apex and nesting into domain -> DNS A records (IPv4 addresses). Since validation is handled by `serde`, all we need to do is specify the types and we can be assured they will be parsed correctly, or the program will fail to run.

```rust
#[derive(Clone, Default, Serialize, Deserialize)]
pub struct Records(BTreeMap<DNSName, BTreeMap<DNSName, Ipv4Addr>>);

fn main() -> Result<(), anyhow::Error> {
    let mut f = std::fs::OpenOptions::new();
    f.read(true);
    let io = f.open("examplens.yaml")?;

    let _records: Records = serde_yaml::from_reader(io)?;

    Ok(())
}
```

### Generating the records

Next, we'll want to generate records. There are only two kinds of records we're going to generate: `SOA`, or "Start of Authority" records, which define a domain apex, and `A`, or address records, which associate a name with one or more IPv4 addresses.

`trust-dns` accomplishes storing these records in a `Record` type, which has associated data. Then, since many DNS records are actually collections of results, stores each record in a `RecordSet` collection associated with the name. Finally, this is pushed into an `Authority`, which is then provided to the `Catalog`. `trust-dns` will happily serve your catalog for you without much instruction.

#### Start of Authority Record

A SOA or "Start of Authority" record lives at the apex of the domain and controls many properties of the domain as a whole, including instructions to other name servers who might resolve through it, and how to behave with regards to caching, hammering the server, and so on.

To create this record, let's define a small routine that does so. This routine accepts a domain name and sets some reasonable defaults. The SOA type has a lot of properties, and some have very well-defined values. It is important to note at this time that a great deal of `trust-dns`'s documentation covers the DNS RFCs as specified, so it's not a bad idea to read the docs especially for the different types. You might just learn something. :)

Note that we are creating a `Record` and `RecordSet`, setting data on the `Record`, then inserting it into the `RecordSet` with a static serial number. The TTL is 30 seconds, specified in a few places. In a real world scenario, TTLs and serials should probably be a lot easier to control external to the program.

```rust
fn generate_soa(domain: DNSName) -> RecordSet {
    let mut rs = RecordSet::new(&domain.0, trust_dns_server::proto::rr::RecordType::SOA, 30);

    let mut rec = Record::with(
        domain.0.clone(),
        trust_dns_server::proto::rr::RecordType::SOA,
        30,
    );

    rec.set_data(Some(trust_dns_server::proto::rr::RData::SOA(
        trust_dns_server::proto::rr::rdata::SOA::new(
            domain.0.clone(),
            Name::from_utf8(format!("administrator.{}", domain.0)).unwrap(),
            1,
            60,
            1,
            120,
            30,
        ),
    )));

    rs.insert(rec, 1);
    rs
}
```

#### A (address) Records

We do the same with the A record, only we're going to accept the appropriate type for IPv4 addresses, which is unsurprisingly called `Ipv4Addr`. We do a similar dance here, where we create the `RecordSet`, and slam a `Record` into it. Most of `trust-dns` works this way.

```rust
fn generate_a(name: DNSName, address: Ipv4Addr) -> RecordSet {
    let mut v4rs = RecordSet::new(&name.0, trust_dns_server::proto::rr::RecordType::A, 30);

    let mut rec = Record::with(
        name.0.clone(),
        trust_dns_server::proto::rr::RecordType::A,
        30,
    );
    rec.set_data(Some(trust_dns_server::proto::rr::RData::A(address)));

    v4rs.insert(rec, 1);
    v4rs
}
```

### Generating the Catalog

Now that we have our `RecordSet`s, we can build the `Catalog`. To build the catalog, we're going to create two `Authority` objects, which are of different types. The first will be our records, and the second will be a `ForwardAuthority` for all other domains which don't match our records. This allows the DNS server to function as a forwarding plane for any records that aren't ours, allowing it to be used as a DNS resolver, for example.

For the `ForwardAuthority`, we need to define some upstream DNS servers. We just use `trust-dns`'s excellent tooling to read the system's `resolv.conf` and inject those for us. So now, your DNS server is not only throwing your records into the mix, but for anything that doesn't match, it just goes to your normal DNS provider.

An `InMemoryAuthority` is used, which is also provided by `trust-dns` for our convenience, which takes a well-formatted `BTreeMap` for it's corpus. Since we've already created everything in `BTreeMap`s, this is an easy conversion. We need to simply convert the keys to `RrKey`s (RR is short for "resource record" and used in many parts of DNS) and associate them with the `RecordSet` we built.

Once we're done building these authorities, we `upsert` them into the catalog, and present the catalog to the caller of this function.

```rust
fn generate_catalog(records: Records) -> Result<Catalog, anyhow::Error> {
    let mut catalog = Catalog::default();

    for (domain, recs) in records.0 {
        let mut rc = BTreeMap::default();
        for (name, rec) in recs {
            rc.insert(
                RrKey::new(
                    domain.0.clone().into(),
                    trust_dns_server::proto::rr::RecordType::SOA,
                ),
                generate_soa(domain.clone()),
            );

            let a_rec = generate_a(name.clone(), rec);

            rc.insert(RrKey::new(name.0.into(), a_rec.record_type()), a_rec);
        }

        let authority = InMemoryAuthority::new(
            domain.0.clone().into(),
            rc,
            trust_dns_server::authority::ZoneType::Primary,
            false,
        )
        .unwrap();

        catalog.upsert(domain.0.into(), Box::new(Arc::new(authority)));
    }

    let resolv = trust_dns_resolver::system_conf::read_system_conf()?;
    let mut nsconfig = NameServerConfigGroup::new();

    for server in resolv.0.name_servers() {
        nsconfig.push(server.clone());
    }

    let options = Some(resolv.1);
    let config = &ForwardConfig {
        name_servers: nsconfig.clone(),
        options,
    };

    let forwarder = ForwardAuthority::try_from_config(
        Name::root(),
        trust_dns_server::authority::ZoneType::Primary,
        config,
    )
    .expect("Could not boot forwarder");

    catalog.upsert(Name::root().into(), Box::new(Arc::new(forwarder)));

    Ok(catalog)
}
```

### Tying it all together

Remember that `main` function? Now we need to rewrite it to both generate our catalog, plus provide the services that we want to serve. That involves setting up some `tokio` stuff, and then binding that to the `trust-dns` library so that DNS can be served properly.

It's important to note at this time that DNS operates over both TCP and UDP, where TCP is used for larger records that UDP can't be used to field, and a few other things. Setting this up properly is key. We've decided to give the TCP socket a 60 second timeout to ensure that any call made into it gets a reasonable chance to get back out before being terminated.

So, tacking on to the rest of our `main` function, we start listeners for TCP and UDP on port 5300, so we don't have to run it as `root`, which is required for ports less than 1024 on the majority of operating systems. Don't worry, we'll look at how to query it later. Then, we take those listeners and encapsulate them in a `trust-dns` `ServerFuture`, which does the job of running the server for us. After that, we call `block_until_done()` on the `ServerFuture` which keeps the server running until the program is terminated, or a serious error occurs.

```rust
#[tokio::main]
async fn main() -> Result<(), anyhow::Error> {
    let mut f = std::fs::OpenOptions::new();
    f.read(true);
    let io = f.open("examplens.yaml")?;

    let records: Records = serde_yaml::from_reader(io)?;

    let sa = SocketAddr::new(std::net::IpAddr::V4(Ipv4Addr::new(127, 0, 0, 1)), 5300);
    let tcp = TcpListener::bind(sa).await?;
    let udp = UdpSocket::bind(sa).await?;

    let mut sf = ServerFuture::new(generate_catalog(records)?);
    sf.register_socket(udp);
    sf.register_listener(tcp, Duration::new(60, 0));
    match sf.block_until_done().await {
        Ok(_) => Ok(()),
        Err(e) => Err(anyhow!(e)),
    }
}
```

## Running and Querying

So, I did not include the myriad of `use` statements you would normally add to your rust program to import all these types. So, for the sake of brevity, if you want to follow along, use [the repository](https://github.com/erikh/examplens.rs).

If you `cargo run` the project, or `cargo install --path .` and run `examplens`, it will expect a configuration file called `examplens.yaml` in the current working directory. If it does not exist, it will fail to run. You can use this configuration, which we will use in the querying examples:

```yaml
example.com:
    foo.example.com: 127.0.0.2
```

This associates a SOA for `example.com`, and then associates the IP `127.0.0.2` for `foo.example.com`. `example.com` itself is a RFC-specified "dead" domain name, intentionally used for examples in RFC documents. It will not resolve to anything on the global internet. Try now, if you'd like. So, this is a good test that our resolver is working properly.

To query, run the server in the background, and use the `dig` tool to query it:

```
$ dig -p 5300 foo.example.com @127.0.0.1

; <<>> DiG 9.10.6 <<>> -p 5300 foo.example.com @127.0.0.1
;; global options: +cmd
;; Got answer:
;; ->>HEADER<<- opcode: QUERY, status: NOERROR, id: 9014
;; flags: qr aa rd; QUERY: 1, ANSWER: 1, AUTHORITY: 0, ADDITIONAL: 0
;; WARNING: recursion requested but not available

;; QUESTION SECTION:
;foo.example.com.               IN      A

;; ANSWER SECTION:
foo.example.com.        30      IN      A       127.0.0.2

;; Query time: 1 msec
;; SERVER: 127.0.0.1#5300(127.0.0.1)
;; WHEN: Wed May 31 12:26:20 PDT 2023
;; MSG SIZE  rcvd: 49
```

You can see here that we had a successful query, it resolved to `127.0.0.2`, and it took `1ms` to run, which we'll learn later is the smallest number `dig` can produce. :)

Let's try `google.com` to test the forwarder:

```
$ dig -p 5300 google.com @127.0.0.1

; <<>> DiG 9.10.6 <<>> -p 5300 google.com @127.0.0.1
;; global options: +cmd
;; Got answer:
;; ->>HEADER<<- opcode: QUERY, status: NOERROR, id: 21458
;; flags: qr rd ra; QUERY: 1, ANSWER: 1, AUTHORITY: 0, ADDITIONAL: 0

;; QUESTION SECTION:
;google.com.                    IN      A

;; ANSWER SECTION:
google.com.             300     IN      A       142.251.214.142

;; Query time: 50 msec
;; SERVER: 127.0.0.1#5300(127.0.0.1)
;; WHEN: Wed May 31 12:25:13 PDT 2023
;; MSG SIZE  rcvd: 44
```

Your IP address will likely be different, but you can see the result was a success, and it took 50ms to run.

## How fast is it?

These numbers are produced on a M1 Mac, on battery, with the [nsbench](https://github.com/erikh/nsbench) utility. Note that this is a fairly experimental (and slightly broken) utility, but it does measure resolves properly and reliably.

`cargo run --release` was used to launch the DNS server, so we get the best code `rustc` can create. Here's some of the output. Note this will be much faster (an order of magnitude or better) on server class hardware or even a cloud VM, but the results are still quite pleasing for something we cobbled together in an hour.

```
1s avg latency: 43.225µs | Successes: 23219 | Failures: 0 | Total Req: 23219
```

That's all there is folks! I hope you enjoyed reading this.
