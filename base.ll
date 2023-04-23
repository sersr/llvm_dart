; ModuleID = './base.c'
source_filename = "./base.c"
target datalayout = "e-m:o-i64:64-i128:128-n32:64-S128"
target triple = "arm64-apple-macosx13.0.0"

%struct.Gen = type { i32, i64, i32 }

@.str = private unnamed_addr constant [7 x i8] c"y: %d\0A\00", align 1
@.str.1 = private unnamed_addr constant [14 x i8] c"64: %ld x %f\0A\00", align 1
@.str.2 = private unnamed_addr constant [7 x i8] c"x: %f\0A\00", align 1
@.str.3 = private unnamed_addr constant [9 x i8] c"str: %s\0A\00", align 1
@__const.printG.ha = private unnamed_addr constant %struct.Gen { i32 22, i64 55, i32 7788 }, align 8
@__const.xxs.xa = private unnamed_addr constant %struct.Gen { i32 1, i64 2, i32 3 }, align 8
@__const.xxs.hh = private unnamed_addr constant %struct.Gen { i32 3, i64 4, i32 5 }, align 8

; Function Attrs: noinline nounwind optnone ssp uwtable
define void @printxx(i32 %0) #0 {
  %2 = alloca i32, align 4
  store i32 %0, i32* %2, align 4
  %3 = load i32, i32* %2, align 4
  %4 = call i32 (i8*, ...) @printf(i8* getelementptr inbounds ([7 x i8], [7 x i8]* @.str, i64 0, i64 0), i32 %3)
  ret void
}

declare i32 @printf(i8*, ...) #1

; Function Attrs: noinline nounwind optnone ssp uwtable
define void @print64(i64 %0) #0 {
  %2 = alloca i64, align 8
  %3 = alloca float, align 4
  %4 = alloca i8*, align 8
  store i64 %0, i64* %2, align 8
  store float 3.000000e+00, float* %3, align 4
  store i8* getelementptr inbounds ([14 x i8], [14 x i8]* @.str.1, i64 0, i64 0), i8** %4, align 8
  %5 = load i8*, i8** %4, align 8
  %6 = call i32 (i8*, ...) @printf(i8* %5, i32 55, double 5.500000e+01)
  ret void
}

; Function Attrs: noinline nounwind optnone ssp uwtable
define void @printfp(float %0) #0 {
  %2 = alloca float, align 4
  store float %0, float* %2, align 4
  %3 = load float, float* %2, align 4
  %4 = fpext float %3 to double
  %5 = call i32 (i8*, ...) @printf(i8* getelementptr inbounds ([7 x i8], [7 x i8]* @.str.2, i64 0, i64 0), double %4)
  ret void
}

; Function Attrs: noinline nounwind optnone ssp uwtable
define void @printstr(i8* %0) #0 {
  %2 = alloca i8*, align 8
  store i8* %0, i8** %2, align 8
  %3 = load i8*, i8** %2, align 8
  %4 = call i32 (i8*, ...) @printf(i8* getelementptr inbounds ([9 x i8], [9 x i8]* @.str.3, i64 0, i64 0), i8* %3)
  ret void
}

; Function Attrs: noinline nounwind optnone ssp uwtable
define void @printG() #0 {
  %1 = alloca %struct.Gen, align 8
  %2 = alloca %struct.Gen, align 8
  %3 = alloca %struct.Gen, align 8
  %4 = alloca %struct.Gen, align 8
  %5 = bitcast %struct.Gen* %1 to i8*
  call void @llvm.memcpy.p0i8.p0i8.i64(i8* align 8 %5, i8* align 8 bitcast (%struct.Gen* @__const.printG.ha to i8*), i64 24, i1 false)
  call void @yy(%struct.Gen* sret(%struct.Gen) align 8 %2, %struct.Gen* %1)
  %6 = bitcast %struct.Gen* %3 to i8*
  %7 = bitcast %struct.Gen* %1 to i8*
  call void @llvm.memcpy.p0i8.p0i8.i64(i8* align 8 %6, i8* align 8 %7, i64 24, i1 false)
  call void @printC(%struct.Gen* %3)
  %8 = bitcast %struct.Gen* %4 to i8*
  %9 = bitcast %struct.Gen* %2 to i8*
  call void @llvm.memcpy.p0i8.p0i8.i64(i8* align 8 %8, i8* align 8 %9, i64 24, i1 false)
  call void @printC(%struct.Gen* %4)
  ret void
}

; Function Attrs: argmemonly nofree nounwind willreturn
declare void @llvm.memcpy.p0i8.p0i8.i64(i8* noalias nocapture writeonly, i8* noalias nocapture readonly, i64, i1 immarg) #2

declare void @yy(%struct.Gen* sret(%struct.Gen) align 8, %struct.Gen*) #1

declare void @printC(%struct.Gen*) #1

; Function Attrs: noinline nounwind optnone ssp uwtable
define void @xxs(%struct.Gen* noalias sret(%struct.Gen) align 8 %0, i32 %1) #0 {
  %3 = alloca i32, align 4
  %4 = alloca %struct.Gen, align 8
  store i32 %1, i32* %3, align 4
  %5 = load i32, i32* %3, align 4
  %6 = icmp eq i32 %5, 10
  br i1 %6, label %7, label %9

7:                                                ; preds = %2
  %8 = bitcast %struct.Gen* %0 to i8*
  call void @llvm.memcpy.p0i8.p0i8.i64(i8* align 8 %8, i8* align 8 bitcast (%struct.Gen* @__const.xxs.xa to i8*), i64 24, i1 false)
  br label %13

9:                                                ; preds = %2
  %10 = bitcast %struct.Gen* %4 to i8*
  call void @llvm.memcpy.p0i8.p0i8.i64(i8* align 8 %10, i8* align 8 bitcast (%struct.Gen* @__const.xxs.hh to i8*), i64 24, i1 false)
  %11 = bitcast %struct.Gen* %0 to i8*
  %12 = bitcast %struct.Gen* %4 to i8*
  call void @llvm.memcpy.p0i8.p0i8.i64(i8* align 8 %11, i8* align 8 %12, i64 24, i1 false)
  br label %13

13:                                               ; preds = %9, %7
  ret void
}

attributes #0 = { noinline nounwind optnone ssp uwtable "frame-pointer"="non-leaf" "min-legal-vector-width"="0" "no-trapping-math"="true" "probe-stack"="__chkstk_darwin" "stack-protector-buffer-size"="8" "target-cpu"="apple-m1" "target-features"="+aes,+crc,+crypto,+dotprod,+fp-armv8,+fp16fml,+fullfp16,+lse,+neon,+ras,+rcpc,+rdm,+sha2,+sha3,+sm4,+v8.5a,+zcm,+zcz" }
attributes #1 = { "frame-pointer"="non-leaf" "no-trapping-math"="true" "probe-stack"="__chkstk_darwin" "stack-protector-buffer-size"="8" "target-cpu"="apple-m1" "target-features"="+aes,+crc,+crypto,+dotprod,+fp-armv8,+fp16fml,+fullfp16,+lse,+neon,+ras,+rcpc,+rdm,+sha2,+sha3,+sm4,+v8.5a,+zcm,+zcz" }
attributes #2 = { argmemonly nofree nounwind willreturn }

!llvm.module.flags = !{!0, !1, !2, !3, !4, !5, !6, !7, !8}
!llvm.ident = !{!9}

!0 = !{i32 2, !"SDK Version", [2 x i32] [i32 13, i32 1]}
!1 = !{i32 1, !"wchar_size", i32 4}
!2 = !{i32 1, !"branch-target-enforcement", i32 0}
!3 = !{i32 1, !"sign-return-address", i32 0}
!4 = !{i32 1, !"sign-return-address-all", i32 0}
!5 = !{i32 1, !"sign-return-address-with-bkey", i32 0}
!6 = !{i32 7, !"PIC Level", i32 2}
!7 = !{i32 7, !"uwtable", i32 1}
!8 = !{i32 7, !"frame-pointer", i32 1}
!9 = !{!"Apple clang version 14.0.0 (clang-1400.0.29.202)"}
