---
title: Shell Tricks Everyone Should Know
date: 2023-08-01 17:47:32
tags:
    - Programming
---

One thing about getting older as a software person is that you get to see certain things fade out of fashion, largely because something better has come along, or the solution is no longer necessary. True to form for tech, a lot of babies get thrown out while discarding the bathwater. The shell is a great example of this; many things have been partially lost to time as shells improved, better shells were made the default on operating systems, as well as the requirement for a minimal shell decreased as computing resources got larger. Still, however, the shell remains something we must all use, and to share our shell scripts with others, we must take certain precautions. This article covers several of them. You may have seen some of these before, but by and large, all of them should be used in any shell script you write.

A lot of Linux users are very familiar with the venerable "Bourne Again Shell" or `bash`. It is more often than not (with a few exceptions, some use ash/dash-based shells) the standard/default shell on any given Linux distribution, with its own symlink to `/bin/sh`. On BSD systems, Solaris/Illumos, and other unixes, `/bin/sh` is frequently its own animal, closer in target to the `ash` derivatives on Linux than `bash`. `bash` has very different semantics than a more classically styled Bourne Shell, and the differences can trip a lot of folks up. For example, `/bin/[` is symlinked to `/bin/test` and that's because those aren't built-ins in a lot of standard Bourne Shells; those are actually programs you execute while you're running the script.

This article does expect you have a basic familiarity with Bourne Shells as well as scripting languages in general.

# /usr/bin/env is here to save you

So I guess the first thing we should cover is situations where you know you need something like `bash`, or maybe even something more esoteric like `zsh`, and want to keep your script portable, so you do this:

```bash
#!/bin/bash
```

Which is wrong. On BSDs and older unixes (although Solaris is in /bin IIRC), bash is usually in `/usr/local/bin/bash`, which is not where this script points. This script will not run on BSD without a symlink manually added. The easy way to do this is by invoking bash from the `$PATH`, which can be done like this:

```bash
#!bash
```

There is no problem with this, it does however benefit you to use `/usr/bin/env` as you get a little more flexibility of control of the commandline as well as the environment passed to it. The `-i` and `-S` options in particular are of use to people who wish to isolate a script or provide additional arguments to it. In general, it is just a little more flexible (without any drawbacks) to:

```bash
#!/usr/bin/env bash
```

This also works great with scripting languages like `ruby`, `perl`, and `python`.

# The 'x' trick

Some Bourne Shells are more finicky about syntax than others, and depending on how intrinsics like `test` are invoked, quoting becomes an issue. Take for example this small script:

```bash
if [ "$foo" = "" ]
then
    echo "foo is empty"
fi
```

This is a problem in a traditional Bourne Shell because of how the `if` line is evaluated. More or less, `[` as previously mentioned is actually a program. When `[` is invoked, the `if` has already swallowed the quoting, so the syntax is essentially:

```bash
[ <expanded $foo> = ]
```

Which is of course a syntax error. This even gets more gory when `$foo` is also empty. The trick here is to use a placeholder character, typically an `x`, to pad the value so you can check for the existence of that. If it's the only thing there, the string is empty, but the syntax error is now gone.

```bash
if [ "x$foo" = "x" ]
then
    echo "foo is empty"
fi
```

# Stream processing with shells

A lot of people deal with file contents only through pipes (e.g., `grep`) or end up using excessive amounts of ram stuffing files into variables. There are actually easier solutions to this.

The variable `$IFS` can be set to a delimiter character (the default is "whitespace") which is then used to delimit data. This variable has impact on `for` loops, as well as the `read` command, which is the key to our trick here.

When `while` and `read` are combined, great things can happen:

```bash
(while read foo
do
    echo $foo
done) < my_file.txt
```

A lot of people do this:

```bash
for foo in $(cat my_file.txt)
do
    echo $foo
done
```

The issue here is that `cat` is going to shove the whole file in RAM. The `<` in the while reads it iteratively, reducing the ram usage to more or less one line at a time.

# fin

That's all I can think of today. Perhaps there will be another one of these in the future!
