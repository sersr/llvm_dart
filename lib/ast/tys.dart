import 'dart:async';

import 'package:equatable/equatable.dart';

import '../llvm_dart.dart';
import 'ast.dart';
import 'buildin.dart';
import 'expr.dart';
import 'llvm/llvm_context.dart';
import 'llvm/variables.dart';

abstract class LifeCycleVariable {
  Identifier get ident;

  Identifier? lifeEnd;

  Identifier? get lifeIdent => lifeEnd ?? ident;

  void updateLifeCycle(Identifier ident) {
    if (lifeEnd == null) {
      lifeEnd = ident;
      return;
    }
    if (ident.start >= lifeEnd!.start) {
      lifeEnd = ident;
    }
  }
}

class ImportPath with EquatableMixin {
  ImportPath(this.name);
  final Identifier name;

  @override
  List<Object?> get props => [name];

  @override
  String toString() {
    return name.toString();
  }
}

typedef ImportHandler = Tys Function(Tys, ImportPath);
typedef RunImport<T> = T Function(T Function());

abstract class GlobalContext {
  Tys import(Tys current, ImportPath path);
  V? getVariable<V>(Identifier ident);
  VA? getKVImpl<K, VA, T>(K k, Map<K, List<VA>> Function(Tys c) map,
      {ImportKV<VA>? handler, bool Function(VA v)? test});

  ExprTempValue? arrayBuiltin(FnBuildMixin context, Identifier ident,
      String fnName, Variable? val, Ty valTy, List<FieldExpr> params) {
    if (valTy is ArrayTy && val != null) {
      if (fnName == 'getSize') {
        final size = BuiltInTy.usize.llty
            .createValue(ident: Identifier.builtIn('${valTy.size}'));
        return ExprTempValue(size);
      } else if (fnName == 'toStr') {
        final element = valTy.llty.toStr(context, val);
        return ExprTempValue(element);
      }
    }

    if (valTy is StructTy) {
      if (valTy.ident.src == 'Array') {
        if (fnName == 'new') {
          if (params.isNotEmpty) {
            final first =
                params.first.build(context, baseTy: BuiltInTy.usize)?.variable;

            if (first is LLVMLitVariable) {
              if (valTy.tys.isNotEmpty) {
                final arr = ArrayTy(valTy.tys.values.first, first.value.iValue);

                final value = LLVMAllocaProxyVariable(context, (value, _) {
                  value.store(
                    context,
                    llvm.LLVMConstNull(arr.typeOf(context)),
                  );
                }, arr, arr.llty.typeOf(context), ident);

                return ExprTempValue(value);
              }
            }
          }
        }
      }
    }

    return null;
  }
}

mixin Tys<V extends LifeCycleVariable> {
  // Tys defaultImport(String path);
  String get currentPath;
  GlobalContext get global;

  final imports = <ImportPath, Tys>{};

  R? runImport<R>(R Function() body) {
    if (_runImport) return null;
    return runZoned(body, zoneValues: {#_runImport: true});
  }

  void pushImport(ImportPath path, {Identifier? name}) {
    if (!imports.containsKey(path)) {
      final im = global.import(this, path);
      imports[path] = im;
      initImportContext(im);
    }
  }

  void initImportContext(Tys child) {}

  final variables = <Identifier, List<V>>{};

  bool get _runImport {
    return Zone.current[#_runImport] == true;
  }

  V? getVariable(Identifier ident) =>
      getVariableImpl(ident) ?? global.getVariable(ident);

  V? getVariableImpl(Identifier ident) {
    final list = variables[ident];
    if (list != null) {
      var last = list.last;
      // ignore: invalid_use_of_protected_member
      if (last.ident.data != ident.data) {
        return last;
      }
      for (var val in list) {
        final valIdent = val.ident;
        if (valIdent.start > ident.start) {
          break;
        }
        if (valIdent.start == ident.start) {
          return val;
        }
        last = val;
      }
      last.updateLifeCycle(ident);
      return last;
    }

    final v = runImport(() {
      for (var imp in imports.values) {
        final v = imp.getVariable(ident);
        if (v != null) {
          v.updateLifeCycle(ident);
          return v;
        }
      }
    });

    return v as V?;
  }

  void pushVariable(V variable, {bool isAlloca = true}) {
    final list = variables.putIfAbsent(variable.ident, () => []);
    if (!list.contains(variable)) {
      if (list.isEmpty) {
        assert(!identical(variable.ident, Identifier.none), variable);
        list.add(variable);
      } else {
        final index =
            list.indexWhere((e) => e.ident.start > variable.ident.start);
        if (index == -1) {
          list.add(variable);
        } else {
          list.insert(index, variable);
        }
      }
    }
  }

  bool _contain(Iterable<List<Ty>> i, Ty ty) {
    return i.any((element) => element.contains(ty));
  }

  bool contains(Ty ty) {
    var result = _contain(structs.values, ty);
    if (!result) {
      result = _contain(enums.values, ty);
    }
    if (!result) {
      result = _contain(impls.values, ty);
    }
    if (!result) {
      result = _contain(components.values, ty);
    }

    return result;
  }

  // 当前范围内可获取的 struct
  final structs = <Identifier, List<StructTy>>{};
  StructTy? getStruct(Identifier ident) {
    return getKV(ident, (c) => c.structs, handler: (c) => c.getStruct(ident));
  }

  void pushStruct(Identifier ident, StructTy ty) {
    pushKV(ident, ty, structs);
  }

  final enums = <Identifier, List<EnumTy>>{};
  EnumTy? getEnum(Identifier ident) {
    return getKV(ident, (c) => c.enums, handler: (c) => c.getEnum(ident));
  }

  void pushEnum(Identifier ident, EnumTy ty) {
    pushKV(ident, ty, enums);
  }

  final fns = <Identifier, List<Fn>>{};
  Fn? getFn(Identifier ident) {
    return getKV(ident, (c) => c.fns, handler: (c) {
      return c.getFn(ident);
    });
  }

  void pushFn(Identifier ident, Fn fn) {
    pushKV(ident, fn, fns);
  }

  final builtinFns = <Identifier, List<BuiltinFn>>{};
  BuiltinFn? getBuiltinFn(Identifier ident) {
    return getKV(ident, (c) => c.builtinFns, handler: (c) {
      return c.getBuiltinFn(ident);
    });
  }

  void pushBuiltinFn(Identifier ident, BuiltinFn fn) {
    pushKV(ident, fn, builtinFns);
  }

  final components = <Identifier, List<ComponentTy>>{};
  ComponentTy? getComponent(Identifier ident) {
    return getKV(ident, (c) => c.components,
        handler: (c) => c.getComponent(ident));
  }

  void pushComponent(Identifier ident, ComponentTy com) {
    pushKV(ident, com, components);
  }

  final impls = <Identifier, List<ImplTy>>{};
  ImplTy? getImpl(Identifier ident) {
    return getKV(ident, (c) => c.impls, handler: (c) {
      return c.getImpl(ident);
    });
  }

  void pushImpl(Identifier ident, ImplTy ty) {
    pushKV(ident, ty, impls);
  }

  final implForTy = <Ty, List<ImplTy>>{};
  ImplFnMixin? getImplFnForTy(Ty ty, Identifier fnIdent) {
    return getImplWith(ty, fnIdent: fnIdent)?.getFnCopy(ty, fnIdent);
  }

  ImplTy? getImplWithCom(Ty ty, Identifier comIdent) {
    return getImplWith(ty, comIdent: comIdent);
  }

  /// 为泛型实现`Com`时
  ///
  /// impl Update for Box<T,S> {
  ///  ...
  /// }
  ///
  /// 如果Box<T,S> 中泛型`T`,`S`参数不是具体的类型则根据`score`规则
  ///
  /// `score` >= 0, 返回最接近于 0 的对象
  ImplTy? getImplWith(
    Ty ty, {
    Identifier? comIdent,
    List<ComponentTy>? constraintComs, // 约束条件
    Identifier? fnIdent,
  }) {
    assert(comIdent == null || constraintComs == null);

    final raw = ty;

    if (ty is StructTy) {
      ty = ty.parentOrCurrent;
    }

    ImplTy? cache;
    int cacheScore = -1;
    final result = _getImplForStruct(ty, (impl) {
      final selfTy = impl.ty!;

      if (fnIdent != null && !impl.contains(fnIdent)) return false;

      // 检查 `com`
      final sameComOrNull = impl.comTy?.ident == comIdent ||
          constraintComs == null ||
          constraintComs.contains(impl.comTy);

      if (!sameComOrNull) return false;

      if (sameComOrNull && raw == selfTy) return true;

      if (raw is! NewInst || selfTy is! NewInst) return false;

      final score = raw.getScore(selfTy);

      if (score == 0) return true;

      if (score != -1 && (cacheScore == -1 || score < cacheScore)) {
        cacheScore = score;
        cache = impl;
      }

      return false;
    });

    return result ?? cache;
  }

  ImplTy? _getImplForStruct(Ty structTy, bool Function(ImplTy v)? test) {
    return getKV(structTy, (c) => c.implForTy,
        handler: (c) => c._getImplForStruct(structTy, test), test: test);
  }

  void pushImplForStruct(Ty structTy, ImplTy ty) {
    if (structTy is StructTy) {
      structTy = structTy.parentOrCurrent;
    }
    pushKV(structTy, ty, implForTy);
  }

  final cTys = <Identifier, List<TypeAliasTy>>{};

  TypeAliasTy? getAliasTy(Identifier ident) {
    return getKV(ident, (c) => c.cTys, handler: (c) {
      return c.getAliasTy(ident);
    });
  }

  void pushAliasTy(Identifier ident, TypeAliasTy ty) {
    pushKV(ident, ty, cTys);
  }

  final _dyTys = <Identifier, List<Ty>>{};

  /// 在当前上下文中额外的类型，如：
  ///
  /// T: i32  => Identifier[T] : Ty[i32]
  ///
  /// 一般是函数，结构体泛型的具体类型
  Ty? getDyTy(Identifier ident) {
    return getKV(ident, (c) => c._dyTys, handler: (c) {
      return c.getAliasTy(ident);
    });
  }

  void pushDyTy(Identifier ident, Ty ty) {
    pushKV(ident, ty, _dyTys);
  }

  void pushDyTys(Map<Identifier, Ty> all) {
    for (var MapEntry(:key, :value) in all.entries) {
      pushKV(key, value, _dyTys);
    }
  }

  void pushAllTy(Iterable<Ty> all) {
    final impls = all.whereType<ImplTy>();
    for (var ty in all) {
      if (ty is StructTy) {
        pushStruct(ty.ident, ty);
      } else if (ty is Fn) {
        pushFn(ty.fnSign.fnDecl.ident, ty);
      } else if (ty is EnumTy) {
        pushEnum(ty.ident, ty);
      } else if (ty is ComponentTy) {
        pushComponent(ty.ident, ty);
      } else if (ty is ImplTy) {
        pushImpl(ty.struct.ident, ty);
      } else if (ty is TypeAliasTy) {
        pushAliasTy(ty.ident, ty);
      } else {
        print('unknown ty {${ty.runtimeType}}');
      }
    }
    for (var impl in impls) {
      final struct = impl.struct.grtOrT(this);
      if (struct != null) {
        pushImplForStruct(struct, impl);
        impl.initStructFns(this);
      }
    }
  }

  Ty? getTy(Identifier i) {
    return getStruct(i) ??
        getComponent(i) ??
        getImpl(i) ??
        getFn(i) ??
        getEnum(i) ??
        getAliasTy(i) ??
        getDyTy(i);
  }

  void errorExpr(UnknownExpr unknownExpr) {}

  VA? getKV<K, VA>(K k, Map<K, List<VA>> Function(Tys c) map,
      {ImportKV<VA>? handler, bool Function(VA v)? test}) {
    return getKVImpl(k, map, handler: handler, test: test) ??
        global.getKVImpl<K, VA, V>(k, map, handler: handler, test: test);
  }

  VA? getKVImpl<K, VA>(K k, Map<K, List<VA>> Function(Tys c) map,
      {ImportKV<VA>? handler, bool Function(VA v)? test}) {
    final list = map(this)[k];
    final hasTest = test != null;

    if (list != null) {
      if (!hasTest) return list.last;
      for (var i = list.length - 1; i >= 0; i--) {
        var item = list[i];
        if (!test(item)) continue;

        return item;
      }
    }
    if (handler != null) {
      final v = runImport(() {
        for (var imp in imports.values) {
          final v = handler(imp);
          if (v != null) {
            if (hasTest && !test(v)) continue;

            return v;
          }
        }
        return null;
      });
      if (v != null) {
        return v;
      }
    }
    return null;
  }

  bool pushKV<K, VA>(K k, VA v, Map<K, List<VA>> map) {
    final list = map.putIfAbsent(k, () => []);
    if (!list.contains(v)) {
      list.add(v);
      return true;
    }
    return false;
  }
}

typedef ImportKV<VA> = VA? Function(Tys c);
