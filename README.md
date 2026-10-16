# MicDuck.spoon

A [Hammerspoon](https://www.hammerspoon.org) Spoon that turns your music down
while you're talking into your Mac's microphone, and back up when you stop.

I wrote it for voice dictation into [Claude Code](https://code.claude.com),
which has no hook for "started listening", but it works with anything that
opens a mic: dictation tools, Zoom, Meet, voice notes.

Not using Hammerspoon? [micduck](https://github.com/dabeeeenster/micduck) does
the same as a standalone background app.

## How it works

MicDuck watches every input device with `hs.audiodevice` watchers. CoreAudio
tells Hammerspoon when a device's "in use" state changes, so it reacts
instantly and doesn't poll. It never records or reads any audio.

When a mic opens, it saves the volume of **Spotify** and **Apple Music**
(whichever are running) and fades them down to 50% over 0.2 seconds. When the
mic closes, it fades them back. Saved volumes are kept in `hs.settings`, so
reloading your config mid-dictation doesn't leave the music turned down.

## Install

```sh
git clone https://github.com/dabeeeenster/MicDuck.spoon.git ~/.hammerspoon/Spoons/MicDuck.spoon
```

Then in `~/.hammerspoon/init.lua`:

```lua
hs.loadSpoon("MicDuck"):start()
```

The first time it turns the music down, macOS asks whether Hammerspoon may
control Spotify or Music; allow it.

## Configure

Set any of these before `start()`:

```lua
hs.loadSpoon("MicDuck")
spoon.MicDuck.duckTo = 40          -- percent of the player's volume (default 50)
spoon.MicDuck.fadeDuration = 0.3   -- seconds (default 0.2)
spoon.MicDuck:start()
```

`spoon.MicDuck.players` lists the apps it ducks, each as
`{ name = "<AppleScript name>", bundleID = "<bundle id>" }`. Any app with an
AppleScript `sound volume` property works.

## Caveats

- Any app holding a mic open counts. Some dictation apps keep it open all the
  time, which would keep the music down.
- Hammerspoon's device-list watcher is a single global callback that many
  configs already use, so MicDuck leaves it alone and checks for newly
  connected mics every 30 seconds instead (`rescanInterval`). A mic plugged in
  within the last 30 seconds may be missed once.
- If you change the music volume while ducked, it's overwritten when the mic
  closes.

## License

MIT
