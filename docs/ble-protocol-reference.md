# OKK Lamp: BLE protocol reference for app developers

Purpose: everything needed to write a client that behaves exactly like the Android app in this
repository. Protocol version 1, live layout version 1, firmware 0.2.0.

How this document was made: written from the firmware source in `src/` (mainly
`lamp-protocol.toit`, `lamp-ble.toit`, `lamp-state.toit`, `lamp-alarm.toit`, `lamp-timer.toit`,
`lamp-telemetry.toit`, `lamp-log.toit`, `lamp-device.toit`), with the design history in
`docs/ble-gatt-spec.md`. If this document and the code disagree, the code wins.

Labels used below:

- [Code] read directly from the firmware source. It says what the code does, not that it has been seen working on hardware.
- [Guess] my inference, not confirmed. Test it before relying on it.
- [Pending] known to be undecided or untested.
- [Decision] a design choice we made (the lamp does this on purpose).

Nothing here has been checked against a running lamp in this session. Hardware test status is in
`docs/ble-gatt-spec.md` section 13.

## 1. Conventions

- All multi-byte integers are little-endian. u8/u16/u32 are unsigned, i16 is signed two's complement.
- Every packet is at most 20 bytes, so it fits the default ATT MTU of 23. [Decision] The peripheral cannot read the negotiated MTU, and the Android app does not request a larger one. [Code]
- "Unknown" sentinels: u16 `0xFFFF`, i16 `0x8000` (-32768). The lamp never sends a real value equal to a sentinel: it clamps real u16 values to 0xFFFE and real i16 values to -32767..32767. [Code]
- Brightness is permille (0 to 1000). The driver applies its own gamma. Colour temperature (CCT) is Kelvin; the lamp's usable range is in Info (this build: 3000 to 6000 K, per the project notes).
- Time is Unix seconds in UTC. Lamp sensor timestamps are *lamp uptime seconds*, not Unix time (section 7).
- All writes use ATT Write Request (with response). No characteristic offers Write Without Response. [Code: properties are WRITE only]
- A write of the wrong size is dropped by the lamp, not rejected: the handler logs a warning and returns normally, so the app will most likely see a successful write response and no effect. [Code for the drop; Guess for what the stack returns] Check sizes on the client.

## 2. UUIDs

Base: `b45f<slot>-4423-4e5d-a885-2418d6adf470`, where `<slot>` is four hex digits. [Code: `UUID-TAIL_`]

| Slot | Name | Full UUID |
|---|---|---|
| 1000 | Lamp service | b45f1000-4423-4e5d-a885-2418d6adf470 |
| 1001 | State | b45f1001-4423-4e5d-a885-2418d6adf470 |
| 1002 | Ramp | b45f1002-4423-4e5d-a885-2418d6adf470 |
| 1003 | Cue | b45f1003-4423-4e5d-a885-2418d6adf470 |
| 1004 | Alarm | b45f1004-4423-4e5d-a885-2418d6adf470 |
| 1005 | Timer | b45f1005-4423-4e5d-a885-2418d6adf470 |
| 2000 | Sensor service | b45f2000-4423-4e5d-a885-2418d6adf470 |
| 2001 | Live | b45f2001-4423-4e5d-a885-2418d6adf470 |
| 2002 | History control | b45f2002-4423-4e5d-a885-2418d6adf470 |
| 2003 | History data | b45f2003-4423-4e5d-a885-2418d6adf470 |
| 3000 | System service | b45f3000-4423-4e5d-a885-2418d6adf470 |
| 3001 | Status | b45f3001-4423-4e5d-a885-2418d6adf470 |
| 3002 | Time | b45f3002-4423-4e5d-a885-2418d6adf470 |
| 3003 | Info | b45f3003-4423-4e5d-a885-2418d6adf470 |
| 3004 | Log control | b45f3004-4423-4e5d-a885-2418d6adf470 |
| 3005 | Log data | b45f3005-4423-4e5d-a885-2418d6adf470 |
| 3006 | Config | b45f3006-4423-4e5d-a885-2418d6adf470 |

## 3. Properties and permissions

"Enc" means the characteristic requires an encrypted (bonded) link; the first access triggers pairing. [Code: permissions are READ-ENCRYPTED / WRITE-ENCRYPTED]

| Characteristic | Read | Write | Notify | Needs encryption | Size (bytes) |
|---|---|---|---|---|---|
| State 1001 | yes | yes | yes | read and write | 5 |
| Ramp 1002 | no | yes | no | write | 7 |
| Cue 1003 | no | yes | no | write | 6 |
| Alarm 1004 | yes | yes | no | read and write | 19 |
| Timer 1005 | yes | yes | no | read and write | 5 |
| Live 2001 | yes | no | yes | read | 18 |
| History control 2002 | no | yes | no | write | 5 |
| History data 2003 | no (not intended) | no | yes | (read permission set) | 20 or 8 |
| Status 3001 | yes | no | yes | **no** | 6 |
| Time 3002 | yes | yes | no | read and write | 8 |
| Info 3003 | yes | no | no | **no** | 14 |
| Log control 3004 | no | yes | no | write | 3 |
| Log data 3005 | no (not intended) | no | yes | (read permission set) | 3 to 20 |
| Config 3006 | yes | yes | no | read and write | 7 |

Notes:

- Status and Info are readable without pairing. That is how an app can identify the lamp and show its state before bonding. [Decision]
- History data and Log data are notify-only. The firmware gives them a placeholder value and a read permission only because the Toit API needs one. Do not read them. [Code]
- Notify characteristics need the client to write the CCCD (enable notifications). Whether CCCD writes on the encrypted characteristics also trigger pairing is [Guess].
- Alarm, Timer, Config and Time are read/write only: there is no notification when they change. State bit 3 (armed) and bit 4 (timer running) are the change signals for Alarm and Timer; re-read the characteristic when they flip.

## 4. Advertising, pairing and connection behaviour

### Advertisement

- Connectable, undirected. [Code]
- Main packet: flags (general discovery, BR/EDR not supported), the Lamp service UUID (128-bit), and the name `OKK Lamp`. [Code]
- Scan response: GAP Appearance AD (type 0x19) value `0x0585` ("Desk Light"). [Code]
- Fallback: if the first advertisement fails to start (the name did not fit), the lamp retries with the name in the scan response instead. [Code] **Scan by the Lamp service UUID, not by name.** The Android app additionally falls back to the name `OKK` for an already-paired lookup [Guess: that prefix match is an app choice, not a protocol guarantee].

### When the lamp advertises [Code, Decision]

- For 5 minutes after boot, and for 5 minutes (restarted) after the encoder button is held for 10 s or more.
- Always while an alarm is armed, even outside the window.
- Never while a client is subscribed to Status.

### Presence detection

Toit's BLE peripheral API gives the firmware no connect or disconnect events. The lamp treats "at least one client subscribed to Status" as "a phone is connected". [Code] Consequences for a client:

- Subscribe to Status as soon as you connect, and keep that subscription for as long as you want to hold the lamp. Without it the lamp keeps advertising and does not know you are there.
- Unsubscribing, or disconnecting (which should drop the subscription, [Guess]), lets the lamp resume advertising (if the window is open or an alarm is armed).
- One phone at a time is the intended use. [Decision]

### Pairing and security

- Just Works bonding, LE legacy pairing (`--bonding --secure-connections=false`). [Code]
- No application-level authorisation exists yet (spec section 5.3 is a draft). Anyone who can bond can control the lamp. [Pending]
- After bonding, reconnect and use encrypted characteristics normally.

### Encoder button (affects what you see)

Physical controls change State and so produce State notifications: turn = ±50 permille brightness or ±200 K (depending on the selected function), press = toggle on/off, hold 3 s = switch function, hold 10 s or more = open the advertising window only. [Code from `project-clock-2.toit`; the per-turn steps are as noted in my project summary, not re-checked here.] Any encoder action cancels a running ramp and cue (section 6.1).

## 5. Recommended connection sequence

This is what a compatible app should do. Steps marked * are optional.

1. Scan for the Lamp service UUID `b45f1000-...`. Connect.
2. Discover services. Read **Info** (no pairing needed). Check protocol byte = 1 and live layout byte = 1; refuse or degrade if different. Note capability bits, `boot id`, CCT range.
3. Read **Status** (no pairing needed) and subscribe to it. This also marks you as present.
4. Bond if not yet bonded (first access to an encrypted characteristic).
5. Write **Time** (section 8.2) immediately. Alarms are refused until the lamp has a clock.
6. Write **Config** (section 8.3). It is RAM only and reverts to defaults after every lamp reboot, so write it on every connect.
7. Read **State**, **Alarm**, **Timer*** and subscribe to **State** and **Live**.
8. Subscribe to **Log data***, then write Log control `replay` with the last line sequence you hold (section 8.5) to catch up.
9. Subscribe to **History data***, then write History control `replay` with the newest uptime you hold (section 7.2) to catch up.
10. Reconcile your alarm (section 6.4): if the lamp's plan with your token is missing and still in the future, write it again.

Compare Info's `boot id` with the one you saw last time. If it changed, the lamp rebooted: its clock, alarm, timer and Config are gone, its uptime restarted, and its history and log buffers are empty. [Code: boot id is a random value drawn once per boot]

## 6. Lamp service (1000)

### 6.1 State (1001): read, write, notify. 5 bytes

Value (read and notify):

| Offset | Type | Field |
|---|---|---|
| 0 | u8 | flags: bit0 on, bit1 ramp running, bit2 cue active, bit3 alarm armed, bit4 timer running |
| 1 | u16 | brightness, permille 0..1000 |
| 3 | u16 | CCT, Kelvin |

- `on` (bit0) is false while the lamp is locked out, even if the stored on-state is true. [Code: `is-on`]
- Brightness is the stored level and is kept while the lamp is off. [Code]
- Bits 1 and 2 are set while a ramp or a cue (flash, nightlight) is running. Brightness and CCT in notifications move while a ramp runs.

Write:

| Offset | Type | Field |
|---|---|---|
| 0 | u8 | flags: bit0 on (other bits ignored [Guess]) |
| 1 | u16 | brightness permille; `0xFFFF` = leave unchanged; values above 1000 are clamped to 1000 |
| 3 | u16 | CCT Kelvin; `0xFFFF` = leave unchanged; otherwise clamped into the Info CCT range |

Behaviour [Code]:

- A State write is a manual override: it cancels any running ramp and cue, with no restore of the pre-cue state. It does *not* disarm the alarm and does *not* end the reading timer by itself (only switching off does, section 6.5).
- Brightness and CCT in a write apply even when `on` is 0 (the level is stored for the next switch-on).
- While locked out (section 8.1) every control write is accepted but ignored, the output stays dark, and State is notified again so the client sees nothing changed.
- Notifications are sent only when the 5 bytes change (apart from the forced re-notifications above, and on lockout changes), and are coalesced to at most about 5 per second (one per 200 ms). During a ramp the lamp updates every 200 ms.

### 6.2 Ramp (1002): write. 7 bytes

| Offset | Type | Field |
|---|---|---|
| 0 | u16 | target brightness permille; `0xFFFF` = keep current; above 1000 clamped |
| 2 | u16 | target CCT Kelvin; `0xFFFF` = keep current; otherwise clamped into range |
| 4 | u16 | duration in seconds; 0 = apply immediately |
| 6 | u8 | curve: 0 linear, 1 smooth (smoothstep `3t²−2t³`); any other value behaves as linear [Code] |

Behaviour [Code]:

- Starts from the current state. If the lamp is off, it starts from brightness 0 and switches the lamp on when the target is above 0.
- Brightness and CCT interpolate together, updated every 200 ms. Linear is in the driver's already gamma-corrected brightness.
- A ramp whose target brightness is 0 switches the lamp off at the end and restores the previous stored brightness for the next switch-on.
- Duration 0: applies at once (target 0 means off).
- A Ramp write first ends any running cue (restoring the pre-cue state), then starts. A State write or encoder action ends the ramp and leaves the lamp as just set.
- Ignored while locked out.

### 6.3 Cue (1003): write. 6 bytes

| Offset | Type | Field |
|---|---|---|
| 0 | u8 | type: 0 stop, 1 flash, 2 nightlight |
| 1 | u8 | flash count, clamped to 1..255 (ignored for stop and nightlight) |
| 2 | u16 | flash period in ms for one on-off cycle, clamped to 100..10000 (ignored for stop and nightlight) |
| 4 | u16 | level permille; `0xFFFF` = default; above 1000 clamped |

Behaviour [Code]:

- Starting a cue saves the current on/off, brightness and CCT. A cue ends and restores that saved state when it finishes (flash), when stopped (type 0), or when a Ramp write replaces it. A State write or encoder action ends it without restoring.
- Flash: on for half the period, off for half, repeated `count` times, at `level` (default: the current brightness).
- Nightlight: lamp on at `level` (default 50 permille) at the lowest CCT (Info min). It stays until stopped, or until a State write, Ramp or encoder action. While the nightlight cue is active the status LED stays dark.
- Unknown cue types are ignored (a warning is logged). Ignored while locked out.

### 6.4 Alarm (1004): read, write. 19 bytes

| Offset | Type | Field |
|---|---|---|
| 0 | u8 | flags: bit0 armed, bit1 smooth curve (otherwise linear) |
| 1 | u32 | start time, Unix seconds UTC |
| 5 | u16 | ramp duration, seconds |
| 7 | u16 | start brightness permille (clamped to 1..1000) |
| 9 | u16 | start CCT Kelvin |
| 11 | u16 | target brightness permille (clamped to at most 1000) |
| 13 | u16 | target CCT Kelvin |
| 15 | u16 | hold time after the ramp, seconds (0 = stay on) |
| 17 | u16 | token, chosen by the phone |

Reading returns the stored plan, or 19 zero bytes when none is armed. [Code]

Behaviour [Code unless noted]:

- One plan only, held in RAM. A reboot or power cut loses it.
- A write with `armed` = 0 disarms (stores the empty plan), whatever the other bytes say.
- An arming write is refused (ignored, nothing stored, State re-notified) when: the lamp is locked out; the lamp has no clock (no Time write since boot); or `start` is not later than the lamp's current time. After a refusal, read Alarm or look at State bit3 to see it was not accepted.
- The lamp checks once per second. When `start` is reached it clears the plan (armed falls to 0, State bit3 clears), cancels a running reading timer, turns the lamp on at the start brightness and CCT (the CCT is clamped into range; there is no "unchanged" sentinel in this characteristic), then ramps to the target over `ramp` seconds with the chosen curve (0 = immediate).
- If the clock jumped and `start` is more than 60 s in the past when the lamp notices, or the lamp is locked out, the plan is dropped without lighting the lamp.
- Hold: if `hold` > 0, `hold` seconds after the ramp ends the lamp switches off, unless anyone touched it in the meantime (State write, Ramp, Cue, encoder), in which case it is left alone.
- State, Ramp or Cue writes and the encoder do not disarm.
- `token` is opaque to the lamp: it is stored and read back, nothing more. The Android app uses it to recognise its own plan and does not arm plans that are not its own. [Decision]
- Armed alarm keeps the lamp advertising (section 4). While armed and the lamp is otherwise quiet, the status LED is steady and very faint instead of off. [Decision; brightness of that LED is [Pending]]
- Clients that start the sunrise themselves (the Android app does this when Sleep as Android sends ALARM_ALERT_START) disarm the stored plan first so the lamp does not ramp a second time. [Decision, spec section 11]

### 6.5 Timer (1005): read, write. 5 bytes

The reading-light timer: stay on for a set time, then fade out and switch off. The lamp counts with its own monotonic clock and needs no Time sync.

Write:

| Offset | Type | Field |
|---|---|---|
| 0 | u8 | flags: bit0 start. Bit0 = 0 cancels |
| 1 | u16 | duration seconds, clamped to 18000 (5 h); must be at least 1 |
| 3 | u16 | fade seconds, clamped to 600; 0 = switch off without fading |

Read:

| Offset | Type | Field |
|---|---|---|
| 0 | u8 | flags: bit0 running (counting down), bit1 fading |
| 1 | u16 | remaining seconds while counting (0 while fading or idle) |
| 3 | u16 | fade seconds of the current/last timer |

Behaviour [Code]:

- A start is refused (ignored, State re-notified) when the lamp is locked out, the output is off, or the duration is 0. A start replaces any running timer.
- A write with bit0 = 0 cancels the timer and leaves the lamp as it is (during the fade, it stops the fade at the current level and leaves the lamp on).
- The timer ends, without touching the lamp, when the lamp is switched off by any means (phone, encoder, lockout, an alarm's hold), and when an alarm fires. Changing brightness or colour does not end it.
- On expiry with fade > 0 the lamp ramps brightness to 0 on the smooth curve over the fade time, then switches off and restores the previous stored brightness for the next switch-on. Touching the lamp during the fade ends the fade and the timer at the level just set.
- State bit4 is set from start until the timer ends (counting and fading). Use it to detect the end.
- The lamp checks every 500 ms. The characteristic value is refreshed at start, at the end of counting and about every 5 seconds while counting, so a read can be up to 5 s stale. Show a countdown by extrapolating from the read value and the time you read it. [Code; the extrapolation is my suggestion]
- The `fade` field is not cleared when the timer ends, so an idle read can show the last timer's fade time. Use `running` and State bit4, not `fade`, to decide whether a timer is active. [Code]
- There is no notification on this characteristic.

## 7. Sensor service (2000)

### 7.1 Live (2001): read, notify. 18 bytes

Sample layout (the same 18 bytes are used in history records):

| Offset | Type | Field | Unit | Unknown |
|---|---|---|---|---|
| 0 | u32 | lamp uptime | seconds | n/a |
| 4 | i16 | BME280 temperature | 0.01 °C | 0x8000 |
| 6 | u16 | BME280 humidity | 0.01 %RH | 0xFFFF |
| 8 | i16 | lamp temperature (DS18B20) | 0.01 °C | 0x8000 |
| 10 | u16 | input voltage | mV | 0xFFFF |
| 12 | i16 | input current | mA | 0x8000 |
| 14 | u16 | 5 V rail voltage | mV | 0xFFFF |
| 16 | i16 | 5 V rail current | mA | 0x8000 |

Behaviour [Code]:

- The value is refreshed once per second, so a read is at most about 1 s old.
- A notification is sent when the Config heartbeat interval has passed since the last notification, or when any field has moved by more than a deadband since the last *sent* sample. The deadband is the larger of the configured percentage of the last sent value and a floor: 0.5 °C, 2 %RH, 100 mV, 20 mA. A sensor appearing or disappearing always triggers a notification. The first sample after boot is always sent. Percentage 0 turns deadband triggers off (heartbeat only).
- The notification check runs once a second, so the maximum notification rate is 1 per second.
- Input power and rail power are not sent. The app multiplies voltage by current. [Code: no power field]

### 7.2 History control (2002): write. 5 bytes

| Offset | Type | Field |
|---|---|---|
| 0 | u8 | command: 1 replay. (2 stops a running transfer. See below.) |
| 1 | u32 | send records with uptime greater than this value (0 = everything) |

Behaviour [Code]:

- The lamp stores one sample every `history interval` (Config, default 60 s) in a RAM ring of 1440 records (24 hours at the default). A record is stored only if at least one sensor has a reading. History is lost on reboot.
- Any write to this characteristic first stops a running transfer. Command 1 then starts a new one. Command 2 is accepted silently (it only stops a transfer); it is not a named constant in the code, so treat it as [Guess] on whether it is meant to stay.
- A replay streams matching records oldest first as History data notifications, paced about 20 ms apart, then one end packet.
- If the ring changes during a transfer on a full ring, a record may be skipped or repeated. [Code comment]

### 7.3 History data (2003): notify. 20 or 8 bytes

Record packet, 20 bytes:

| Offset | Type | Field |
|---|---|---|
| 0 | u8 | kind = 0x01 |
| 1 | u8 | sequence, starts at 0 for each transfer, wraps at 256 |
| 2 | 18 bytes | one Live-format sample (section 7.1) |

End packet, 8 bytes:

| Offset | Type | Field |
|---|---|---|
| 0 | u8 | kind = 0xFF |
| 1 | u8 | sequence (the next one that would have been used) |
| 2 | u16 | number of records sent (capped at 65535) |
| 4 | u32 | uptime of the newest record sent (equals the request's `since` value if none were sent) |

A client must subscribe before it writes the replay command. Distinguish packet kinds by byte 0 (and size). [Code]

### 7.4 Turning uptime into real time

The lamp stamps samples with uptime, not wall time. [Code] To place a record on a real timeline, take the newest Live sample (uptime U, received at phone time T) and compute `T − (U − record uptime)`. This is my derivation, not code in the firmware [Derived]. Record uptimes are only comparable within one boot: store the Info `boot id` with your data, and when it changes treat all older uptimes as a different timeline.

## 8. System service (3000)

### 8.1 Status (3001): read, notify. 6 bytes. No encryption needed

| Offset | Type | Field |
|---|---|---|
| 0 | u8 | status code (table below) |
| 1 | u8 | flags: bit0 12 V OK, bit1 time synced, bit2 locked out, bit3 time stale |
| 2 | u16 | negotiated USB-PD contract, mV (`0xFFFF` = none) |
| 4 | u16 | negotiated USB-PD contract, mA (`0xFFFF` = none) |

Status codes [Code]:

| Code | Name | Meaning | Lockout |
|---|---|---|---|
| 0 | OK | normal | no |
| 1 | HUSB238 missing | USB-PD chip not found | yes |
| 2 | Legacy 5 V | only 5 V offered | yes |
| 3 | No 12 V | 12 V not offered | yes |
| 4 | No cable | no cable or source | yes |
| 5 | Request failed | the 12 V request failed | yes |
| 6 | Contract mismatch | contract differs from request | yes |
| 7 | Contract not set | PD check not finished (the initial state) | yes |
| 8 | INA3221 missing | power monitor missing | no |
| 9 | BME280 missing | environment sensor missing | no |
| 10 | DS18B20 failed | lamp temperature sensor failed | no |

(Names are from the constants; the "meaning" column is my reading of those names [Guess].)

- Lockout is codes 1 to 7. While locked out, the lamp stays dark and ignores State, Ramp, Cue, Alarm arming and Timer start writes (accepted but no effect, State re-notified). Flags bit2 is set and bit0 is clear. [Code]
- Flags: bit1 is set once any Time write has been applied since boot. Bit3 (time stale) is set when more than the Config `stale hours` have passed since the last Time write; it is never set before the first sync. [Code]
- The lamp starts in code 7 (locked out) until its power check finishes, so the first Status read after boot can show a lockout that clears within seconds. [Code]
- Status is notified whenever the 6 bytes change. The time flags are re-evaluated once a second.

### 8.2 Time (3002): read, write. 8 bytes

| Offset | Type | Field |
|---|---|---|
| 0 | u32 | Unix seconds, UTC |
| 4 | u16 | milliseconds, 0..999 (larger values are clamped to 999) |
| 6 | i16 | phone's UTC offset in minutes (east positive) |

- Write: sets the lamp's real-time clock. The first write after boot marks the clock synced; later writes re-sync it. The lamp has no battery clock, so every reboot needs a new write. [Code]
- Read: returns the lamp's current time in the same layout, with unix = 0 and ms = 0 if never synced (the offset is still returned, 0 before any sync). [Code]
- The offset is stored for display and is also visible in the device report. The lamp does not use it to schedule anything: Alarm start times are absolute UTC seconds. [Code]
- Accuracy: the app compares a Time read with the phone clock and shows "Clock offset". BLE latency is not compensated. Expect errors of the order of tens to a few hundred ms [Guess].

### 8.3 Config (3006): read, write. 7 bytes

| Offset | Type | Field | Range | Default |
|---|---|---|---|---|
| 0 | u16 | Live heartbeat, seconds | 10..3600 | 30 |
| 2 | u8 | Live change threshold, percent | 0..100 | 5 |
| 3 | u16 | history interval, seconds | 10..3600, rounded down to a multiple of 10 | 60 |
| 5 | u8 | stale hours (time flag) | 1..255 | 24 |
| 6 | u8 | log level | 0..3 | 1 |

- Out-of-range values are clamped, not rejected. Read back to see what the lamp applied. [Code]
- Held in RAM only: defaults return after every reboot, so write Config on every connect.
- Log level: 0 debug, 1 info, 2 warn, 3 error. It sets the minimum level the lamp *buffers* (and so what Log data can deliver). The console output is unaffected. [Code]

### 8.4 Info (3003): read. 14 bytes. No encryption needed

| Offset | Type | Field |
|---|---|---|
| 0 | u8 | protocol version (1) |
| 1 | u8 | live layout version (1) |
| 2 | u8 | firmware major |
| 3 | u8 | firmware minor |
| 4 | u8 | firmware patch |
| 5 | u8 | capability bits |
| 6 | u32 | boot id (random per boot, 31-bit) |
| 10 | u16 | CCT minimum, Kelvin |
| 12 | u16 | CCT maximum, Kelvin |

Capability bits [Code]: 0x01 history, 0x02 cue, 0x04 ramp, 0x08 log, 0x10 config, 0x20 device report, 0x40 alarm, 0x80 timer. Firmware 0.2.0 sets all eight. A client should check the bit before using a feature, so that older lamp firmware without a feature still works.

### 8.5 Log: Log control (3004, write) and Log data (3005, notify)

Log control write, 3 bytes:

| Offset | Type | Field |
|---|---|---|
| 0 | u8 | command: 1 replay, 2 device report |
| 1 | u16 | argument: for replay, the last line sequence you already have (0 = everything buffered); unused for the device report |

Log data notification, 3 to 20 bytes:

| Offset | Type | Field |
|---|---|---|
| 0 | u16 | line sequence number |
| 2 | u8 | bit7 = last chunk of this line; bits 0..6 = chunk index (0, 1, 2...) |
| 3 | up to 17 bytes | UTF-8 text chunk |

Behaviour [Code]:

- The lamp keeps the newest 64 lines in RAM. Sequence numbers are 16-bit, start at 1, wrap 0xFFFF to 1. Zero means "all" in a replay.
- A line is sent as chunks in order, chunks of one line never interleave with another line. Reassemble by line sequence: append chunk payloads in index order and decode the whole byte string as UTF-8 only when the last-chunk bit is seen (a chunk boundary can split a multi-byte character).
- Lines longer than 105 bytes are truncated by the lamp.
- Live lines are pushed only while a client is subscribed to Log data. A replay can overlap with live lines, so the same line sequence can arrive twice: drop duplicates by sequence. Packets are paced about 15 ms apart.
- Replay lines newer than `arg` use wrap-aware comparison (a sequence within half the 16-bit range ahead counts as newer).
- Line format: `<L> <logger name>: <message> {key: value, key: value}`, where `<L>` is one of T D I W E F. The logger-name part is omitted when empty and the brace part is omitted when there are no keys. Example shape: `I: Alarm armed {start-in-s: 3600, ramp-s: 900, target: 600, hold-s: 600, token: 1}`. [Code for the format; the example is illustrative, not captured from a lamp]
- Device report (command 2): the lamp writes five info-level lines named `device-toit`, `device-chip`, `device-time`, `device-net`, `device-mem` with key/value tags (Toit SDK versions and model, fw, architecture, MAC, last reset reason, time sync state and offset, IP address or `none`, free memory, history and log sizes, uptime). They arrive through Log data like any other line, so they are lost if the Config log level is 2 or 3 and the lamp's buffer is not receiving info lines. [Code]

## 9. Timing and rates summary

| Item | Value |
|---|---|
| State notify | on change, at most 1 per 200 ms |
| Status notify | on change (coalesced, at most 1 per 50 ms) |
| Live refresh / notify check | 1 s |
| Live heartbeat | Config, default 30 s |
| Ramp/cue update | every 200 ms |
| Alarm check | 1 s; plan dropped if more than 60 s late |
| Timer check | 500 ms; value refreshed about every 5 s |
| History record | Config, default 60 s; 1440 records |
| Log buffer | 64 lines; chunk payload 17 bytes; line max 105 bytes |
| Advertising window | 5 minutes after boot or after a 10 s button hold |

## 10. Limits and gaps a compatible client should expect

- The lamp keeps no wall clock across reboots, and no alarm, timer or Config either. A compatible app reconciles on every connect (section 5).
- A Time write is needed before Alarm arming works. Clock is only as good as the BLE round trip.
- One alarm plan only. One reading timer only.
- No connect or disconnect events on the lamp side. A phone that wants the lamp to stop advertising must subscribe to Status.
- Malformed writes are dropped silently (section 1).
- No application-level authentication (section 4).
- Over-temperature protection, History download UI in the app, and the device authorisation scheme are not done. [Pending]
- The following have not been confirmed on hardware in this session: [Pending]
  - behaviour at the end of a flash cue and nightlight restore;
  - whether CCCD writes alone trigger pairing;
  - reconnect after the lamp reboots;
  - the exact error a client gets from a malformed write.

## 11. Where to look in the source

| Topic | File |
|---|---|
| Layouts, constants, encode/decode | `src/lamp-protocol.toit` |
| Characteristics, advertising, write handlers | `src/lamp-ble.toit` |
| On/off, ramp, cue, lockout | `src/lamp-state.toit` |
| Alarm | `src/lamp-alarm.toit` |
| Timer | `src/lamp-timer.toit` |
| Live gate, history ring, clock, status | `src/lamp-telemetry.toit` |
| Log buffer and line format | `src/lamp-log.toit` |
| Device report | `src/lamp-device.toit` |
| Android client for all of the above | `android/app/src/main/java/com/milkmansson/okklamp/LampProtocol.kt`, `LampClient.kt` |
| Design history, Sleep as Android intents | `docs/ble-gatt-spec.md` |
