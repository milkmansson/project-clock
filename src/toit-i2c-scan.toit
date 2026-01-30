import system
import system.firmware
import system.base.network
import system.containers
import device
import gpio
import i2c
import esp32
import encoding.ubjson

ESP32-SDA-PIN := 26
ESP32-SCL-PIN := 25
ESP32C6-SDA-PIN := 19
ESP32C6-SCL-PIN := 20
ESP32S3-SDA-PIN := 8
ESP32S3-SCL-PIN := 9
//ESP32S3-SDA-PIN := 14
//ESP32S3-SCL-PIN := 13

device-library/Map     := {
  0x08: "HUSB238",
  0x0C: "AK09916",
  0x18: "47L16 (Control)",
  0x23: "BH1750",
  0x29: "VL53L0X",
  0x39: "APDS9960",
  0x76: "BMP280/BME280",
  0x3c: "SSD1306",
  0x40: "INA219- INA226- INA3221-",
  0x50: "47L16 (Data)",
  0x53: "ENS160",
  0x5a: "MPR121- CCS811-",
  0x68: "DS3231- MPU6050- ",
  0x69: "ICM20948",
  0x57: "AT24C32",
  0x36: "MAX1704x- AS5600- "
}

mac-address-string separator/int=':' -> string:
  out-list/List := []
  esp32.mac-address.do: | byte |
    out-list.add "$(%02x byte)"
  return out-list.join (string.from-rune separator)

main:
  // System Information
  print
  print "SYSTEM INFO:"
  print " Device Name:        $(device.name)"
  print " Device Hardware ID: $(device.hardware-id)"

  print " MAC Address:        $mac-address-string"
  print " Network Hostname:   $(system.hostname)"
  print " Chip Platform:      $(system.platform)"
  print " Chip Architecture:  $(system.architecture)"
  print " SDK Version:        $(system.app-sdk-version)"
  print " Program Name:       $(system.program-path)  $(system.program-name)"
  print " Firmware:           $(firmware.uri)"

  firmware-decoded := ubjson.decode firmware.config.ubjson
  print " Firmware Config:    $(firmware-decoded)"

  containers := containers.images
  print " Containers:    ($(containers.size))"
  containers.do:
    print " - Image name:    $(it.name)"

  sda-pin-number := ESP32-SDA-PIN
  scl-pin-number := ESP32-SCL-PIN
  // Rudimentary Chip/Pin Selection
  if system.architecture == "esp32c6":
    sda-pin-number = ESP32C6-SDA-PIN
    scl-pin-number = ESP32C6-SCL-PIN
  else if system.architecture == "esp32s3":
    sda-pin-number = ESP32S3-SDA-PIN
    scl-pin-number = ESP32S3-SCL-PIN

  // I2C Information
  sda := gpio.Pin sda-pin-number
  scl := gpio.Pin scl-pin-number

  // Connect and Query
  frequency := 100_000
  bus := i2c.Bus --sda=sda --scl=scl --frequency=frequency
  print
  print "I2C INFO:"
  print "  [I2C Established on SDA:$sda-pin-number SCL:$scl-pin-number]"
  print

  // Test without bus scan for known devices:
  print "  Testing for each of $(device-library.size) known I2C addresses:"
  count := 0
  device-library.do:
    if bus.test it:
      print "  - 0x$(%02x it): $(device-library[it])"
      count++
  print

  // Bus scan to find remainder
  devices := bus.scan

  if count < devices.size:
    print "  Other devices detected on bus scan:"
    devices.do:
      if not (device-library.contains it):
        print "  - 0x$(%02x it)"
    print

  print "  Total: $(devices.size) devices."
  print
