# Planetary Image Processing

This repository contains several Bash and Python scripts for processing, correcting and map-projecting different sources of planetary remote sensing data. Currently, these sources are Mars Reconnaissance Orbiter (MRO) HiRISE (High Resolution Imaging Science Experiment) and Lunar Reconnaissance Orbiter Narrow Angle Camera (LROC NAC).

These processing scripts may require one or both of the ISIS or GDAL software suites to be installed. A PDF has been provided in this document which gives instructions for how to do this for a Windows OS. However, further instructions for setting up conda environments separately for GDAL and ISIS, or one environment containing both packages, can be found here for [ISIS](https://github.com/DOI-USGS/ISIS3) and here for [GDAL](https://gdal.org/en/stable/download.html).

## Processing Batches of Individual LROC NAC Images

`LROC_NAC_process_and_convert.sh` is a Bash script for processing an entire directory full of raw LROC NAC `.IMG` files, which can be downloaded from NASA's Planetary Data System (PDS). This script performs all of the necessary correction processes, but also converts the map-projected result into a GIS-ready GeoTiff.

By looping over each raw image and then performing every one of steps listed below, the script allows for intermediary files (i.e. everything bar the final GeoTiff) to be deleted as a means of preserving disk space.

* (`lronac2isis`) Conversion from raw image product format (`.IMG`) to an ISIS cube (`.cub`).
* (`spiceinit`) Initialisation of the SPICE kernels using the USGS SPICE web service.
* (`lronaccal`) Radiometric calibration of the raw image digital numbers into I/F.
* (`lronacecho`) Echo-correction to remove repeated lines in the raw image.
* (`cam2map`) Map-projection to place the image correctly on the Moon's surface.
* (`gdal_translate`) Conversion from ISIS cube format into a UInt8 GeoTiff.

## Processing and Mosaicking Multiple LROC NAC Images

### Mosaicking

`LROC_NAC_mosaic_and_convert.sh` is another Bash script which processes, mosaics and converts multiple LROC NAC raw image products into a single GeoTiff. As the command for stitching the images together (`automos`) requires all images to be map-projected ISIS cubes, meaning that every one of the steps listed above have to be performed for every image before moving on to the next step. This script also gives the option for applying photometric correction on the batch of images, using `lronacpho`. The purpose for this is to blend between the overlapping images, and thus lessening the visibility of seams in the mosaic. For this to work, the directory containing the raw images will need to also contain the photometric model in a file called `lronacpho.pvl`, which can be found [here](https://isis.astrogeology.usgs.gov/8.1.0/Application/presentation/PrinterFriendly/lronacpho/lronacpho.html).

### Extracting Mosaicking information

The Python script `extract_tracking.py` can be used to convert the tracking ISIS cube produced when mosaicking LROC NAC images into an ESRI shapefile. The tracking ISIS cube is an image of the same dimensions as the mosaic that records which the source image product for every pixel (as an integer). This requires the extra argument `track=true` when performing the `automos` command above. This added information may be useful for a range of reasons, such as finding the image name of a detection made by a Machine/Deep Learning model.

## Correcting HiRISE Map Projection

For HiRISE images taken before approximately 2018, there is an error in the embedded map projection of MRO HiRISE Reduced Data Record Version 1.1 (RDRV11) which places them at the wrong latitude within GIS suites such as QGIS. `correct_HiRISE.sh` corrects this mis-projection by reading the Proj4 string of the source image and editing it before re-projecting it with the GDAL package. MRO HiRISE RDRV11 images can be downloaded from NASA's PDS as UInt16 JP2 files.

## Other Scripts

Some other scripts are those found in the `old` folder, and another Bash script named `downscale.sh`. The former contains Bash scripts which can perform the processing, mosaicking, or converting steps separately. The latter can re-project already processed GeoTiffs to downscale them with a new resolution.
