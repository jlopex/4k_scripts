#!/bin/bash

if [ -z "${1}" ] || [ -z "${2}" ]; then
	echo "Missing parameters"
	echo "${0} <input> <output>"
	exit 0
fi

OUTPUT_WIDTH=3840
OUTPUT_HEIGHT=2160

# Very ugly but it gets the current FPS!
FRAME_RATE=$(ffmpeg -i ${1} 2>&1 | grep 'fps' | sed -n 's/.*\([0-9][0-9]\) fps.*/\1/p')

# This command will create a 3840x2160 yuv raw (A) at original frame rate, appending padding if necessary
ffmpeg -i $1 -f rawvideo -pix_fmt yuv420p -vf "scale=iw*sar:ih , pad=max(iw\,ih*(16/9)):ow/(16/9):(ow-iw)/2:(oh-ih)/2, scale=${OUTPUT_WIDTH}x${OUTPUT_HEIGHT}" - | NGS_FragmentPreprocessorYUV -w ${OUTPUT_WIDTH} -h ${OUTPUT_HEIGHT} -f ${FRAME_RATE} --A > A_${2}.yuv

# This command will create a 3840x2160 yuv raw (AP) at original frame rate, appending padding if necessary (THIS MIGHT ME BE GENERATED LATER)
ffmpeg -i $1 -f rawvideo -pix_fmt yuv420p -vf "scale=iw*sar:ih , pad=max(iw\,ih*(16/9)):ow/(16/9):(ow-iw)/2:(oh-ih)/2, scale=${OUTPUT_WIDTH}x${OUTPUT_HEIGHT}" - | NGS_FragmentPreprocessorYUV -w ${OUTPUT_WIDTH} -h ${OUTPUT_HEIGHT} -f ${FRAME_RATE} --APrime > AP_${2}.yuv

ffmpeg -y -f rawvideo -s ${OUTPUT_WIDTH}x${OUTPUT_HEIGHT} -r ${FRAME_RATE} -i A_${2}.yuv -preset fast -x265-params level=5.1:bitrate=8000:vbv-bufsize=24000:bframes=3:ref=4:keyint=48:min-keyint=24:scenecut=0:b-adapt=1:b-pyramid=0:tskip=1 -movflags +faststart -map_chapters -1 -f mp4 -vcodec libx265 -b:v 8000k -minrate 8000k -maxrate 8000k -bufsize 24000k -s:v:0 ${OUTPUT_WIDTH}x${OUTPUT_HEIGHT} -coder 1 -an -pass 1 /dev/null

ffmpeg -y -f rawvideo -s ${OUTPUT_WIDTH}x${OUTPUT_HEIGHT} -r ${FRAME_RATE} -i A_${2}.yuv -i ${1} -preset fast -x265-params level=5.1:bitrate=8000:vbv-bufsize=24000:bframes=3:ref=4:keyint=48:min-keyint=24:scenecut=0:b-adapt=1:b-pyramid=0:tskip=1 -movflags +faststart -map_chapters -1 -f mp4 -vcodec libx265 -b:v 8000k -minrate 8000k -maxrate 8000k -bufsize 24000k -s:v:0 ${OUTPUT_WIDTH}x${OUTPUT_HEIGHT} -coder 1 -map 0:0 -map 1:1 -acodec libfaac -ac 2 -ab 128k -ar 44100 -pass 2 A_${2}

ffmpeg -y -f rawvideo -s ${OUTPUT_WIDTH}x${OUTPUT_HEIGHT} -r ${FRAME_RATE} -i AP_${2}.yuv -i $1 -preset fast -x265-params level=5.1:bitrate=8000:vbv-bufsize=24000:bframes=3:ref=4:keyint=48:min-keyint=24:scenecut=0:b-adapt=1:b-pyramid=0:tskip=1 -movflags +faststart -map_chapters -1 -f mp4 -vcodec libx265 -b:v 8000k -minrate 8000k -maxrate 8000k -bufsize 24000k -s:v:0 ${OUTPUT_WIDTH}x${OUTPUT_HEIGHT} -coder 1 -map 0:0 -map 1:1 -acodec libfaac -ac 2 -ab 128k -ar 44100 -pass 2 AP_${2}


