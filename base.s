	.section	__TEXT,__text,regular,pure_instructions
	.build_version macos, 13, 0	sdk_version 13, 1
	.globl	_printxx                        ; -- Begin function printxx
	.p2align	2
_printxx:                               ; @printxx
	.cfi_startproc
; %bb.0:
	sub	sp, sp, #32
	stp	x29, x30, [sp, #16]             ; 16-byte Folded Spill
	add	x29, sp, #16
	.cfi_def_cfa w29, 16
	.cfi_offset w30, -8
	.cfi_offset w29, -16
	stur	w0, [x29, #-4]
	ldur	w9, [x29, #-4]
                                        ; implicit-def: $x8
	mov	x8, x9
	mov	x9, sp
	str	x8, [x9]
	adrp	x0, l_.str@PAGE
	add	x0, x0, l_.str@PAGEOFF
	bl	_printf
	ldp	x29, x30, [sp, #16]             ; 16-byte Folded Reload
	add	sp, sp, #32
	ret
	.cfi_endproc
                                        ; -- End function
	.section	__TEXT,__literal8,8byte_literals
	.p2align	3                               ; -- Begin function print64
lCPI1_0:
	.quad	0x404b800000000000              ; double 55
	.section	__TEXT,__text,regular,pure_instructions
	.globl	_print64
	.p2align	2
_print64:                               ; @print64
	.cfi_startproc
; %bb.0:
	sub	sp, sp, #64
	stp	x29, x30, [sp, #48]             ; 16-byte Folded Spill
	add	x29, sp, #48
	.cfi_def_cfa w29, 16
	.cfi_offset w30, -8
	.cfi_offset w29, -16
	stur	x0, [x29, #-8]
	fmov	s0, #3.00000000
	stur	s0, [x29, #-12]
	adrp	x8, l_.str.1@PAGE
	add	x8, x8, l_.str.1@PAGEOFF
	str	x8, [sp, #24]
	ldr	x0, [sp, #24]
	mov	x8, sp
	mov	x9, #55
	str	x9, [x8]
	adrp	x9, lCPI1_0@PAGE
	ldr	d0, [x9, lCPI1_0@PAGEOFF]
	str	d0, [x8, #8]
	bl	_printf
	ldp	x29, x30, [sp, #48]             ; 16-byte Folded Reload
	add	sp, sp, #64
	ret
	.cfi_endproc
                                        ; -- End function
	.globl	_printfp                        ; -- Begin function printfp
	.p2align	2
_printfp:                               ; @printfp
	.cfi_startproc
; %bb.0:
	sub	sp, sp, #48
	stp	x29, x30, [sp, #32]             ; 16-byte Folded Spill
	add	x29, sp, #32
	.cfi_def_cfa w29, 16
	.cfi_offset w30, -8
	.cfi_offset w29, -16
	sub	x8, x29, #4
	stur	s0, [x29, #-4]
	str	x8, [sp, #16]
	ldr	x8, [sp, #16]
	ldr	s0, [x8]
	fcvt	d0, s0
	mov	x8, sp
	str	d0, [x8]
	adrp	x0, l_.str.2@PAGE
	add	x0, x0, l_.str.2@PAGEOFF
	bl	_printf
	ldp	x29, x30, [sp, #32]             ; 16-byte Folded Reload
	add	sp, sp, #48
	ret
	.cfi_endproc
                                        ; -- End function
	.globl	_printstr                       ; -- Begin function printstr
	.p2align	2
_printstr:                              ; @printstr
	.cfi_startproc
; %bb.0:
	sub	sp, sp, #32
	stp	x29, x30, [sp, #16]             ; 16-byte Folded Spill
	add	x29, sp, #16
	.cfi_def_cfa w29, 16
	.cfi_offset w30, -8
	.cfi_offset w29, -16
	str	x0, [sp, #8]
	ldr	x8, [sp, #8]
	mov	x9, sp
	str	x8, [x9]
	adrp	x0, l_.str.3@PAGE
	add	x0, x0, l_.str.3@PAGEOFF
	bl	_printf
	ldp	x29, x30, [sp, #16]             ; 16-byte Folded Reload
	add	sp, sp, #32
	ret
	.cfi_endproc
                                        ; -- End function
	.globl	_printG                         ; -- Begin function printG
	.p2align	2
_printG:                                ; @printG
	.cfi_startproc
; %bb.0:
	sub	sp, sp, #128
	stp	x29, x30, [sp, #112]            ; 16-byte Folded Spill
	add	x29, sp, #112
	.cfi_def_cfa w29, 16
	.cfi_offset w30, -8
	.cfi_offset w29, -16
	adrp	x8, l___const.printG.ha@PAGE
	add	x8, x8, l___const.printG.ha@PAGEOFF
	ldr	q0, [x8]
	sub	x0, x29, #32
	stur	q0, [x29, #-32]
	ldr	x8, [x8, #16]
	stur	x8, [x29, #-16]
	add	x8, sp, #56
	bl	_yy
	ldur	q0, [x29, #-32]
	add	x0, sp, #32
	str	q0, [sp, #32]
	ldur	x8, [x29, #-16]
	str	x8, [sp, #48]
	bl	_printC
	ldur	q0, [sp, #56]
	mov	x0, sp
	str	q0, [sp]
	ldr	x8, [sp, #72]
	str	x8, [sp, #16]
	bl	_printC
	ldp	x29, x30, [sp, #112]            ; 16-byte Folded Reload
	add	sp, sp, #128
	ret
	.cfi_endproc
                                        ; -- End function
	.globl	_xxs                            ; -- Begin function xxs
	.p2align	2
_xxs:                                   ; @xxs
	.cfi_startproc
; %bb.0:
	sub	sp, sp, #48
	.cfi_def_cfa_offset 48
	str	x8, [sp, #8]                    ; 8-byte Folded Spill
	str	w0, [sp, #44]
	ldr	w8, [sp, #44]
	subs	w8, w8, #10
	b.ne	LBB5_2
	b	LBB5_1
LBB5_1:
	ldr	x9, [sp, #8]                    ; 8-byte Folded Reload
	adrp	x8, l___const.xxs.xa@PAGE
	add	x8, x8, l___const.xxs.xa@PAGEOFF
	ldr	q0, [x8]
	str	q0, [x9]
	ldr	x8, [x8, #16]
	str	x8, [x9, #16]
	b	LBB5_3
LBB5_2:
	ldr	x9, [sp, #8]                    ; 8-byte Folded Reload
	adrp	x8, l___const.xxs.hh@PAGE
	add	x8, x8, l___const.xxs.hh@PAGEOFF
	ldr	q0, [x8]
	str	q0, [sp, #16]
	ldr	x8, [x8, #16]
	str	x8, [sp, #32]
	ldr	q0, [sp, #16]
	str	q0, [x9]
	ldr	x8, [sp, #32]
	str	x8, [x9, #16]
	b	LBB5_3
LBB5_3:
	add	sp, sp, #48
	ret
	.cfi_endproc
                                        ; -- End function
	.section	__TEXT,__cstring,cstring_literals
l_.str:                                 ; @.str
	.asciz	"y 1111: %d\n"

l_.str.1:                               ; @.str.1
	.asciz	"64: %ld x %f\n"

l_.str.2:                               ; @.str.2
	.asciz	"x: %f\n"

l_.str.3:                               ; @.str.3
	.asciz	"str: %s\n"

	.section	__TEXT,__const
	.p2align	3                               ; @__const.printG.ha
l___const.printG.ha:
	.long	22                              ; 0x16
	.space	4
	.quad	55                              ; 0x37
	.long	7788                            ; 0x1e6c
	.space	4

	.p2align	3                               ; @__const.xxs.xa
l___const.xxs.xa:
	.long	1                               ; 0x1
	.space	4
	.quad	2                               ; 0x2
	.long	3                               ; 0x3
	.space	4

	.p2align	3                               ; @__const.xxs.hh
l___const.xxs.hh:
	.long	3                               ; 0x3
	.space	4
	.quad	4                               ; 0x4
	.long	5                               ; 0x5
	.space	4

.subsections_via_symbols
