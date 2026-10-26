# Download fixture

`download-sample.mp4` is a generated 2-second H.264 test pattern (160×90,
12 fps). It contains no external media. The HTTP integration tests compare
the downloaded file byte for byte with this source.

Regenerate with FFmpeg:

```sh
ffmpeg -f lavfi -i testsrc=size=160x90:rate=12 -t 2 -c:v libx264 -pix_fmt yuv420p -movflags +faststart -y test/fixtures/download-sample.mp4
ffmpeg -i test/fixtures/download-sample.mp4 -frames:v 1 -y test/fixtures/thumbnail-frame.jpg
```
