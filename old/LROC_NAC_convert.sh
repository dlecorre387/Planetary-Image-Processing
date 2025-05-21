#!/bin/sh
# Convert all processed ISIS cubes in the directory to 8-bit GeoTiff images.
# This shell script takes one optional argument:
#
# Argument 1:   Should intermediary files (Level 2 mapped ISIS cubes) be deleted?
# Usage:        0 = Keep all intermediary files
#               1 = Delete all intermediary files

if [ $# -le 1 ]; then
    echo "Converting all processed and mapped ISIS cubes in:"
    pwd
else
    echo "Usage: bash $0 [0|1]"
    echo "[0|1] = Keep|Delete all intermediary files"
fi

# Convert from ISIS cube to GeoTiff format using 'gdal_translate'
for i in *.map.cub; do
    base=`basename $i .map.cub`
    new="$base.tiff"
    echo "gdal_translate -ot Byte -of GTiff -a_nodata none -scale $i $new"
    gdal_translate -ot Byte -of GTiff -a_nodata none -scale $i $new
    if [[ -f "./$new" ]] && [ $1 -eq 1 ]; then
        rm $i
    fi
done