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
  0x08:  "HUSB238",
  0x23 : "BH1750",
  0x29 : "VL53L0X",
  0x39 : "APDS9960",
  0x76 : "BMP280/BME280",
  0x3c : "SSD1306",
  0x40 : "INA219- INA226- INA3221-",
  0x5a : "MPR121- CCS811-",
  0x68 : "DS3231- MPU6050- ",
  0x57 : "AT24C32",
  0x36 : "MAX1704x- AS5600- "
}



main:
  // System Information
  print
  print "SYSTEM INFO:"
  print " Device Name:        $(device.name)"
  print " Device Hardware ID: $(device.hardware-id)"

  print " MAC Address:        $(%02x esp32.mac-address[00]):$(%02x esp32.mac-address[01]):$(%02x esp32.mac-address[02]):$(%02x esp32.mac-address[03]):$(%02x esp32.mac-address[04]):$(%02x esp32.mac-address[05])"
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

  print
  process-stats := system.process-stats
  print "PROCESS STATS:"
  print " Stats: 0. New-space (small collection) GC count for the process: $(process-stats[0])"
  print " Stats: 1. Allocated memory on the Toit heap of the process: $(process-stats[1])"
  print " Stats: 2. Reserved memory on the Toit heap of the process: $(process-stats[2])"
  print " Stats: 3. Process message count: $(process-stats[3])"
  print " Stats: 4. Bytes allocated in object heap: $(process-stats[4])"
  print " Stats: 5. Group ID: $(process-stats[5])"
  print " Stats: 6. Process ID: $(process-stats[6])"
  print " Stats: 7. Free memory in the system: $(process-stats[7])"
  print " Stats: 8. Largest free area in the system: $(process-stats[8])"
  print " Stats: 9. Full GC count for the process (including compacting GCs): $(process-stats[9])"
  print " Stats: 10. Full compacting GC count for the process: $(process-stats[10])"
  print


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
  print "I2C INFORMATION:"
  print "  [I2C Established on SDA:$sda-pin-number SCL:$scl-pin-number]"
  print

  // Test without bus scan for known devices:
  print "  Testing for each of $(device-library.size) known I2C addresses:"
  device-library.do:
    if bus.test it:
      print "  - 0x$(%02x it): $(device-library[it])  Device Found"
  print

  // Bus scan to find remainder
  print "  Bus scan for other devices..."
  devices := bus.scan
  print

  print "  Devices detected on bus scan:"
  devices.do:
    if device-library.contains it:
      // Already Attempted Explicitly - skip
      // print "                    - 0x$(%02x it): $(device-library[it])  Device Found"
    else:
      print "  - 0x$(%02x it)"

  print
  print "  Total: $(devices.size) devices."
  print
