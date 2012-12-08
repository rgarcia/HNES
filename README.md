# Hacker News Enhancement Suite

[Reddit Enhancement Suite](RHES) ported to Hacker News.

## Features

## Installing

```bash
git clone git@github.com:rgarcia/HNES.git
npm install coffee-script coffeelint recess -g
make
# browse to chrome://extensions
# check "Developer Mode"
# click the "Load unpacked extension..." button, point it to the HNES directory
```

## Developing

```bash
npm install -g watchr
make watch
```