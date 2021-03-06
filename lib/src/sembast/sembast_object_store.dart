import 'package:idb_shim/idb.dart';
import 'package:idb_shim/src/common/common_meta.dart';
import 'package:idb_shim/src/common/common_validation.dart';
import 'package:idb_shim/src/common/common_value.dart';
import 'package:idb_shim/src/sembast/sembast_cursor.dart';
import 'package:idb_shim/src/sembast/sembast_database.dart';
import 'package:idb_shim/src/sembast/sembast_index.dart';
import 'package:idb_shim/src/sembast/sembast_transaction.dart';
import 'package:idb_shim/src/utils/core_imports.dart';
import 'package:sembast/sembast.dart' as sdb;

class ObjectStoreSembast extends ObjectStore with ObjectStoreWithMetaMixin {
  @override
  final IdbObjectStoreMeta meta;

  final TransactionSembast transaction;

  DatabaseSembast get database => transaction.database;

  sdb.Database get sdbDatabase => database.db;
  sdb.StoreExecutor _sdbStore;

  // lazy creation
  // If we are not in a transaction that's likely during open
  sdb.StoreExecutor get sdbStore =>
      _sdbStore ??= transaction.sdbTransaction == null
          ? sdbDatabase.getStore(name)
          : transaction.sdbTransaction.getStore(name);

  ObjectStoreSembast(this.transaction, this.meta) {
    // Don't compute sdbStore yet we don't have the transaction
    /*
    // If we are not in a transaction that's likely during open
    sdbStore = transaction.sdbTransaction == null
        ? sdbDatabase.getStore(name)
        : transaction.sdbTransaction.getStore(name);
        */
  }

  Future<T> inWritableTransaction<T>(FutureOr<T> computation()) {
    if (transaction.meta.mode != idbModeReadWrite) {
      return Future.error(DatabaseReadOnlyError());
    }
    return inTransaction(computation);
  }

  Future<T> inTransaction<T>(FutureOr<T> computation()) {
    return transaction.execute(computation);
//    transaction.txn

//    // create the transaction if needed
//    // make it async so that we get the result of the action before transaction completion
//    Completer completer = new Completer();
//    transaction._completed = completer.future;
//
//    return sdbStore.inTransaction(() {
//      return computation();
//    }).then((result) {
//      completer.complete();
//      return result;
//
//    })
//    return sdbStore.inTransaction(() {
//      return new Future.sync(computation).then((result) {
//
//      });
//    });
  }

  /// extract the key from the key itself or from the value
  /// it is a map and keyPath is not null
  dynamic _getKey(value, [key]) {
    if ((keyPath != null) && (value is Map)) {
      var keyInValue = value[keyPath];
      if (keyInValue != null) {
        if (key != null) {
          throw ArgumentError(
              "both key ${key} and inline keyPath ${keyInValue} are specified");
        } else {
          return keyInValue;
        }
      }
    }

    if (key == null && (!autoIncrement)) {
      throw DatabaseError(
          'neither keyPath nor autoIncrement set and trying to add object without key');
    }

    return key;
  }

  Future _put(value, key) {
    // Check all indexes
    List<Future> futures = [];
    if (value is Map) {
      meta.indecies.forEach((IdbIndexMeta indexMeta) {
        var fieldValue = mapValueAtKeyPath(value, indexMeta.keyPath);
        if (fieldValue != null) {
          sdb.Finder finder = sdb.Finder(
              filter: keyFilter(indexMeta.keyPath, fieldValue), limit: 1);
          futures.add(sdbStore.findRecord(finder).then((sdb.Record record) {
            // not ourself
            if ((record != null) &&
                (record.key != key) //
                &&
                ((!indexMeta.multiEntry) && indexMeta.unique)) {
              throw DatabaseError(
                  "key '${fieldValue}' already exists in ${record} for index ${indexMeta}");
            }
          }));
        }
      });
    }
    return Future.wait(futures).then((_) {
      return sdbStore.put(value, key);
    });
  }

  @override
  Future add(value, [key]) {
    return inWritableTransaction(() {
      key = _getKey(value, key);

      if (key != null) {
        return sdbStore.get(key).then((existingValue) {
          if (existingValue != null) {
            throw DatabaseError(
                'Key ${key} already exists in the object store');
          }
          return _put(value, key);
        });
      } else {
        return _put(value, key);
      }
    });
  }

  @override
  Future clear() {
    return inWritableTransaction(() {
      return sdbStore.clear();
    }).then((_) {
      return null;
    });
  }

  sdb.Filter _storeKeyOrRangeFilter([key_OR_range]) {
    return keyOrRangeFilter(sdb.Field.key, key_OR_range);
  }

  @override
  Future<int> count([key_OR_range]) {
    return inTransaction(() {
      return sdbStore.count(_storeKeyOrRangeFilter(key_OR_range));
    });
  }

  @override
  Index createIndex(String name, keyPath, {bool unique, bool multiEntry}) {
    IdbIndexMeta indexMeta = IdbIndexMeta(name, keyPath, unique, multiEntry);
    meta.createIndex(database.meta, indexMeta);
    return IndexSembast(this, indexMeta);
  }

  @override
  void deleteIndex(String name) {
    meta.deleteIndex(database.meta, name);
  }

  @override
  Future delete(key) {
    return inWritableTransaction(() {
      return sdbStore.delete(key).then((_) {
        // delete returns null
        return null;
      });
    });
  }

  dynamic _recordToValue(sdb.Record record) {
    if (record == null) {
      return null;
    }
    var value = record.value;
    // Add key if _keyPath is not null
    if ((keyPath != null) && (value is Map)) {
      value[keyPath] = record.key;
    }

    return value;
  }

  @override
  Future getObject(key) {
    checkKeyParam(key);
    return inTransaction(() {
      return sdbStore.getRecord(key).then((sdb.Record record) {
        return _recordToValue(record);
      });
    });
  }

  @override
  Index index(String name) {
    IdbIndexMeta indexMeta = meta.index(name);
    return IndexSembast(this, indexMeta);
  }

  List<sdb.SortOrder> sortOrders(bool ascending) =>
      keyPathSortOrders(keyField, ascending);

  sdb.Filter cursorFilter(key, KeyRange range) {
    if (range != null) {
      return keyRangeFilter(keyField, range);
    } else {
      return keyFilter(keyField, key);
    }
  }

  dynamic get keyField => keyPath != null ? keyPath : sdb.Field.key;

  @override
  Stream<CursorWithValue> openCursor(
      {key, KeyRange range, String direction, bool autoAdvance}) {
    IdbCursorMeta cursorMeta =
        IdbCursorMeta(key, range, direction, autoAdvance);
    StoreCursorWithValueControllerSembast ctlr =
        StoreCursorWithValueControllerSembast(this, cursorMeta);

    inTransaction(() {
      return ctlr.openCursor();
    });

    return ctlr.stream;
  }

  @override
  Future put(value, [key]) {
    return inWritableTransaction(() {
      return _put(value, _getKey(value, key));
    });
  }
}
