//
// *** All base layers go here ***
//

//// Google satellite imagery
//var googleLayer = new ol.layer.Tile({
//    title: 'Google satellite',
//    zIndex: 4,
//    type: 'base',
//    visible: true,
//    source: new ol.source.XYZ({
//        url: 'https://mt1.google.com/vt/lyrs=s&x={x}&y={y}&z={z}' 
//    })
//});
//
//var esriLayer = new ol.layer.Tile({
//    title: 'ESRI imagery',
//    zIndex: 3,
//    type: 'base',
//    visible: true,
//    source: new ol.source.XYZ({
//        attributions: 'Tiles © <a href="https://services.arcgisonline.com/' +
//        'ArcGIS/rest/services/World_Imagery/MapServer">ArcGIS</a>',
//        url: 'https://server.arcgisonline.com/ArcGIS/rest/services/' +
//        'World_Imagery/MapServer/tile/{z}/{y}/{x}'
//    })
//});
//
//// Define Bing base layer.
//var bingLayer = new ol.layer.Tile({
//    title: 'Bing Aerial',
//    zIndex: 2,
//    type: 'base',
//    visible: false,
//    source: new ol.source.BingMaps({
//        url: "http://ecn.t3.tiles.virtualearth.net/tiles/a{q}.jpeg?g=0&dir=dir_n'",
//        key: imageAttributes[1],
//        imagerySet: 'Aerial'
//    })
//});

// Define Mapbox base layer.
// var mapboxkey = imageAttributes[1][1]
// var mapboxLayer = new ol.layer.Tile({
//     title: 'Mapbox',
//     zIndex: 1,
//     type: 'base',
//     visible: false,
//     source: new ol.source.XYZ({
//         attributions: '&copy; <a href="https://www.mapbox.com/map-feedback/">Mapbox</a>',
//         tileSize: [512, 512],
//         // url: 'https://api.mapbox.com/styles/v1/mapbox/satellite-v9/tiles/{z}/{x}/{y}?access_token=***REMOVED***'
//         url: `https://api.mapbox.com/styles/v1/mapbox/satellite-v9/tiles/{z}/{x}/{y}?access_token=${mapboxkey}`
//     })
// });
