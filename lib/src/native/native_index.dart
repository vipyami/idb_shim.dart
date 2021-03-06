import 'package:idb_shim/idb.dart';
import 'package:idb_shim/src/native/native_cursor.dart';
import 'dart:async';
import 'dart:indexed_db' as idb;

import 'package:idb_shim/src/native/native_error.dart';
import 'package:idb_shim/src/native/native_key_range.dart';

class IndexNative extends Index {
  idb.Index idbIndex;
  IndexNative(this.idbIndex);

  @override
  Future get(dynamic key) {
    return catchAsyncNativeError(() {
      return idbIndex.get(key);
    });
  }

  @override
  Future getKey(dynamic key) {
    return catchAsyncNativeError(() {
      return idbIndex.getKey(key);
    });
  }

  @override
  Future<int> count([key_OR_range]) {
    Future<int> countFuture;
    return catchAsyncNativeError(() {
      if (key_OR_range == null) {
        countFuture = idbIndex.count();
        /*
            .catchError((e) {
          // as of SDK 1.12 count() without argument crashes
          // so let's count manually
          if (e.toString().contains('DataError')) {
            int count = 0;
            // count manually
            return idbIndex.openKeyCursor(autoAdvance: true).listen((_) {
              count++;
            }).asFuture(count);
          } else {
            throw e;
          }
        });
        */
      } else if (key_OR_range is KeyRange) {
        idb.KeyRange idbKeyRange = toNativeKeyRange(key_OR_range);
        countFuture = idbIndex.count(idbKeyRange);
      } else {
        countFuture = idbIndex.count(key_OR_range);
      }
      return countFuture;
    });
  }

  @override
  Stream<Cursor> openKeyCursor(
      {key, KeyRange range, String direction, bool autoAdvance}) {
    CursorControllerNative ctlr = CursorControllerNative(idbIndex.openKeyCursor(
        key: key,
        range: range == null ? null : toNativeKeyRange(range),
        direction: direction,
        autoAdvance: autoAdvance));
    return ctlr.stream;
  }

  /// Same implementation than for the Store
  @override
  Stream<CursorWithValue> openCursor(
      {key, KeyRange range, String direction, bool autoAdvance}) {
    CursorWithValueControllerNative ctlr = CursorWithValueControllerNative(
        idbIndex.openCursor(
            key: key,
            range: range == null ? null : toNativeKeyRange(range),
            direction: direction,
            autoAdvance: autoAdvance));

    return ctlr.stream;
  }

  @override
  dynamic get keyPath => idbIndex.keyPath;

  @override
  bool get unique => idbIndex.unique;

  @override
  bool get multiEntry => idbIndex.multiEntry;

  @override
  int get hashCode => idbIndex.hashCode;

  @override
  String get name => idbIndex.name;

  @override
  bool operator ==(other) {
    if (other is IndexNative) {
      return idbIndex == other.idbIndex;
    }
    return false;
  }
}
