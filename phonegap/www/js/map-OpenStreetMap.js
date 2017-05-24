function set_map_config(perm) {
    var permalink_id;
    if ($('#map_permalink').length) {
        permalink_id = 'map_permalink';
    }
    fixmystreet.controls = [
        new OpenLayers.Control.ArgParser(),
        //new OpenLayers.Control.LayerSwitcher(),
        new OpenLayers.Control.Navigation(),
        new OpenLayers.Control.Permalink(permalink_id),
        new OpenLayers.Control.PermalinkFMS('osm_link', 'https://www.openstreetmap.org/'),
        new OpenLayers.Control.PanZoomFMS({id: 'fms_pan_zoom' })
    ];
}

// http://www.openstreetmap.org/openlayers/OpenStreetMap.js (added maxResolution)

/**
 * Namespace: Util.OSM
 */
OpenLayers.Util.OSM = {};

/**
 * Constant: MISSING_TILE_URL
 * {String} URL of image to display for missing tiles
 */
OpenLayers.Util.OSM.MISSING_TILE_URL = "https://www.openstreetmap.org/openlayers/img/404.png";

/**
 * Property: originalOnImageLoadError
 * {Function} Original onImageLoadError function.
 */
OpenLayers.Util.OSM.originalOnImageLoadError = OpenLayers.Util.onImageLoadError;

/**
 * Function: onImageLoadError
 */
OpenLayers.Util.onImageLoadError = function() {
    if (this.src.match(/^http:\/\/[abc]\.[a-z]+\.openstreetmap\.org\//)) {
        this.src = OpenLayers.Util.OSM.MISSING_TILE_URL;
    } else if (this.src.match(/^http:\/\/[def]\.tah\.openstreetmap\.org\//)) {
        // do nothing - this layer is transparent
    } else {
        OpenLayers.Util.OSM.originalOnImageLoadError();
    }
};

/**
 * Class: OpenLayers.Layer.OSM.Mapnik
 *
 * Inherits from:
 *  - <OpenLayers.Layer.OSM>
 */
OpenLayers.Layer.OSM.Mapnik = OpenLayers.Class(OpenLayers.Layer.OSM, {
    /**
     * Constructor: OpenLayers.Layer.OSM.Mapnik
     *
     * Parameters:
     * name - {String}
     * options - {Object} Hashtable of extra options to tag onto the layer
     */
    initialize: function(name, options) {
        var url = [
            "https://a.tile.openstreetmap.org/${z}/${x}/${y}.png",
            "https://b.tile.openstreetmap.org/${z}/${x}/${y}.png",
            "https://c.tile.openstreetmap.org/${z}/${x}/${y}.png"
        ];
        options = OpenLayers.Util.extend({
            /* Below line added to OSM's file in order to allow minimum zoom level */
            maxResolution: 156543.0339/Math.pow(2, options.zoomOffset || 0),
            numZoomLevels: 19,
            buffer: 0
        }, options);
        var newArguments = [name, url, options];
        OpenLayers.Layer.OSM.prototype.initialize.apply(this, newArguments);
    },

    CLASS_NAME: "OpenLayers.Layer.OSM.Mapnik"
});

/**
 * Class: OpenLayers.Layer.OSM.Osmarender
 *
 * Inherits from:
 *  - <OpenLayers.Layer.OSM>
 */
OpenLayers.Layer.OSM.Osmarender = OpenLayers.Class(OpenLayers.Layer.OSM, {
    /**
     * Constructor: OpenLayers.Layer.OSM.Osmarender
     *
     * Parameters:
     * name - {String}
     * options - {Object} Hashtable of extra options to tag onto the layer
     */
    initialize: function(name, options) {
        var url = [
            "https://a.tah.openstreetmap.org/Tiles/tile/${z}/${x}/${y}.png",
            "https://b.tah.openstreetmap.org/Tiles/tile/${z}/${x}/${y}.png",
            "https://c.tah.openstreetmap.org/Tiles/tile/${z}/${x}/${y}.png"
        ];
        options = OpenLayers.Util.extend({ numZoomLevels: 18, buffer: 0 }, options);
        var newArguments = [name, url, options];
        OpenLayers.Layer.OSM.prototype.initialize.apply(this, newArguments);
    },

    CLASS_NAME: "OpenLayers.Layer.OSM.Osmarender"
});

/**
 * Class: OpenLayers.Layer.OSM.CycleMap
 *
 * Inherits from:
 *  - <OpenLayers.Layer.OSM>
 */
OpenLayers.Layer.OSM.CycleMap = OpenLayers.Class(OpenLayers.Layer.OSM, {
    /**
     * Constructor: OpenLayers.Layer.OSM.CycleMap
     *
     * Parameters:
     * name - {String}
     * options - {Object} Hashtable of extra options to tag onto the layer
     */
    initialize: function(name, options) {
        var url = [
            "https://a.tile.opencyclemap.org/cycle/${z}/${x}/${y}.png",
            "https://b.tile.opencyclemap.org/cycle/${z}/${x}/${y}.png",
            "https://c.tile.opencyclemap.org/cycle/${z}/${x}/${y}.png"
        ];
        options = OpenLayers.Util.extend({
            /* Below line added to OSM's file in order to allow minimum zoom level */
            maxResolution: 156543.0339/Math.pow(2, options.zoomOffset || 0),
            numZoomLevels: 19,
            buffer: 0
        }, options);
        var newArguments = [name, url, options];
        OpenLayers.Layer.OSM.prototype.initialize.apply(this, newArguments);
    },

    CLASS_NAME: "OpenLayers.Layer.OSM.CycleMap"
});
