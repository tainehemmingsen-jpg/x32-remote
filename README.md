# X32 Remote

A native iPad (and iPhone) app for mixing a **Behringer X32 / Midas M32** over Wi‑Fi — a replacement for the discontinued X32‑Mix app.

- **Mixer** — layers (Ch 1–16, Ch 17–32, Aux/FX, Mix buses, Mtx/Main, DCA and two custom layers) in a two-column panel down the right with Fine, Mute Enable, sends on fader, mute groups and Clear Solo. Each strip shows its input and gain, +48/gate/EQ/comp lights, a mini EQ curve and compressor graph, mute, pan, fader with meter, and solo. Tap the scribble strip (or the gain, EQ or compressor picture) for the channel page.
- **Channel page** — a block bar with live pictures of every section; Overview with everything side by side; Input (gain, 48 V, trim, polarity, low cut, delay), Gate, EQ with a draggable curve and the desk's analyser (RTA) behind it, Compressor, Sends as faders, and Config (name, colour, input source, stereo link, DCA and mute groups, LR/mono). Inserts, compressor position and gate/compressor sidechain (key source and key filter) too. Copy any section to another channel.
- **Sends on faders** — pick a mix bus in the right-hand panel (top-right menu on a phone) and the faders become that bus's sends (the strip tints in the bus colour so you can't mistake it for the main mix).
- **Monitor mix mode** — one performer's mix on big faders, with only the inputs they need, lockable with a PIN.
- **Simple mode** — a few big controls (e.g. Music, Mic, Main volume) for staff, with optional level caps and a PIN lock.
- **Effects** — the FX icon shows all eight slots: what's loaded, which mix feeds it, where it's inserted, and the return level. Reverbs, delays, chorus and flanger in slots 1–4 are fully editable, and graphic EQs (GEQ/TEQ, stereo or dual) in any slot get a 31-band editor — drag a band, or sweep across to draw a curve.
- **Output patch** — from the desk-name menu: what each local out, aux out, P16 (Ultranet), AES and record output carries, and the tap point for direct outs. Every change asks first.
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
- **Parameters** (gain, EQ, dynamics…) are slider bars: drag left/right anywhere on the bar. Double‑tap resets EQ gain and trim.
- **Fine:** switch it on (right-hand panel, or the channel page header) and every fader, pan and bar moves 4× more slowly under your finger.
- **Pan:** drag sideways; double‑tap centres.
- **Exact values:** long‑press any slider, gain or pan — or double‑tap a fader — to type a value or step it by 0.1 / 1 dB.
- **Gain on faders:** tap **Gain** at the bottom of the sends list; the faders turn red and control preamp gain.
- **DCA spill:** on the DCA layer, tap a DCA's name to see its channels; tap again to go back.
- **Custom layers:** User 1 and User 2 — tap an empty one (or long‑press it) to pick channels.
- **Config:** long‑press any channel name to jump to its name, colour and group settings.
- **Meters:** the bar‑chart icon shows every meter on the desk.
- **Undo:** the curved arrow undoes your last change (a whole fader move counts as one). Recalling a scene clears it.
- **Copy / paste:** on a channel page, the copy icon copies everything or one section (preamp, gate, EQ, compressor, sends); open another channel and paste.
- **Presets:** the same menu saves a channel's preamp, gate, EQ and compressor as a named preset on your iPad, and loads a preset (all of it or one section) onto any channel.
- **Solo and talkback:** the headphones icon has the solo/phones level, Dim, Mono, what the phones listen to, PFL/AFL, exclusive solo, and where Talk A and B go. Talk A/B: tap to latch on, or hold to talk and let go to stop.
- **Stereo links:** linked pairs show a link mark under the fader; link or unlink a pair on the Config page. The app re-reads the other side after each change so the screen matches the desk.
- **Select on desk** (Settings): opening a channel in the app also selects it on the X32's own screen.
- **RTA:** tap RTA on the EQ page to see the desk's analyser for that channel behind the curve (it points the desk's RTA at the channel you have open). If the desk was just switched on, tap Start to wake its analyser.
- **Tap tempo:** delays in the effects rack have a TAP button — tap along to the music to set the delay time.
- **Graphic EQ:** on a GEQ in the effects rack, drag a band up or down; sweep sideways to draw a curve; double-tap a band to reset it.
- **48 V** asks for confirmation before switching on.
- **Scenes** ask before recalling, then the app re-reads the desk.
- **Locking:** in Monitor or Simple mode, set a PIN and lock. The mixer is then hidden until someone enters the PIN.

## How it was tested

- `Tests/CoreTests` — 70 unit tests for the OSC codec, X32 value scales (fader law, EQ, dynamics, typed values), addresses, meters, the client (request window, retries, coalescing, reconnect), undo, copy/paste, stereo links, DCA spill, layers and the demo desk.
- `Tests/Integration` — drives the real networking code against [Patrick‑Gilles Maillot's X32 emulator](https://github.com/pmaillot/X32-Behringer) over UDP: connects, reads ~680 parameters plus ~390 channel-page parameters, checks changes reach the desk, updates from another client arrive, and meters decode.
- `ci/` + `.github/workflows/ios.yml` — on every push, a self-hosted GitHub Actions runner on the owner's Mac (so it costs nothing) builds the app with Xcode, runs the tests, screenshots every screen in the iPad and iPhone simulators, and runs the app against the emulator to check its changes reach the "desk". Results (logs + screenshots) land on the `ci-results` branch.

It hasn't been run against a physical X32 yet. If something behaves differently on the real desk, the X32's own screen is the source of truth.

## Not in this version

Input routing blocks, editing the EQ/dynamics processors in FX slots 5–8 (other than graphic EQs), and the desk's own library presets.

---

Not made by or affiliated with Behringer, Midas or Music Tribe. X32 and M32 are their trademarks.
