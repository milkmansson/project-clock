# Project: Clock
A bedside clock project, featuring CCT LED strip to assist with waking, and
other features.

## Mission
Create a bedside lamp that could have a white light at the right temperatures
(cool/warm) to assist with waking and sleeping.

### Features (Side Missions)
- Implement [INA226](https://github.com/milkmansson/toit-ina226) and
  [INA3221](https://github.com/milkmansson/toit-ina3221) to measure current and
  throughput and determine if things are going well.
- Implement [HUSB238](https://github.com/milkmansson/toit-husb238) - USB-C PD
  trigger to try and get the best wattage out of the available power supplies.
  In addition - prevent the light from working if/when insufficient power is
  available.
- Implement [47l16](https://github.com/milkmansson/toit-eeram) flash-backed
  EERAM chip to save information and other settings, and be persistent across
  reboots without causing wear on ESP32 onboard flash.
