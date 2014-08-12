#!/bin/bash

if [ -z "${1}" ] || [ -z "${2}" ]; then
	echo "Missing parameters"
	echo "${0} <input> <output>"
	exit 0
fi

OUTPUT_WIDTH=3840
OUTPUT_HEIGHT=2160

# Very ugly but it works!
FRAME_RATE=$(ffmpeg -i ${1} 2>&1 | grep 'fps' | sed -n 's/.*\([0-9][0-9]\) fps.*/\1/p')

# We create a fifo to duplicate the pipe
mkfifo pipe

# We launch the ffmpeg with rescaling to 3840x2160 adding padding if necessary
ffmpeg -i ${1} -vf "scale=iw*sar:ih , pad=max(iw\,ih*(16/9)):ow/(16/9):(ow-iw)/2:(oh-ih)/2, scale=${OUTPUT_WIDTH}x${OUTPUT_HEIGHT}" \
       -f rawvideo -pix_fmt yuv420p - | tee pipe | NGS_FragmentPreprocessorYUV -w ${OUTPUT_WIDTH} -h ${OUTPUT_HEIGHT}-f 30 --APrime > AP_h265.yuv

# Read the pipe to generate the second YUV
cat pipe | (NGS_FragmentPreprocessorYUV -w ${OUTPUT_WIDTH} -h ${OUTPUT_HEIGHT} -f ${FRAME_RATE} --A > A_h265.yuv) &

