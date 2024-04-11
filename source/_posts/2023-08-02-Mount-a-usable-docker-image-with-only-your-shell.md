---
title: Mount a usable docker image with only your shell
date: 2023-08-02 23:36:38
tags:
    - Containers
    - Programming
---

So, today's bag of tricks is something I enjoy bragging about from time to time because it's really not that complicated when you break it down, but bends the brains of anyone who understands the basics. Today we are going to mount a docker image, fully capable for use, with only our shell. Docker will only be used to fetch the image from the registry, and export it to disk.

To start, let's get that image. We'll use `nginx:latest` to play with for now, so the sums (it will make sense later) will be different almost for certain, but the concepts are fundamentally the same.

# Fetching the image

To start, pull the image down with `docker pull`. This will pull it into your local cache and make it available for immediate use. Second, we need to get that image _out_ of docker, so we use `docker save` for this task:

```bash
docker save nginx:latest >nginx.tar
```

# Docker images are just tarballs

This is not exactly an industry secret, but it's important for the tools we're about to use. Docker images can technically be in numerous compression formats so we will use the `-a` flag to GNU `tar` which allows it to guess at which compression is in use, which may be none. It likely very much depends on how you installed docker, so even though my images are uncompressed, yours may be compressed, and these commands will still work.

To start, let's unroll the tarball with `tar tvaf nginx.tar`:

```
drwxr-xr-x 0/0               0 2023-06-14 00:16 29e982a8136c59c627357cdffedab9f61e3d5dcd6005e3e0106ce7b01c866b5d/
-rw-r--r-- 0/0               3 2023-06-14 00:16 29e982a8136c59c627357cdffedab9f61e3d5dcd6005e3e0106ce7b01c866b5d/VERSION
-rw-r--r-- 0/0             482 2023-06-14 00:16 29e982a8136c59c627357cdffedab9f61e3d5dcd6005e3e0106ce7b01c866b5d/json
-rw-r--r-- 0/0            4608 2023-06-14 00:16 29e982a8136c59c627357cdffedab9f61e3d5dcd6005e3e0106ce7b01c866b5d/layer.tar
drwxr-xr-x 0/0               0 2023-06-14 00:16 374633a942b2e41c70d01730031762f6b5731dd5be08ddfe9d82c4ef89bc929d/
-rw-r--r-- 0/0               3 2023-06-14 00:16 374633a942b2e41c70d01730031762f6b5731dd5be08ddfe9d82c4ef89bc929d/VERSION
-rw-r--r-- 0/0             482 2023-06-14 00:16 374633a942b2e41c70d01730031762f6b5731dd5be08ddfe9d82c4ef89bc929d/json
-rw-r--r-- 0/0            2560 2023-06-14 00:16 374633a942b2e41c70d01730031762f6b5731dd5be08ddfe9d82c4ef89bc929d/layer.tar
drwxr-xr-x 0/0               0 2023-06-14 00:16 86131a9f697d3ae15020ef4dc2fec85ab88e7514d4143fbd99a3109677ab9bd0/
-rw-r--r-- 0/0               3 2023-06-14 00:16 86131a9f697d3ae15020ef4dc2fec85ab88e7514d4143fbd99a3109677ab9bd0/VERSION
-rw-r--r-- 0/0             406 2023-06-14 00:16 86131a9f697d3ae15020ef4dc2fec85ab88e7514d4143fbd99a3109677ab9bd0/json
-rw-r--r-- 0/0        77810176 2023-06-14 00:16 86131a9f697d3ae15020ef4dc2fec85ab88e7514d4143fbd99a3109677ab9bd0/layer.tar
drwxr-xr-x 0/0               0 2023-06-14 00:16 9bc035c0cb4c3d93a825575441117f3297ba36e3961ad7f0d6a57d2ea3ed32db/
-rw-r--r-- 0/0               3 2023-06-14 00:16 9bc035c0cb4c3d93a825575441117f3297ba36e3961ad7f0d6a57d2ea3ed32db/VERSION
-rw-r--r-- 0/0             482 2023-06-14 00:16 9bc035c0cb4c3d93a825575441117f3297ba36e3961ad7f0d6a57d2ea3ed32db/json
-rw-r--r-- 0/0       113197568 2023-06-14 00:16 9bc035c0cb4c3d93a825575441117f3297ba36e3961ad7f0d6a57d2ea3ed32db/layer.tar
drwxr-xr-x 0/0               0 2023-06-14 00:16 ae06af1da66865a722c3452159b9bd5f5cf487f9a95e7651e01b840e8d1da7c8/
-rw-r--r-- 0/0               3 2023-06-14 00:16 ae06af1da66865a722c3452159b9bd5f5cf487f9a95e7651e01b840e8d1da7c8/VERSION
-rw-r--r-- 0/0             482 2023-06-14 00:16 ae06af1da66865a722c3452159b9bd5f5cf487f9a95e7651e01b840e8d1da7c8/json
-rw-r--r-- 0/0            5120 2023-06-14 00:16 ae06af1da66865a722c3452159b9bd5f5cf487f9a95e7651e01b840e8d1da7c8/layer.tar
drwxr-xr-x 0/0               0 2023-06-14 00:16 b0a70170b78b39f4d732bb232ae03a5af2e85e7d65097018fcfa8252eefe1aed/
-rw-r--r-- 0/0               3 2023-06-14 00:16 b0a70170b78b39f4d732bb232ae03a5af2e85e7d65097018fcfa8252eefe1aed/VERSION
-rw-r--r-- 0/0             482 2023-06-14 00:16 b0a70170b78b39f4d732bb232ae03a5af2e85e7d65097018fcfa8252eefe1aed/json
-rw-r--r-- 0/0            3584 2023-06-14 00:16 b0a70170b78b39f4d732bb232ae03a5af2e85e7d65097018fcfa8252eefe1aed/layer.tar
drwxr-xr-x 0/0               0 2023-06-14 00:16 e3725737249294bc2055a8467dde596c4cc68d032fd33e4d145b0ac512d47fd5/
-rw-r--r-- 0/0               3 2023-06-14 00:16 e3725737249294bc2055a8467dde596c4cc68d032fd33e4d145b0ac512d47fd5/VERSION
-rw-r--r-- 0/0            1688 2023-06-14 00:16 e3725737249294bc2055a8467dde596c4cc68d032fd33e4d145b0ac512d47fd5/json
-rw-r--r-- 0/0            7168 2023-06-14 00:16 e3725737249294bc2055a8467dde596c4cc68d032fd33e4d145b0ac512d47fd5/layer.tar
-rw-r--r-- 0/0            8152 2023-06-14 00:16 eb4a57159180767450cb8426e6367f11b999653d8f185b5e3b78a9ca30c2c31d.json
-rw-r--r-- 0/0             663 1969-12-31 16:00 manifest.json
-rw-r--r-- 0/0              88 1969-12-31 16:00 repositories
```

We see several hexadecimally-named directories with some contents, a file named `manifest.json` and another file named `repositories` which are very small. The hex named dirs are just SHA-256 sums of the contents of each `layer.tar` inside the dir. Each `layer.tar` is a "Layer", and layers are mounted _atop_ each other to create your container's filesystem. To do this, a technology like `overlayfs` or `aufs` (which is used more rarely these days) is used to perform what's called a "union mount", which is the concept of laying a secondary set of content directly atop a primary set of content, namely a filesystem. Deletions are managed through a process called "whiting out" a file, which involves putting a placeholder where the previously deleted file or directory existed, to indicate to the higher layers that this file no longer exists, even though it exists in the earlier ones, which may be numerous; for example imagine your `apt-get` archive of packages for some installs, then you `apt-get clean` and all of a sudden about 200 files disappear.

In this vein, ordering is _incredibly_ important, so that's where the `manifest.json` comes into play. This file is a map to that ordering.

# The Manifest and Layers

`manifest.json` looks like this, processed through `jq` (it is whitespace-compressed by default):

```json
[
    {
        "Config": "eb4a57159180767450cb8426e6367f11b999653d8f185b5e3b78a9ca30c2c31d.json",
        "RepoTags": ["nginx:latest"],
        "Layers": [
            "86131a9f697d3ae15020ef4dc2fec85ab88e7514d4143fbd99a3109677ab9bd0/layer.tar",
            "9bc035c0cb4c3d93a825575441117f3297ba36e3961ad7f0d6a57d2ea3ed32db/layer.tar",
            "b0a70170b78b39f4d732bb232ae03a5af2e85e7d65097018fcfa8252eefe1aed/layer.tar",
            "29e982a8136c59c627357cdffedab9f61e3d5dcd6005e3e0106ce7b01c866b5d/layer.tar",
            "374633a942b2e41c70d01730031762f6b5731dd5be08ddfe9d82c4ef89bc929d/layer.tar",
            "ae06af1da66865a722c3452159b9bd5f5cf487f9a95e7651e01b840e8d1da7c8/layer.tar",
            "e3725737249294bc2055a8467dde596c4cc68d032fd33e4d145b0ac512d47fd5/layer.tar"
        ]
    }
]
```

The important data here is the `Layers` section, which we can pull out with `jq` trivially:

```bash
jq -r '.[0].Layers[]' manifest.json
```

# What goes into a Layer?

So, let's pull the first layer apart. I will not output all the files here (that would be quite a bit) but go over some of the basics as there is a well-defined container layout, even though it is very simple.

This is the first layer in the tar, which is usually the largest. In a squashed image, it will be the only tarball.

```bash
tar vxaf nginx.tar 86131a9f697d3ae15020ef4dc2fec85ab88e7514d4143fbd99a3109677ab9bd0/layer.tar
tar tvaf 86131a9f697d3ae15020ef4dc2fec85ab88e7514d4143fbd99a3109677ab9bd0/layer.tar
```

The first thing we should notice is that there are a loooot of files. It's a whole filesystem, after all. This is the basis for everything else, so it usually consists of the most stuff as a result. Pulling apart the next layer should be less.

Also, let's make a note of the fact that layer tarballs assume they're at the root. It is very obvious from the filesystem layout.

Let's pull apart the next one:

```bash
tar vxaf nginx.tar 9bc035c0cb4c3d93a825575441117f3297ba36e3961ad7f0d6a57d2ea3ed32db/layer.tar
tar tvaf 9bc035c0cb4c3d93a825575441117f3297ba36e3961ad7f0d6a57d2ea3ed32db/layer.tar
```

## Whiteout Files

And we see a lot more files, but I see one of these:

```
-rwxr-xr-x 0/0               0 1969-12-31 16:00 var/log/nginx/.wh..wh..opq
```

Which is a whiteout file. This file is an instruction to the union mount system (overlayfs, IIRC, in this case), that indicates that we are creating a new directory and we want to make sure it exists. There are a few types of whiteout files. As the union mount system finds these files it engages in behavior that would be abnormal on a normal filesystem. These files do not have a place themselves once the system is mounted.

# Mounting layers with overlayfs
