---
title: Compiler-driven Development with Golang
date: 2021-01-25 01:16:40
tags:
  - Golang
  - Programming
---

# Why am I here?

Compiler-driven development is a simple pattern that generally makes developers much faster and more efficient. I have been working this way for some time, and wanted to share my experiences; ones I hope are useful to you.

Most of this article covers usage in Golang and vim. You should not need to be a user of vim -- just comfortable in your editor -- to make use of these tips.

# What is compiler-driven development?

Compiler-driven development is just a fancy term for letting the compiler, linter, tests, or other automated code management tools tell you where to go next. Basically, it's a useful pattern in a variety of scenarios for distilling problems with your code into small, compose-able fixes by letting the compiler tell you in steps what is broken.

Naturally, this doesn't work for everything (you still have to use your brain sometimes, after all) but it can be quite efficient when you have a nice workflow configured. Additionally, this only works well for languages that have compilers, ideally type-inferred or at least statically typed ones.

Today we will be using [Golang](https://Golang.org) and most of the tools will be centered around it. However, many of the techniques you will find applicable to other languages; "Compiler-driven development" as a term is something I picked up from the [Rust Book](https://doc.rust-lang.org/book/). I love that there is finally a phrase for it (well, at least, a new one to me).

Anyway, on to the meat.

# Find your editor's "save hook" functionality, or use file notification tools

Continuously running your compiler, linter, or other tools is how you get ahead; this is typically easiest to set up as a save hook. In vim for Golang, this is as easy as importing [vim-go](https://github.com/fatih/vim-go), which will do much of this for you automatically. `vim-go` will also format and lint your code, as well as compile check it by default. The results will be in your quicklist for easy search and manipulation.

If you don't (or can't; sometimes projects are large and rebuilding large chunks of them isn't realistic on save) want to invade your editor, consider [reflex](https://github.com/cespare/reflex) or similar file-watching tools to scan your tree and run your commands. Grouping your commands into a script or `make` task will make it easier to run them, as well as include them in your CI to ensure others are running them, too.

# The pattern

So, get ready to have your mind blown:

- Hack on errors present in the output.
- Save.
- Wait.
- Read the output.
- Repeat.

If this sounds familiar, well, that's because most of us do this basically already. The real win is in the tooling here, and adapting our workflow to depend on the tools and their output to drive us forward.

# Things you might want to do on save

Here are a few tools and things you might want to try doing to your code on save to yield a better experience.

## Vim-specific things

[syntastic](https://github.com/vim-syntastic/syntastic) is a nice little addition that puts anchors on the left column of any line that errors out. It can also highlight specific portions of the syntax in some cases. Both linters and compilers can be used, it is quite general. It is quite easy to configure: this will enable several linters, for example.

```vim
let g:syntastic_go_checkers = ['golint', 'govet', 'gocyclo']
```

[coc.vim](https://github.com/neoclide/coc.vim) is an adaptation of much of the vscode functionality in javascript, providing a TON of language support for things like compiler-driven development as well as dynamic tab completion and other features, in a multitude of languages. **Note**: CoC should be used with a language server protocol plugin like [gopls](https://github.com/Golang/tools/blob/master/gopls/README.md). Note that `vim-go` and CoC will both install these tools on demand.

To install Golang support for CoC, type `:CocInstall coc-go` in editing mode. CoC has a lot of support for different languages and other tools on [npm](https://npmjs.org); please take a look around at its repository!

To install tools to support `vim-go` (including gopls), type `:GoUpdateBinaries`

Personally, I've found including them both beneficial, but can be buggy. Be sure you have `gopls` configured so that each plugin does not run its own version of it. If I were to use only one of these, it would be CoC.

## Golang-specific things

[staticcheck](https://github.com/dominikh/go-tools) (inside this repo) is a great tool for finding all sorts of stuff. It finds everything from common bugs to deprecated APIs. It deserves a special mention because most of the reports you get from using the tool below this one will be from this one specifically; it does cover that much.

[Golangci-lint](https://github.com/Golangci/Golangci-lint/) is a multi-linter that runs staticcheck as well as a lot of others, and can accept configuration that can live on a per-repository basis, making it great for editor integration (in some cases).

Also, Golang has a nice [build and test cache](https://Golang.org/cmd/go/#hdr-Build_and_test_caching). Combining this behavior with save hooks or tools like reflex really shines great for focusing on what you're actually dealing with.

## General things

Always try to leverage your language/compiler's build cache, if available. This will greatly improve response time of your save/notify tools. If your language has something similar to Golang's test cache, great! Use it.

In that same vein, isolating tests (e.g., with `go test -run`) can also be a win when working on a project, but be careful to not over-isolate, as then you will get a nasty surprise when it's time to run the full suite; or worse, in CI!

Identifying your (and your team's) working habits and distilling them into new tasks to run will be essential to fitting this into your workflow. In an event where you cannot introduce general workflow tasks, consider building your own tools outside of the repository to introduce when you get stuff done twice as fast as everyone else. :D
