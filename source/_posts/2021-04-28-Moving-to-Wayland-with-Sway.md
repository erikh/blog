---
title: Moving to Wayland (with Sway)
date: 2021-04-28 22:27:45
tags:
  - Computing
---

[Wayland](https://wayland.freedesktop.org/) provides a lot of fine enhancements over X11 and xorg, which has tried hard to maintain a protocol older than most of the people that will probably read this. Some of the things it brings:

- **Composition**: While [there is a specific meaning for compositing window manager](https://en.wikipedia.org/wiki/Compositing_window_manager), this is more frequently used as a bucket term for a number of technologies that use the 3-D features of your graphics card to provide enhanced visual effects, such as V-Sync on fast output, transparency, and a few other things.
- **Simplification & Integration**: Wayland puts more control of the operating system in the hands of the window manager, allowing it to function more like a cohesive product, instead of two things that happen to work together: a consequence of the X11 client/server architecture.
- **Performance**: all this adds up to a nice healthy performance boost. Personally, I've seen my idle CPU usage drop by about 8% or so on a i7-8790k.

You heard that right: it's _faster_, it's _smarter_ and it's even _prettier_. So why isn't it more used?

It's a little less mature than most people would accept, but with the adoption of it in several major Linux desktop providers and the ubiquitous [GNOME](https://gnome.org) desktop environment, it is gaining rapid maturity. I have caused two crashes while configuring the thing, and experienced one while not expecting something bad as of this writing (about 24h in).

That said, today we're not using GNOME. We're using something else, called [Sway](https://swaywm.org/). Sway is much like [i3](https://i3wm.org/) down to the point where it will _ingest most of i3's configuration file_. As an i3 user, I found this an attractive and low-risk way to test Wayland. After all, I could always just go back to i3 and X; but my configuration is somewhat complicated to build, and a 3 day configuration festival was not in the cards this time... I have shit to do! Sway's "close-enough" parsing of i3's configuration was exactly what I needed to make the trial run fast.

What follows is my journey into the vortex of GUI configuration, a black hole for many software developers, leeching the light and breath out of many of you that would rather be doing anything else. I took this bullet for you.

## Hardware

Let's talk about hardware really quick. [Graphics cards matter](https://www.phoronix.com/scan.php?page=news_item&px=NVIDIA-470-Wayland-Friendly). For now, I strongly recommend getting a low end, current generation AMD Radeon. I have a 5500. If you want to play games, go up, but you want a Radeon for now.

My setup is different than many, and a picture is worth a thousand words, so:

![my battlestation](/assets/img/battlestation.jpg)

Here lies:

- Three 4k monitors in portrait mode, this is 2160 x 3840 in effect, a set of numbers we'll see more useful as we dive the configuration. Sway does not support this configuration natively, (neither does X or i3, really, fwiw) so shoving it into place is an exercise we'll touch on later.
- One ZSA Moonlander and one Apple Magic Trackpad. These only matter because I had to do next to nothing to get these to work exactly as I'd like them to. Sway and Wayland had the goods configured right, and it does help that the keyboard is firmware-programmable.
- The video card as previously mentioned is a Radeon 5500. Other kit doesn't matter much; it's fast. The machine has 32GB of RAM, but even with all apps loaded it idles at around 5-6GB without any extra VM work or lots of browser tabs, etc.

## Starting Software

If you're playing the at-home game:

- [Manjaro GNOME](https://manjaro.org) 21.0.3 w/ `linux511` 5.11 kernel package. `5.11.16-2-MANJARO` is currently in use.
  - Arch probably works here but some of the package names may be different, or come with different default configuration.
- i3 is configured and ready to work (but this is not necessary to follow along). GNOME is mostly left untouched.

## Installing

The Manjaro/Arch packages we need are:

- sway (window manager)
- swaylock (desktop locker)
- swayidle (idle management, powers of screens, locks computer)
- waybar (status bar)
- alacritty (terminal)
- mako (notification daemon)

_Plenty_ of other dependencies will be pulled in; don't worry, you're not getting off that easy.

## Configuration

Configuring Sway is much like configuring i3; some of the commands are different, however, especially around the I/O systems (your keyboard and your monitors, for example). Please review the following manual pages for more information on configuration:

- `man 5 sway`: this is most of the configuration language. The `sway` binary can also be used to execute these statements as standalone commands, as we will see soon.
- `man 5 swaymsg`: this is a tool used to query sway, which you will use to configure your displays later.
- `man 5 sway-output`: a manual page just for the output subcommand.

Those are the ones we will need to complete this post, but there are others such as the ones for `swaylock` and other associated tools, as well as more for `sway` itself.

### Initial Configuration

Start with the [defaults](https://github.com/swaywm/sway/blob/master/config.in). This will fit the documentation better, most of my tweaks aren't very useful to anyone but me. Instead of providing a full configuring for you to pick through, we'll highlight parts of the configuration that were sticky instead.

### Display Support

Display support is mainly covered by the `output` configuration directive, and is used in configuration to set the initial layout, but _also_, you can use it to manipulate the video on the fly similar to the `xrandr` tool for X11.

In my case, I need to set up the three monitors so that they are occupying enough space -- a problem with sway is that all of the displays seem to require being set at the initial rotation that Wayland set them to; you cannot adjust this directly in the configuration file.

Instead, we allocate enough space for them to rotate themselves, assuming we will do that as a part of our login. What a mess, right? Maybe eventually this can be resolved.

Anyway, we can do this with the following configuration for 3 vertical monitors:

```
output DP-2 scale 2 pos 0 0
output DP-1 scale 2 pos 1080 0
output DP-3 scale 2 pos 2160 0
```

Note that we are splitting by 1080, not 2160 as mentioned prior; this is because of the `scale 2` argument transforming the virtual real-estate you have on your screen. If you are doing this yourself, you can query the names of your outputs with `swaymsg -t get_outputs`.

The nice thing about this problem is it gets us to think about the orientation of these monitors, because they are all on arms that rotate, allowing us to manage them independently.

[This script](https://gist.github.com/erikh/36db9fccea81d7a220905ce43e9541dc) is what I use to manage the monitors:

- Keeps workspaces sticky to monitors, even after they have changed orientation. 1,4,7 are on monitor 1, 2,5,8 on 2, etc.
- Allows me to select what configuration I need:
  - `share` moves to landscape orientation so I can more easily share my screen with others.
  - `fix` rights all the monitors in the expected portrait configuration.
  - `focus` turns the side monitors off for when chatter and other distractions are too much.

Note that the script runs the following commands:

- `sway output <output> dpms on/off` - this controls the screen's power state.
- `sway output <output> enable/disable` - this controls the screen's membership in the session; a disabled screen is basically power attached but not a part of the sway environment until re-enabled.
- `sway output <output> transform <normal/90 clockwise>` - this is what transforms our screens. To avoid doing relative calculations, I reset it to normal first in a lot of instances.

### Locking

For locking you can use `swaylock`, but this is best used with the `swayidle` tool that works as an idle detector (and therefore invokes autolock). Try these configuration lines:

```
exec swayidle -w timeout 300 'swaylock -f -c 000000' timeout 600 'swaymsg "output * dpms off"' resume 'swaymsg "output * dpms on"' before-sleep 'swaylock -f -c 000000' lock 'swaylock -f -c 000000'
bindsym $mod+Ctrl+l exec --no-startup-id loginctl lock-session
```

This lock the screen after 5 minutes, turn the monitors off after 10, work with your laptop, and also `loginctl`, which we've assigned to `<mod>+Ctrl+l`.

### Status Bars

For status bars, we've put together something using [waybar](https://github.com/Alexays/Waybar). I've made a small tweak on [robertjk's configuration](https://github.com/robertjk/dotfiles/tree/253b86442dae4d07d872e8b963fa33b5f8819594/.config/waybar) that you can find [here](https://gist.github.com/erikh/dbda692bc2a1781b15dfe84bdebef745).

## Putting it all together

It looks like this! This screenshot was taken with `grim`, a Wayland screenshot tool. The colors are generated by [pywal](https://github.com/dylanaraps/pywal).

![screenshot!](/assets/img/wayland-screenshot.png)

### Electron Apps

Electron apps, in particular don't play very well with Wayland; this is an open issue that is being addressed, however.

You can enable the "Ozone Platform" on some builds of Slack, at least, and that will allow you to enable Wayland:

```
slack --enable-features=UseOzonePlatform --ozone-platform=wayland
```

### Other things:

- You can just start `mako` to manage notifications; but it has tunables as well as a manual.
- `rofi` is what I use for launching but it's not technically a Wayland program I don't think. Still good!

# Thanks!

Thanks for reading!
