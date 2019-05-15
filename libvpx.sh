#    Copyright (C) 2019  davidj361 <david.j.361@gmail.com>
#    
#    This program is free software: you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation, either version 3 of the License, or
#    (at your option) any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program.  If not, see <https://www.gnu.org/licenses/>.

#!/bin/bash
#set -x # for debugging
scriptname=$(basename "$0")
if (($# == 0)); then
	echo "$scriptname"' [-ss 1] [-to 2 | -t 2] [-scale 720] [-samesubs | -subs file] [-title title] [-audio] [-altref] [-brchange] input_file output_file filelimit_in_MiB'
	echo "-ss and -t/-to should be in the same order"
	exit 1
fi

threads=8
samesubs=""
audio=""
trimArr=("" "") # 0 = -ss, 1 = -t/-to
duration=""
start=""
filter=("" "") # 0 = scale, 1 = subs
title=""
brchange=""
altref=""
while :; do
	case "$1" in
		-scale)
			scaleratio="$2"
			filters[0]=scale=-1:"$scale"
			#scale="-vf scale=-1:$scaleratio"
			shift
			;;
		-subs)
			filters[1]+=subtitles="$2"
			shift
			;;
		-samesubs)
			samesubs=true
			;;
		-audio)
			audio=true
			;;
		-brchange)
			brchange=true
			;;
		-altref)
			altref=true
			;;
		-ss)
			trimArr[0]="-ss $2"
			if [[ "$2" =~ : ]]; then
				minutes=$(echo "$2" | awk -F: '{print $1}')
				seconds=$(echo "$2" | awk -F: '{print $2}')
				start=$(awk -v minutes=$minutes -v seconds=$seconds 'BEGIN { print (minutes * 60) + seconds }')
			else
				start="$2"
			fi
			shift
			;;
		-t)
			# is it timestamped with ':'?
			if [[ "$2" =~ : ]]; then
				minutes=$(echo "$2" | awk -F: '{print $1}')
				seconds=$(echo "$2" | awk -F: '{print $2}')
				duration=$(awk -v minutes=$minutes -v seconds=$seconds 'BEGIN { print (minutes * 60) + seconds }')
			else
				duration=$2
			fi
			trimArr[1]="-t $2"
			shift
			;;
		-to)
			# is it timestamped with ':'?
			if [[ "$2" =~ : ]]; then
				minutes=$(echo "$2" | awk -F: '{print $1}')
				seconds=$(echo "$2" | awk -F: '{print $2}')
				duration=$(awk -v minutes=$minutes -v seconds=$seconds -v start=$start 'BEGIN { print (minutes * 60) + seconds - start }')
			else
				duration=$(awk -v time:$2 -v start=$start 'BEGIN { print time - start }')
			fi
			trimArr[1]="-t $duration"
			shift
			;;
		-title)
			title="$2"
			shift
			;;
		--)
			shift
			break
			;;
		*)
			break
	esac
	shift
done
input="$1"
filename=$(basename -- "$input")
inputname="${filename%.*}"
output="$2"

# For better -fs functionality, since it sucks with byte form
filelimitmb="$3"
# needs to be in kB since integers, make sure it's in integers. add 50 kilobytes as leeway
outputLimitSize=$(awk -v filelimitmb=$filelimitmb 'BEGIN { printf "%.0f", (filelimitmb*1024) + 200 }')

# Size are in bytes. Make sure it's rounded to integers of bytes.
filelimit=$(awk -v filelimit=$3 'BEGIN { printf "%.0f", filelimit * (1024 * 1024) }')
echo File limit = "$filelimit" bytes
newbitrate="" # for lowering bitrate if within 5% of target
newbitrateTries=0

if [[ -n "$samesubs" ]]; then
	echo "Subs enabled"
	if [[ -z "${trimArr[0]}" ]]; then
		filters[1]=subtitles=\'"$input"\'
	else
		filters[1]=setpts=PTS+$start/TB,subtitles=\'"$input"\',setpts=PTS-STARTPTS
	fi
fi

trim="${trimArr[*]}"
if [[ -n "$trim" ]]; then
	echo 'Utilizing given trim: '"$trim"
fi

function join() {
	printf '%s\n' "$*"
}

if [[ "${filters[*]}" ]]; then
	args=(-vf "$(IFS=, join "${filters[@]}")")
fi

if [[ -z "$title" ]]; then
	title=$(ffprobe -v error -show_entries format_tags=title -of default=noprint_wrappers=1:nokey=1 "$input")
	if [[ -z "$title" ]]; then
		title="$inputname"
	fi
fi

# Bitrate is in bits per second
bitrate="0"
if [[ -z "$duration" ]]; then
	duration=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$input")
	duration=$(awk -v duration=$duration -v start=$start 'BEGIN { print duration - start }')
fi
# Round duration to last 4 decimal places
duration=$(awk -v duration=$duration 'BEGIN { printf "%.4f", duration }')
echo Duration = "$duration" seconds

# Size are in bits per seconds. Make sure it's rounded to integers.
bitrate=$(awk -v filelimit=$filelimit -v duration=$duration 'BEGIN { printf "%.0f", (filelimit * 8) / duration }')
echo Total bitrate = "$bitrate" bps
logfile="$output".log
qmax=(-qmax:v 30)

bitratecmd=(-b:v "$bitrate")
audiocmd=(-an)
qi=0 # downgrade the audio -q option if needed
abr=(-q:a "$qi")
if [[ "$audio" ]]; then
	echo "Audio enabled"
	audiocmd=(-c:a libvorbis -ac 1)
fi

altrefcmd=""
if [[ -n "$altref" ]]; then
	altrefcmd="-auto-alt-ref 1 -lag-in-frames 25"
fi

function ffmpegcmdlog() {
	ffmpeg $trim -i "$input" -an -c:v libvpx "${bitratecmd[@]}" "${qmax[@]}" -fs "$outputLimitSize"k $altrefcmd "${args[@]}" -sws_flags lanczos -sn -metadata title="$title" -pass 1 -passlogfile "$logfile" -threads $threads -speed 0 -quality best -v error -stats -f webm /dev/null -y
	echo Finished creating 2-pass file
}

function ffmpegcmd() {
	set -x
	ffmpeg $trim -i "$input" -c:v libvpx "${audiocmd[@]}" "${bitratecmd[@]}" "${qmax[@]}" -fs "$outputLimitSize"k $altrefcmd "${args[@]}" -sws_flags lanczos -sn -metadata title="$title" -pass 2 -passlogfile "$logfile" -threads $threads -speed 0 -quality best -v error -stats "$output" -y
	{ set +x; } 2>/dev/null
	updateFilesize
	if [[ -n "$brchange" ]]; then
		# Is the file size 5% or less distance to the file limit?
		local diff=""
		diff=$(awk -v filesize=$filesize -v filelimit=$filelimit 'function abs(v) {return (v < 0) ? -v : v} BEGIN { printf "%.0f", (abs(filesize - filelimit) / filelimit) * 100 }')
		if [[ "$newbitrateTries" -lt 1 ]] && isOverFilelimit && [[ "$diff" -le 5 ]]; then
			echo File size is 5% away from target, adjusting bitrate...
			lowerBitrate
			ffmpegcmd
			restoreBitrate
		fi
	fi
}

function downscale() {
	echo Trying ratio "$1"
	filters[0]=scale=-1:"$1"
	args=(-vf "$(IFS=, join "${filters[@]}")")
	ffmpegcmd
}

function degradeaudio() {
	if [[ -z "$audio" ]]; then
		return
	fi
	abr=(-b:a 32k)
	# kbits to bits
	bitrate=$(awk -v filelimit=$filelimit -v duration=$duration 'BEGIN { print ((filelimit * 8) / duration) - (32*1024) }')
	bitratecmd=(-b:v "$bitrate")
	if [[ "$audio" ]]; then
		audiocmd=(-c:a libvorbis -ac 1 "${abr[@]}")
	fi
	echo Degraded audio.
	echo Video bitrate = "$bitrate" bps
}

function tryqmax() {
	echo Trying qmax value: "$1"
	qmax=(-qmax:v "$1")
}

function updateFilesize() {
	filesize=$(stat -c %s "$output")
	# Get filesize in MiB
	local mbsize=""
	mbsize=$(awk -v filesize=$filesize 'BEGIN { printf "%.2f", filesize / (1024 * 1024) }')
	echo filesize = "$filesize"
	echo filelimit = "$filelimit"
	echo File was "$mbsize" MiB
	if ! isOverFilelimit; then
		echo "+++Success+++"
	fi
}

function isOverFilelimit() {
	if [[ "$filesize" -gt "$filelimit" ]]; then
		return 0
	else
		return 1
	fi
}

# Adjust the bitrate if the output ends up being 5% or less of a difference from the target
function lowerBitrate() {
	newbitrateTries=$(( newbitrateTries + 1 ))
	if [[ -z "$newbitrate" ]]; then
		newbitrate="$bitrate"
	fi
	newbitrate=$(awk -v newbitrate=$newbitrate 'BEGIN { printf "%.0f", newbitrate - (newbitrate * 0.1) }')
	bitratecmd=(-b:v "$newbitrate")
	echo Lowering bitrate...
	echo Video bitrate = "$newbitrate" bps
}

function restoreBitrate() {
	newbitrateTries=0
	newbitrate=""
	bitratecmd=(-b:v "$bitrate")
	echo Restoring bitrate...
	echo Video bitrate = "$bitrate" bps
}

function downscaleLoop() {
	# if file size still over file size limit then downscale to preset ratios
	local ratios=("$@")
	local i=0
	while isOverFilelimit; do
		local ratio="${ratios[i]}"
		if [[ i -ge "${#ratios[@]}" ]]; then
			break
		fi

		# Are we going to utilize qmax to limit crap quality?
		if [[ -z "$qmax" ]]; then
			downscale "$ratio"
		else
			local qmaxArr=""
			read -ra qmaxArr <<< "${qmaxMap[$ratio]}"
			echo Trying qmax array '('"${qmaxArr[@]}"')' for ratio "$ratio"
			for x in "${qmaxArr[@]}"; do
				tryqmax "$x"
				downscale "$ratio"
				if ! isOverFilelimit ; then
					break
				fi
			done
		fi
		i=$(( i + 1 ))
	done
}

# +++++++++ MAIN CODE +++++++++

# Make log file for 2 pass
ffmpegcmdlog

# No downscaling and 30 qmax
ffmpegcmd

# Try downscaling and various qmax
degradeaudio
declare -A qmaxMap
qmaxMap[480]="30 40"
qmaxMap[360]="40"
qmaxMap[240]="40"
qmaxMap[144]="40"
downscaleLoop 480 360 240 144

# If still too large, disable qmax all together
if isOverFilelimit; then
	echo Disabling qmax...
	unset qmax
	downscaleLoop 480 360 240 144
fi

# if still too large, limit by filesize
if isOverFilelimit; then
	cutOutput="cut-$output"
	echo File still was too large.
	echo Making a "$cutOutput" file...
	readlink -f "$cutOutput"
	ffmpeg -i "$output" -fs "$filelimitmb"M -c copy -v error "$cutOutput" -y
fi

if [[ -f "$output".log-0.log ]]; then
	rm -v "$output".log-0.log
fi

echo -ne '\007' # beep, where it will highlight the terminal once done
echo Output file is:
readlink -f "$output"
