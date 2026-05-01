import 'package:flutter/cupertino.dart';

/// مسار RTL مع انتقال مناسب للسحب للرجوع (Cupertino) على iOS وأندرويد.
Route<T> buildAdaptiveRtlRoute<T extends Object?>(Widget page) {
  return CupertinoPageRoute<T>(
    builder: (BuildContext context) => Directionality(
      textDirection: TextDirection.rtl,
      child: page,
    ),
  );
}

void pushAdaptiveRtlPage(BuildContext context, Widget page) {
  Navigator.of(context).push(buildAdaptiveRtlRoute<Object?>(page));
}

/// يغلق كل الشاشات المكدّسة حتى الشاشة الجذرية (الرئيسية بعد الشاشة الترحيبية).
void popToAppRoot(BuildContext context) {
  Navigator.of(context).popUntil((Route<void> route) => route.isFirst);
}
