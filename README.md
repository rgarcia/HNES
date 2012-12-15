# Hacker News Enhancement Suite

[Reddit Enhancement Suite](https://github.com/honestbleeps/Reddit-Enhancement-Suite/) ported to Hacker News.

## Features

* j/k to browse
* enter to collapse a comment or follow a submission link
* c to go to the comments on a submission
* a/z upvote/downvote comment or submission
* f flag
* u follow user link on comment or submission

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
