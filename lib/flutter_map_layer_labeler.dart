/// Collision-free labels for flutter_map markers, polylines and polygons.
library;

export 'src/label_controller.dart' show LabelCollisionController;
export 'src/labeled_marker.dart';
export 'src/labeled_marker_layer.dart'
    show LabelPriorityCallback, LabelStyleCallback, LabeledMarkerLayer;
export 'src/labeled_polygon_layer.dart'
    show
        LabeledPolygon,
        LabeledPolygonLayer,
        PolygonLabelAnchor,
        PolygonLabelStyleCallback,
        PolygonPriorityCallback;
export 'src/labeled_polyline_layer.dart'
    show
        LabeledPolyline,
        LabeledPolylineLayer,
        PolylineLabelStyleCallback,
        PolylinePriorityCallback;
