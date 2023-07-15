function init(gridJson, kmlName, assignmentId, tryNum, resultsAccepted, refJson, 
    workJson, imageAttributes, snapTolerance) {
	
    var saveStrategyActive = false;
    var workerFeedback = false;
    // If this is a mapping HIT or training map, let user save changes.
    if (assignmentId.length > 0) {
        saveStrategyActive = true;
    // Else, check if this is a worker feedback map.
    } else if (refJson.length != 0) {
        workerFeedback = true;
    }
    var defaultCategory = undefined;

    
    // Base layer imagery
    var googleLayer = new ol.layer.Tile({
        title: 'Google satellite',
        zIndex: 4,
        type: 'base',
        visible: true,
        source: new ol.source.XYZ({
            url: 'https://mt1.google.com/vt/lyrs=s&x={x}&y={y}&z={z}' 
        })
    });

    // ESRI
    var esriLayer = new ol.layer.Tile({
        title: 'ESRI imagery',
        zIndex: 3,
        type: 'base',
        visible: true,
        source: new ol.source.XYZ({
            attributions: 'Tiles © <a href="https://services.arcgisonline.com/' +
            'ArcGIS/rest/services/World_Imagery/MapServer">ArcGIS</a>',
            url: 'https://server.arcgisonline.com/ArcGIS/rest/services/' +
            'World_Imagery/MapServer/tile/{z}/{y}/{x}'
        })
    });

    // Bing base layer.
    var bingLayer = new ol.layer.Tile({
        title: 'Bing Aerial',
        zIndex: 2,
        type: 'base',
        visible: false,
        source: new ol.source.BingMaps({
            url: "http://ecn.t3.tiles.virtualearth.net/tiles/a{q}.jpeg?g=0&dir=dir_n'",
            key: imageAttributes[1],
            imagerySet: 'Aerial'
        })
    });

    // MapBox
    var mapboxkey = imageAttributes[2];
    var mapboxLayer = new ol.layer.Tile({
        title: 'Mapbox',
        zIndex: 1,
        type: 'base',
        visible: false,
        source: new ol.source.XYZ({
            attributions: '&copy; <a href="https://www.mapbox.com/map-feedback/">Mapbox</a>',
            tileSize: [512, 512],
            url: `https://api.mapbox.com/styles/v1/mapbox/satellite-v9/tiles/{z}/{x}/{y}?access_token=${mapboxkey}`
        })
    });

    // *** Create map, overlays, and view ***
    //
    var map = new ol.Map({
        controls: ol.control.defaults({
            attributionOptions:  ({
                collapsible: false
            })
        }).extend([new ol.control.MousePosition({
            coordinateFormat: ol.coordinate.createStringXY(3),
            projection: 'EPSG:4326',
            undefinedHTML: '&nbsp;'
        })]),
        interactions: ol.interaction.defaults({
            doubleClickZoom :false
        }),
        // NOTE: the zIndex convention (higher number = higher layer) is as follows:
        // 0-9: Base layers (only one at a time is visible)
        // 10-99: XYZ layers (zIndex determined by code below)
        // 100: KML layer (not visible in layer switcher)
        // 101: Fields layer (mapped by worker)
        // 102: Reference map layer (worker feedback case)
        // 103: Worker map layer (worker feedback case)
        layers: [
            // Create overlay layer(s) group.
            new ol.layer.Group({
                title: 'Field Overlay(s)',
                layers: []
            }),
            // Create multi-band image layer group.
            new ol.layer.Group({
                title: 'Images to Label',
                layers: []
            }),
            // Create base layer group.
            new ol.layer.Group({
                title: 'Base Layer',
                layers: [googleLayer, esriLayer, bingLayer, mapboxLayer]
            })
        ],
        // Use the specified DOM element
        target: document.getElementById('kml_display')
    });
    // Set view and zoom.
    map.setView(new ol.View({
        projection: 'EPSG:4326',
        center: [0,0],
        zoom: 14,
        minZoom: 4,
        maxZoom: 19
    }));
    // Disable right-click context menu to allow right-click map panning.
    map.getViewport().addEventListener('contextmenu', function (evt) {
        evt.preventDefault();
    });
    
    //
    //*** Create the image overlays ***
    //
    // Named constants (must match order in getXYZAttributes()).
    // var SEASON = 0;
    // var URL = 1;

    var ZINDEX_BASE = 10;    
    // Desired order is: True, False color
    // Array is assumed to be in GS/OS season order, one row for each.
    // URL is None if no overlay for that season.
    var DESCRIPTION = ['True color', 'False color'];
    var COLORS = ['1_TRUE-COLOR', '2_FALSE-COLOR'];
    // var COLORS = [imageAttributes[1][0], imageAttributes[1][1]];
    var imageLayer = [];
    var visible = true;

    var SHUB_INSTANCE_ID = imageAttributes[0];
    for (var i = 0; i < DESCRIPTION.length; i++) {
        imageLayer[i] = new ol.layer.Tile({
            zIndex: ZINDEX_BASE + i,
            visible:  visible,
            title: DESCRIPTION[i],
            source: new ol.source.TileWMS({
                url: `https://services.sentinel-hub.com/ogc/wms/${SHUB_INSTANCE_ID}`,
                params: {
                    "LAYERS": COLORS[i], // Layer name form Configure utility
                    "FORMAT": "image/png",
                    // "TRANSPARENT": true,
                    // "MAXCC": 10,
                    // "BBOX": gridJson.join(','),
                    // "TIME":  startdate + '/' + enddate,
                    "TILE": true
                }
            })
        });
        map.getLayers().getArray()[1].getLayers().push(imageLayer[i]);
        visible = false;
    }

    // *** Create grid cell ***
    // Bounding box KML layer
    // No title: so not in layer switcher.
    var gridSource = new ol.source.Vector({
	    features: new ol.format.GeoJSON().readFeatures(gridJson),
    });
    var gridLayer = new ol.layer.Vector({
	zIndex: 100,
	source: gridSource,
	style: new ol.style.Style({
	    fill: new ol.style.Fill({
		    color: 'rgba(255, 255, 255, 0.0)'
	    }),
	    stroke: new ol.style.Stroke({
		    color: 'rgba(255, 255, 255, 1.0)',
		    width: 2
	    })
	}),
    });
    map.getView().fit(gridSource.getExtent(), map.getSize());
    gridLayer.setMap(map);

    // *** If not a worker feedback case, add mapped fields and XYZ layers ***
    if (!workerFeedback) {
        var fieldsLayer = new ol.layer.Vector({
            title: "Mapped Fields",
            zIndex: 101,
            source: new ol.source.Vector({
                features: new ol.Collection()
            }),
            style: function (feature) {
                // If not a Point then style normally.
                if (feature.getGeometry().getType() !== 'Point') {
                    return [
                        new ol.style.Style({
                            fill: new ol.style.Fill({
                                // Edit line below to change unselected shapes' transparency.
                                color: 'rgba(255, 255, 255, 0.2)'
                            }),
                            stroke: new ol.style.Stroke({
                                color: '#ffcc33',
                                width: 2
                            })
                        }),
                        new ol.style.Style({
                            image: new ol.style.Circle({
                                radius: 3,
                                fill: new ol.style.Fill({
                                    color: '#ffcc33'
                                })
                            }),
                            geometry: function(feature) {
                                // return the coordinates of the all rings of the polygon
                                var coordinates = [];
                                for (i in feature.getGeometry().getCoordinates()) {
                                    coordinates = coordinates.concat(feature.getGeometry().getCoordinates()[i]);
                                }
                                return new ol.geom.MultiPoint(coordinates);
                            }
                        })
                    ];
                // Else, just draw a circle.
                } else {
                    return [
                        new ol.style.Style({
                            image: new ol.style.Circle({
                                radius: 5,
                                fill: new ol.style.Fill({
                                    color: '#ffcc33'
                                })
                            })
                        })
                    ];
                }
            }
        });
        // Add fieldsLayer as a managed layer (i.e., don't use setMap()).
        map.getLayers().getArray()[0].getLayers().push(fieldsLayer);
        
    // Else, create reference map and worker map layers
    } else {
	var wMapLayer = new ol.layer.Vector({
            title: "Worker Map",
            zIndex: 103,
            source: new ol.source.Vector({
		        features: new ol.format.GeoJSON().readFeatures(workJson),
	        }),
	    style: new ol.style.Style({
                fill: new ol.style.Fill({
                    color: 'rgba(0, 0, 255, 0.2)'
                }),
                stroke: new ol.style.Stroke({
                    color: '#0000ff',
                    width: 2
                })
            })
        });
	map.getLayers().getArray()[0].getLayers().push(wMapLayer);
 
	var rMapLayer = new ol.layer.Vector({
            title: "Reference Map", 
            zIndex: 102,                                                                                                                                                                source: new ol.source.Vector({
		    features: new ol.format.GeoJSON().readFeatures(refJson),
	    }),
	    style: new ol.style.Style({
                fill: new ol.style.Fill({
                    color: 'rgba(255, 204, 51, 0.4)'
                }),                                                                                                                                                                         stroke: new ol.style.Stroke({
                    color: '#ffcc33',
                    width: 2
                }),
            })
        });
        map.getLayers().getArray()[0].getLayers().push(rMapLayer);
    }

    // *** Add miscellaneous controls ***
    //
    // Zoom control
    var zoomSlider = new ol.control.ZoomSlider();
    map.addControl(zoomSlider);

    // Scale line
    var scaleLine = new ol.control.ScaleLine();
    map.addControl(scaleLine);
    
    // Layer Switcher control
    if (!workerFeedback) {
        showPanel = false;
    } else {
        showPanel = true;
    }
    var layerSwitcher = new ol.control.LayerSwitcher({
        reverse: false,
        showPanel: showPanel,
        tipLabel: 'Layer Switcher'
    });
    map.addControl(layerSwitcher);

    // Main control bar with sub-menus
    if (!workerFeedback) {
        var retVals = addControlBar(map, fieldsLayer, checkSaveStrategy, checkReturnStrategy, gridSource, kmlName, snapTolerance);
        var mainbar = retVals[0];
        var selectButton = retVals[1];

    // Worker feedback field selection.
    } else{
        selectFeedback = new ol.interaction.Select({
            condition: ol.events.condition.click,
            layers: [wMapLayer, rMapLayer]
        });
        map.addInteraction(selectFeedback);

        // Adjust labeling block so fields are read-only and save button is invisible.
        document.getElementById("categLabel").setAttribute("disabled", true);
        document.getElementById("commentLabel").setAttribute("readonly", true);
        document.getElementById("labelDone").style.display = "none";
    }

    // *** Handle the labeling block ***
    // Mapping cases.
    if (!workerFeedback) {
        // Add event handler to execute each time a shape is drawn.
        var mainbarVisible = true;
        var activeControl = null;
        fieldsLayer.getSource().on('addfeature', function(event) {
            // Render the control bar invisible and inactive.
            mainbar.setVisible(false);
            // Remember which drawing control is active so we can reactivate it later.
            var ctrls = mainbar.getControls()[0].getSubBar().getControls();
            for (var i = 0; i < ctrls.length; i++) {
                activeControl = ctrls[i];
                if (activeControl.getActive()) {
                    break;
                }
            }
            mainbar.setActive(false);
            mainbarVisible = false;
            // Clear all shape selections.
            selectButton.getInteraction().getFeatures().clear();
            // Display the labeling block.
            showLabelBlock(event.feature);
        });
        // Add event handler to execute each time a shape is selected.
        selectButton.getInteraction().getFeatures().on('add', function (event) {
            // Display the labeling block, but only if a single feature is selected.
            if (selectButton.getInteraction().getFeatures().getLength() == 1) {
                showLabelBlock(event.element);
            } else {
                // Hide the labeling block, in case visible.
                document.getElementById("labelBlock").style.display = "none";
            }
        });
        // Add event handler to execute each time a shape is unselected.
        selectButton.getInteraction().getFeatures().on('remove', function (event) {
            // Hide the labeling block, in case visible.
            document.getElementById("labelBlock").style.display = "none";
        });
        selectButton.getInteraction().on('change:active', function(e) {
            console.log("SELECT interaction changed active state: " + e.target.getActive());
            if (!e.target.getActive()) {
                // Clear all shape selections.
                selectButton.getInteraction().getFeatures().clear();
                // Hide the labeling block, in case visible.
                document.getElementById("labelBlock").style.display = "none";
            }
        });
        // Add event handler for when layerswitcher makes layer visible/invisible.
        fieldsLayer.on('propertychange', function(event) {
            if (event.key == 'visible') {
                // If layer now invisible, clear selection and hide labeling block.
                if (!fieldsLayer.getVisible()) {
                    // Clear all shape selections.
                    selectButton.getInteraction().getFeatures().clear();
                    // Hide the labeling block, in case visible.
                    document.getElementById("labelBlock").style.display = "none";
                // If layer now visible, display labeling block if toolbar invisible.
                } else {
                    // Render the labeling block visible if control bar invisible,
                    // as this means we're currently labeling a new feature.
                    if (!mainbarVisible) {
                        showLabelBlock(curFeature);
                    }
                }
            }
        });
    // Worker feedback case.
    } else {
        // Add event handler to execute each time a shape is selected.
        selectFeedback.getFeatures().on('add', function(event) {
            // Ensure that only one layer is enabled.
            if (rMapLayer.getVisible() && wMapLayer.getVisible()) {
                // Clear all shape selections.
                selectFeedback.getFeatures().clear();
                // Hide the labeling block, in case visible.
                document.getElementById("labelBlock").style.display = "none";
                // setTimeout() allows the background tasks above to complete in the 1 second allowed.
                setTimeout("alert('Please deselect the Reference Map or the Worker Map so that your click uniquely identifies a field on a specific layer.');", 1);
            // Display the labeling block, but only if a single feature is selected.
            } else {
                if (selectFeedback.getFeatures().getLength() == 1) {
                    showLabelBlock(event.element);
                } else {
                    // Hide the labeling block, in case visible.
                    document.getElementById("labelBlock").style.display = "none";
                }
            }
        });
        // Add event handler to execute each time a shape is unselected.
        selectFeedback.getFeatures().on('remove', function (event) {
            // Hide the labeling block, in case visible.
            document.getElementById("labelBlock").style.display = "none";
        });
        // Add event handler to clear selection and hide labeling block when 
        // layerswitcher changes visibility of reference layer.
        rMapLayer.on('propertychange', function(event) {
            if (event.key == 'visible') {
                // Clear all shape selections.
                selectFeedback.getFeatures().clear();
                // Hide the labeling block, in case visible.
                document.getElementById("labelBlock").style.display = "none";
            }
        });
        // Add event handler to clear selection and hide labeling block when 
        // layerswitcher changes visibility of worker layer.
        wMapLayer.on('propertychange', function(event) {
            if (event.key == 'visible') {
                // Clear all shape selections.
                selectFeedback.getFeatures().clear();
                // Hide the labeling block, in case visible.
                document.getElementById("labelBlock").style.display = "none";
            }
        });
    }
    // Display the label block for the specified feature.
    var curFeature;
    function showLabelBlock(feature) {
        // Get the pixel coordinates of the center of the feature.
        curFeature = feature;
        var extent = feature.getGeometry().getExtent();
        var coords = ol.extent.getCenter(extent);
        var pixel = map.getPixelFromCoordinate(coords);

        // Adjust as needed for offscreen locations.
        var left = Math.round(pixel[0]);
        var top = Math.round(pixel[1]);
        var limits = map.getSize();
        var leftLimit = 20;
        var topLimit = 30;
        var rightLimit = limits[0] - 180;
        var bottomLimit = limits[1] - 50;
        if (left < leftLimit) left = leftLimit;
        if (left > rightLimit) left = rightLimit;
        if (top < topLimit) top = topLimit;
        if (top > bottomLimit) top = bottomLimit;

        // Position the labeling block at the computed location.
        var style = document.getElementById("labelBlock").style;
        style.left = left + "px";
        style.top = top + "px";
        //console.log('left: ' + left + "px");
        //console.log('top: ' + top + "px");

        // Set the category and categComment values.
        category = feature.get('category');
        // If attributes are present in the feature, use them.
        if (category !== undefined) {
            categComment = feature.get('categ_comment');
            document.getElementById("categLabel").value = category;
            document.getElementById("commentLabel").value = categComment;
        // Else, initialize the input elements.
        } else {
            // Use select default for normal case, empty selection for worker feedback case.
            if (!workerFeedback) {
                // If first time here, capture the default select value for future use.
                if (defaultCategory == undefined) {
                    defaultCategory = document.getElementById("categLabel").selectedIndex;
                } else {
                    document.getElementById("categLabel").selectedIndex = defaultCategory;
                }
            } else {
                document.getElementById("categLabel").value = "";
            }
            document.getElementById("commentLabel").value = "";
        }
        // Display the labeling block.
        style.display = "block";
    };
    // Add event handler to process post-drawing labeling.
    $(document).on("click", "button#labelDone", function() {
        var category = document.getElementById("categLabel").value;
        curFeature.set('category', category);
        var comment = document.getElementById("commentLabel").value;
        curFeature.set('categ_comment', comment);

        // Clear all shape selections.
        selectButton.getInteraction().getFeatures().clear();

        // Hide the labeling block.
        document.getElementById("labelBlock").style.display = "none";

        // Render the control bar active and visible if needed.
        if (!mainbarVisible) {
            mainbarVisible = true;
            mainbar.setActive(true);
            // Reactivate the control that was active prior to labeling.
            activeControl.setActive(true);
            mainbar.setVisible(true);
        }
    });

    // Training case only.
    if (tryNum > 0) {
        if (resultsAccepted == 1) {
            alert("Congratulations! You successfully mapped the crop fields in this map. Please click OK to work on the next training map.");
        } else if (resultsAccepted == 2) {
            alert("We're sorry, but you failed to correctly map the crop fields in this map. Please click OK to try again.");
        }
    }
    // Mapping HIT or training map cases.
    if (resultsAccepted == 3) {
        alert("Error! Through no fault of your own, your work could not be saved. Please try the same map again. We apologize for the inconvenience.");
    }

    function checkSaveStrategy(kmlName) {
        var msg;

        // Check if the Save button is enabled.
        if (!saveStrategyActive) {
            return;
        }
        var features = fieldsLayer.getSource().getFeatures();
        if (features != '') {
            msg = 'You can only save your mapped fields ONCE!\nPlease confirm that you\'re COMPLETELY done mapping fields.\nIf not done, click Cancel.';
        } else {
            msg = 'You have not mapped any fields!\nYou can only save your mapped fields ONCE!\nPlease confirm that you\'re COMPLETELY done mapping fields.\nIf not done, click Cancel.'
        }
        if (!confirm(msg)) {
            return;
        }
        // Don't allow Save button to be used again.
        saveStrategyActive = false

        // Save the current polygons if there are any.
        // NOTE: the KML writeFeatures() function does not support extended attributes.
        // So we need to extract them from each feature and pass them separately as arrays.
        if (features != '') {
            var i = 1;
            for (var feature in features) {
                features[feature].set('name', kmlName + '_' + i);
                i = i + 1;
            }
            var kmlFormat = new ol.format.KML();
            var kmlData = kmlFormat.writeFeatures(features, {featureProjection: 'EPSG:4326', dataProjection: 'EPSG:4326'});
            // Save the kmlData in the HTML mappingform.
            document.mappingform.kmlData.value = kmlData;
        }
        // Mark that we saved our results.
        document.mappingform.savedMaps.value = true;

        document.mappingform.submit();
    }

    function checkReturnStrategy(kmlName) {
        var msg;

        // Check if the Return button is enabled.
        if (!saveStrategyActive) {
            return;
        }
        msg = 'You are about to return this map without saving any results!\nPlease confirm that this is what you want to do.\nNOTE: this may result in a reduction of your quality score.\nIf you do not wish to return this map, click Cancel.';
        if (!confirm(msg)) {
            return;
        }
        // Don't allow Return button to be used again.
        saveStrategyActive = false

        // Mark that we returned this map.
        document.mappingform.savedMaps.value = false;

        document.mappingform.submit();
    }

}
