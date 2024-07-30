#!/bin/sh

# Down/upscale all raster files in a directory, and create footprints if necessary.
# This script takes two mandatory and four optional arguments:
#
# Argument 1:   Target resolution to downscale the images to [in m].
# Usage:        A single float value
#
# Argument 2:   File type of the images to be converted.
# Usage:        JP2, tif, tiff etc.
#
# Argument 3:   Path to the folder containing the images to be downscaled.
# Usage:        A string containing the path to the input directory (set to pwd by default)
#
# Argument 4:   File type of downscaled images.
# Usage:        JP2, tif, tiff etc. (same as input file type by default)
# 
# Argument 5:   Path to the folder for saving all downscaled images.
# Usage:        A string containing the path to the output directory (within pwd by default)
#
# Argument 6:   Should footprint shapefiles be produced
# Usage:        True or False
#
# Argument 7:   Mode for interpolating between pixels.
# Usage:        'cubicspline', 'cubic' or 'bilinear'


if [ $# -ge 2 ]; then
    echo "Downscaling all images in:"
else
    echo "Usage: bash $0 [tres] [path] [JP2|tif|tiff] [path] [JP2|tif|tiff] [True|False] [cubicspline|cubic|bilinear]"
    echo "[tres] Target resolution in m"
    echo "[JP2|tif|tiff] = Input file type of images to be downscaled"
    echo "[path] = Path to folder containing images to be downscaled"
    echo "[JP2|tif|tiff] = Output file type. Same as input by default"
    echo "[path] = Path to folder where downscaled images should be saved. Within input folder by default"
    echo "[True|False] = Produce footprint shapefiles"
    echo "[cubicspline|cubic|bilinear] = Mode for interpolating pixel values" 
fi

# Set the default values
$inext=${2:-"tiff"}
$inpath=${3:-$PWD}
$outext=${$4:-$inext}
$outpath=${5:-"$inpath$1/"}
$footprint=${6:-"False"}
$mode=${7:-"cubicspline"}

# Create the output directory if it doesn't already exist
mkdir -p $outpath

# Loop through all files in input path ending with the chosen extension
for i in "$inpath*.$inext"; do

    echo "--- Downscaling $i"
    
    # Get the product name of the file
    base=`basename $i ".$inext"`

    # Define the new filename
    new="$base.$outext"
    
    if [ $footprint == "True" ]; then

        # Translate raster with new resolution
        echo "--- gdal_translate -tr $1 $1 -r $mode -ot Byte -scale $i $outpath$new"
        gdal_translate -tr "$1" "$1" -r $mode -ot Byte -scale $i $outpath$new

        # Calculate a binary raster with 1s where there is data and 0s where there is not
        echo "--- gdal_calc.py -A $outpath$new --calc=numpy.where(A > 0, 1, 0) --format=GTiff --type=UInt16 --NoDataValue=0  --A_band=1 --outfile=$outpath"binary_$new""
        gdal_calc.py -A $outpath$new --calc="numpy.where(A > 0, 1, 0)" --format=GTiff --type=UInt16 --NoDataValue=0  --A_band=1 --outfile=$outpath"binary_$new"

        # Polygonise the raster using the nodata as a mask
        echo "--- gdal_polygonize.py $outpath"binary_$new" -b 1 -f "ESRI Shapefile" "$outpath$base.shp""
        gdal_polygonize.py $outpath"binary_$new" -b 1 -f "ESRI Shapefile" "$outpath$base.shp"

    elif [ $footprint == "False" ]; then

        if [ "$1" != "0" ]; then

        # Translate raster with new resolution
        echo "--- gdal_translate -tr "$1" "$1" -r $mode -ot Byte -scale $i $outpath$new"
        gdal_translate -tr "$1" "$1" -r $mode -ot Byte -scale $i $outpath$new

        elif [ "$1" == "0" ]; then

            # Translate raster with the same resolution
            echo "--- gdal_translate -ot Byte -scale $i $outpath$new"
            gdal_translate -ot Byte -scale $i $outpath$new

        fi

    fi

done