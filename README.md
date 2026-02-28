# Stable Action

A camera app for iPhone that keeps your shot level no matter how much you tilt your phone. Point it at something, roll your wrist, and the footage stays perfectly upright - like the horizon is locked in place.

![Stable Action demo](demo.gif)

---

## What problem does it solve?

When you're filming action - running, cycling, skiing, handheld on a boat - your phone naturally tilts and rolls with your body. Normal camera apps just record that tilt, so your footage looks wonky. Stable Action watches the phone's orientation in real time and counteracts the roll, so the output video always looks like you were holding the phone perfectly straight.

Think of it like a virtual gimbal built into the software.

---

## How it works (the idea, not the code)

### 1. The horizon rectangle

When you open the app, you're not seeing the full camera frame. You're looking through a cropped 3:4 portrait window sitting in the middle of the sensor. This window is smaller than the actual camera output on purpose - that "extra" space around the edges is the room the stabilisation has to work with.

Picture it like a picture frame floating inside a larger canvas. When the canvas tilts, the frame stays upright by using the surrounding canvas as a buffer.

### 2. The gyroscope does the heavy lifting

Your iPhone has a gyroscope and an accelerometer that Stable Action reads continuously - 120 times per second. Two separate things are tracked at once:

**Roll correction** - if you tilt the phone sideways, the crop window tilts the opposite direction by the exact same amount. The two cancel each other out and the horizon stays flat.

**Translation correction** - if your hand jerks left, right, up, or down, the crop window slides in the opposite direction to compensate. The phone's accelerometer detects that lateral movement, integrates it into a velocity, and shifts the crop window against it. When the movement stops, the window gently drifts back to centre on its own.

So if you tilt the phone 15° clockwise AND take a step to the left, the crop rotates 15° counter-clockwise AND shifts right - both corrections happen simultaneously, every frame.

### 3. What you record is what you see

The preview on screen and the actual recorded video go through the exact same process. There's no difference between what you watch in the viewfinder and what ends up saved - the stabilisation isn't applied after the fact, it's baked in as you shoot.

### 4. Hardware stabilisation on top

On top of the roll correction, the app also turns on the iPhone's built-in hardware stabilisation. This handles the smaller, faster vibrations - hand tremor, footstep impacts, engine vibration - that the gyroscope-based roll correction isn't designed for. The two layers work together: hardware handles the micro-jitter, software handles the macro roll.

### 5. Tap to focus

Tap anywhere on the preview to lock focus and exposure to that spot, just like the native Camera app.

### 6. Action Mode

There's a toggle at the bottom labelled Action Mode. Turning it on switches the hardware stabilisation to the most aggressive setting available on your device. It's designed for high-speed or high-vibration situations where you need maximum smoothness. The tradeoff is a slightly tighter crop and a small amount of added latency - perfectly fine for action footage, less ideal for slow cinematic work.

---

## Basic usage

1. Open the app - the camera starts immediately.
2. The viewfinder shows the stabilised, horizon-locked crop. What you see is what you get.
3. Tap anywhere on screen to focus on a specific subject.
4. Hit the red record button to start recording. A **REC** indicator appears at the top while recording is active.
5. Hit the button again to stop. The video saves to your Photos library automatically.
6. Tap the thumbnail in the bottom-left corner to play back your last clip without leaving the app.
7. Toggle **Action Mode** on when shooting fast-moving subjects or in bumpy conditions.

---

## Things worth knowing

- **The app always records portrait 3:4 video.** The crop is intentional - it's what gives the stabilisation room to work without black borders appearing when the phone tilts.
- **Stabilisation is always on.** There's no way to accidentally record unstabilised footage. The roll correction runs on every single frame, recording or not.
- **The preview IS the recording.** You're not watching a separate live feed - you're watching the exact frames that will be written to disk the moment you hit record.
- **You need a real iPhone to use this.** The camera and gyroscope aren't available on the Simulator.
- **Videos save to Photos automatically** the moment you stop recording. You'll be prompted for Photos access the first time.

---

## Permissions needed

| Permission | Why |
|---|---|
| Camera | To capture video |
| Microphone | To record audio alongside video |
| Photos | To save finished clips to your library |

---

## Who is this for?

Anyone who films handheld and wants cleaner, more professional-looking footage without carrying a physical gimbal. Particularly useful for:

- Sports and action footage (skiing, skating, running, cycling)
- Vlogging while walking
- Filming from a moving vehicle
- Any situation where your hands or body are naturally moving while you shoot

---

## Credits

Designed and built by **[Rudra Shah](https://rudrahsha.in)**.

---

*Built for iPhone. Requires iOS 16 or later for full stabilisation features; iOS 18 or later recommended for the best Action Mode performance.*
