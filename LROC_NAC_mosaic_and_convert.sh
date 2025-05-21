#!/bin/sh
# 
# Process all raw PDS IMG files and then mosaic them into a single photometrically corrected GeoTiff. 
# 
# This shell script takes five arguments:
#
# Argument 1:   Path to folder containing raw IMG files
#
# Argument 2:   Delete (1) or don't delete (0) intermediary files (Level 0/1 ISIS cubes and .lis files)
#
# Argument 3:   Resolution to map project images with (set to zero to not change original resolution)
#
# Argument 4:   Patch size used for map-projection (larger of DEM/raw and output/raw, where all values are resolutions)
# 
# Argument 5:   Perform (pho) or don't perform (echo) photometric correction

if [ $# -eq 5 ]; then
    echo "Processing and mosaicking all PDS .IMG files in $1 to GeoTiffs"
else
    echo "Usage: bash $0 [1|str] [2|int] [3|float] [4|int]"
    echo "[1|str]   = Path to folder containing raw IMG files"
    echo "[2|int]   = Delete (1) or don't delete (0) all intermediary files (Level 0/1 ISIS cubes and .lis files)"
    echo "[3|float] = Resolution to map project images with (set to zero to not change original resolution)"
    echo "[4|int]   = Patch size to be used for map-projection (larger of DEM/raw and output/raw, where all values are resolutions)"
    echo "[5|str]   = Perform (pho) or don't perform (echo) photometric correction"
fi

# Check how many input IMG files are found
input=`ls *.IMG | wc -l`

# Define the name of the mosaic
$mosaic="mosaic"

# Convert the IMG files to ISIS cubes using 'lronac2isis'
for i in $1*.IMG; do
    base=`basename $i .IMG`
    new=$1$base.cub
    echo "--- lronac2isis from=$i to=$new"
    lronac2isis from=$i to=$new
done

# Initialise the spice kernels for all ISIS cube files using 'spiceinit'
for i in $1*.cub; do
    echo "--- spiceinit from=$i spksmithed=true web=yes url=https://astrogeology.usgs.gov/apis/ale/v0.9.1/spiceserver/"
    spiceinit from=$i spksmithed=true web=yes url=https://astrogeology.usgs.gov/apis/ale/v0.9.1/spiceserver/

done

# Radiometrically calibrate all ISIS cube files using 'lronaccal'
for i in $1*.cub; do
    base=`basename $i .cub`
    new=$1$base.cal.cub
    echo "--- lronaccal from=$i to=$new"
    lronaccal from=$i to=$new
    if [[ -f "./$new" ]] && [ $2 -eq 1 ]; then
        rm $i
    fi
done

# Echo-correct all calibrated ISIS cubes files using 'lronacecho'
for i in $1*.cal.cub; do
    base=`basename $i .cal.cub`
    new=$1$base.echo.cub
    echo "--- lronacecho from=$i to=$new"
    lronacecho from=$i to=$new
    if [[ -f "./$new" ]] && [ $2 -eq 1 ]; then
        rm $i
    fi
done

# Photometrically correct images using 'lronacpho'
if [ "$5" == "pho" ]; then
    for i in $1*.echo.cub; do
        base=`basename $i .echo.cub`
        new=$1$base.pho.cub
        echo "--- lronacpho from=$i to=$new phopar=lronacpho.pvl"
        lronacpho from=$i to=$new phopar=lronacpho.pvl
        if [[ -f "./$new" ]] && [ $2 -eq 1 ]; then
            rm $i
        fi
    done
elif [ "$5" != "echo" ]; then
    echo "Argument 6 should be echo or pho. Exiting..."
    exit
fi

# List the images
list=$1$mosaic.lis
ls $1*.$5.cub > $list

# Produce a single map file for all images using 'mosrange'
map=$1$mosaic.map
echo "--- mosrange fromlist=$list projection=equirectangular to=$map"
mosrange fromlist=$list projection=equirectangular to=$map

# Map-project each processed ISIS cube using 'cam2map'
for i in $1*.$5.cub; do
    base=`basename $i .$5.cub`
    new=$1$base.map.cub
    echo "--- cam2map from=$i to=$new map=$map interp=cubicconvolution warpalgorithm=forwardpatch patchsize=$4 pixres=mpp resolution=$3"
    cam2map from=$i to=$new map=$map interp=cubicconvolution warpalgorithm=forwardpatch patchsize=$4 pixres=mpp resolution="$3"
    if [[ -f "./$new" ]] && [ $2 -eq 1 ]; then
        rm $i
    fi
done

# Check how many processed map cubes are found
output=`ls $1*.map.cub | wc -l`

# Check that all ISIS cubes exist before mosaicking into one ISIS cube using 'automos'
if [ $input -eq $output ]; then
    maplist=$1$mosaic.map.lis
    ls $1*.map.cub > $list
    echo "--- automos fromlist=$maplist mosaic=$1$mosaic.map.cub tolist=$1$mosaic.lis priority=beneath"
    automos fromlist=$maplist mosaic=$1$mosaic.map.cub tolist=$1$mosaic.lis priority=beneath
    if [[ -f "./$new" ]] && [ $2 -eq 1 ]; then
        rm $list 
        rm $map
    fi
else
    echo "$input were expected, found $output. Exiting..."
    exit
fi

# Convert the mapped ISIS cube to a 0-255 GeoTiff
echo "--- gdal_translate -a_nodata none -of GTiff -ot Byte -scale $1$mosaic.map.cub $1$mosaic.tif"
gdal_translate -a_nodata none -of GTiff -ot Byte -scale $1$mosaic.map.cub $1$mosaic.tif

# Calculate a binary raster with 1s where there is data and 0s where there is not
echo "--- gdal_calc.py -A $1$mosaic.tif --quiet --calc='numpy.where(A >= 0, 1, 0)' --format=GTiff --type=UInt16 --NoDataValue=0 --A_band=1 --outfile=$1$mosaic.binary.tif"
gdal_calc.py -A $1$mosaic.tif --quiet --calc="numpy.where(A >= 0, 1, 0)" --format=GTiff --type=UInt16 --NoDataValue=0 --A_band=1 --outfile=$1$mosaic.binary.tif

# Rename the MSK for the original image to to match the binary mask
mv $1$mosaic.tif.msk $1$mosaic.binary.tif.msk

# Polygonise the raster using the nodata as a mask
echo "--- gdal_polygonize.py $1$mosaic.binary.tif -f ESRI Shapefile $1$mosaic.shp"
gdal_polygonize.py $1$mosaic.binary.tif -f "ESRI Shapefile" $1$mosaic.shp

# Remove binary mask
if [[ -f "./$1$mosaic.tif" ]] && [[ -f "./$1$mosaic.shp" ]] && [ $2 -eq 1 ]; then
    rm $1*.map.cub
    rm $1$mosaic.binary.tif
    rm $1$mosaic.binary.tif.msk
    rm $1$mosaic.tif.aux.xml
fi