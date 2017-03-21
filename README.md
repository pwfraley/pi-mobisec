# Pi-MobiSec - Secure your computer on unsecure networks

Secure your computer while using public wifi hotspots or other unsecure networks.  Instead of connecting your computer directly with public wifi hotspots, you connect your Pi-MobiSec device with it and let it filter and protect the traffic going in and out of your computer.

Pi-MobiSec turns your Raspberry Pi Zero W (others will be supported in the near future) into a mobile firewall protecting your computer and optionally your traffic while you are using unsecure or public hotspots.

## Features
* Plug and play
* Firewall to protect your computer from unwanted access
* Hide your connection from ip scanners
* Prevent fingerprinting the operating system on your computer
* Use public DNS servers to prevent the hotspot owner from logging your DNS queries (Optional)
* VPN support to prevent others from spying on your connection (Comming soon)
* Easy to use Webinterface (Comming soon)

## Quick Installation

To install Pi-MobiSec you need a RaspberryPi Zero W (the one with build in Wifi).  A current Version of Raspbian, ssh enabled and the PiZero W connected to your WiFi network.

Simply ssh into your PiZero and execute:

```bash
curl -sSL https://raw.githubusercontent.com/pwfraley/pi-mobisec/master/install/install.sh | sudo bash
# Comming soon:
# curl -sSL https://install.pi-mobisec.net | sudo bash
```

## Full Installation

For full installation instructions, inlcuding securing your PiZero W, please visit the [Wiki](https://github.com/pwfraley/pi-mobisec/wiki).
