#!/bin/sh
#
# Process and convert raw LROC NAC image products to map projected GeoTiffs.
# 
# This shell script takes four arguments:
#
# Argument 1:   Path to folder containing raw IMG files
#
# Argument 2:   Delete (1) or don't delete (0) intermediary files (Level 0/1 ISIS cubes and .lis files)
#
# Argument 3:   Resolution to map project images with (set to zero to not change original resolution)
#
# Argument 4:   Patch size used for map-projection (larger of DEM/raw and output/raw, where all values are resolutions)

if [ $# -eq 4 ]; then
    echo "Processing and converting all PDS .IMG files in $1 to GeoTiffs"
else
    echo "Usage: bash $0 [1|str] [2|int] [3|float] [4|int]"
    echo "[1|str]   = Path to folder containing raw IMG files"
    echo "[2|int]   = Delete (1) or don't delete (0) all intermediary files (Level 0/1 ISIS cubes and .lis files)"
    echo "[3|float] = Resolution to map project images with (set to zero to not change original resolution)"
    echo "[4|int]   = Patch size to be used for map-projection (larger of DEM/raw and output/raw, where all values are resolutions)"
fi

# Check how many input IMG files are found
input=`ls *.IMG | wc -l`

# Loop through each IMG file in the directory
for i in $1*.IMG; do

    # Get the base name of the image product
    base=`basename $i .IMG`

    echo "--- Processing $base"

    # Convert the IMG file to an ISIS cube using 'lronac2isis'
    echo "--- lronac2isis from=$i to=$1$base.cub"
    lronac2isis from=$i to=$1$base.cub

    # Initialise the spice kernels for the raw ISIS cube using 'spiceinit'
    echo "--- spiceinit from=$1$base.cub spksmithed=true web=yes url=https://astrogeology.usgs.gov/apis/ale/v0.9.1/spiceserver/"
    spiceinit from=$1$base.cub spksmithed=true web=yes url=https://astrogeology.usgs.gov/apis/ale/v0.9.1/spiceserver/
    
    # Radiometrically calibrate the spice-initialised ISIS cube using 'lronaccal'
    echo "--- lronaccal from=$1$base.cub to=$1$base.cal.cub"
    lronaccal from=$1$base.cub to=$1$base.cal.cub

    # Delete the raw ISIS cube if the calibrated ISIS cube is present
    if [[ -f "./$1$base.cal.cub" ]] && [ $2 -eq 1 ]; then
        rm $1$base.cub
    fi

    # Echo-correct the calibrated ISIS cube using 'lronacecho'
    echo "--- lronacecho from=$1$base.cal.cub to=$1$base.echo.cub"
    lronacecho from=$1$base.cal.cub to=$1$base.echo.cub

    # Delete the calibrated ISIS cube if the echo-corrected ISIS cube is present
    if [[ -f "./$1$base.echo.cub" ]] && [ $2 -eq 1 ]; then
        rm $1$base.cal.cub
    fi

    # Produce a map file for the image using 'mosrange'
    list=$1$base.lis
    map=$1$base.map
    echo $1$base.echo.cub > $list
    echo "--- mosrange fromlist=$list projection=equirectangular to=$map"
    mosrange fromlist=$list projection=equirectangular to=$map

    # Delete the list if the map file is present
    if [[ -f "./$map" ]] && [ $2 -eq 1 ]; then
        rm $list
    fi    

    # Map-project the processed ISIS cube using 'cam2map'
    if [ "$3" == "0" ]; then
        echo "--- cam2map from=$1$base.echo.cub to=$1$base.map.cub map=$map warpalgorithm=forwardpatch patchsize=$4 matchmap=true"
        cam2map from=$1$base.echo.cub to=$1$base.map.cub map=$map warpalgorithm=forwardpatch patchsize=$4 matchmap=true
    elif [ "$3" != "0" ]; then
        echo "--- cam2map from=$1$base.echo.cub to=$1$base.map.cub map=$map interp=cubicconvolution warpalgorithm=forwardpatch patchsize=$4 pixres=mpp resolution=$3"
        cam2map from=$1$base.echo.cub to=$1$base.map.cub map=$map interp=cubicconvolution warpalgorithm=forwardpatch patchsize=$4 pixres=mpp resolution="$3"
    fi

    # Delete the echo-corrected ISIS cube and map file if the mapped ISIS cube is present
    if [[ -f "./$1$base.map.cub" ]] && [ $2 -eq 1 ]; then
        rm $1$base.echo.cub
        rm $map
    fi

    # Convert the mapped ISIS cube to a 0-255 GeoTiff
    echo "--- gdal_translate -a_nodata none -of GTiff -ot Byte -scale $1$base.map.cub $1$base.tif"
    gdal_translate -a_nodata none -of GTiff -ot Byte -scale $1$base.map.cub $1$base.tif

    # Calculate a binary raster with 1s where there is data and 0s where there is not
    echo "--- gdal_calc.py -A $1$base.tif --quiet --calc='numpy.where(A >= 0, 1, 0)' --format=GTiff --type=UInt16 --NoDataValue=0 --A_band=1 --outfile=$1$base.binary.tif"
    gdal_calc.py -A $1$base.tif --quiet --calc="numpy.where(A >= 0, 1, 0)" --format=GTiff --type=UInt16 --NoDataValue=0 --A_band=1 --outfile=$1$base.binary.tif

    # Rename the MSK for the original image to to match the binary mask
    mv $1$base.tif.msk $1$base.binary.tif.msk 

    # Polygonise the raster using the nodata as a mask
    echo "--- gdal_polygonize.py $1$base.binary.tif -f ESRI Shapefile $1$base.shp"
    gdal_polygonize.py $1$base.binary.tif -f "ESRI Shapefile" $1$base.shp

    # Delete the raw IMG file and binary GeoTiff if the footprint shapefile is present
    if [[ -f "./$1$base.tif" ]] && [[ -f "./$1$base.shp" ]] && [ $2 -eq 1 ]; then
        rm $i
        rm $1$base.map.cub
        rm $1$base.binary.tif
        rm $1$base.binary.tif.msk
    fi

done

# Check that all GeoTiffs have been produced
output=`ls *.tif | wc -l`
if [ $input -eq $output ]; then
    echo "All $input mapped GeoTiffs present. Finishing..."
else
    echo "$input GeoTiffs were expected, found $output. Exiting..."
fi