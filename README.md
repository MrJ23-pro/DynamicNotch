# DynamicNotch

English | [Français](README.fr.md)

A Dynamic Island for the MacBook notch. Shows what's playing on Spotify right around the camera, with playback controls when you hover it.

![DynamicNotch expanded](docs/preview.png)

When a song is playing, the notch gets a bit wider: album art on the left of the camera, a small equalizer on the right.

![DynamicNotch compact](docs/compact.png)

Hover it and it expands with the title, artist, a progress bar and previous / play-pause / next buttons. When nothing is playing it hides back into the notch.

It's a free, open source take on what apps like NotchNook or Alcove do, focused on Spotify and kept as light as possible.

## Requirements

- macOS 14 or later
- A Mac with a notch (on other Macs it shows as a small pill in the menu bar)
- The Spotify desktop app
- Xcode command line tools: `xcode-select --install`

## Download

Grab `DynamicNotch.zip` from the [latest release](https://github.com/MrJ23-pro/DynamicNotch/releases/latest), unzip it and move `DynamicNotch.app` to Applications. Apple Silicon only.

The app isn't notarized, so macOS will block it the first time. Either go to System Settings > Privacy & Security and click "Open Anyway", or run:

```bash
xattr -dr com.apple.quarantine /Applications/DynamicNotch.app
```

## Build from source

```bash
git clone https://github.com/MrJ23-pro/DynamicNotch.git
cd DynamicNotch
./build.sh
open DynamicNotch.app
```

On first launch macOS asks whether DynamicNotch can control Spotify. Click OK, otherwise nothing shows up. If you denied it by mistake: System Settings > Privacy & Security > Automation.

To start it at login, move `DynamicNotch.app` to Applications and add it in System Settings > General > Login Items.

## Usage

- Hover the notch to expand it
- Click the progress bar to seek
- The palette button switches theme
- Right click the island to pick a theme or quit

Themes: Classique, Pochette (gradient from the album art color), Spotify, Néon, Mono. Your choice is remembered.

![Themes](docs/themes.png)

## How it works

Spotify posts a system notification every time the track or playback state changes, so the app just listens to that instead of polling. AppleScript is only used for the album art and the buttons, and it runs off the main thread. Result: 0% CPU when you're not touching it, around 25 MB of memory.

The window is a transparent `NSPanel` sitting above the menu bar. It only catches clicks while the mouse is over the island, so the menu bar keeps working. The equalizer is animated with plain Core Animation layers.

## Limitations

- Spotify only for now (no Apple Music)
- With several displays, the island stays on the one with the notch
- Not notarized, see [Download](#download) to get past Gatekeeper

## License

MIT, see [LICENSE](LICENSE).
