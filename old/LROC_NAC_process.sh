#!/bin/sh
# Process all raw PDS IMG files in directory to calibrated, echo-corrected and map-projected ISIS cubes.
# This shell script takes three optional arguments:
#
# Argument 1:   Should intermediary files be deleted?
# Usage:        0 = Keep all intermediary files
#               1 = Delete all intermediary files
#
# Argument 2:   Should the USGS SPICE web service be used for retrieving kernels?
# Usage:        yes = SPICE web service will be used
#               no = Local SPICE kernels will be used
#
# Argument 3:   What patch size should be used when mapping?
# Usage:        An integer which should be larger of DEM/raw or output/raw pixel resolutions.
#               i.e. for a 100 m/px DEM used to map a 0.5 m/px raw image to a 1 m/px output.
#               100 / 0.5 = 200 and 1 / 0.5 = 2, so a patch size of 200 should be used.

if [ $# -le 3 ]; then
    echo "Processing all PDS .IMG files in:"
    pwd
else
    echo "Usage: bash $0 [0|1] [yes|no] [int]"
    echo "[0|1] = Keep|Delete all intermediary files"
    echo "[yes|no] = Use|Don't use the USGS SPICE web service for retrieving kernels (Default: no)"
    echo "[int] = Patch size used when mapping (Default: 50)"
fi

# Set the default values for the optional arguments
$1=${1:-1}
$2=${2:-'no'}
$3=${3:-50}

# Check how many input IMG files are found
input=`ls *.IMG | wc -l`

# Convert the IMG files to ISIS cubes using 'lronac2isis'
for i in *.IMG; do
    base=`basename $i .IMG`
    new="$base.cub"
    echo lronac2isis "from=$i to=$new"
    lronac2isis from=$i to=$new
done

# Initialise the spice kernels for all ISIS cube files using 'spiceinit'
for i in *.cub; do
    if [ $2 == 'yes' ]; then 
        echo "spiceinit from=$i web=true"
        spiceinit from=$i web=true
    elif [ $2 == 'no' ]; then
        echo "spiceinit from=$i spksmithed=true"
        spiceinit from=$i spksmithed=true
    else
        echo "Argument two should be "yes" or "no". Exiting..."
        exit
    fi
done

# Radiometrically calibrate all ISIS cube files using 'lronaccal'
for i in *.cub; do
    base=`basename $i .cub`
    new="$base.cal.cub"
    echo "lronaccal from=$i to=$new"
    lronaccal from=$i to=$new
    if [[ -f "./$new" ]] && [ $1 -eq 1 ]; then
        rm $i
    fi
done

# Echo-correct all calibrated ISIS cubes files using 'lronacecho'
for i in *.cal.cub; do
    base=`basename $i .cal.cub`
    new="$base.echo.cub"
    echo "lronacecho from=$i to=$new"
    lronacecho from=$i to=$new
    if [[ -f "./$new" ]] && [ $1 -eq 1 ]; then
        rm $i
    fi
done

# Produce a map file for each image using 'mosrange'
for i in *.echo.cub; do
    base=`basename $i .echo.cub`
    list="$base.lis"
    map="$base.map"
    echo "ls *.echo.cub > $list"
    ls *.echo.cub > $list
    echo "mosrange fromlist=$list projection=equirectangular to=$map"
    mosrange fromlist=$list projection=equirectangular to=$map
    if [[ -f "./$map" ]] && [ $1 -eq 1 ]; then
        rm $list
    fi
done

# Map-project each calibrated and echo-corrected ISIS cube using 'cam2map'
for i in *.echo.cub; do
    base=`basename $i .echo.cub`
    new="$base.map.cub"
    map="$base.map"
    echo "cam2map from=$i to=$new map=$map warpalgorithm=forwardpatch patchsize=$3"
    cam2map from=$i to=$new map=$map warpalgorithm=forwardpatch patchsize=$3
    if [[ -f "./$new" ]] && [ $1 -eq 1 ]; then
        rm $i
    fi
done

# Check that all ISIS cubes exist
output=`ls *.map.cub | wc -l`
if [ $input -eq $output ]; then
    echo "All $input mapped ISIS cube(s) present. Finishing..."
    exit
else
    echo "$input were expected, found $output. Exiting..."
    exit
fi