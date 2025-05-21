#!/bin/sh
#
# Down/upscale all raster files in a directory to a given resolution.
#
# This script takes two arguments:
#
# Argument 1:   Path to the folder containing the images to be downscaled.
#
# Argument 2:   Target resolution to downscale the images to in metres.


if [ $# -ne 2 ]; then
    echo "Downscaling all images in:"
    pwd
else
    echo "Usage: bash $0 [1|str] [2|float]"
    echo "[1|str]   = Path to folder containing images to be downscaled"
    echo "[2|float] = Target resolution in metres"
fi

# Loop through JP2 or GeoTiff files in the given input directory
for i in $1*.{JP2,tif,tiff}; do

    echo "--- Downscaling $i"
    
    # Get the product name of the file
    base=$(basename "$i" | cut -d. -f1)

    # Define the new filename
    new=$base"_$2.tif"
    
    # Translate raster with new resolution
    echo "--- gdal_translate -tr $2 $2 -r cubicspline -ot Byte -scale $i $1$new"
    gdal_translate -tr "$2" "$2" -r cubicspline -ot Byte -scale $i $1$new

done