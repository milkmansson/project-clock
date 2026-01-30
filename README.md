# Project: Clock
A bedside clock project, featuring CCT LED strip to assist with waking, and
other features.

## Mission
Create a bedside lamp that could have a white light at the right temperatures
(cool/warm) to assist with waking and sleeping.
- Allow on/off/light temperature control
- Implement a sleep function
- Use a sensor to determine if someone is there.. disable/mute alarms if nobody
  is nearby.
- Using a strip of NEOPIXEL LED's, implement a basic dot-matrix style display
  such that basic information like time can be shown on the lampshade.
**Extra Ideas**
- Get time information from Internet/GPS.

### Features (aka. Side Missions)
- Implement an event handler to take alarm clock events from a phone alarm clock
  application. [Sleep-as-android](https://github.com/milkmansson/toit-sleep-as-android)
  MQTT event library.  Implement any smart alerts/features/capabilities from the
  app such as gradual fade up of lights, actions for snoring detection, etc.
- Use [NTP](https://github.com/toitlang/pkg-ntp) to get Time from the internet.
- Use calls to the internet to determine location information (GeoIP lookup).
  Use this information to determine outside weather/temperature information for
  display to the user. (Using
  [encoding.json](https://libs.toit.io/encoding/json/library-summary),
  [net](https://libs.toit.io/net/library-summary),
  [http](https://github.com/toitlang/pkg-http) and
  [certificate-roots](https://github.com/toitware/toit-cert-roots) libraries.)
- Implement [INA226](https://github.com/milkmansson/toit-ina226) and
  [INA3221](https://github.com/milkmansson/toit-ina3221) to measure current and
  throughput to determine if operating within design tolerances.
- Implement [HUSB238](https://github.com/milkmansson/toit-husb238) - USB-C PD
  trigger to try and get the best wattage out of the available power supplies.
  Use information from the device to take action to prevent LED power draw
  from browning out the whole system if/when insufficient power is available.
- Implement [47L16](https://github.com/milkmansson/toit-eeram) flash-backed
  EERAM chip to save information and other settings, to be persistent across
  reboots without causing wear on ESP32 onboard flash.
- Implement two [PWM](https://docs.toit.io/tutorials/hardware/pwm-led) drivers
  to control the CCT strip.  Implement a [library] to perform basic control of
  white balance, and include gamma correction.
- Implement a touch sensor [MPR121](https://github.com/milkmansson/toit-mpr121)
  to use as buttons to control the device.  Implement the proximity sensor
  feature to help as a snooze button to ensure the user is not annoyed by
  hitting the wrong sensor when an alarm happens.
- Using a pin interrupt, implement an event handler for the
  [MPR121](https://github.com/milkmansson/toit-mpr121) to assign code for execution
  when assigned touch channels are triggered.
- Using an [SSD1306](https://github.com/toitware/toit-ssd1306) to display
  information, implement a [display manager](./src/toit-clock-screen.toit) which
  switches between pages on the display.
- Use a [BME280](https://github.com/toitware/bme280-driver) to get basic
  environmental information for display to the user.  Potentially do some logging
  to the internet for assistance in assessing the sleep environment.
- Use a [DS3231](https://github.com/pkarsy/toit-ds3231) to keep time after power
  off events.  Use the [cat24c32](https://github.com/toitware/toit-cat24c32)
  driver to store information (such as the timezone) on the small flash module
  common to many DS3231 modules.
- Implement [ENS160](https://github.com/milkmansson/toit-ens16x) and [AHT21] to
  use as environment monitor/sensor.
- Use a GPS get time also.  Potentially use this information to help with
  determining location for better weather information.  (Several projects
  related to this, including this Toit [NMEA Message Parser](https://github.com/milkmansson/toit-nmea-message)
  and/or Toit's [uBlox GNSS driver](https://github.com/toitware/ublox-gnss-driver))


- **(Optional)** Implement an [MQ2] sensor/smoke detector.  Fires aren't
  expected but for the size of the sensor, and the existence of alarm
  capability, why wouldn't we?
