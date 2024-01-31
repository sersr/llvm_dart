import 'dart:async';

import 'package:equatable/equatable.dart';

import '../llvm_dart.dart';
import '../parsers/str.dart';
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
  ImportPath(this.name) : rawPath = '';
  ImportPath.path(this.rawPath) : name = Identifier.none;
  final Identifier name;
  final String rawPath;

  String get path {
    if (rawPath.isNotEmpty) {
      return rawPath;
    }
    return parseStr(name.src);
  }

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
  VA? getKVImpl<VA, T>(List<VA>? Function(Tys c) map,
      {bool Function(VA v)? test});

  bool isStd(Tys c);

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

  final _imports = <ImportPath, Tys>{};

  R? runImport<R>(R Function() body) {
    if (_runImport) return null;
    return runZoned(body, zoneValues: {#_runImport: true});
  }

  R? runIgnoreImport<R>(R Function() body) {
    return runZoned(body, zoneValues: {#_runImport: false});
  }

  void pushImport(ImportPath path, {Identifier? name}) {
    if (!_imports.containsKey(path)) {
      final im = global.import(this, path);
      _imports[path] = im;
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
      for (var imp in _imports.values) {
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

  // 当前范围内可获取的 struct
  final _structs = <Identifier, List<StructTy>>{};
  StructTy? getStruct(Identifier ident) {
    return getKV((c) => c._structs[ident]);
  }

  void pushStruct(Identifier ident, StructTy ty) {
    pushKV(ident, ty, _structs);
  }

  final _enums = <Identifier, List<EnumTy>>{};
  EnumTy? getEnum(Identifier ident) {
    return getKV((c) => c._enums[ident]);
  }

  void pushEnum(Identifier ident, EnumTy ty) {
    pushKV(ident, ty, _enums);
  }

  final fns = <Identifier, List<Fn>>{};
  Fn? getFn(Identifier ident) {
    return getKV((c) => c.fns[ident]);
  }

  void pushFn(Identifier ident, Fn fn) {
    pushKV(ident, fn, fns);
  }

  final _builtinFns = <Identifier, List<BuiltinFn>>{};
  BuiltinFn? getBuiltinFn(Identifier ident) {
    return getKV((c) => c._builtinFns[ident]);
  }

  void pushBuiltinFn(Identifier ident, BuiltinFn fn) {
    pushKV(ident, fn, _builtinFns);
  }

  final _components = <Identifier, List<ComponentTy>>{};
  ComponentTy? getComponent(Identifier ident) {
    return getKV((c) => c._components[ident]);
  }

  void pushComponent(Identifier ident, ComponentTy com) {
    pushKV(ident, com, _components);
  }

  final _implForTy = <Ty, List<ImplTy>>{};
  ImplFnMixin? getImplFnForTy(Ty ty, Identifier fnIdent) {
    return getImplWith(ty, fnIdent: fnIdent)?.getFn(fnIdent);
  }

  /// 为泛型实现`Com`时
  ///
  /// impl Update for Box<T,S> {
  ///  ...
  /// }
  ///
  /// 如果Box<T,S> 中泛型`T`,`S`参数不是具体的类型则根据`score`规则
  ///
  /// `score` >= 0, 返回最大值
  ImplTy? getImplWith(Ty ty,
      {Identifier? comIdent, Ty? comTy, Identifier? fnIdent}) {
    assert(comIdent == null || comTy == null || fnIdent != null);
    final raw = ty;

    if (ty is NewInst) {
      ty = ty.parentOrCurrent;
    }

    ImplTy? cache;
    int cacheScore = -1;

    bool test(ImplTy impl) {
      if (fnIdent != null && !impl.contains(fnIdent)) return false;

      // 检查 `com`
      if (comIdent != null && impl.comTy?.ident != comIdent) return false;
      if (raw is NewInst) {
        if (!raw.done) {
          cache = impl;
          return true;
        }
      }
      final tyImpl =
          runIgnoreImport(() => impl.compareStruct(this, raw, comTy));

      if (tyImpl != null) {
        if (raw.isLimited) {
          final valid = raw.constraints.any((e) => tyImpl.comTy == e);
          if (!valid) return false;
        }

        final baseTy = impl.parentOrCurrent.ty;
        if (baseTy != null && baseTy is! NewInst) {
          cache = tyImpl;
          return true;
        }

        var score = 0;

        if (baseTy is NewInst) {
          assert(raw is NewInst);
          score = baseTy.tys.length;

          final maxScore = (raw as NewInst).tys.length;
          if (score == maxScore) {
            cache = tyImpl;
            return true;
          }
        }

        if (score > cacheScore) {
          cacheScore = score;
          cache = tyImpl;
        }
        return false;
      }

      return false;
    }

    /// for ty 可识别
    getKV((c) {
      return c._implForTy[ty];
    }, test: test);
    if (cache != null) return cache;

    // for ty 无法识别的情况
    getKV((c) => c._implTys, test: test);

    return cache;
  }

  void pushImplForStruct(Ty structTy, ImplTy ty) {
    if (structTy is NewInst) {
      structTy = structTy.parentOrCurrent;
    }
    pushKV(structTy, ty, _implForTy);
  }

  final _implTys = <ImplTy>[];
  void pushImplTy(ImplTy ty) {
    ty = ty.parentOrCurrent;
    if (!_implTys.contains(ty)) {
      _implTys.add(ty);
    }
  }

  final _aliasTys = <Identifier, List<TypeAliasTy>>{};

  TypeAliasTy? getAliasTy(Identifier ident) {
    return getKV((c) => c._aliasTys[ident]);
  }

  void pushAliasTy(Identifier ident, TypeAliasTy ty) {
    pushKV(ident, ty, _aliasTys);
  }

  final _dyTys = <Identifier, List<Ty>>{};

  /// 在当前上下文中额外的类型，如：
  ///
  /// T: i32  => Identifier[T] : Ty[i32]
  ///
  /// 一般是函数，结构体泛型的具体类型
  Ty? getDyTy(Identifier ident) {
    return getKV((c) => c._dyTys[ident]);
  }

  void pushDyTy(Identifier ident, Ty ty) {
    pushKV(ident, ty, _dyTys);
  }

  void pushDyTys(Map<Identifier, Ty> all) {
    for (var MapEntry(:key, :value) in all.entries) {
      pushKV(key, value, _dyTys);
    }
  }

  Ty? getTy(Identifier i) {
    return getStruct(i) ??
        getAliasTy(i) ??
        getFn(i) ??
        getEnum(i) ??
        getDyTy(i) ??
        getComponent(i);
  }

  void errorExpr(UnknownExpr unknownExpr) {}

  VA? getKV<VA>(List<VA>? Function(Tys c) map, {bool Function(VA v)? test}) {
    return getKVImpl(map, test: test) ??
        global.getKVImpl<VA, V>(map, test: test);
  }

  VA? getKVImpl<VA>(List<VA>? Function(Tys c) map,
      {bool Function(VA v)? test}) {
    final list = map(this);
    final hasTest = test != null;

    VA? cache;
    void getItem(List<VA> list) {
      if (!hasTest) {
        cache = list.last;
        return;
      }

      for (var i = list.length - 1; i >= 0; i--) {
        var item = list[i];
        if (!test(item)) continue;

        cache = item;
        return;
      }
    }

    if (list != null) getItem(list);

    if (cache == null) {
      runImport(() {
        for (var imp in _imports.values) {
          final list = map(imp);
          if (list == null) continue;
          getItem(list);
        }
      });
    }

    return cache;
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
