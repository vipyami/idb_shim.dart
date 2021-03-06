import 'package:idb_shim/idb.dart';
import 'dart:async';
import 'dart:indexed_db' as idb;

import 'package:idb_shim/src/common/common_transaction.dart';
import 'package:idb_shim/src/native/native_database.dart';
import 'package:idb_shim/src/native/native_error.dart';
import 'package:idb_shim/src/native/native_object_store.dart';

abstract class TransactionNativeBase extends IdbTransactionBase {
  TransactionNativeBase(Database database) : super(database);
}

class TransactionNative extends TransactionNativeBase {
  idb.Transaction idbTransaction;

  TransactionNative(Database database, this.idbTransaction) : super(database);

  @override
  ObjectStore objectStore(String name) {
    return catchNativeError(() {
      idb.ObjectStore idbObjectStore = idbTransaction.objectStore(name);
      return ObjectStoreNative(idbObjectStore);
    });
  }

  @override
  Future<Database> get completed {
    return catchAsyncNativeError(() {
      return idbTransaction.completed.then((_) {
        return database;
      });
    });
  }
}

//
// Safari fake multistore transaction
// create the transaction when objectStore is called
class FakeMultiStoreTransactionNative extends TransactionNativeBase {
  //List<_NativeTransaction> transactions = [];
  // We sequencialize the transactions
  DatabaseNative get _nativeDatabase => (database as DatabaseNative);
  TransactionNative lastTransaction;
  ObjectStore lastStore;
  idb.Database get idbDatabase => _nativeDatabase.idbDatabase;
  String mode;
  FakeMultiStoreTransactionNative(Database database, this.mode)
      : super(database);

  @override
  ObjectStore objectStore(String name) {
    if (lastTransaction != null) {
      // same store, reuse it
      if (lastStore.name == name) {
        return lastStore;
      }

      // will wait for the previous transaction to be completed
      // so that it wannot be re-used
      lastTransaction.completed;
    }
    lastTransaction =
        _nativeDatabase.transaction(name, mode) as TransactionNative;
    lastStore = lastTransaction.objectStore(name);
    return lastStore;
  }

  @override
  Future<Database> get completed {
    if (lastTransaction == null) {
      return Future.value(database);
    } else {
      // Somehow waiting for all transaction hangs
      // just wait for the last one created!
      return lastTransaction.completed;
    }
  }
}
