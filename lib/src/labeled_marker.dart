/// @docImport 'package:flutter_map_layer_labeler/flutter_map_layer_labeler.dart';
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';

/// The side of the marker where the label is placed.
enum LabelSide { bottom, top, right, left }

/// Wrapper class that associates a marker with a label and additional data.
class LabeledMarker<T> {
  const new _({
    required this.marker,
    required this.label,
    required this.data,
  });

  /// Creates a labeled marker with the specified marker, text label, and optional additional data.
  factory({
    required Marker marker,
    required String labelText,
    T? data,
  }) => LabeledMarker._(
    marker: marker,
    label: TextLabel(labelText),
    data: data,
  );

  /// Creates a labeled marker with the specified marker, sized widget label, and optional additional data.
  factory widget({
    required Marker marker,
    required Widget labelWidget,
    required Size labelSize,
    T? data,
    bool ignorePointer = false,
    double spacing = 2,
  }) => LabeledMarker._(
    marker: marker,
    label: WidgetLabel(
      labelWidget,
      labelSize,
      ignorePointer: ignorePointer,
      spacing: spacing,
    ),
    data: data,
  );

  /// The marker associated with this labeled marker.
  final Marker marker;

  /// The label associated with the marker.
  ///
  /// If null, the marker has no label, but it still takes part in the
  /// collision detection as an obstacle.
  final Label? label;

  /// Additional data for the priority and style callbacks.
  final T? data;
}

/// Base class for different types of labels associated with a marker.
sealed class Label {
  const new();
}

/// A label that contains plain text.
///
/// Styled by [LabeledMarkerLayer.labelStyle] or by the result of
/// [LabeledMarkerLayer.labelStyleCallback].
class TextLabel extends Label {
  const new(this.text);

  /// The text content of the label.
  final String text;
}

/// A label that contains a sized widget.
///
/// The widget is drawn as is: [LabelStyle] has no effect on it.
class WidgetLabel extends Label {
  const new(
    this.widget,
    this.size, {
    this.ignorePointer = false,
    this.spacing = 2,
  });

  /// The widget content of the label.
  final Widget widget;

  /// The size of the widget label.
  final Size size;

  /// If set to false, the label can receive pointer events.
  final bool ignorePointer;

  /// The spacing between the label and its associated marker.
  final double spacing;
}

/// Represents the style for [TextLabel] type labels.
///
/// This style has no effect on [WidgetLabel] type labels.
class LabelStyle {
  /// Creates a style that draws the label text with [textStyle].
  const new(
    TextStyle this.textStyle, {
    this.padding = const .symmetric(horizontal: 4, vertical: 2),
    this.halo = const TextLabelHalo(),
    this.decoration,
    this.spacing = 2,
  });

  /// Creates a style that hides the label: a [TextLabel] with this style is
  /// not drawn, and it does not block anything.
  ///
  /// Return it from a label style callback (for example
  /// [LabeledMarkerLayer.labelStyleCallback]) to hide the label of single
  /// items, for example at certain zoom levels or for certain data. The item
  /// itself (marker, polyline, polygon) is not affected: a marker still takes
  /// part in the collision detection as an obstacle.
  const new hidden()
    : textStyle = null,
      padding = EdgeInsets.zero,
      halo = const TextLabelHalo.zero(),
      decoration = null,
      spacing = 2;

  const new _(
    this.textStyle,
    this.padding,
    this.halo,
    this.decoration,
    this.spacing,
  );

  /// The style to use for the label text.
  ///
  /// Null if the style hides the label (see [LabelStyle.hidden]).
  final TextStyle? textStyle;

  /// Whether this style hides the label, because it has no [textStyle].
  bool get isHidden => textStyle == null;

  /// The padding around the label text.
  final EdgeInsets padding;

  /// The halo effect around the label text.
  final TextLabelHalo halo;

  /// The decoration to apply to the label container.
  final BoxDecoration? decoration;

  /// The spacing between the label and its associated marker.
  final double spacing;

  /// Returns a copy of this style.
  ///
  /// A hidden style stays hidden unless a [textStyle] is given.
  LabelStyle copyWith({
    TextStyle? textStyle,
    EdgeInsets? padding,
    TextLabelHalo? halo,
    BoxDecoration? decoration,
    double? spacing,
  }) => LabelStyle._(
    textStyle ?? this.textStyle,
    padding ?? this.padding,
    halo ?? this.halo,
    decoration ?? this.decoration,
    spacing ?? this.spacing,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LabelStyle &&
          runtimeType == other.runtimeType &&
          textStyle == other.textStyle &&
          padding == other.padding &&
          halo == other.halo &&
          decoration == other.decoration &&
          spacing == other.spacing;

  @override
  int get hashCode =>
      Object.hash(textStyle, padding, halo, decoration, spacing);
}

/// Represents the visual halo around a label text, that ensures readability.
class TextLabelHalo {
  /// Creates a halo with a default semi-transparent white color and a width of 3.
  const new([this.color = const Color(0xB3FFFFFF)]) : width = 3;

  /// Creates a halo with no color and zero width.
  const new zero() : color = null, width = 0;

  /// Creates a custom halo with the specified color and width.
  const new custom({this.color, this.width});

  /// The color of the halo.
  ///
  /// If null, no halo is drawn.
  final Color? color;

  /// The width of the halo.
  ///
  /// If null or zero, no halo is drawn.
  final double? width;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TextLabelHalo &&
          runtimeType == other.runtimeType &&
          color == other.color &&
          width == other.width;

  @override
  int get hashCode => Object.hash(color, width);
}
