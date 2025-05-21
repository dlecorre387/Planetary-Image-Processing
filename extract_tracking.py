'''
Created by Daniel Le Corre (1,2)* 
Last edited on 21/05/2025
1   Centre for Astrophysics and Planetary Science, University of Kent, Canterbury, United Kingdom
2   Centres d'Etudes et de Recherches de Grasse, ACRI-ST, Grasse, France
*   Correspondence: dl387@kent.ac.uk
    Website: https://www.danlecorre.com/
    
This project is part of the Europlanet 2024 RI which has received
funding from the European Union’s Horizon 2020 research and innovation
programme under grant agreement No 871149.

'''

import argparse
import os
import logging
import numpy as np
from osgeo import ogr, gdal, osr

# Use GDAL exceptions
gdal.UseExceptions()

# Set up the logger
logging.basicConfig(level = logging.INFO,
                    format='| %(asctime)s | %(levelname)s | Message: %(message)s',
                    datefmt='%d/%m/%y @ %H:%M:%S')

# Initialise arguments parser
PARSER = argparse.ArgumentParser()

# Relative or absolute path to the directory containing the mosaics
PARSER.add_argument("-i", "--inputdir",
                    type=str,
                    required=True,
                    help="Relative or absolute path to the directory containing the mosaics [type: str]")

# Rotation angles to train on (in deg)
PARSER.add_argument("-m", "--mosaic", 
                    type=str,
                    required=True,
                    help="File name of the mosaic in GeoTiff format to extract the tracking information for [type: str]")

# Range of minimum/maximum values of the tracking image
PARSER.add_argument("-r", "--range",
                    type=int,
                    nargs=2,
                    required=True,
                    help="Minimum/maximum values of the tracking image [type: int]")

# Parse the arguments
ARGS = PARSER.parse_args()

def main(input_dir,  
        mosaic_name,
        range):
    
    # Open the LIS file listing the order that the images were overlaid
    low, high = range
    image_names = []
    with open(os.path.join(input_dir, f"{mosaic_name}.map.lis")) as lines:
        for line in lines:
            image_name = line.split(',')[0].split('.')[0]
            if image_name != "":
                image_names.append(image_name)
    image_names = image_names[low-3:high-2]
                
    logging.info(f"{len(image_names)} images found.")
    
    # Define the driver names for dealing with raster and vector data
    driver1 = gdal.GetDriverByName('GTiff')  
    driver2 = ogr.GetDriverByName("ESRI Shapefile")
    
    # Define the path to the mosaic
    mosaic_path = os.path.join(input_dir, f"{mosaic_name}.tif")
    
    # Open the input mosaic dataset
    mosaic_dataset = gdal.Open(mosaic_path, gdal.GA_ReadOnly)
    
    # Get the geotransform of the mosaic
    geot = mosaic_dataset.GetGeoTransform()
    
    # Get the map projection of the mosaic
    proj = mosaic_dataset.GetProjection()
    
    # Get the spatial reference
    image_srs_wkt = mosaic_dataset.GetProjectionRef()
    image_srs = osr.SpatialReference()
    image_srs.ImportFromWkt(image_srs_wkt)
    
    # Check there is only one raster band
    n_bands = mosaic_dataset.RasterCount 
    assert n_bands == 1
    
    # Get the number of pixels in the x-y direction
    xsize, ysize = mosaic_dataset.RasterXSize, mosaic_dataset.RasterYSize
    
    # Define the path to the mosaic tracking file
    non_proj_path = os.path.join(input_dir, f"{mosaic_name}_tracking.tif")
    
    # Open the mosaic tracking file as an array
    non_proj_dataset = gdal.Open(non_proj_path, gdal.GA_ReadOnly)
    non_proj_band = non_proj_dataset.GetRasterBand(1)
    array = non_proj_band.ReadAsArray()
    
    # Get the unique values of the tracking array and check it is equal to the number of images in LIS file
    unique_image_ids = np.unique(array)
    unique_image_ids = unique_image_ids[unique_image_ids != 0]
    
    # Calculate the original pixel values starting from minimum value, and map them to 1-255
    original_values = np.arange(0, len(image_names)) + low
    norm_values = (original_values - np.amin(original_values)) / (np.amax(original_values) - np.amin(original_values))
    new_values = np.floor((norm_values * (255 - 1)) + 1).astype(int)
    for unique_image_id, new_value, image_name in zip(list(unique_image_ids), list(new_values), image_names):
        print(f"{str(unique_image_id).zfill(3)}/{str(new_value).zfill(3)}      {image_name}")
    
    # Write the array to a geo-referenced GeoTiff
    proj_path = os.path.join(input_dir, f"{mosaic_name}_tracking_projected.tif")
    
    # If the map projected tracking array does not exist
    if not os.path.exists(proj_path):
    
        # Create the new dataset and set the geotransform and projection to that of the mosaic
        proj_dataset = driver1.Create(proj_path, xsize, ysize, 1, gdal.GDT_Byte)
        proj_dataset.SetGeoTransform(geot)
        proj_dataset.SetProjection(proj)
        
        # Write the array to the raster band
        proj_band = proj_dataset.GetRasterBand(1)
        proj_band.SetNoDataValue(np.nan)
        proj_band.WriteArray(array)
        proj_band.FlushCache()
        proj_dataset = proj_band = None
        
    # Open the mosaic tracking file as an array
    proj_dataset = gdal.Open(proj_path, gdal.GA_ReadOnly)
    proj_band = proj_dataset.GetRasterBand(1)
            
    # Define the driver name for dealing with vector data
    driver2 = ogr.GetDriverByName("ESRI Shapefile")
    
    # Define the output spatial reference and the transform for reprojecting
    output_srs = osr.SpatialReference()
    output_srs.ImportFromProj4("+proj=longlat +a=1737400 +b=1737400 +no_defs")
    transform = osr.CoordinateTransformation(image_srs, output_srs)
    
    # Create the shapefile to store polygonised mapping
    dissolved_path = os.path.join(input_dir, f"{mosaic_name}_tracking.shp")

    # Create the output shapefile
    dissolved_ds = driver2.CreateDataSource(dissolved_path)
    dissolved_layer = dissolved_ds.CreateLayer(mosaic_name, srs=output_srs)
    dissolved_layer_defn = dissolved_layer.GetLayerDefn()
    dissolved_field = ogr.FieldDefn("product_id", ogr.OFTString)
    dissolved_layer.CreateField(dissolved_field)
    
    # Create the temporary shapefile for polygonising into
    temp_ds = driver2.CreateDataSource(os.path.join(input_dir, "temp.shp"))
    temp_layer = temp_ds.CreateLayer("temp", srs=image_srs)
    temp_field = ogr.FieldDefn("id", ogr.OFTInteger)
    temp_layer.CreateField(temp_field)
    temp_field_idx = temp_layer.GetLayerDefn().GetFieldIndex("id")
    
    # Polygonise the tracking raster into the temporary shapefile
    gdal.Polygonize(proj_band, proj_band, temp_layer, temp_field_idx, [], callback=None)
    
    # Loop through each unique image used in the mosaic
    for image_id in unique_image_ids:
        
        # Create a multipolygon geometry
        multipolygon_geom = ogr.Geometry(ogr.wkbMultiPolygon)
        
        # Create the new dissolved feature
        new_feature = ogr.Feature(dissolved_layer_defn)
    
        # Filter the temporary layer to get all the polygons with the same image id
        temp_layer.SetAttributeFilter(f"id = {image_id}")
        for feature in temp_layer:
            
            # Get the geometry of the feature
            geom = feature.GetGeometryRef()
            
            # Reproject the geometry
            transform = osr.CoordinateTransformation(image_srs, output_srs)
            new_geom = geom.Clone()
            new_geom.Transform(transform)
            
            # Add the reprojected geometry to the multipolygon
            multipolygon_geom.AddGeometry(new_geom)
        
        # Set the geometry of the dissolved feature
        new_feature.SetGeometry(multipolygon_geom)

        # Set the value of the product_id field
        idx = np.where(new_values == image_id)[0][0]
        new_feature.SetField("product_id", image_names[idx])
            
        # Add the new dissolved feature to the layer
        dissolved_layer.CreateFeature(new_feature)
        new_feature = None
        dissolved_layer.SyncToDisk()
        
    # Close the dataset and layer
    dissolved_ds = dissolved_layer = None
    
    # Remove the temporary layer
    for file in os.listdir(input_dir):
        if file.startswith("temp"):
            os.remove(os.path.join(input_dir, file))
    
if __name__ == "__main__":
    main(ARGS.inputdir,
        ARGS.mosaic,
        ARGS.range)