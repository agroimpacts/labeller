//
// Static variables denoting the order of the drawing tools.
// NOTE: These must be changed if the order of the drawing tools in drawBar is changed.
//
var POLYGON = 0;
var CIRCLE = 1;
var RECTANGLE = 2;
var SQUARE = 3;
var HOLE = 4;
var POINT = 5;

// 
// *** Create control bar ***
//
function addControlBar(map, fieldsLayer, checkSaveStrategy, checkReturnStrategy, gridSource, kmlName, snapTolerance) {
    // JSTS is used to prevent feature overlaps.
    var jstsParser = new jsts.io.OL3Parser();
    var geomFactory = new jsts.geom.GeometryFactory();
    var LI = new jsts.algorithm.RobustLineIntersector();

    // Check for self-intersection.
    // Used in polygon/polygon-hole 'condition' and 'finishCondition' clauses, and for 'modifyend' processing.
    function hasSelfIntersection(geom, closed=false) {
        // Only applies to quadrilaterals or greater.
        if (geom && geom.getLinearRing(0).getCoordinates().length >= 5) {
            // Convert to JSTS geometry and coordinates.
            var jsts_geom = jstsParser.read(geom);
            var jsts_coords = jsts_geom.getCoordinates();
            //console.log(jsts_coords);
            // Remove any adjacent duplicate coordinates (caused by closing shape).
            uniqCoords = [];
            for (i = 0; i < jsts_coords.length - 1; i++) {
                if (!(jsts_coords[i].x == jsts_coords[i + 1].x &&
                        jsts_coords[i].y == jsts_coords[i + 1].y)) {
                    uniqCoords.push(jsts_coords[i]);
                }
            }
            // Don't include the last (same as first) coordinate if shape not yet closed.
            // This will prevent the inclusion of the virtual segment formed by the last
            // point drawn and the first point drawn in the intersection check. This
            // virtual segment will keep changing until the shape is completed.
            if (closed) {
                uniqCoords.push(jsts_coords[jsts_coords.length - 1]);
            }
            //console.log(uniqCoords);
            // Check all non-adjacent segments for intersection.
            //  If any intersect, then report back self-intersection.
            for (i = 0; i < uniqCoords.length - 3; i++) {
                for (j = i + 2; j < uniqCoords.length - 1; j++) {
                    // If closed shape, don't compare first and last segments
                    // since they are effectively adjacent.
                    if (!(closed && (i == 0 && j == (uniqCoords.length - 2)))) {
                        selfIntersects = LI.hasIntersection(LI.computeIntersection(
                            uniqCoords[i],
                            uniqCoords[i + 1],
                            uniqCoords[j],
                            uniqCoords[j +1]
                        ));
                        console.log("hasSelfIntersection: " + i + "-" + j + ": " + selfIntersects);
                        if (selfIntersects) {
                            return true;
                        }
                    }
                }
            }
            console.log("hasSelfIntersection: false");
            return false;
        }
    }

    // Check for self-intersection within each ring of a polygon.
    // Create a set of single-ring polygons from the pre-existing polygon.
    // Used with multi-ring polygons for 'modifyend' processing.
    function hasInternalSelfIntersection(mrPolygon) {
        // Ring 0 is the outer ring; rings 1 through N are inner rings.
        for (var i = 0; i < mrPolygon.getLinearRingCount(); i++) {
            iLinearRing = mrPolygon.getLinearRing(i);
            srPolygon = new ol.geom.Polygon([iLinearRing.getCoordinates()]);
            console.log(srPolygon.getCoordinates());
            // Check this ring for self-intersections.
            if (hasSelfIntersection(srPolygon, true)) {
                return true;
            }
        }
        return false;
    }

    // Check most-recent drawn segment against all other shapes on the canvas for any intersection.
    // Used in polygon 'condition' clause.
    function hasLastSegmentIntersection(geom) {
        // Create array of JSTS geometries for all features on the canvas.
        var features = fieldsLayer.getSource().getFeatures();
        var jsts_geomSet = [];
        for (var f in features) {
            var feature = features[f];
            var jsts_featureGeom = jstsParser.read(feature.getGeometry());
            // Add this feature to the array.
            jsts_geomSet = jsts_geomSet.concat(jsts_featureGeom);
        }
        // Compare last polygon segment drawn to the segments of all shapes on the canvas.
        return hasLastSegmentIntersectionWithSet(geom, jsts_geomSet, -1);
    }

    // Check most-recent drawn segment against all rings associated with the polygon for any intersection.
    // Used in DrawHole 'condition' clause.
    function hasLastSegmentInternalIntersection(origPolygon, geom) {
        if (!origPolygon) {
            return false;
        }
        // Create array of single-ring polygons for all of origPolygon's rings.
        var jsts_geomSet = [];
        // Convert to JSTS geometry and coordinates.
        var jsts_origGeom = jstsParser.read(origPolygon);
        // Make origPolygon's exterior ring into a single-ring polygon.
        var oCoords = jsts_origGeom.getExteriorRing().getCoordinates();
        var oPolygon = geomFactory.createPolygon(oCoords);
        console.log(oPolygon.getCoordinates());
        // Add this polygon to the array.
        jsts_geomSet = jsts_geomSet.concat(oPolygon);

        // Create single-ring polygons for origPolygon's inner rings.
        for (i = 0; i < jsts_origGeom.getNumInteriorRing(); i++) {
            var iCoords = jsts_origGeom.getInteriorRingN(i).getCoordinates(); 
            var iPolygon = geomFactory.createPolygon(iCoords);
            console.log(iPolygon.getCoordinates());
            // Add this polygon to the array.
            jsts_geomSet = jsts_geomSet.concat(iPolygon);
        }
        // Compare last polygon segment drawn to the segments of all origPolygon rings.
        return hasLastSegmentIntersectionWithSet(geom, jsts_geomSet, +1);
    }

    function hasLastSegmentIntersectionWithSet(geom, jsts_geomSet, buffer) {
        if (!(geom && geom.getLinearRing(0).getCoordinates().length >= 3)) {
            return false;
        }
        // If drawing first segment, handle as special case
        // since JSTS considers this an invalid geometry.
        if (geom.getLinearRing(0).getCoordinates().length == 3) {
            var coords = geom.getLinearRing(0).getCoordinates();
            uniqCoords = [];
            uniqCoords.push(new jsts.geom.Coordinate(coords[0][0], coords[0][1]));
            uniqCoords.push(new jsts.geom.Coordinate(coords[1][0], coords[1][1]));
            i = 0;
        // Convert polygon being drawn to JSTS geometry and coordinates.
        } else if (geom.getLinearRing(0).getCoordinates().length >= 4) {
            var jsts_geom = jstsParser.read(geom);
            var jsts_coords = jsts_geom.getCoordinates();
            // Remove any adjacent duplicate coordinates (caused by closing shape).
            // Also leave off final duplicate coordinate.
            uniqCoords = [];
            for (i = 0; i < jsts_coords.length - 1; i++) {
                if (!(jsts_coords[i].x == jsts_coords[i + 1].x &&
                        jsts_coords[i].y == jsts_coords[i + 1].y)) {
                    uniqCoords.push(jsts_coords[i]);
                }
            }
            // Specify the index of the last segment's starting coordinate.
            i = uniqCoords.length - 2;
        }
        // Compare last polygon segment drawn to the segments of all shapes in the set.
        var resolution = map.getView().getResolution();
        for (var f in jsts_geomSet) {
            var jsts_featureGeom = jsts_geomSet[f];
            // Create a negative 1-pixel buffer to allow for border sharing.
            var jsts_bufGeom = jsts_featureGeom.buffer(parseFloat(buffer) * resolution);
            // Note that buffering may result in multiple geometries for wasp-waisted polygons.
            // Look for intersections within each sub-geometry.
            for (g = 0; g < jsts_bufGeom.getNumGeometries(); g++) {
                jsts_bufSubGeom = jsts_bufGeom.getGeometryN(g);
                var jsts_bufCoords = jsts_bufSubGeom.getExteriorRing().getCoordinates();
                for (j = 0; j < jsts_bufCoords.length - 1; j++) {
                    intersects = LI.hasIntersection(LI.computeIntersection(
                        uniqCoords[i],
                        uniqCoords[i + 1],
                        jsts_bufCoords[j],
                        jsts_bufCoords[j +1]
                    ));
                    if (intersects) {
                        console.log("hasLastSegmentIntersectionWithSet: seg " + i + "-> feature " + f + ":seg " + j + ": true");
                        return true;
                    }
                }
            }
        }
        console.log("hasLastSegmentIntersectionWithSet: false");
        return false;
    }

    // Used in all Draw tool 'condition' clauses (except DrawHole) for point overlap testing.
    function pointOverlapCheck(event) {
        var feature = getClickFeature(event, 0);

        // If we found an overlap, check to see if it's inside the feature's boundary.
        // If it's only on the border, we return true to allow adding the vertex.
        if (feature) {
            // Create JSTS geometries for the click coordinates and the feature it overlaps with.
            var jsts_point = geomFactory.createPoint(
                new jsts.geom.Coordinate(event.coordinate[0], event.coordinate[1])
            );
            var jsts_feature = jstsParser.read(feature.getGeometry());
            // Create a negative 1-pixel buffer to allow for border sharing.
            var resolution = map.getView().getResolution();
            jsts_feature = jsts_feature.buffer(-resolution);
            // See if the point overlaps with the buffered feature.
            // Return the negation (false if it is contained); true otherwise.
            // Returning false will prevent adding the point.
            var contains = jsts_feature.contains(jsts_point);
            console.log("pointOverlapCheck: contains: " + contains);
            return !contains;
        }
        // No overlap: add the vertex.
        console.log("pointOverlapCheck: true");
        return true;
    };

    //Used by Point 'condition' clause to ensure points being drawn in bounding box
    function pointInGridCheck(event){
        // Create JSTS geometries for the click coordinates and the feature it overlaps with.
        var grid = gridSource.getFeatureById(0);
	var jsts_point = geomFactory.createPoint(
	    new jsts.geom.Coordinate(event.coordinate[0], event.coordinate[1])
	);
	var jsts_grid = jstsParser.read(grid.getGeometry());
	// Create a negative 1-pixel buffer to allow for border sharing.
       	var resolution = map.getView().getResolution();
	jsts_grid = jsts_grid.buffer(-resolution);
	// See if the point overlaps with the buffered feature.
	// Return the negation (true if it is contained); false otherwise.
	// Returning false will prevent adding the point.
	var contains = jsts_grid.contains(jsts_point);
	console.log("pointInGridCheck: contains: " + contains);
	return contains;
    };

    // Used by Point 'condition' clause to ensure limited number of points drawn at one time
    function featureLimitCheck(event, limit){
    	// get number of features in fields layer
    	var featureCount = fieldsLayer.getSource().getFeatures().length;
	// See if there's one feature left to reach the limit
	// Return the negation (true if no features; false otherwise).
	// Returning false wll prevent adding the point
	var reachLimit = featureCount == limit - 1;
	console.log("featureLimitCheck: ", reachLimit); 
	return reachLimit;
    };

    // Used by DrawHole 'condition' clause to ensure points being drawn do not overlap
    // with other outer and inner rings.
    function pointInternalOverlapCheck(event) {
        var feature = getClickFeature(event, 0);

        // If we found an overlap, check to see if it's truly inside the outer or inner ring's 
        // boundary. If it's on the border, we return false to prevent adding the vertex.
        if (feature) {
            // Create JSTS geometries for the click coordinates and the feature it overlaps with.
            var jsts_point = geomFactory.createPoint(
                new jsts.geom.Coordinate(event.coordinate[0], event.coordinate[1])
            );
            console.log(jsts_point.getCoordinates());
            // Create a *positive* 1-pixel buffer to prevent border sharing.
            var resolution = map.getView().getResolution();
            jsts_bufPoint = jsts_point.buffer(resolution);
            var jsts_feature = jstsParser.read(feature.getGeometry());
            //console.log(jsts_feature.getCoordinates());
            // See if the buffered point overlaps with the feature.
            // Return the status (true if it is contained); false otherwise.
            var contains = jsts_feature.contains(jsts_bufPoint);
            console.log("pointInternalOverlapCheck: contains: " + contains);
            return contains;
        }
        // No overlap: don't add the vertex.
        console.log("pointInternalOverlapCheck: false");
        return false;
    };

    // Function to return feature at click event.
    // Used by pointOverlapCheck() and pointInternalOverlapCheck().
    function getClickFeature(event, clickTolerance) {
        var features = map.getFeaturesAtPixel(
            event.pixel, 
            {
                // Only check the fieldsLayer for overlaps.
                layerFilter: function(layer) {
                    if (layer.getZIndex() == 101) {
                        return true;
                    }
                    return false;
                },
                hitTolerance: clickTolerance
            }
        );
        // Return the feature's starting coordinates if there's only one.
        if (features && features.length == 1) {
            console.log("getClickFeature: 1 feature at pixel.");
            return features[0];
        } else {
            if (!features) {
                console.log("getClickFeature: No feature at pixel.");
            } else {
                console.log("getClickFeature: " + features.length + " feature(s) at pixel.");
            }
            return undefined;
        }
    };

    // Function to check if specified geometry overlaps with other existing features.
    // Used in all Draw tool 'finishCondition' clauses (except for DrawHole), 
    // 'modifyend' processing, and 'translateend' processing.
    function hasOverlap(geom) {
        var jsts_geom = jstsParser.read(geom);
        // Create a negative 1-pixel buffer to allow for border sharing.
        var resolution = map.getView().getResolution();
        jsts_geomBuf = jsts_geom.buffer(-resolution);
        var features = fieldsLayer.getSource().getFeatures();
        for (var i in features) {
            var feature = features[i];
            var jsts_featureGeom = jstsParser.read(feature.getGeometry());
            try {
                // Don't compare to feature being modified.
                if (jsts_geom.equals(jsts_featureGeom)) {
                    continue;
                }
                if (jsts_geomBuf.intersects(jsts_featureGeom)) {
                    console.log("hasOverlap: feature intersects.");
                    return true;
                }
            } catch (e) {
                if (e.name == "TopologyException") {
                    console.log(e.name + ": " + e.message);
                    console.log("hasOverlap: feature intersects.");
                    return true;
                } else {
                    throw e;
                }
            }
        }
        console.log("hasOverlap: feature does not intersect.");
        return false;
    };

    // Check that outer ring and inner ring(s) don't intersect with one another.
    // Must be a 1-pixel buffer separation between rings.
    // Create a set of single-ring polygons from the multi-ring polygon.
    // Used with multi-ring polygons for 'modifyend' processing.
    function hasInternalOverlap_Modify(mrPolygon) {
        // Ring 0 is the outer ring; rings 1 through N are inner rings.
        for (var i = 1; i < mrPolygon.getLinearRingCount(); i++) {
            iLinearRing = mrPolygon.getLinearRing(i);
            srPolygon = new ol.geom.Polygon([iLinearRing.getCoordinates()]);
            console.log("hasInternalOverlap_Modify");
            console.log(srPolygon.getCoordinates());
            // Check this ring for overlap with other rings.
            if (hasInternalOverlap(mrPolygon, srPolygon)) {
                return true;
            }
        }
        return false;
    }

    // Check that outer ring and inner ring(s) don't intersect with one another.
    // Must be a 1-pixel buffer separation between rings.
    // Create a set of single-ring polygons from the pre-existing polygon (1st argument).
    // Used in DrawHole finishCondition clause.
    function hasInternalOverlap(origPolygon, geom) {
        // Convert to JSTS geometry and coordinates.
        var jsts_origPolygon = jstsParser.read(origPolygon);
        var jsts_geom = jstsParser.read(geom);
        console.log("hasInternalOverlap");
        console.log(jsts_geom.getCoordinates());
        // Now, create a *positive* 1-pixel buffer around the inner polygon being drawn.
        // This is to prevent border-sharing with the outer polygon and other inner polygons.
        var resolution = map.getView().getResolution();
        var jsts_bufGeom = jsts_geom.buffer(resolution);

        // Then, make origPolygon's exterior ring into a single-ring polygon.
        // First check the exterior ring of the polygon.
        var oCoords = jsts_origPolygon.getExteriorRing().getCoordinates();
        var oPolygon = geomFactory.createPolygon(oCoords);
        console.log(oPolygon.getCoordinates());
        // Check if it contains the buffered hole-polygon being drawn.
        contains = oPolygon.contains(jsts_bufGeom);
        console.log("contains: " + contains);
        if (!contains) {
            console.log("hasInternalOverlap: outer contains buffered inner: false");
            return true;
        }
        // Create array of single-ring polygons for origPolygon's inner rings.
        for (var i = 0; i < jsts_origPolygon.getNumInteriorRing(); i++) {
            var iCoords = jsts_origPolygon.getInteriorRingN(i).getCoordinates(); 
            var iPolygon = geomFactory.createPolygon(iCoords);
            console.log(iPolygon.getCoordinates());
            // Don't compare to feature being modified.
            if (iPolygon.equals(jsts_geom)) {
                console.log("skipped identical inner ring");
                continue;
            }
            // Check if it intersects the buffered hole-polygon being drawn.
            var intersects = iPolygon.intersects(jsts_bufGeom);
            console.log("intersects: " + intersects);
            if (intersects) {
                console.log("hasInternalOverlap: inner intersects buffered inner: true");
                return true;
            }
        }
        console.log("hasInternalOverlap: false");
        return false;
    }

    // Create new control bar and add it to the map.
    var mainbar = new ol.control.Bar({
        autoDeactivate: true,   // deactivate controls in bar when parent control off
        toggleOne: true,	    // one control active at the same time
        group: false	        // group controls together
    });
    mainbar.setPosition("top-right");
    map.addControl(mainbar);

    // Add editing tools to the editing sub control bar
    var drawBar = new ol.control.Bar({
        toggleOne: true,    	// one control active at the same time
        autoDeactivate: true,   // deactivate controls in bar when parent control off
        group: false		    // group controls together
    });
    var polyGeom = undefined;
    var polyGeomDone = false;
    drawBar.addControl( new ol.control.Toggle({
        html: '<i class="icon-polygon-o" ></i>',
        title: 'Polygon creation: Click at each corner of field; press ESC key to remove most recent corner. Double-click to complete field.',
        autoActivate: true,
        interaction: new ol.interaction.Draw({
            type: 'Polygon',
            features: fieldsLayer.getSource().getFeaturesCollection(),
            // Store the geometry being currently drawn for use by the finishCondition.
            // NOTE: 'geometryFunction' is always called *after* 'condition' and 'finishCondition'.
            geometryFunction: function(coords, intPolyGeom) {
                // intPolyGeom is undefined initially, after the completion of the finishCondition, 
                // and when this interaction is deactivated.
                if (!intPolyGeom) {
                    intPolyGeom = new ol.geom.Polygon(null);
                }
                // Close the polygon each time we come through here.
                drawCoords = coords[0].slice();
                if (drawCoords.length > 0) {
                    drawCoords.push(drawCoords[0].slice());
                }
                intPolyGeom.setCoordinates([drawCoords]);
                // If we're done with a shape, undefine polyGeom.
                if (polyGeomDone) {
                    polyGeom = undefined;
                    polyGeomDone = false;
                } else{
                    polyGeom = intPolyGeom;
                }
                return intPolyGeom;
            },
            // Check for feature overlap on each click.
            condition: function(event) {
                if (hasSelfIntersection(polyGeom)) {
                    return false;
                }
                if (hasLastSegmentIntersection(polyGeom)) {
                    return false;
                }
                return pointOverlapCheck(event);
            },
            // Check that currently drawn geometry doesn't overlap any previously drawn feature.
            finishCondition: function(event) {
                if (hasSelfIntersection(polyGeom, true)) {
                    // Remove last point.
                    var ctrl = drawBar.getControls()[POLYGON];
                    ctrl.getInteraction().removeLastPoint();
                    return false;
                }
                if (hasOverlap(polyGeom)) {
                    // Remove last point.
                    var ctrl = drawBar.getControls()[POLYGON];
                    ctrl.getInteraction().removeLastPoint();
                    return false;
                }
                // Prepare for re-use. 'intPolyGeom' is undefined the first time 'condition'
                // is called, so polyGeom will not get reset until afterward.
                polyGeomDone = true;
                return true;
            },
            style: new ol.style.Style({
                fill: new ol.style.Fill({
                    color: 'rgba(255, 255, 255, 0.2)',
                }),
                stroke: new ol.style.Stroke({
                    color: 'rgba(0, 153, 255, 1.0)',
                    width: 2
                }),
                image: new ol.style.Circle({
                    radius: 7,
                    fill: new ol.style.Fill({
                        color: 'rgba(0, 153, 255, 0.5)'
                    })
                })
            })
        })
    }));
    drawBar.getControls()[POLYGON].getInteraction().on('change:active', function(e) {
        console.log("POLYGON interaction changed active state: " + e.target.getActive());
        if (!e.target.getActive()) {
            polyGeom = undefined;
        }
    });
    var circleGeom = undefined;
    var circleGeomDone = false;
    drawBar.addControl( new ol.control.Toggle({
        html: '<i class="icon-circle-thin" ></i>',
        title: 'Circle creation: Click at center of field; slide mouse to expand and click when done.',
        interaction: new ol.interaction.Draw({
            type: 'Circle',
            features: fieldsLayer.getSource().getFeaturesCollection(),
            geometryFunction: function(coords, intCircleGeom) {
                func = ol.interaction.Draw.createRegularPolygon();
                intCircleGeom = func(coords, intCircleGeom);
                // If we're done with a shape, undefine circleGeom.
                if (circleGeomDone) {
                    circleGeom = undefined;
                    circleGeomDone = false;
                } else{
                    circleGeom = intCircleGeom;
                }
                return intCircleGeom;
            },
            // Check for feature overlap on each click.
            condition: function(event) {
                return pointOverlapCheck(event);
            },
            // Check that currently drawn geometry doesn't overlap any previously drawn feature.
            // NOTE: Requires a specially patched version of OpenLayers v4.6.5.
            finishCondition: function(event) {
                if (hasOverlap(circleGeom)) {
                    return false;
                }
                // Prepare for re-use. 'intCircleGeom' is undefined the first time 'condition'
                // is called, so circleGeom will not get reset until afterward.
                circleGeomDone = true;
                return true;
            },
            style: new ol.style.Style({
                fill: new ol.style.Fill({
                    color: 'rgba(255, 255, 255, 0.2)',
                }),
                stroke: new ol.style.Stroke({
                    color: 'rgba(0, 153, 255, 1.0)',
                    width: 2
                }),
                image: new ol.style.Circle({
                    radius: 7,
                    fill: new ol.style.Fill({
                        color: 'rgba(0, 153, 255, 0.5)'
                    })
                })
            })
        })
    }));
    drawBar.getControls()[CIRCLE].getInteraction().on('change:active', function(e) {
        console.log("CIRCLE interaction changed active state: " + e.target.getActive());
        if (!e.target.getActive()) {
            circleGeom = undefined;
        }
    });
    var rectGeom = undefined;
    var rectGeomDone = false;
    drawBar.addControl( new ol.control.Toggle({
        html: '<i class="icon-rectangle-o" ></i>',
        title: 'Rectangle creation: Click at corner of field; slide mouse to expand and click when done.',
        interaction: new ol.interaction.Draw({
            type: 'Circle',
            features: fieldsLayer.getSource().getFeaturesCollection(),
            geometryFunction: function(coords, intRectGeom) {
                func = ol.interaction.Draw.createBox();
                intRectGeom = func(coords, intRectGeom);
                // If we're done with a shape, undefine rectGeom.
                if (rectGeomDone) {
                    rectGeom = undefined;
                    rectGeomDone = false;
                } else{
                    rectGeom = intRectGeom;
                }
                return intRectGeom;
            },
            // Check for feature overlap on each click.
            condition: function(event) {
                return pointOverlapCheck(event);
            },
            // Check that currently drawn geometry doesn't overlap any previously drawn feature.
            // NOTE: Requires a specially patched version of OpenLayers v4.6.5.
            finishCondition: function(event) {
                if (hasOverlap(rectGeom)) {
                    return false;
                }
                // Prepare for re-use. 'intRectGeom' is undefined the first time 'condition'
                // is called, so rectGeom will not get reset until afterward.
                rectGeomDone = true;
                return true;
            },
            style: new ol.style.Style({
                fill: new ol.style.Fill({
                    color: 'rgba(255, 255, 255, 0.2)',
                }),
                stroke: new ol.style.Stroke({
                    color: 'rgba(0, 153, 255, 1.0)',
                    width: 2
                }),
                image: new ol.style.Circle({
                    radius: 7,
                    fill: new ol.style.Fill({
                        color: 'rgba(0, 153, 255, 0.5)'
                    })
                })
            })
        })
    }));
    drawBar.getControls()[RECTANGLE].getInteraction().on('change:active', function(e) {
        console.log("RECTANGLE interaction changed active state: " + e.target.getActive());
        if (!e.target.getActive()) {
            rectGeom = undefined;
        }
    });
    var squareGeom = undefined;
    var squareGeomDone = false;
    drawBar.addControl( new ol.control.Toggle({
        html: '<i class="icon-square-o" ></i>',
        title: 'Square creation: Click at center of field; slide mouse to expand and click when done.',
        interaction: new ol.interaction.Draw({
            type: 'Circle',
            features: fieldsLayer.getSource().getFeaturesCollection(),
            geometryFunction: function(coords, intSquareGeom) {
                func = ol.interaction.Draw.createRegularPolygon(4);
                intSquareGeom = func(coords, intSquareGeom);
                // If we're done with a shape, undefine squareGeom.
                if (squareGeomDone) {
                    squareGeom = undefined;
                    squareGeomDone = false;
                } else{
                    squareGeom = intSquareGeom;
                }
                return intSquareGeom;
            },
            // Check for feature overlap on each click.
            condition: function(event) {
                return pointOverlapCheck(event);
            },
            // Check that currently drawn geometry doesn't overlap any previously drawn feature.
            // NOTE: Requires a specially patched version of OpenLayers v4.6.5.
            finishCondition: function(event) {
                if (hasOverlap(squareGeom)) {
                    return false;
                }
                // Prepare for re-use. 'intSquareGeom' is undefined the first time 'condition'
                // is called, so squareGeom will not get reset until afterward.
                squareGeomDone = true;
                return true;
            },
            style: new ol.style.Style({
                fill: new ol.style.Fill({
                    color: 'rgba(255, 255, 255, 0.2)',
                }),
                stroke: new ol.style.Stroke({
                    color: 'rgba(0, 153, 255, 1.0)',
                    width: 2
                }),
                image: new ol.style.Circle({
                    radius: 7,
                    fill: new ol.style.Fill({
                        color: 'rgba(0, 153, 255, 0.5)'
                    })
                })
            })
        })
    }));
    drawBar.getControls()[SQUARE].getInteraction().on('change:active', function(e) {
        console.log("SQUARE interaction changed active state: " + e.target.getActive());
        if (!e.target.getActive()) {
            squareGeom = undefined;
        }
    });
    var holeGeom = undefined;
    var holeGeomDone = false;
    drawBar.addControl( new ol.control.Toggle({
        html: '<i class="icon-stop-circled" ></i>',
        title: 'Polygon Hole creation: Click at each corner of field; press ESC key to remove most recent corner. Double-click to complete field.',
        interaction: new ol.interaction.DrawHole({
            // Use a layer filter to select the fieldsLayer only.
            layers: function(layer) {
                if (layer.getZIndex() == 101) {
                    return true;
                }
                return false;
            },
            // Store the geometry being currently drawn for use by condition and  finishCondition.
            geometryFunction: function(coords, intHoleGeom) {
                // Unlike the OL draw tools, this ol-ext DrawHole tool does not undefine intHoleGeom
                // when this interaction is deactivated. So we undefine it here when the
                // external holeGeom is undefined by the listener below.
                if (!holeGeom) {
                    intHoleGeom = undefined;
                }
                if (!intHoleGeom) {
                    intHoleGeom = new ol.geom.Polygon(null);
                }
                // Close the polygon each time we come through here.
                drawCoords = coords[0].slice();
                if (drawCoords.length > 0) {
                    drawCoords.push(drawCoords[0].slice());
                }
                intHoleGeom.setCoordinates([drawCoords]);
                // If we're done with a shape, undefine holeGeom.
                if (holeGeomDone) {
                    holeGeom = undefined;
                    holeGeomDone = false;
                } else{
                    holeGeom = intHoleGeom;
                }
                return intHoleGeom;
            },
            // Check for feature overlap on each click.
            condition: function(event) {
                console.log("DrawHole: condition");
                if (hasSelfIntersection(holeGeom)) {
                    return false;
                }
                origPolygon = drawBar.getControls()[HOLE].getInteraction().getPolygon();
                if (hasLastSegmentInternalIntersection(origPolygon, holeGeom)) {
                    return false;
                }
                return pointInternalOverlapCheck(event);
            },
            // Check that currently drawn geometry doesn't overlap any previously drawn feature.
            finishCondition: function(event) {
                console.log('DrawHole: finishCondition');
                if (hasSelfIntersection(holeGeom, true)) {
                    // Remove last point.
                    var ctrl = drawBar.getControls()[HOLE];
                    ctrl.getInteraction().removeLastPoint();
                    return false;
                }
                origPolygon = drawBar.getControls()[HOLE].getInteraction().getPolygon();
                if (hasInternalOverlap(origPolygon, holeGeom)) {
                    return false;
                }
                // Prepare for re-use. 'intHoleGeom' is undefined the first time 'condition'
                // is called, so holeGeom will not get reset until afterward.
                holeGeomDone = true;
                return true;
            },
            style: new ol.style.Style({
                fill: new ol.style.Fill({
                    color: 'rgba(255, 255, 255, 0.2)',
                }),
                stroke: new ol.style.Stroke({
                    color: 'rgba(0, 153, 255, 1.0)',
                    width: 2
                }),
                image: new ol.style.Circle({
                    radius: 7,
                    fill: new ol.style.Fill({
                        color: 'rgba(0, 153, 255, 0.5)'
                    })
                })
            })
        })
    }));
    drawBar.getControls()[HOLE].getInteraction().on('change:active', function(e) {
        console.log("HOLE interaction changed active state: " + e.target.getActive());
        if (!e.target.getActive()) {
            holeGeom = undefined;
        }
    });
    drawBar.addControl( new ol.control.Toggle({
        html: '<i class="icon-dot" ></i>',
        title: 'Point creation: Click on map at desired location.',
        interaction: new ol.interaction.Draw({
            type: 'Point',
            features: fieldsLayer.getSource().getFeaturesCollection(),
            // Check for feature overlap on each click.
            condition: function(event) {
		if (!pointInGridCheck(event)){
		    return false;
		}
		if (!featureLimitCheck(event, 1)) {
		    return false;
		}
		return pointOverlapCheck(event);
            },
            style: new ol.style.Style({
                fill: new ol.style.Fill({
                    color: 'rgba(255, 255, 255, 0.2)',
                }),
                stroke: new ol.style.Stroke({
                    color: 'rgba(0, 153, 255, 1.0)',
                    width: 2
                }),
                image: new ol.style.Circle({
                    radius: 7,
                    fill: new ol.style.Fill({
                        color: 'rgba(0, 153, 255, 0.5)'
                    })
                })
            })
        })
    }));
    // Add drawing sub control bar to the drawButton control
    var drawButton = new ol.control.Toggle({
        html: '<i class=" icon-draw" ></i>',
        title: 'To create mapped fields, click on one of the tools to the left.',
        autoActivate: true, // activate controls in bar when parent control on
        active: true,
        bar: drawBar
    });
    mainbar.addControl(drawButton);

    // Remove last drawn vertex when Esc key pressed.
    document.addEventListener('keydown', function(event) {
        if (event.which == 27) {
            // Ensure that the polygon or polygon-hole drawing control is currently active.
            var ctrl = drawBar.getControls()[POLYGON];
            if (ctrl.getActive()) {
                // If so, remove its last drawn vertex.
                ctrl.getInteraction().removeLastPoint();
            }
            var ctrl = drawBar.getControls()[HOLE];
            if (ctrl.getActive()) {
                // If so, remove its last drawn vertex.
                ctrl.getInteraction().removeLastPoint();
            }
        }
    });

    // Add the new drag interaction. It will be active in edit mode only.
    // Interaction must be added before the Modify interaction below so 
    // that they will allow both editing and dragging.
    var dragInteraction = new ol.interaction.Translate({
        layers: function (layer) {
            // If it's the fieldsLayer and we are in edit mode, allow dragging.
            if (layer.getZIndex() == 101 && editButton.getActive()) {
                return true;
            }
            // Otherwise, no dragging allowed.
            return false;
        }
    });
    map.addInteraction(dragInteraction);
 
    // Prevent overlap while dragging.
    // Save the feature being dragged's initial coordinates at the start.
    var translateCoords;
    dragInteraction.on('translatestart', function(event) {
        // Save the current feature's starting coordinates.
        if (event.features.getArray().length == 1) {
            var modifyFeature = event.features.getArray()[0];
            translateCoords = modifyFeature.getGeometry().getCoordinates().slice();
            //translateCoords = [...modifyFeature.getGeometry().getCoordinates()];
            //translateCoords = new Array(modifyFeature.getGeometry().getCoordinates());
            console.log("translatestart");
            console.log(translateCoords);
        }
    });
    // At the end, compare the feature being dragged (with a 1-pixel negative buffer)
    // to all other features. If any intersect, restore the coordinates of the
    // feature being dragged to its saved starting coordinates.
    dragInteraction.on('translateend', function(event) {
        if (event.features.getArray().length == 1) {
            var modifyFeature = event.features.getArray()[0];
            console.log("translateend");
            console.log(modifyFeature.getGeometry().getCoordinates());
            // If current feature intersects with another feature,
            // restore current feature to pre-modification coordinates.
            if (hasOverlap(modifyFeature.getGeometry())) {
                modifyFeature.getGeometry().setCoordinates(translateCoords);
            }
        }
    });

    // Add edit tool.
    // NOTE: It needs to follow the Draw tools and drag interaction to ensure Modify tool processes clicks first.
    var editButton = new ol.control.Toggle({
        html: '<i class=" icon-edit" ></i>',
        title: 'To edit any mapped field, drag center of field to move it; drag any border line to stretch it; shift-click on any field corner to delete vertex.',
        interaction: new ol.interaction.Modify({
            features: fieldsLayer.getSource().getFeaturesCollection(),
            // Snap interaction is doing the heavy lifting here. So we only need a pixelTolerance
            // of 1 because 0 causes the edge detection of the modify interaction not to work.
            pixelTolerance: 1,
            // The SHIFT key must be pressed to delete vertices, so that new
            // vertices can be drawn at the same position as existing vertices.
            deleteCondition: function(event) {
                return ol.events.condition.shiftKeyOnly(event) &&
                ol.events.condition.singleClick(event);
            },
            style: new ol.style.Style({
                image: new ol.style.Circle({
                    radius: 7,
                    fill: new ol.style.Fill({
                        color: '#ffcc33'
                    }),
                    stroke: new ol.style.Stroke({
                        color: 'white',
                        width: 2
                    })
                })
            }) 
        })
    });
    mainbar.addControl(editButton);

    // Prevent overlap during modifications.
    // Save the feature being modified's initial coordinates at the start.
    // NOTE: Requires a specially patched version of OpenLayers v4.6.5.
    var modifyCoords;
    editButton.getInteraction().on('modifystart', function(event) {
        // Save the current feature's starting coordinates.
        if (event.features.getArray().length == 1) {
            var modifyFeature = event.features.getArray()[0];
            modifyCoords = modifyFeature.getGeometry().getCoordinates().slice();
            //modifyCoords = [...modifyFeature.getGeometry().getCoordinates()];
            //modifyCoords = new Array(modifyFeature.getGeometry().getCoordinates());
            console.log("modifystart");
        }
    });
    // At the end, compare the feature being modified (with a 1-pixel negative buffer)
    // to all other features. If any intersect, restore the coordinates of the
    // feature being modified to its saved starting coordinates.
    // NOTE: Requires a specially patched version of OpenLayers v4.6.5.
    editButton.getInteraction().on('modifyend', function(event) {
        if (event.features.getArray().length == 1) {
            var modifyFeature = event.features.getArray()[0];
            console.log("modifyend");
            // If current feature self-intersects,
            // restore current feature to pre-modification coordinates.
            if (hasInternalSelfIntersection(modifyFeature.getGeometry())) {
                modifyFeature.getGeometry().setCoordinates(modifyCoords);
                return;
            }
            // If current feature has an internal between-rings intersection.
            if (hasInternalOverlap_Modify(modifyFeature.getGeometry())) {
                modifyFeature.getGeometry().setCoordinates(modifyCoords);
                return;
            }
            // If current feature intersects with another feature,
            // restore current feature to pre-modification coordinates.
            if (hasOverlap(modifyFeature.getGeometry())) {
                modifyFeature.getGeometry().setCoordinates(modifyCoords);
                return;
            }
        }
    });

    // Add selection tool (a toggle control with a select interaction)
    var delBar = new ol.control.Bar();

    delBar.addControl( new ol.control.Toggle({
        html: '<i class="icon-delete-o"></i>',
        title: "Click this button to delete selected mapped field(s).",
        className: "noToggle",
        onToggle: function() {
            var features = selectButton.getInteraction().getFeatures();
            if (!features.getLength()) alert("Please click on one or more mapped fields to select for deletion first.");
            for (var i=0, f; f=features.item(i); i++) {
                fieldsLayer.getSource().removeFeature(f);
            }
            // Clear all shape selections.
            selectButton.getInteraction().getFeatures().clear();

            // Hide the labeling block.
            document.getElementById("labelBlock").style.display = "none";
        }
    }));
    var selectButton = new ol.control.Toggle({
        html: '<i class="icon-select-o"></i>',
        title: "Select tool: Click a mapped field to select it for category editing or deletion. Shift-click to select multiple fields.",
        interaction: new ol.interaction.Select({
            condition: ol.events.condition.click,
            layers: [fieldsLayer]
        }),
        bar: delBar
    });
    mainbar.addControl(selectButton);

    // The snap interaction is added after the Draw and Modify interactions
    // in order for its map browser event handlers to be fired first. 
    // Its handlers are responsible of doing the snapping.
    var snapInteraction = new ol.interaction.Snap({
        source: fieldsLayer.getSource(),
        pixelTolerance: snapTolerance
    });
    map.addInteraction(snapInteraction);

    // Add a return button with on active event
    var returnButton = new ol.control.Toggle(
            {	html: '<i class="icon-back"></i>',
                title: 'Return map: Click this button if you wish to return this map and be provided with another one. NOTE: this may result in a reduction of your quality score.',
                className: "noToggle"
            });
    mainbar.addControl(returnButton);

    returnButton.on("change:active", function(e)
    {	
        if (e.active) {
            checkReturnStrategy(kmlName);
        }
    });

    // Add a save button with on active event
    var saveButton = new ol.control.Toggle(
            {	html: '<i class="icon-save"></i>',
                title: 'Save changes: Click this button only ONCE when all mapped fields have been created, and you are satisfied with your work. Click when done even if there are NO fields to draw on this map.',
                className: "noToggle"
            });
    mainbar.addControl(saveButton);

    saveButton.on("change:active", function(e)
    {	
        if (e.active) {
            checkSaveStrategy(kmlName);
        }
    });

    return [mainbar, selectButton];
};
