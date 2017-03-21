# Pi-MobiSec - Secure your computer on unsecure hotspots

Secure your laptop while using public wifi hotspots.  Instead of connecting your laptop directly with public wifi hotspots, you connect your Pi-MobiSec device with it and let it filter and protect the traffic going in and out of your laptop.

Pi-MobiSec turns your Raspberry Pi Zero W (others will be supported in the near future) into a mobile firewall protecting your computer and optionally your traffic while you are using unsecure or public hotspots.

## Features
* Plug and play
* Firewall to protect your laptop from unwanted access
* Use public DNS servers to prevent the hotspot owner from logging your DNS queries (Optional)
* VPN support to prevent others from spying on your connection (Comming soon)
* Easy to use Webinterface (Comming soon)

## Quick Installation

To install Pi-MobiSec you need a RaspberryPi Zero W (the one with build in Wifi).  A current Version of Raspbian, ssh enabled and the PiZero W connected to your WiFi network.

Simply ssh into your PiZero and execute:

```
curl -sSL https://install.pi-mobisec.net | sudo bash
```

## Full Installation

The full installation will help you setup and secure your PiZero, before starting the Pi-MobiSec installation.
