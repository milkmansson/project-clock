import system
import device
import gpio
import i2c
import gpio.pwm
import math
import binary

import ntp
import esp32

import ssd1306 show *
import dhtxx show *
import bme280
import ds3231
import cat24c32

import log

// SSD1306 Pixel Display.
import pixel-display show *
import pixel-display.two-color
import pixel-display.true-color               // color helper
import pixel-strip                            // WS2812B driver (package)


// Device Drivers in development.
import ..drivers-released.toit-ina226.src.ina226 as ina226
import ..drivers-released.toit-ina3221.src.ina3221 as ina3221

// Experimental Drivers.
import ..drivers-released.toit-mpr121.src.mpr121 show Mpr121
import ..drivers-released.toit-mpr121.src.mpr121 show Mpr121Events
import ..drivers-released.toit-husb238.src.husb238 show Husb238
import ..drivers-released.toit-eeram.src.eeram show Eeram
import ..drivers-released.toit-eeram.src.eeram show PersistentMap

import ..drivers.toit-pwmledmixer.src.pwmledmixer show PwmLedMixer
import ..drivers.toit-esp32s3rgbled.src.esp32s3rgbled as esp32s3rgbled
import ..drivers.toit-timehelper.src.timehelper as timehelper
import ..drivers.toit-pixel-strip-matrix.src.pixel-strip-matrix show PixelStripMatrix

import .clock-screen as clock-screen

import font show *
import font-x11-adobe.sans-10
import font-x11-adobe.sans-08
import font-x11-adobe.sans-06
import font-x11-adobe.typewriter-08

import font-tiny.tiny
import font-tiny.tiny-bigger-digits




import pixel-strip show *                            // WS2812B driver (package)

// Touch sensor driver and preparation.
TOUCH-INTRPT-PIN ::= 33

// Top I2C channel.
UPPER-SDA-PIN ::= 14
UPPER-SCL-PIN ::= 13
UPPER-BUS-FREQUENCY ::= 400_000

// Lower I2C channel.
LOWER-SDA-PIN ::= 8
LOWER-SCL-PIN ::= 9
LOWER-BUS-FREQUENCY ::= 400_000

// White light channels.
COOL-CHANNEL-PIN  ::= 5
WARM-CHANNEL-PIN  ::= 4
COOL-CHANNEL-TEMP ::= 6000  // 100% Cool White Channel Temp in Kelvin
WARM-CHANNEL-TEMP ::= 3000  // 100% Warm White Channel Temp in Kelvin

// Neopixel channels.
NEOPIXEL-A     ::= 6
NEOPIXEL-B     ::= 7
PIXELS-HEIGHT  ::= 8
PIXELS-WIDTH   ::= 38

// Status pixel.
STATUS-PIXEL-PIN := 38

// Default Timezone.
//TIMEZONE-POSIX-CODE := "GMT0BST,M3.5.0/1,M10.5.0"

// MPR121 INT pin.
MPR121-INTERRUPT-PIN := 18

// Devices: UPPER-BUS
//  - 0x76: BME280
//  - 0x3c: SSD1306
//  - 0x5a: MPR121
//  - 0x68: DS3231
//  - 0x57: AT24C32
//  - 0x38:
//  - 0x53:

// Devices:
//  - 0x40: INA226
//  - 0x41: INA3221
INA3221-I2C-ADDRESS-ALT  ::= 0x41
//  - 0x08: HUSB238

settings-pmap := ?

pd-voltage/bool := false

main:
  print
  print

  // Establish Log.
  logger := log.default.with-name "clock"
  logger.with-level log.DEBUG-LEVEL

  // Upper Bus I2C Setup.
  logger.info "establishing UPPER i2c bus"
  upper-sda-pin := gpio.Pin UPPER-SDA-PIN
  upper-scl-pin := gpio.Pin UPPER-SCL-PIN
  upper-bus := i2c.Bus --sda=upper-sda-pin --scl=upper-scl-pin --frequency=UPPER-BUS-FREQUENCY
  upper-devices := upper-bus.scan

  // Lower Bus I2C Setup.
  logger.info "establishing LOWER i2c bus"
  lower-sda-pin := gpio.Pin LOWER-SDA-PIN
  lower-scl-pin := gpio.Pin LOWER-SCL-PIN
  lower-bus := i2c.Bus --sda=lower-sda-pin --scl=lower-scl-pin --frequency=LOWER-BUS-FREQUENCY
  lower-devices := lower-bus.scan


  // PD trigger device (lower bus).
  husb238-device   := null
  husb238-driver   := null
  if not lower-devices.contains Husb238.I2C-ADDRESS:
    logger.error "HUSB238 [0x$(%02x Husb238.I2C-ADDRESS)] *NOT* present"
  else:
    logger.info "HUSB238 [0x$(%02x Husb238.I2C-ADDRESS)] present"
    husb238-device = lower-bus.device Husb238.I2C-ADDRESS
    husb238-driver = Husb238 husb238-device --logger=logger
    sleep --ms=100

    if not husb238-driver.is-legacy-5v:
      pd-capabilities := husb238-driver.get-capabilities
      pd-max := max-product-entry pd-capabilities
      result := husb238-driver.request-pdo pd-max

      if husb238-driver.is-pd-present:
        logger.info "PDO contract set" --tags={"volts":"$(husb238-driver.read-status-voltage)","amps":"$(husb238-driver.read-status-current)"}
        pd-voltage = true
      else:
        logger.error "PDO contract attempted but not set"

  // Establish eeram device to use for settings.
  eeram-data-device := null
  eeram-controller-device := null
  if not lower-devices.contains Eeram.I2C-CONTROL-ADDRESS:
    logger.error "47L16 Controller [0x$(%02x Eeram.I2C-CONTROL-ADDRESS)] *NOT* present"
  else:
    logger.info "47L16 Controller [0x$(%02x Eeram.I2C-CONTROL-ADDRESS)] present"
    eeram-data-device = lower-bus.device Eeram.I2C-DATA-ADDRESS

  if not lower-devices.contains Eeram.I2C-DATA-ADDRESS:
    logger.error "47L16 SRAM [0x$(%02x Eeram.I2C-DATA-ADDRESS)] *NOT* present"
  else:
    logger.info "47L16 SRAM [0x$(%02x Eeram.I2C-DATA-ADDRESS)] present"
    eeram-controller-device = lower-bus.device Eeram.I2C-CONTROL-ADDRESS

  if eeram-data-device and eeram-controller-device:
    settings-pmap = PersistentMap
        --control=eeram-controller-device
        --data=eeram-data-device
        --capacity=Eeram.CAPACITY-16KBIT
        --logger=logger

  // Establish indicator LED.
  pixel-pin := gpio.Pin STATUS-PIXEL-PIN
  pixel-driver := esp32s3rgbled.Esp32s3RGBLed pixel-pin --logger=logger
  pixel-driver.alight 255 0 0
  pixel-driver.brightness 1.0
  sleep --ms=1000
  //pixel-driver.heartbeat


  // Set screen on first - allow it to show current time.
  ssd1306-device  := null
  ssd1306-driver  := null
  ssd1306-display := null
  screen-helper := null
  if not upper-devices.contains Ssd1306.I2C-ADDRESS:
    logger.error "SSD1306 [0x$(%02x Ssd1306.I2C-ADDRESS)] *NOT* present"
  else:
    logger.info "SSD1306 present [0x$(%02x Ssd1306.I2C-ADDRESS)]"
    ssd1306-device = upper-bus.device Ssd1306.I2C-ADDRESS
    ssd1306-driver = Ssd1306.i2c ssd1306-device
    ssd1306-display = PixelDisplay.two-color ssd1306-driver
    ssd1306-display.background = two-color.BLACK
    ssd1306-display.draw

    // Screen Helper
    screen-helper = clock-screen.ScreenHelper ssd1306-display --logger=logger
    //screen-helper.keep-screen-updated
    sleep --ms=100

  // Environment Sensor device.
  bme280-device                := null
  bme280-driver/bme280.Driver? := null
  if not upper-devices.contains bme280.I2C-ADDRESS:
    logger.error "BME280 [0x$(%02x bme280.I2C-ADDRESS)] *NOT* present"
  else:
    logger.info "BME280 [0x$(%02x bme280.I2C-ADDRESS)] present"
    bme280-device = upper-bus.device bme280.I2C-ADDRESS
    bme280-driver = bme280.Driver bme280-device
    screen-helper.add-device bme280-driver
    sleep --ms=100


  // Power Sensor device (overall).
  ina226-device                := null
  ina226-driver/ina226.Ina226? := null
  if not lower-devices.contains ina226.Ina226.I2C-ADDRESS:
    logger.error "INA226 [0x$(%02x ina226.Ina226.I2C-ADDRESS)] *NOT* present"
  else:
    logger.info "INA226 [0x$(%02x ina226.Ina226.I2C-ADDRESS)] present"
    ina226-device = lower-bus.device ina226.Ina226.I2C-ADDRESS
    ina226-driver = ina226.Ina226 ina226-device --logger=logger --shunt-resistor=0.010
    ina226-driver.set-sampling-rate 0x0002
    screen-helper.add-device ina226-driver
    sleep --ms=100

  // Power Sensor device (per bus).
  ina3221-device                  := null
  ina3221-driver/ina3221.Ina3221? := null
  if not lower-devices.contains ina3221.Ina3221.I2C-ADDRESS:
    logger.error "INA3221 [0x$(%02x INA3221-I2C-ADDRESS-ALT)] *NOT* present"
  else:
    logger.info "INA3221 [0x$(%02x INA3221-I2C-ADDRESS-ALT)] present"
    ina3221-device = lower-bus.device INA3221-I2C-ADDRESS-ALT
    ina3221-driver = ina3221.Ina3221 ina3221-device --logger=logger
    ina3221-driver.set-sampling-rate 0x0002
    ina3221-driver.set-shunt-resistor 0.010 --channel=1
    screen-helper.add-device ina3221-driver
    sleep --ms=100

  // Touch Sensor device (using MPR121 device if present)
  mpr121-device               := null
  mpr121-driver/Mpr121?       := null
  mpr121-events/Mpr121Events? := null
  if not upper-devices.contains Mpr121.I2C-ADDRESS-5a:
    logger.error "MPR121 [0x$(%02x Mpr121.I2C-ADDRESS-5a)] *NOT* present"
  else:
    logger.info "MPR121 [0x$(%02x Mpr121.I2C-ADDRESS-5a)] present"
    mpr121-device  = upper-bus.device Mpr121.I2C-ADDRESS-5a
    mpr121-driver  = Mpr121 mpr121-device --logger=logger

    //mpr121-driver.debug-touched

    mpr121-events = Mpr121Events mpr121-driver
        --intrpt-pin=(gpio.Pin MPR121-INTERRUPT-PIN)

    sleep --ms=100

  // Initalise RTC (use DS3231 Device if present)
  ds3231-device                := null
  ds3231-driver/ds3231.Ds3231? := null
  if not upper-devices.contains ds3231.Ds3231.I2C-ADDRESS:
    logger.error "DS3231 [0x$(%02x ds3231.Ds3231.I2C-ADDRESS)] *NOT* present"
  else:
    logger.info "DS3231 [0x$(%02x ds3231.Ds3231.I2C-ADDRESS)] present"
    ds3231-device = upper-bus.device ds3231.Ds3231.I2C-ADDRESS
    ds3231-driver = ds3231.Ds3231 ds3231-device
    time-helper  := timehelper.TimeHelper --device=ds3231-driver --logger=logger
    time-helper.maintain-system-time-via-ntp
    screen-helper.add-device time-helper
    sleep --ms=100

  // Timezone feature (use CAT24c32 if built in to DS3231)
  cat24c32-device                            := null
  cat24c32-driver/cat24c32.Cat24c32?         := null
  timezone-helper/timehelper.TimezoneHelper? := null
  if not upper-devices.contains timehelper.DEFAULT-DS3231-AT24C32-I2C-ADDRESS:
    logger.error "AT24C32 [0x$(%02x timehelper.DEFAULT-DS3231-AT24C32-I2C-ADDRESS)] *NOT* present"
    timezone-helper = timehelper.TimezoneHelper --logger=logger
    screen-helper.add-device timezone-helper
  else:
    logger.info "AT24C32 [0x$(%02x timehelper.DEFAULT-DS3231-AT24C32-I2C-ADDRESS)] present"
    cat24c32-device = upper-bus.device timehelper.DEFAULT-DS3231-AT24C32-I2C-ADDRESS
    cat24c32-driver = cat24c32.Cat24c32 cat24c32-device
    timezone-helper = timehelper.TimezoneHelper cat24c32-driver --logger=logger
    timezone-helper.auto-config
    timezone-helper.update-data-from-internet
    screen-helper.add-device timezone-helper
    sleep --ms=100

  // PD trigger device (lower bus).
  if husb238-driver:
    screen-helper.add-device husb238-driver

  // Establish White LEDs.
  warm-white-pin := gpio.Pin WARM-CHANNEL-PIN --output
  cool-white-pin := gpio.Pin COOL-CHANNEL-PIN --output

  cct-strip := PwmLedMixer --logger=logger
      --warm-pin=warm-white-pin
      --warm-temp=WARM-CHANNEL-TEMP
      --cool-pin=cool-white-pin
      --cool-temp=COOL-CHANNEL-TEMP
  //cct-strip.temperature --kelvin=6000
  //cct-strip.set-brightness 1.0
  // configure-strip --kelvin=7000 --brightness=0.5 --warm-channel=warm-channel --cool-channel=cool-channel --gain-warm=1.15


  gpio-pin           := gpio.Pin NEOPIXEL-B
  total-pixels       := 300 // PIXELS-HEIGHT * PIXELS-WIDTH
  pixel-strip        := PixelStrip.uart total-pixels --pin=gpio-pin

  //pixel-strip-matrix := PixelStripMatrix --pin=gpio-pin --height=PIXELS-HEIGHT --width=PIXELS-WIDTH
  //pixel-display-col  := PixelDisplay.true-color pixel-strip-matrix
  //pixel-display-col.background = true-color.BLACK
  //pixel-display-col.draw


  if mpr121-events:
    mpr121-events.on-press Mpr121Events.CHANNEL-01 --callback=(:: toggle-brightness cct-strip)
    if screen-helper:
      mpr121-events.on-press Mpr121Events.CHANNEL-11 --callback=(:: screen-helper.next-screen)
      mpr121-events.on-press Mpr121Events.CHANNEL-10 --callback=(:: cct-strip.swipe --cycle-ms=10_000)
      //mpr121-events.on-press Mpr121Events.CHANNEL-10 --callback=(:: led-time-on pixel-display-col)
      //mpr121-events.on-release Mpr121Events.CHANNEL-01  --callback=(:: toggle-brightness cct-strip)


      mpr121-events.on-press Mpr121Events.CHANNEL-02 --callback=(:: leds-on pixel-strip total-pixels)
      mpr121-events.on-press Mpr121Events.CHANNEL-03 --callback=(:: leds-off pixel-strip total-pixels)




  //gpio-pin.close



  // Keep the program alive.
  while true: sleep --ms=1000

toggle-brightness strip/PwmLedMixer -> none:
  if strip.animations-running:
    strip.stop-all
  if strip.get-brightness != 1:
    strip.set-brightness 1.0
  else:
    strip.set-brightness 0.0

max-product-entry data/Map -> any:
  best-key := null
  best-product := null
  best-value := null

  data.keys.do: | key |
    product := key * data[key]
    if best-product == null or product > best-product:
      best-product = product
      best-key = key
      best-value = data[key]

  return best-key


leds-on strip/PixelStrip total-pixels/int -> none:
  print "leds-on"
  r := ByteArray total-pixels
  g := ByteArray total-pixels
  b := ByteArray total-pixels

  // TEST: Paint some pixels with #4480ff, To verify correctly operating

  //for i := 0; i < total-pixels; i += 1:
  total-pixels.repeat: | pixel |
    r[pixel] = 0x44
    g[pixel] = 0x80
    b[pixel] = 0xff


  strip.output r g b

leds-off strip/PixelStrip total-pixels/int -> none:
  print "leds-off"
  r := ByteArray total-pixels
  g := ByteArray total-pixels
  b := ByteArray total-pixels

  r.fill 0x00
  g.fill 0x00
  b.fill 0x00

  strip.output r g b

led-time-on pixel-display -> none:
  TYPEWRITER-08 ::= Font [typewriter-08.ASCII, typewriter-08.LATIN-1-SUPPLEMENT]

  sans := TYPEWRITER-08
  [
    pixel-display.Label --x=0 --y=08 --id="time",
  ].do: pixel-display.add it

  STYLE ::= pixel-display.Style
      --type-map={
          "label": pixel-display.Style --font=sans --color=pixel-display.WHITE,
      }
  pixel-display.set-styles [STYLE]

  //date/Label := pixel-display.get-element-by-id "date"
  time := pixel-display.get-element-by-id "time"

  //while true:
  time.text     = "$(%02d Time.now.local.h):$(%02d Time.now.local.m):$(%02d Time.now.local.s)"
    //date.text     = "$(Time.now.local.year)-$(%02d Time.now.local.month)-$(%02d Time.now.local.day)  -"

  pixel-display.draw
  //  sleep --ms=30000
