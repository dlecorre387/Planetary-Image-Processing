#!/bin/sh
# 
# Correct the map projection of early HiRISE Reduced Data Record Version 1.1 (RDRV11) 
# observations and convert them to 0-255 GeoTiffs
# 
# This script takes one argument:
# 
# Argument 1:   Path to the folder containing the mis-projected JP2 files 

if [ $# -eq 1 ]; then
    echo "Correcting map project of HiRISE images in $PWD:"
else
    echo "Usage: bash $0 [1|str]"
    echo "[1|str] = Path to the folder containing HiRISE images (as JP2 files)"
fi

# Loop through all JP2 files in current
for i in $1*.JP2; do

    # Get the name of the image
    base=`basename $i ".JP2"`

    # Get the Proj4 string for the spatial reference
    str=`gdalsrsinfo -o proj4 $i`
    str_list=($str)

    # Find the standard parallel (lat_ts) and the centre latitude (lat_0)
    lat_ts=${str_list[1]:8}
    lat_0=${str_list[2]:7}

    # Find if lat_0 is non-zero
    if [ $lat_0 -ne 0 ]; then
        
        # Reassign parameter values
        var1="+lat_ts=${lat_0}"
        var2="+lat_0=${lat_ts}"

        # Input new parameter values into Proj4 string
        str_list[1]=$var1
        str_list[2]=$var2
        srs=$(IFS=" " ; echo "${str_list[*]}")

        # Translate .JP2 to GeoTiff and use new projection
        gdal_translate -ot Byte -a_srs "${srs[@]}" -scale $i $1$base.tif
    
    else

        # If lat_0 is zero, just convert to UInt8 GeoTiff
        gdal_translate -ot Byte -a_srs "$str" -scale $i $1$base.tif
    
    fi
done