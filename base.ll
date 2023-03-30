; ModuleID = './base.c'
source_filename = "./base.c"
target datalayout = "e-m:o-i64:64-i128:128-n32:64-S128"
target triple = "arm64-apple-macosx13.0.0"

%struct.Gen = type { i32, i32, i32 }

@__const.getGen.g = private unnamed_addr constant %struct.Gen { i32 10, i32 555, i32 224 }, align 4
@.str = private unnamed_addr constant [7 x i8] c"y: %d\0A\00", align 1
@.str.1 = private unnamed_addr constant [14 x i8] c"xxa: y_p: %d\0A\00", align 1
@.str.2 = private unnamed_addr constant [15 x i8] c"gen: %d %d %d\0A\00", align 1
@__const.stra.ss = private unnamed_addr constant %struct.Gen { i32 301, i32 544442, i32 553 }, align 4

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
  store i32 %0, i32* %2, align 4
  %3 = load i32, i32* %2, align 4
  %4 = call i32 (i8*, ...) @printf(i8* getelementptr inbounds ([7 x i8], [7 x i8]* @.str, i64 0, i64 0), i32 %3)
  ret i32 11
}

declare i32 @printf(i8*, ...) #2

; Function Attrs: noinline nounwind optnone ssp uwtable
define i32 @printxxa(i32* %0) #0 {
  %2 = alloca i32*, align 8
  store i32* %0, i32** %2, align 8
  %3 = load i32*, i32** %2, align 8
  %4 = load i32, i32* %3, align 4
  %5 = call i32 (i8*, ...) @printf(i8* getelementptr inbounds ([14 x i8], [14 x i8]* @.str.1, i64 0, i64 0), i32 %4)
  %6 = load i32*, i32** %2, align 8
  store i32 50505, i32* %6, align 4
  ret i32 1
}

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
define void @stra() #0 {
  %1 = alloca %struct.Gen, align 4
  %2 = alloca [2 x i64], align 8
  %3 = alloca %struct.Gen, align 4
  %4 = alloca [2 x i64], align 8
  %5 = bitcast %struct.Gen* %1 to i8*
  call void @llvm.memcpy.p0i8.p0i8.i64(i8* align 4 %5, i8* align 4 bitcast (%struct.Gen* @__const.stra.ss to i8*), i64 12, i1 false)
  %6 = bitcast [2 x i64]* %2 to i8*
  %7 = bitcast %struct.Gen* %1 to i8*
  call void @llvm.memcpy.p0i8.p0i8.i64(i8* align 8 %6, i8* align 4 %7, i64 12, i1 false)
  %8 = load [2 x i64], [2 x i64]* %2, align 8
  %9 = call [2 x i64] @yy(i32 12, [2 x i64] %8)
  store [2 x i64] %9, [2 x i64]* %4, align 8
  %10 = bitcast %struct.Gen* %3 to i8*
  %11 = bitcast [2 x i64]* %4 to i8*
  call void @llvm.memcpy.p0i8.p0i8.i64(i8* align 4 %10, i8* align 8 %11, i64 12, i1 false)
  ret void
}

declare [2 x i64] @yy(i32, [2 x i64]) #2

; Function Attrs: noinline nounwind optnone ssp uwtable
define void @hhhx([2 x i64] %0) #0 {
  %2 = alloca %struct.Gen, align 4
  %3 = alloca [2 x i64], align 8
  store [2 x i64] %0, [2 x i64]* %3, align 8
  %4 = bitcast %struct.Gen* %2 to i8*
  %5 = bitcast [2 x i64]* %3 to i8*
  call void @llvm.memcpy.p0i8.p0i8.i64(i8* align 4 %4, i8* align 8 %5, i64 12, i1 false)
  ret void
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
