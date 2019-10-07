# FFMPEG WebM libvpx (vp8) Bash Script
## IMPORTANT
#### Change the threads variable to how many cores your CPU has.
#### Time stamps only work for minutes and seconds, not hours and so on.

## What it does & How it works
The script will try to encode a webm via libvpx (and libvorbis if audio enabled) with the best possible quality given a file size limit in MiB and will degrade and even provide a cut version if the output still does not fit the given file size limit. It will use the slowest and most CPU demanding options.

#### Order of operations
* The script first tries to encode at the same resolution with qmax 30 (-q:a 3 if audio enabled)
* The script will start to downscale and change qmax values (and degrade audio to use an average bitrate of 32 kbps)
  * Resolution 480; qmax 30, 40
  * Resolution 360; qmax 40
  * Resolution 240; qmax 40
* Disable qmax and retry all downscales
* Make a cut version that is limited by the given file size limit

## How to use
libvpx.sh [-ss 1] [-to 2 | -t 2] [-scale 720] [-samesubs | -subs file] [-title title] [-audio] [-altref] [-brchange] input_file output_file filelimit_in_MiB

*-ss and -t/-to should be in the same order*

### Optional
* -ss is the time stamp or seconds of where to start a trim
* -t is the duration of the trim
* -to is the timestamp of the end of the trim
* -audio enables the audio stream with mono audio channels
* -scale is what vertical/height resolution you want to encode in
* -samesubs uses the same input for hardcoding subtitles
* -subs uses a given file as input for hardcoding subtitles
* -title gives a metadata title manually, normally the encoded file will take the same metadata tile or give it one from the input_file's filename
* -altref enables auto-alt-ref with "-auto-alt-ref 1 -lag-in-frames 25". It is supposed to improve quality but there are noticeable bugs like stutters when a scene is being panned horizontally.
* -brchange changes the target bitrate if the encoding is within 5% of the target filesize, use this if you prefer resolution over quality

## Configuration

You can change what resolutions and qmax values you want by editing `qmaxMap` for the qmax values for each resolution and calling/changing the arguments for `downscaleLoop`. They are after the `# +++++++++ MAIN CODE +++++++++` section.
