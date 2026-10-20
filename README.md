# X32 Remote

A native iPad (and iPhone) app for mixing a **Behringer X32 / Midas M32** over Wi‑Fi — a replacement for the discontinued X32‑Mix app.

- **Mixer** — layers (Ch 1–16, Ch 17–32, Aux, FX returns, Buses, Matrix·Main, DCA) in a panel down the right with mute groups, sends on fader and Fine. Each strip shows its input and gain, +48/gate/EQ/comp lights, a mini EQ curve and compressor graph, mute, pan, fader with meter, and solo. Tap the scribble strip (or the gain, EQ or compressor picture) for the channel page.
- **Channel page** — Input (gain, 48 V, trim, polarity, low cut), EQ with a draggable curve, gate and compressor, sends, and setup (name, colour, DCA and mute-group assignment, LR/mono).
- **Sends on faders** — pick a mix bus in the right-hand panel (top-right menu on a phone) and the faders become that bus's sends (the strip tints in the bus colour so you can't mistake it for the main mix).
- **Monitor mix mode** — one performer's mix on big faders, with only the inputs they need, lockable with a PIN.
- **Simple mode** — a few big controls (e.g. Music, Mic, Main volume) for staff, with optional level caps and a PIN lock.
- **Demo desk** — a built-in simulated X32 so you can try everything without a console.

It talks to the desk directly (OSC over UDP port 10023), so there's no extra box.

## Put it on your iPad (MacBook + Xcode)

1. Open **`X32Remote.swiftpm`** in Xcode (double-click it, or File › Open…). Give Xcode a moment to load the package.
2. Plug the iPad into the Mac with a cable. On the iPad, tap **Trust**, then turn on **Settings › Privacy & Security › Developer Mode** (the iPad restarts).
3. In Xcode, choose the **X32 Remote** scheme and your iPad as the run destination (top of the window).
4. Click the project in the left sidebar, open **Signing & Capabilities**, and pick your Apple ID as the **Team** (Xcode › Settings › Accounts › + if it isn't listed).
   - If Xcode says the bundle identifier is taken, change `bundleIdentifier` in `Package.swift` to something unique, like `nz.yourname.x32remote`.
5. Press **Run** (⌘R). The first time, the iPad may ask you to trust the developer: **Settings › General › VPN & Device Management** › your Apple ID › Trust.

With a free Apple ID the app works for **7 days**, then needs re‑installing — just plug in and press Run again. A paid Apple Developer membership makes it last a year and lets you use TestFlight.

### No Mac handy?

The same folder is a Swift Playgrounds app: copy `X32Remote.swiftpm` to the iPad (AirDrop or iCloud Drive), open it in **Swift Playgrounds**, and tap Run. It runs inside Playgrounds, so there's no 7‑day limit.

## First connection

1. Put the iPad on the same network as the X32 (usually a Wi‑Fi access point plugged into the desk's Ethernet port).
2. Open the app and tap **Allow** when iOS asks about Local Network access.
3. The desk appears under *Mixers on this network* — tap it. Or type its IP address (on the X32: **Setup › Network**).

The app remembers the desk and reconnects on launch (turn that off in Settings). It keeps the screen awake while connected.

## Tips

- **Faders:** touch anywhere on a fader and drag — it never jumps to your finger. Slide your finger sideways off the strip while dragging for fine control. Several faders can be moved at once.
- **Parameters** (gain, EQ, dynamics…) are wide slider bars: drag left/right anywhere on the bar, or tap − / + for one step (hold to repeat). Double‑tap resets EQ gain and trim.
- **Fine:** switch it on (right-hand panel, or the channel page header) and every fader, pan and bar moves 4× more slowly under your finger.
- **Pan:** drag sideways; double‑tap centres.
- **48 V** asks for confirmation before switching on.
- **Scenes** ask before recalling, then the app re-reads the desk.
- **Locking:** in Monitor or Simple mode, set a PIN and lock. The mixer is then hidden until someone enters the PIN.

## How it was tested

- `Tests/CoreTests` — 39 unit tests for the OSC codec, X32 value scales (fader law, EQ, dynamics), addresses, meters, the client (request window, retries, coalescing, reconnect) and the demo desk.
- `Tests/Integration` — drives the real networking code against [Patrick‑Gilles Maillot's X32 emulator](https://github.com/pmaillot/X32-Behringer) over UDP: connects, reads ~680 parameters plus ~390 channel-page parameters, checks changes reach the desk, updates from another client arrive, and meters decode.
- `ci/` + `.github/workflows/ios.yml` — on every push, GitHub Actions builds the app with Xcode, runs the tests, screenshots every screen in the iPad and iPhone simulators, and runs the app against the emulator to check its changes reach the "desk". Results (logs + screenshots) land on the `ci-results` branch.

It hasn't been run against a physical X32 yet. If something behaves differently on the real desk, the X32's own screen is the source of truth.

## Not in this version

FX rack editing, routing/patching, graphic EQ, RTA, channel-link display, custom layers and library presets.

---

Not made by or affiliated with Behringer, Midas or Music Tribe. X32 and M32 are their trademarks.
