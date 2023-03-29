; ModuleID = './base.c'
source_filename = "./base.c"
target datalayout = "e-m:o-i64:64-i128:128-n32:64-S128"
target triple = "arm64-apple-macosx13.0.0"

%struct.Gen = type { i32, i32, i32 }

@__const.getGen.g = private unnamed_addr constant %struct.Gen { i32 10, i32 555, i32 224 }, align 4
@.str = private unnamed_addr constant [12 x i8] c"hhhhh : %d\0A\00", align 1
@.str.1 = private unnamed_addr constant [7 x i8] c"y: %d\0A\00", align 1
@.str.2 = private unnamed_addr constant [15 x i8] c"gen: %d %d %d\0A\00", align 1
@.str.3 = private unnamed_addr constant [8 x i8] c"... %d\0A\00", align 1
@.str.4 = private unnamed_addr constant [12 x i8] c"... ......\0A\00", align 1
@__const.stra.ss = private unnamed_addr constant %struct.Gen { i32 301, i32 544442, i32 553 }, align 4
@.str.5 = private unnamed_addr constant [24 x i8] c"gen y: %d x: %d z: %d \0A\00", align 1
@.str.6 = private unnamed_addr constant [7 x i8] c"ggg%d,\00", align 1
@__const.cG.g = private unnamed_addr constant %struct.Gen { i32 15, i32 11, i32 11 }, align 4

; Function Attrs: noinline nounwind optnone ssp uwtable
define [2 x i64] @getGen() #0 {
  %1 = alloca %struct.Gen, align 4
  %2 = alloca [2 x i64], align 8
  %3 = bitcast %struct.Gen* %1 to i8*
  call void @llvm.memcpy.p0i8.p0i8.i64(i8* align 4 %3, i8* align 4 bitcast (%struct.Gen* @__const.getGen.g to i8*), i64 12, i1 false)
  %4 = bitcast [2 x i64]* %2 to i8*
  %5 = bitcast %struct.Gen* %1 to i8*
  call void @llvm.memcpy.p0i8.p0i8.i64(i8* align 8 %4, i8* align 4 %5, i64 12, i1 false)
  %6 = load [2 x i64], [2 x i64]* %2, align 8
  ret [2 x i64] %6
}

; Function Attrs: argmemonly nofree nounwind willreturn
declare void @llvm.memcpy.p0i8.p0i8.i64(i8* noalias nocapture writeonly, i8* noalias nocapture readonly, i64, i1 immarg) #1

; Function Attrs: noinline nounwind optnone ssp uwtable
define i32 @printxx(i32 %0) #0 {
  %2 = alloca i32, align 4
  %3 = alloca i32, align 4
  store i32 %0, i32* %2, align 4
  %4 = call i32 bitcast (i32 (...)* @hhh to i32 ()*)()
  store i32 %4, i32* %3, align 4
  %5 = load i32, i32* %3, align 4
  %6 = call i32 (i8*, ...) @printf(i8* getelementptr inbounds ([12 x i8], [12 x i8]* @.str, i64 0, i64 0), i32 %5)
  %7 = load i32, i32* %2, align 4
  %8 = call i32 (i8*, ...) @printf(i8* getelementptr inbounds ([7 x i8], [7 x i8]* @.str.1, i64 0, i64 0), i32 %7)
  ret i32 11
}

declare i32 @hhh(...) #2

declare i32 @printf(i8*, ...) #2

; Function Attrs: noinline nounwind optnone ssp uwtable
define void @strx(i32 %0, %struct.Gen* %1) #0 {
  %3 = alloca i32, align 4
  %4 = alloca %struct.Gen*, align 8
  store i32 %0, i32* %3, align 4
  store %struct.Gen* %1, %struct.Gen** %4, align 8
  %5 = load i32, i32* %3, align 4
  %6 = load %struct.Gen*, %struct.Gen** %4, align 8
  %7 = getelementptr inbounds %struct.Gen, %struct.Gen* %6, i32 0, i32 0
  %8 = load i32, i32* %7, align 4
  %9 = call i32 (i8*, ...) @printf(i8* getelementptr inbounds ([15 x i8], [15 x i8]* @.str.2, i64 0, i64 0), i32 %5, i32 %8, i32 8)
  ret void
}

; Function Attrs: noinline nounwind optnone ssp uwtable
define void @stra([2 x i64] %0) #0 {
  %2 = alloca %struct.Gen, align 4
  %3 = alloca [2 x i64], align 8
  %4 = alloca %struct.Gen, align 4
  %5 = alloca %struct.Gen, align 4
  %6 = alloca [2 x i64], align 8
  %7 = alloca [2 x i64], align 8
  store [2 x i64] %0, [2 x i64]* %3, align 8
  %8 = bitcast %struct.Gen* %2 to i8*
  %9 = bitcast [2 x i64]* %3 to i8*
  call void @llvm.memcpy.p0i8.p0i8.i64(i8* align 4 %8, i8* align 8 %9, i64 12, i1 false)
  %10 = getelementptr inbounds %struct.Gen, %struct.Gen* %2, i32 0, i32 0
  %11 = load i32, i32* %10, align 4
  %12 = call i32 (i8*, ...) @printf(i8* getelementptr inbounds ([8 x i8], [8 x i8]* @.str.3, i64 0, i64 0), i32 %11)
  %13 = call i32 (i8*, ...) @printf(i8* getelementptr inbounds ([12 x i8], [12 x i8]* @.str.4, i64 0, i64 0))
  %14 = bitcast %struct.Gen* %4 to i8*
  call void @llvm.memcpy.p0i8.p0i8.i64(i8* align 4 %14, i8* align 4 bitcast (%struct.Gen* @__const.stra.ss to i8*), i64 12, i1 false)
  %15 = bitcast [2 x i64]* %6 to i8*
  %16 = bitcast %struct.Gen* %4 to i8*
  call void @llvm.memcpy.p0i8.p0i8.i64(i8* align 8 %15, i8* align 4 %16, i64 12, i1 false)
  %17 = load [2 x i64], [2 x i64]* %6, align 8
  %18 = call [2 x i64] @yy(i32 12, [2 x i64] %17)
  store [2 x i64] %18, [2 x i64]* %7, align 8
  %19 = bitcast %struct.Gen* %5 to i8*
  %20 = bitcast [2 x i64]* %7 to i8*
  call void @llvm.memcpy.p0i8.p0i8.i64(i8* align 4 %19, i8* align 8 %20, i64 12, i1 false)
  %21 = getelementptr inbounds %struct.Gen, %struct.Gen* %5, i32 0, i32 0
  %22 = load i32, i32* %21, align 4
  %23 = getelementptr inbounds %struct.Gen, %struct.Gen* %5, i32 0, i32 1
  %24 = load i32, i32* %23, align 4
  %25 = getelementptr inbounds %struct.Gen, %struct.Gen* %5, i32 0, i32 2
  %26 = load i32, i32* %25, align 4
  %27 = call i32 (i8*, ...) @printf(i8* getelementptr inbounds ([24 x i8], [24 x i8]* @.str.5, i64 0, i64 0), i32 %22, i32 %24, i32 %26)
  ret void
}

declare [2 x i64] @yy(i32, [2 x i64]) #2

; Function Attrs: noinline nounwind optnone ssp uwtable
define void @ggg(%struct.Gen* %0) #0 {
  %2 = alloca %struct.Gen*, align 8
  %3 = alloca i32, align 4
  %4 = alloca i64, align 8
  store %struct.Gen* %0, %struct.Gen** %2, align 8
  %5 = load %struct.Gen*, %struct.Gen** %2, align 8
  %6 = getelementptr inbounds %struct.Gen, %struct.Gen* %5, i32 0, i32 0
  %7 = load i32, i32* %6, align 4
  store i32 %7, i32* %3, align 4
  %8 = load i32, i32* %3, align 4
  %9 = icmp sgt i32 %8, 10
  br i1 %9, label %10, label %11

10:                                               ; preds = %1
  store i64 10101, i64* %4, align 8
  br label %11

11:                                               ; preds = %10, %1
  %12 = load i32, i32* %3, align 4
  %13 = call i32 (i8*, ...) @printf(i8* getelementptr inbounds ([7 x i8], [7 x i8]* @.str.6, i64 0, i64 0), i32 %12)
  ret void
}

; Function Attrs: noinline nounwind optnone ssp uwtable
define void @hhhaa([2 x i64] %0) #0 {
  %2 = alloca %struct.Gen, align 4
  %3 = alloca [2 x i64], align 8
  %4 = alloca i32, align 4
  store [2 x i64] %0, [2 x i64]* %3, align 8
  %5 = bitcast %struct.Gen* %2 to i8*
  %6 = bitcast [2 x i64]* %3 to i8*
  call void @llvm.memcpy.p0i8.p0i8.i64(i8* align 4 %5, i8* align 8 %6, i64 12, i1 false)
  %7 = getelementptr inbounds %struct.Gen, %struct.Gen* %2, i32 0, i32 0
  %8 = load i32, i32* %7, align 4
  store i32 %8, i32* %4, align 4
  ret void
}

; Function Attrs: noinline nounwind optnone ssp uwtable
define [2 x i64] @cG() #0 {
  %1 = alloca %struct.Gen, align 4
  %2 = alloca i32, align 4
  %3 = alloca [2 x i64], align 8
  %4 = bitcast %struct.Gen* %1 to i8*
  call void @llvm.memcpy.p0i8.p0i8.i64(i8* align 4 %4, i8* align 4 bitcast (%struct.Gen* @__const.cG.g to i8*), i64 12, i1 false)
  %5 = getelementptr inbounds %struct.Gen, %struct.Gen* %1, i32 0, i32 2
  %6 = load i32, i32* %5, align 4
  store i32 %6, i32* %2, align 4
  %7 = bitcast [2 x i64]* %3 to i8*
  %8 = bitcast %struct.Gen* %1 to i8*
  call void @llvm.memcpy.p0i8.p0i8.i64(i8* align 8 %7, i8* align 4 %8, i64 12, i1 false)
  %9 = load [2 x i64], [2 x i64]* %3, align 8
  ret [2 x i64] %9
}

attributes #0 = { noinline nounwind optnone ssp uwtable "frame-pointer"="non-leaf" "min-legal-vector-width"="0" "no-trapping-math"="true" "probe-stack"="__chkstk_darwin" "stack-protector-buffer-size"="8" "target-cpu"="apple-m1" "target-features"="+aes,+crc,+crypto,+dotprod,+fp-armv8,+fp16fml,+fullfp16,+lse,+neon,+ras,+rcpc,+rdm,+sha2,+sha3,+sm4,+v8.5a,+zcm,+zcz" }
attributes #1 = { argmemonly nofree nounwind willreturn }
attributes #2 = { "frame-pointer"="non-leaf" "no-trapping-math"="true" "probe-stack"="__chkstk_darwin" "stack-protector-buffer-size"="8" "target-cpu"="apple-m1" "target-features"="+aes,+crc,+crypto,+dotprod,+fp-armv8,+fp16fml,+fullfp16,+lse,+neon,+ras,+rcpc,+rdm,+sha2,+sha3,+sm4,+v8.5a,+zcm,+zcz" }

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
