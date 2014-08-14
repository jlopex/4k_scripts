#!/bin/bash

# TODO Now there's a lot of redundant code split in shorter functions and reuse common code
# TODO Review ffmpeg libx265 command line as there are duplicates parameters between libx265 and ffmpeg
# TODO We're forcing bitrate to 8000kbps specify MIN/MAX values
# TODO Make the default values updateable through script options
# TODO Review ffmpeg commands for non watermarked output, probably we don't need to create a tmp yuv

# Default Values -- should be configurable at some point
OUTPUT_WIDTH=3840									#px
OUTPUT_HEIGHT=2160								#px
BITRATE=8000											#kbps
BUFFER_SIZE=$((3*${BITRATE}))			#kbps
MIN_RATE=${BITRATE}								#kbps
MAX_RATE=${BITRATE}								#kbps
FADE_DURATION=50									#frames
FADE_MARGIN=100										#frames
LOGO_WIDTH_MARGIN=30							#px
LOGO_HEIGHT_MARGIN=30							#px

# simple usage for user
usage() {
    echo "Usage: $0 [-i <input_video>] [-o <output_video>] optional {[-l <logo_file>], [-w]}" 1>&2
    exit 1
}

start_end_logo_frames() {

    FRAMES=$(ffmpeg -i ${INPUT_VIDEO} -vcodec copy -f rawvideo -y /dev/null 2>&1 | tr ^M '\n' | awk '/^frame=/ {print $2}'| tail -n 1)
    START_LOGO_FRAME=${FADE_MARGIN}
    END_LOGO_FRAME=$((${FRAMES}-${FADE_MARGIN}))
}

yuv() {
    ffmpeg -i ${INPUT_VIDEO} -f rawvideo -pix_fmt yuv420p -vf "scale=iw*sar:ih , pad=max(iw\,ih*(16/9)):ow/(16/9):(ow-iw)/2:(oh-ih)/2, scale=${OUTPUT_WIDTH}x${OUTPUT_HEIGHT}"  ${OUTPUT_VIDEO}.yuv
}

yuv_with_logo() {

    start_end_logo_frames
    ffmpeg -i ${INPUT_VIDEO} -loop 1 -i ${LOGO_FILE} -f rawvideo -pix_fmt yuv420p -filter_complex "[0:v] scale=iw*sar:ih , pad=max(iw\,ih*(16/9)):ow/(16/9):(ow-iw)/2:(oh-ih)/2, scale=${OUTPUT_WIDTH}x${OUTPUT_HEIGHT} [scaled]; [1:v] fade=in:${START_LOGO_FRAME}:${FADE_DURATION}:alpha=1, fade=out:${END_LOGO_FRAME}:${FADE_DURATION}:alpha=1 [logo]; [scaled][logo] overlay=W-w-${LOGO_WIDTH_MARGIN}:H-h-${LOGO_HEIGHT_MARGIN}:shortest=1"  ${OUTPUT_VIDEO}.yuv
}

yuv_with_logo_and_watermarking_A() {

    ffmpeg -i ${INPUT_VIDEO} -loop 1 -i ${LOGO_FILE} -f rawvideo -pix_fmt yuv420p -filter_complex "[0:v] scale=iw*sar:ih , pad=max(iw\,ih*(16/9)):ow/(16/9):(ow-iw)/2:(oh-ih)/2, scale=${OUTPUT_WIDTH}x${OUTPUT_HEIGHT} [scaled]; [1:v] fade=in:${START_LOGO_FRAME}:${FADE_DURATION}:alpha=1, fade=out:${END_LOGO_FRAME}:${FADE_DURATION}:alpha=1 [logo]; [scaled][logo] overlay=W-w-${LOGO_WIDTH_MARGIN}:H-h-${LOGO_HEIGHT_MARGIN}:shortest=1" -f rawvideo - | NGS_FragmentPreprocessorYUV -w ${OUTPUT_WIDTH} -h ${OUTPUT_HEIGHT} -f ${FRAME_RATE} --A > ${OUTPUT_VIDEO}.yuvA
}

yuv_with_logo_and_watermarking_AP() {
    ffmpeg -i ${INPUT_VIDEO} -loop 1 -i ${LOGO_FILE} -f rawvideo -pix_fmt yuv420p -filter_complex "[0:v] scale=iw*sar:ih , pad=max(iw\,ih*(16/9)):ow/(16/9):(ow-iw)/2:(oh-ih)/2, scale=${OUTPUT_WIDTH}x${OUTPUT_HEIGHT} [scaled]; [1:v] fade=in:${START_LOGO_FRAME}:${FADE_DURATION}:alpha=1, fade=out:${END_LOGO_FRAME}:${FADE_DURATION}:alpha=1 [logo]; [scaled][logo] overlay=W-w-${LOGO_WIDTH_MARGIN}:H-h-${LOGO_HEIGHT_MARGIN}:shortest=1" - | NGS_FragmentPreprocessorYUV -w ${OUTPUT_WIDTH} -h ${OUTPUT_HEIGHT} -f ${FRAME_RATE} --APrime > ${OUTPUT_VIDEO}.yuvAP
}

yuv_with_watermarking_A() {
    ffmpeg -i ${INPUT_VIDEO} -f rawvideo -pix_fmt yuv420p -vf "scale=iw*sar:ih , pad=max(iw\,ih*(16/9)):ow/(16/9):(ow-iw)/2:(oh-ih)/2, scale=${OUTPUT_WIDTH}x${OUTPUT_HEIGHT}" - | NGS_FragmentPreprocessorYUV -w ${OUTPUT_WIDTH} -h ${OUTPUT_HEIGHT} -f ${FRAME_RATE} --A > ${OUTPUT_VIDEO}.yuvA
}

yuv_with_watermarking_AP() {
    ffmpeg -i ${INPUT_VIDEO} -f rawvideo -pix_fmt yuv420p -vf "scale=iw*sar:ih , pad=max(iw\,ih*(16/9)):ow/(16/9):(ow-iw)/2:(oh-ih)/2, scale=${OUTPUT_WIDTH}x${OUTPUT_HEIGHT}" - | NGS_FragmentPreprocessorYUV -w ${OUTPUT_WIDTH} -h ${OUTPUT_HEIGHT} -f ${FRAME_RATE} --APrime > ${OUTPUT_VIDEO}.yuvAP
}

# create two yuvs files with resampling, logo and watermarking
yuvs_with_logo_and_watermarking() {

    # Calculate start end logo frame
    start_end_logo_frames
    # Generate A yuv
    yuv_with_logo_and_watermarking_A
    # Generate AP yuv
    yuv_with_logo_and_watermarking_AP
}

yuvs_with_watermarking() {

    # Generate A yuv
    yuv_with_watermarking_A
    # Generate AP yuv
    yuv_with_watermarking_AP
}

# create h265 output from yuv files
h265_two_pass_from_watermarked_yuvs() {
    # Pass 1 x265 
    ffmpeg -y -f rawvideo -s ${OUTPUT_WIDTH}x${OUTPUT_HEIGHT} -r ${FRAME_RATE} -i ${OUTPUT_VIDEO}.yuvA -preset fast -x265-params level=5.1:bitrate=${BITRATE}:vbv-bufsize=${BUFFER_SIZE}:bframes=3:ref=4:keyint=48:min-keyint=24:scenecut=0:b-adapt=1:b-pyramid=0:tskip=1 -movflags +faststart -map_chapters -1 -f mp4 -vcodec libx265 -b:v ${BITRATE}k -minrate ${MIN_RATE}k -maxrate ${MAX_RATE}k -bufsize ${BUFFER_SIZE}k -s:v:0 ${OUTPUT_WIDTH}x${OUTPUT_HEIGHT} -coder 1 -an -pass 1 /dev/null

    # Pass 2 (A) x265 + Audio
    ffmpeg -y -f rawvideo -s ${OUTPUT_WIDTH}x${OUTPUT_HEIGHT} -r ${FRAME_RATE} -i ${OUTPUT_VIDEO}.yuvA -i ${INPUT_VIDEO} -preset fast -x265-params level=5.1:bitrate=${BITRATE}:vbv-bufsize=${BUFFER_SIZE}:bframes=3:ref=4:keyint=48:min-keyint=24:scenecut=0:b-adapt=1:b-pyramid=0:tskip=1 -movflags +faststart -map_chapters -1 -f mp4 -vcodec libx265 -b:v ${BITRATE}k -minrate ${MIN_RATE}k -maxrate ${MAX_RATE}k -bufsize ${BUFFER_SIZE}k -s:v:0 ${OUTPUT_WIDTH}x${OUTPUT_HEIGHT} -coder 1 -map 0:0 -map 1:1 -acodec libfaac -ac 2 -ab 128k -ar 44100 -pass 2 ${OUTPUT_VIDEO}.A

    # Pass 2 (AP) x265 + Audio
    ffmpeg -y -f rawvideo -s ${OUTPUT_WIDTH}x${OUTPUT_HEIGHT} -r ${FRAME_RATE} -i ${OUTPUT_VIDEO}.yuvAP -i $1 -preset fast -x265-params level=5.1:bitrate=${BITRATE}:vbv-bufsize=${BUFFER_SIZE}:bframes=3:ref=4:keyint=48:min-keyint=24:scenecut=0:b-adapt=1:b-pyramid=0:tskip=1 -movflags +faststart -map_chapters -1 -f mp4 -vcodec libx265 -b:v ${BITRATE}k -minrate ${MIN_RATE}k -maxrate ${MAX_RATE}k -bufsize ${BUFFER_SIZE}k -s:v:0 ${OUTPUT_WIDTH}x${OUTPUT_HEIGHT} -coder 1 -map 0:0 -map 1:1 -acodec libfaac -ac 2 -ab 128k -ar 44100 -pass 2 ${OUTPUT_VIDEO}.AP

}

# create h265 output from yuv file
h265_two_pass_from_non_watermarked_yuv() {
    # Pass 1 x265 
    ffmpeg -y -f rawvideo -s ${OUTPUT_WIDTH}x${OUTPUT_HEIGHT} -r ${FRAME_RATE} -i ${OUTPUT_VIDEO}.yuv -preset fast -x265-params level=5.1:bitrate=${BITRATE}:vbv-bufsize=${BUFFER_SIZE}:bframes=3:ref=4:keyint=48:min-keyint=24:scenecut=0:b-adapt=1:b-pyramid=0:tskip=1 -movflags +faststart -map_chapters -1 -f mp4 -vcodec libx265 -b:v ${BITRATE}k -minrate ${MIN_RATE}k -maxrate ${MAX_RATE}k -bufsize ${BUFFER_SIZE}k -s:v:0 ${OUTPUT_WIDTH}x${OUTPUT_HEIGHT} -coder 1 -an -pass 1 /dev/null

    # Pass 2 (A) x265 + Audio
    ffmpeg -y -f rawvideo -s ${OUTPUT_WIDTH}x${OUTPUT_HEIGHT} -r ${FRAME_RATE} -i ${OUTPUT_VIDEO}.yuv -i ${INPUT_VIDEO} -preset fast -x265-params level=5.1:bitrate=${BITRATE}:vbv-bufsize=${BUFFER_SIZE}:bframes=3:ref=4:keyint=48:min-keyint=24:scenecut=0:b-adapt=1:b-pyramid=0:tskip=1 -movflags +faststart -map_chapters -1 -f mp4 -vcodec libx265 -b:v ${BITRATE}k -minrate ${MIN_RATE}k -maxrate ${MAX_RATE}k -bufsize ${BUFFER_SIZE}k -s:v:0 ${OUTPUT_WIDTH}x${OUTPUT_HEIGHT} -coder 1 -map 0:0 -map 1:1 -acodec libfaac -ac 2 -ab 128k -ar 44100 -pass 2 ${OUTPUT_VIDEO}

}

#### MAIN ####
set -e

while getopts ":i:o:l:w" o; do
    case "${o}" in
        i)
            INPUT_VIDEO=${OPTARG}
            ;;
        o)
            OUTPUT_VIDEO=${OPTARG}
            ;;
        l)
            LOGO_FILE=${OPTARG}
            ;;
        w)
            WATERMARKING=true
            ;;
        *)
            usage
            ;;
    esac
done

shift $((OPTIND-1))

if [ -z "${INPUT_VIDEO}" ] || [ -z "${OUTPUT_VIDEO}" ]; then
    usage
fi

# Ugly but we need input file fps!
FRAME_RATE=$(ffprobe ${INPUT_VIDEO} 2>&1 | grep 'fps' | sed -n 's/.*\([0-9][0-9]\) fps.*/\1/p')

if [ -z "${WATERMARKING}" ]; then
    if [ -z "${LOGO_FILE}" ]; then
        yuv
    else
        yuv_with_logo
    fi
    h265_two_pass_from_non_watermarked_yuv
else
    if [ -z "${LOGO_FILE}" ]; then
        yuvs_with_watermarking
    else
        yuvs_with_logo_and_watermarking
    fi
    h265_two_pass_from_watermarked_yuvs
fi

exit 0
