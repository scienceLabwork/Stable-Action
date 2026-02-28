# Stable Action

**Samsung Super Steady Horizon Lock - rebuilt for iPhone.**

Samsung's Galaxy S25 Ultra ships a feature called Super Steady with Horizon Lock that keeps your footage perfectly level no matter how much you tilt or shake the phone. It's one of the most impressive stabilisation tricks in mobile cameras right now - and it's exclusive to Android.

Stable Action brings that exact same experience to iOS. Point it at anything, tilt your wrist, run, jump, ride - the horizon stays locked flat, just like on the S25 Ultra.

![Stable Action demo](demo.gif)

---

## Inspired by Samsung Super Steady Horizon Lock

The Galaxy S25 Ultra's Horizon Lock works by cropping into the sensor and counter-rotating that crop window against the phone's tilt in real time. The result is a video where the horizon never moves, even when the phone is spinning in your hand.

Stable Action replicates this on iPhone using the exact same principle - gyroscope-driven counter-rotation, a floating crop window inside a larger sensor buffer, and hardware ISP stabilisation layered on top. The implementation is native Swift, runs entirely on-device, and adds translation correction (up/down/left/right drift) that Samsung's version doesn't publicly advertise.

---

## What problem does it solve?

When you're filming action - running, cycling, skiing, handheld on a boat - your phone naturally tilts and rolls with your body. Normal camera apps just record that tilt. Stable Action watches the phone's orientation 120 times per second and counteracts it, so the output always looks like you were holding the phone perfectly straight.

Think of it as a virtual gimbal built into the software.

---

## How it works (the idea, not the code)

### 1. The horizon rectangle

When you open the app in Action Mode, you're not seeing the full camera frame. You're looking through a cropped 3:4 portrait window floating in the middle of the sensor. That window is intentionally smaller than the actual sensor output - the surrounding space is the buffer the stabilisation uses to move without hitting the edge of the frame.

Picture it like a picture frame floating inside a larger canvas. When the canvas tilts, the frame stays upright.

### 2. The gyroscope does the heavy lifting

Two corrections happen simultaneously, every single frame:

**Roll correction** - if you tilt the phone sideways, the crop window rotates the opposite direction by the exact same amount. The two cancel out and the horizon stays flat. This is the core of what Samsung calls Horizon Lock.

**Translation correction** - if your hand jerks left, right, up, or down, the crop window slides in the opposite direction to compensate. The accelerometer detects the lateral movement, integrates it into a velocity, and shifts the crop window against it. When the movement stops the window drifts back to centre on its own.

### 3. What you record is what you see

The preview on screen and the recorded video go through the exact same processing pipeline. What you see in the viewfinder is exactly what gets written to disk - no post-processing, no surprises.

### 4. Hardware stabilisation on top

On top of the gyroscope corrections, Stable Action also engages the iPhone's built-in ISP stabilisation. This handles micro-jitter - hand tremor, footstep impact, engine vibration - that the gyroscope-based corrections aren't designed for. The two layers stack: hardware cleans up the small stuff, software handles the big roll.

### 5. Normal vs Action Mode

- **Normal mode** - plain full-frame camera view, no crop, standard stabilisation. Looks and feels like the native Camera app.
- **Action mode** - the full Samsung-style Horizon Lock pipeline kicks in. Gyroscope roll correction, translation correction, and the most aggressive hardware stabilisation your device supports.

---

## Basic usage

1. Open the app - camera starts immediately in Normal mode.
2. Toggle **Action Mode** on at the bottom to enable Horizon Lock stabilisation.
3. The viewfinder switches to the stabilised crop view. Tilt the phone - the horizon stays flat.
4. Tap anywhere on screen to lock focus and exposure to that spot.
5. Hit the red button to record. A **REC** indicator pulses at the top.
6. Hit it again to stop - the clip saves to Photos automatically.
7. Tap the thumbnail in the bottom-left to play back your last clip without leaving the app.

---

## Things worth knowing

- **Action Mode always records 3:4 portrait video.** The crop is what gives stabilisation room to work - it is not a bug.
- **Normal Mode records the full sensor frame** with no crop and no roll correction.
- **Stabilisation is always on in Action Mode.** There is no way to accidentally shoot unstabilised footage once the toggle is on.
- **Requires a real iPhone.** Camera and gyroscope are not available in the Simulator.
- **Videos save to Photos automatically** the moment you stop recording.

---

## Permissions needed

| Permission | Why |
|---|---|
| Camera | To capture video |
| Microphone | To record audio alongside video |
| Photos | To save finished clips to your library |

---

## Who is this for?

Anyone who wants Samsung Galaxy-level Horizon Lock stabilisation on their iPhone, without buying an Android phone. Particularly useful for:

- Sports and action footage (skiing, skating, running, cycling)
- Vlogging while walking
- Filming from a moving vehicle
- Any situation where your hands or body are naturally moving while you shoot

---

## Credits

Designed and built by **[Rudra Shah](https://rudrahsha.in)**.

---

*Built for iPhone. Requires iOS 16 or later. iOS 18 or later recommended for best Action Mode performance.*
*Built for iPhone. Requires iOS 16 or later for full stabilisation features; iOS 18 or later recommended for the best Action Mode performance.*
