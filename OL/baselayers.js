//
// *** All base layers go here ***
//
// Define Bing base layer.
var bingLayer = new ol.layer.Tile({
    title: 'Bing Aerial',
    zIndex: 2,
    type: 'base',
    visible: false,
    source: new ol.source.BingMaps({
        key: 'key',
        imagerySet: 'Aerial'
    })
});

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

// Define Mapbox base layer.
var mapboxLayer = new ol.layer.Tile({
    title: 'Mapbox',
    zIndex: 1,
    type: 'base',
    visible: false,
    source: new ol.source.XYZ({
        attributions: '&copy; <a href="https://www.mapbox.com/map-feedback/">Mapbox</a>',
        tileSize: [512, 512],
        url: 'https://api.mapbox.com/styles/v1/mapbox/satellite-v9/tiles/{z}/{x}/{y}?access_token=<key>'
    })
});

