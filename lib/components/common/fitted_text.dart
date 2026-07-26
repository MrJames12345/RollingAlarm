import 'package:flutter/material.dart';

/// Scale-to-fit single line text used on dense rows and alarm chrome.
Widget RA_FittedText(
  String text, {
  Key? key,
  TextStyle? style,
  AlignmentGeometry alignment = Alignment.centerLeft,
  int maxLines = 1,
  bool softWrap = false,
}) {
  return FittedBox(
    fit: BoxFit.scaleDown,
    alignment: alignment,
    child: Text(
      text,
      key: key,
      style: style,
      maxLines: maxLines,
      softWrap: softWrap,
      overflow: TextOverflow.ellipsis,
    ),
  );
}
