; ModuleID = 'base.c'
source_filename = "base.c"
target datalayout = "e-m:w-p270:32:32-p271:32:32-p272:64:64-i64:64-f80:128-n8:16:32:64-S128"
target triple = "x86_64-w64-windows-gnu"

%struct.BaseC = type { i32 }
%struct.Base = type { i32, i32, i32 }

@vvs = dso_local global i32 0, align 4
@__const.hh.b = private unnamed_addr constant %struct.BaseC { i32 1 }, align 4
@.str = private unnamed_addr constant [12 x i8] c"hello world\00", align 1
@global = dso_local global ptr @.str, align 8
@__const.main.base = private unnamed_addr constant %struct.Base { i32 1, i32 2, i32 6 }, align 4
@.str.1 = private unnamed_addr constant [32 x i8] c"\E5\AD\97\E7\AC\A6\E4\B8\B2\E5\88\86\E5\BC\80\E7\9A\84\E4\B8\A4\E7\A7\8D\E5\BD\A2\E5\BC\8F \00", align 1

; Function Attrs: noinline nounwind optnone uwtable
define dso_local void @test_main() #0 {
  %1 = alloca i32, align 4
  %2 = alloca i32, align 4
  store i32 10, ptr %1, align 4
  store i32 11, ptr %2, align 4
  ret void
}

; Function Attrs: noinline nounwind optnone uwtable
define dso_local i32 @hh() #0 {
  %1 = alloca %struct.BaseC, align 4
  call void @llvm.memcpy.p0.p0.i64(ptr align 4 %1, ptr align 4 @__const.hh.b, i64 4, i1 false)
  %2 = getelementptr inbounds %struct.BaseC, ptr %1, i32 0, i32 0
  %3 = load i32, ptr %2, align 4
  ret i32 %3
}

; Function Attrs: nocallback nofree nounwind willreturn memory(argmem: readwrite)
declare void @llvm.memcpy.p0.p0.i64(ptr noalias nocapture writeonly, ptr noalias nocapture readonly, i64, i1 immarg) #1

; Function Attrs: noinline nounwind optnone uwtable
define dso_local void @test_base(ptr noundef %0) #0 {
  %2 = alloca ptr, align 8
  store ptr %0, ptr %2, align 8
  %3 = getelementptr inbounds %struct.Base, ptr %0, i32 0, i32 0
  store i32 111, ptr %3, align 4
  ret void
}

; Function Attrs: noinline nounwind optnone uwtable
define dso_local i32 @main(i32 noundef %0, ptr noundef %1) #0 {
  %3 = alloca i32, align 4
  %4 = alloca i32, align 4
  %5 = alloca ptr, align 8
  %6 = alloca %struct.Base, align 4
  %7 = alloca %struct.Base, align 4
  %8 = alloca %struct.BaseC, align 4
  store i32 0, ptr %3, align 4
  store i32 %0, ptr %4, align 4
  store ptr %1, ptr %5, align 8
  call void @test_main()
  call void @llvm.memcpy.p0.p0.i64(ptr align 4 %6, ptr align 4 @__const.main.base, i64 12, i1 false)
  call void @llvm.memcpy.p0.p0.i64(ptr align 4 %7, ptr align 4 %6, i64 12, i1 false)
  call void @test_base(ptr noundef %7)
  %9 = call i32 @hh()
  %10 = getelementptr inbounds %struct.BaseC, ptr %8, i32 0, i32 0
  store i32 %9, ptr %10, align 4
  %11 = call i32 (ptr, ...) @printf(ptr noundef @.str.1)
  ret i32 0
}

declare dso_local i32 @printf(ptr noundef, ...) #2

attributes #0 = { noinline nounwind optnone uwtable "min-legal-vector-width"="0" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="x86-64" "target-features"="+cmov,+cx8,+fxsr,+mmx,+sse,+sse2,+x87" "tune-cpu"="generic" }
attributes #1 = { nocallback nofree nounwind willreturn memory(argmem: readwrite) }
attributes #2 = { "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="x86-64" "target-features"="+cmov,+cx8,+fxsr,+mmx,+sse,+sse2,+x87" "tune-cpu"="generic" }

!llvm.module.flags = !{!0, !1, !2, !3}
!llvm.ident = !{!4}

!0 = !{i32 1, !"wchar_size", i32 2}
!1 = !{i32 8, !"PIC Level", i32 2}
!2 = !{i32 7, !"uwtable", i32 2}
!3 = !{i32 1, !"MaxTLSAlign", i32 65536}
!4 = !{!"clang version 17.0.6"}
