<p align="center">
  <img src="xauwatch_poster.png" width="500">
</p>

<h1 align="center">XAUWATCH – Live Gold Monitor</h1>

<p align="center">
A Bash tool that displays the live price of gold (XAU/USD) directly in your terminal.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Arch%20Linux-supported-1793D1?style=for-the-badge&logo=arch-linux">
  <img src="https://img.shields.io/badge/Bash-Script-green?style=for-the-badge&logo=gnu-bash">
  <img src="https://img.shields.io/github/v/release/KlodCripta/xauwatch?style=for-the-badge">
</p>

---

XAUWATCH is a lightweight terminal-based monitor for the XAU/USD pair.

It provides real-time bid and ask prices, spread, and gold value conversions in a clean and readable interface.

The tool is designed for quick monitoring, without requiring a browser or external applications.

---

## Screenshot

<p align="center">
  <img src="screenshots/xauwatch_screenshot_1.png" width="500">
</p>

---

## Features

- Live gold price (XAU/USD)
- Bid / Ask and spread
- Price per gram and troy ounce
- Daily variation (external reference)
- Terminal-based interface with structured layout

---

## Installation

### Clone the repository

```bash
git clone https://github.com/KlodCripta/xauwatch.git
cd xauwatch
chmod +x xauwatch.sh
./xauwatch.sh
```

## Usage
```bash
./xauwatch.sh
```
## Requirements

- bash
- curl
- python
- awk

## Notes

Live data is fetched from Swissquote
Daily variation is based on external reference data
This tool is intended for monitoring purposes only

## License

This project is released under the MIT License.
