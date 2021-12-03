import os
import sys
from datetime import datetime
from webob import Request, Response
from webob.response import ResponseBodyFile
from webapp.MappingCommon import MappingCommon

def application(environ, start_response):
    req = Request(environ)
    res = Response()
    rbf = ResponseBodyFile(res)

    mapc = MappingCommon()

    # Get name of KML to be generated.
    kmlName = req.params['kmlName']

    # Retrieve the central point from the kml_data table.
    mapc.cur.execute("""select x, y from kml_data inner join master_grid using (name) 
            where name = '%s'""" % kmlName)
    (lon, lat) = mapc.cur.fetchone()
    mapc.dbcon.commit()
    lon = float(lon)
    lat = float(lat)
    
    # Accept dlon/dlat from either a request parameter or from the configuration table.
    try:
        dlon = float(req.params['dlon'])
        dlat = float(req.params['dlat'])
    except:
        dlon = float(mapc.getConfiguration('KMLdlon'))
        dlat = float(mapc.getConfiguration('KMLdlat'))
        
    # Compute the 4 corner coordinates of the bounding box.
    ll_lon = lon-dlon
    ll_lat = lat-dlat
    ul_lon = lon-dlon
    ul_lat = lat+dlat
    ur_lon = lon+dlon
    ur_lat = lat+dlat
    lr_lon = lon+dlon
    lr_lat = lat-dlat

    # Substitute the KML name and coordinates in KML template.
    kml = '''<?xml version="1.0" encoding="utf-8" ?>
        <kml xmlns="http://www.opengis.net/kml/2.2">
        <Document><Folder><name>{kml_name}</name>
        <Schema name="{kml_name}" id="{kml_name}">
            <SimpleField name="Name" type="string"></SimpleField>
            <SimpleField name="Description" type="string"></SimpleField>
            <SimpleField name="name" type="string"></SimpleField>
        </Schema>
            <Placemark>
                <name>{kml_name}</name>
                <Style><LineStyle><color>ff0000ff</color></LineStyle><PolyStyle><fill>0</fill></PolyStyle></Style>
                <ExtendedData><SchemaData schemaUrl="#{kml_name}">
                    <SimpleData name="Name">{kml_name}</SimpleData>
                </SchemaData></ExtendedData>
                <Polygon><outerBoundaryIs><LinearRing><coordinates>
                    {ll_lon},{ll_lat} {ul_lon},{ul_lat} {ur_lon},{ur_lat} {lr_lon},{lr_lat} {ll_lon},{ll_lat}
                </coordinates></LinearRing></outerBoundaryIs></Polygon>
            </Placemark>
        </Folder></Document></kml>
    '''.format(
        kml_name=kmlName,
        ll_lon=ll_lon, ll_lat=ll_lat, ul_lon=ul_lon, ul_lat=ul_lat,
        ur_lon=ur_lon, ur_lat=ur_lat, lr_lon=lr_lon, lr_lat=lr_lat
    )
    # Send XML stream back as an HHTP response.
    rbf.writelines(kml)
    res.content_type = 'application/xml'
    return res(environ, start_response)
