part of 'builders.dart';

abstract class CallBuilder {
  static final _callCom = 'FnCall'.ident;
  static final _callIdent = 'call'.ident;

  static ExprTempValue? callImpl(
      FnBuildMixin context, Variable variable, List<FieldExpr> params) {
    final implFn = context
        .getImplWith(variable.ty, comIdent: _callCom, fnIdent: _callIdent)
        ?.getFn(_callIdent);
    if (implFn == null) return null;

    final fnValue = implFn.genFn();

    return AbiFn.fnCallInternal(
      context: context,
      fn: fnValue,
      decl: implFn.fnDecl,
      params: params,
      struct: variable,
      extern: false,
    );
  }

  static AnalysisVariable? callImplTys(AnalysisContext context,
      AnalysisVariable variable, List<FieldExpr> params) {
    final implFn = context
        .getImplWith(variable.ty, comIdent: _callCom, fnIdent: _callIdent)
        ?.getFn(_callIdent);
    final ty = implFn?.fnDecl.getRetTy(context);
    if (ty != null) {
      return context.createVal(ty, variable.ident);
    }

    return null;
  }
}
