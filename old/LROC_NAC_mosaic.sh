#!/bin/sh
# Process all raw PDS IMG files and then mosaic them into a single photometrically corrected ISIS cube. 
# This shell script takes four arguments (one mandatory, three optional):
#
# Argument 1:   What name should be given to the mosaicked ISIS cube?
# Usage:        A string (not including file extension) which the mapped ISIS cube will be saved as.
#
# Argument 2:   Should intermediary files be deleted?
# Usage:        0 = Keep all intermediary files
#               1 = Delete all intermediary files
#
# Argument 3:   Should the USGS SPICE web service be used for retrieving kernels?
# Usage:        yes = SPICE web service will be used
#               no = Local SPICE kernels will be used
#
# Argument 4:   What patch size should be used when mapping?
# Usage:        An integer which should be larger of DEM/raw or output/raw pixel resolutions.
#               i.e. for a 100 m/px DEM used to map a 0.5 m/px raw image to a 1 m/px output.
#               100 / 0.5 = 200 and 1 / 0.5 = 2, so a patch size of 200 should be used.

if [ $# -ge 1 ]; then
    echo "Creating a mosaic for the PDS .IMG files in:"
    pwd
else
    echo "Usage: bash $0 [name] [0|1] [yes|no] [int]"
    echo "[name]    = File name for the mosaicked ISIS cube (not including extension)"
    echo "[0|1]     = Keep|Delete all intermediary files (Default: 1)"
    echo "[yes|no]  = Use|Don't use the USGS SPICE web service for retrieving kernels (Default: no)"
    echo "[int]     = Patch size used when mapping (Default: 50)"
fi

# Set the default values for the optional arguments
$2=${2:-1}
$3=${3:-'no'}
$4=${4:-50}

# Check how many input IMG files are found
input=`ls *.IMG | wc -l`

# Convert the IMG files to ISIS cubes using 'lronac2isis'
for i in *.IMG; do
    base=`basename $i .IMG`
    new="$base.cub"
    echo "lronac2isis from=$i to=$new"
    lronac2isis from=$i to=$new
done

# Initialise the spice kernels for all ISIS cube files using 'spiceinit'
for i in *.cub; do
    if [ $3 == 'yes' ]; then 
        echo "spiceinit from=$i web=true"
        spiceinit from=$i web=true
    elif [ $3 == 'no' ]; then
        echo "spiceinit from=$i spksmithed=true"
        spiceinit from=$i spksmithed=true
    else
        echo "Argument two should be yes or no. Exiting..."
        exit
    fi
done

# Radiometrically calibrate all ISIS cube files using 'lronaccal'
for i in *.cub; do
    base=`basename $i .cub`
    new="$base.cal.cub"
    echo "lronaccal from=$i to=$new"
    lronaccal from=$i to=$new
    if [[ -f "./$new" ]] && [ $2 -eq 1 ]; then
        rm $i
    fi
done

# Echo-correct all calibrated ISIS cubes files using 'lronacecho'
for i in *.cal.cub; do
    base=`basename $i .cal.cub`
    new="$base.echo.cub"
    echo "lronacecho from=$i to=$new"
    lronacecho from=$i to=$new
    if [[ -f "./$new" ]] && [ $2 -eq 1 ]; then
        rm $i
    fi
done

# Photometrically correct images to make mosaic using 'photomet'
for i in *.echo.cub; do
    base=`basename $i .echo.cub`
    new="$base.pho.cub"
    echo "photomet from=$i to=$new frompvl=basicpho.pvl"
    photomet from=$i to=$new frompvl=basicpho.pvl
    if [[ -f "./$new" ]] && [ $2 -eq 1 ]; then
        rm $i
    fi
done

# List all processed (non-mapped) ISIS cubes to be mosaicked
list="$1.lis"
echo "ls *.pho.cub > $list"
ls *.pho.cub > $list

# Retrieve the camera stats such as resolution and solar incidence angle
if [ -f "$4.csv" ]; then
    rm $4.csv
fi
for i in *.cub; do
    base=`basename $i .cub`
    new=$base.pvl
    echo "camstats from=$i to=$new format=PVL linc=100 sinc=100"
    camstats from=$i to=$new format=PVL linc=100 sinc=100
    inc=`getkey from=$new grpname=IncidenceAngle keyword=IncidenceAverage`
    res=`getkey from=$new grpname=ObliqueResolution keyword=ObliqueResolutionAverage`
    echo $base.map.cub,$res,$inc >> $4.csv
    if [[ -f "$4.csv" ]] && [ $1 -eq 1 ]; then
        rm $new
    fi
done

# Produce a single map file for all images to be mosaicked using 'mosrange'
map="$1.map"
echo "mosrange fromlist=$list projection=equirectangular to=$map"
mosrange fromlist=$list projection=equirectangular to=$map
if [[ -f "./$map" ]] && [ $2 -eq 1 ]; then
    rm $list
fi

# Map-project each calibrated, photometrically- and echo-corrected ISIS cube using 'cam2map'
for i in *.pho.cub; do
    base=`basename $i .pho.cub`
    new="$base.map.cub"
    echo "cam2map from=$i to=$new map=$map warpalgorithm=forwardpatch patchsize=$4 matchmap=yes"
    cam2map from=$i to=$new map=$map warpalgorithm=forwardpatch patchsize=$4 matchmap=yes
done



# List all mapped ISIS cubes to be mosaicked
list="$1.lis"
echo "ls *.map.cub > $list"
ls *.map.cub > $list

# Check that all ISIS cubes exist before mosaicking into one ISIS cube using 'automos'
output=`ls *.map.cub | wc -l`
if [ $input -eq $output ]; then
    name="$1.map.cub"
    echo "All mapped ISIS cubes present. Mosaicking..."
    echo "automos fromlist=$list mosaic=$name"
    automos fromlist=$list mosaic=$name
    rm $list
else
    echo "$input were expected, found $output. Exiting..."
    exit
fi