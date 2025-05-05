rcode segment stack                                                      
assume CS:rcode, DS:rcode 


seg_desc struc                                   
    limit_l dw 0FFFFh ; low 16 of limit
    base_l dw 0000h ; low 16 of base
    base_m db 00h ; mid 8 of base
    access db -1 ; |  is present (1), privelege level (2), 1
                 ; |  type flags: is code (1), allow lower priv. access / is stack (1), 
                 ; |_ readable / writeable (1), 0
    attrs_limit_h db -1 ; |  attrs: limit *= 0x1000 (1), 32 bits memory (1), 0, 0
                        ; |_ hight 4 of limit
    base_h db 00h ; high 8 of base
seg_desc ends        


intr_desc struc                                   
    off_l dw 0 ; low 16 of offset
    seg_sel dw 0 ; segment selector inside the gdt
    db 0 ; reserved 8
    params db -1 ; |  is present (1), privelege level (2), 0
                 ; |_ gate type: 0b1110/0b1111 for 32-bit interrupt/trap
    off_h dw 0 ; high 16 of offset
intr_desc ends        


gdtr_idtr struc        
    limit dw 0                            
    addr dd 0 
gdtr_idtr ends


gdt:
    gdt_null seg_desc<0, 0, 0, 0, 0, 0>                              
    gdt_pcode seg_desc<,      ,    , 10011110b, 11001111b, >
    gdt_pdata seg_desc<,      ,    , 10010010b, 11001111b, >       
    gdt_rcode seg_desc<,      ,    , 10011010b, 10001111b, >             
    gdt_rdata seg_desc<,      ,    , 10010010b, 10001111b, >       
    gdt_text  seg_desc<, 8000h, 0Bh, 10010010b, 11001111b, > 
    ;gdt_idt seg_desc<,      ,    ,          ,          , >                  
    gdtr gdtr_idtr<(offset gdtr) - (offset gdt) - 1, (offset gdt)>

PCODE_SEG equ (offset gdt_pcode) - (offset gdt)
PDATA_SEG equ (offset gdt_pdata) - (offset gdt)
RCODE_SEG equ (offset gdt_rcode) - (offset gdt)
RDATA_SEG equ (offset gdt_rdata) - (offset gdt)
TEXT_SEG equ (offset gdt_text) - (offset gdt)


idt:
    irpc N, 0123456789ABCDEF
        idt_0&N intr_desc<0, PCODE_SEG, , 10001111b, 0>
    endm
    irpc N, 0123456789ABCDEF
        idt_1&N intr_desc<0, PCODE_SEG, , 10001111b, 0> 
    endm
    idt_rtc intr_desc<0, PCODE_SEG, , 10001110b, 0>
    idt_kb  intr_desc<0, PCODE_SEG, , 10001110b, 0>
    irpc N, 23456789ABCDEF
        idt_2&N intr_desc<0, PCODE_SEG, , 10001110b, 0>
    endm
    idtr gdtr_idtr<(offset idtr) - (offset idt) - 1, (offset idt)>
    null_idtr gdtr_idtr<0, 0>


start:
    .386p ; enable 32-bit extensions

    fj16 macro seg, lbl
        db 0EAh         ; |
        dd (offset lbl) ; |
        dw seg          ; |_ manually encoded jmp seg:lbl
    endm
    fj32 macro seg, lbl
        db 66h ; specify 32-bit operand
        fj16 seg, lbl
    endm


    mov AX, CS ; | 
    mov DS, AX ; |_ DS = CS, single segment

    ; setup gdt

    ; calculate physical addr for this segment
    mov EAX, CS          
    shl EAX, 4          

    add gdtr.addr, EAX 
    add idtr.addr, EAX 

    ; write physical addresses for rmode into gdt
    mov gdt_rcode.base_l, AX
    mov gdt_rdata.base_l, AX 
    shr EAX, 16
    mov gdt_rcode.base_m, AL
    mov gdt_rcode.base_h, AH
    mov gdt_rdata.base_m, AL
    mov gdt_rdata.base_h, AH

    ; calculate physical addr of protected segment
    mov EAX, pcode                
    shl EAX, 4                  

    ; write physical addresses for pmode into gdt
    mov gdt_pcode.base_l, AX   
    mov gdt_pdata.base_l, AX
    shr EAX, 16
    mov gdt_pcode.base_m, AL
    mov gdt_pcode.base_h, AH
    mov gdt_pdata.base_m, AL
    mov gdt_pdata.base_h, AH

    ; setup idtr

    irpc N, 0123456789ABCDEF                 ;Заполнить векторы 00-0F исключениями
        mov EAX, offset exception_0&N
        mov idt_0&N.off_l, AX
        shr EAX, 16
        mov idt_0&N.off_h, AX
    endm
    irpc N, 0123456789ABCDEF                 ;Заполнить векторы 10-1F исключениями
        mov EAX, offset exception_1&N
        mov idt_1&N.off_l, AX
        shr EAX, 16
        mov idt_1&N.off_h, AX
    endm

    mov EAX, offset nop_irq_master                      ;Поместить обработчик прерывания таймера на 20 шлюз
    mov idt_rtc.off_l, AX
    shr EAX, 16
    mov idt_rtc.off_h, AX

    mov EAX, offset kb_handler                   ;Поместить обработчик прерывания клавиатуры на 21 шлюз
    mov idt_kb.off_l, AX
    shr EAX, 16
    mov idt_kb.off_h, AX

    ; other master interrupts
    irpc N, 234567
        mov EAX, offset nop_irq_master
        mov idt_2&N.off_l, AX
        shr EAX, 16
        mov idt_2&N.off_h, AX
    endm
    
    ; slave interrupts
    irpc N, 89ABCDEF
        mov EAX, offset nop_irq_slave
        mov idt_2&N.off_l, AX
        shr EAX, 16
        mov idt_2&N.off_h, AX
    endm

    ; disable interrupts
    cli
    in AL, 70h       ; | 
    or AL, 10000000b ; |
    out 70h, AL      ; |_ set bit 7 in CMOS register to disable nmi 

    in AL, 92h  ; |
    or AL, 10b  ; |
    out 92h, AL ; |_ set bit 1 in PS/2 to enable A20 line

    ; enter pmode
    lgdt gdtr
    lidt idtr
    mov EAX, CR0 
    or EAX, 1b  
    mov CR0, EAX 

    ; enable interrupts
    in AL, 70h        ; |
    and AL, 01111111b ; |
    out 70h, AL       ; |_ clear bit 7 in CMOS register to enable nmi 
    sti               

    hlt
    fj32 gdt_pcode, pstart

continue:
    ; setup segments
    mov AX, CS ; | 
    mov DS, AX ; | 
    mov SS, AX ; |_ DS = SS = CS, single segment
    mov SP, (offset rstack_end) ; setup stack 


    ; exit
    mov AL, 00h
    mov AH, 4Ch               
    int 21h                  


return_to_rmode:
    lidt null_idtr

    ; back to rmode
    mov EAX, CR0
    and AL, (not 1b)
    mov CR0, EAX 

    fj32 rcode, continue


rstack db 256 dup (?) 
rstack_end:


rcode ends   


pcode segment use32
assume CS:pcode, DS:pcode


pstart:

    ; setup segments
    mov AX, PDATA_SEG          ; |
    mov DS, AX                 ; |
    mov SS, AX                 ; |_ DS = SS = PDATA, single segment
    mov ESP, (offset pstack_end) ; setup stack
    mov AX, TEXT_SEG           ; |
    mov ES, AX                 ; |_ ES = TEXT

    mov DX, 0141h
    lp:
        push AX
        mov AX, DX
        xor EDI, EDI
        mov ECX, 80*3
        rep stosw
        pop AX
        inc DX
        jmp lp

    exit_rmode:
        fj16 gdt_rcode, return_to_rmode


    phexb proc ; DH - value, ES:DI - start address
        push AX

        mov AL, DH
        shr AL, 4
        call phexhalf
        stosw
        mov AL, DH
        call phexhalf
        stosw

        pop AX
        ret

        phexhalf proc ; AL - value to print  ->  AL - char to print
            and AL, 0Fh
            cmp AL, 09h
            jle phexhalf_add_0
            jg phexhalf_add_a

            phexhalf_add_0:
            add AL, ("0" - 00h)
            jmp phexhalf_end_add

            phexhalf_add_a:
            add AL, ("A" - 0Ah)
            jmp phexhalf_end_add

            phexhalf_end_add:
            ret
        phexhalf endp
    phexb endp

    phexw proc ; DX - value, ES:DI - start address
        push DX
        call phexb
        shl DX, 8
        call phexb
        pop DX
    phexw endp

    phexdw proc ; EDX - value, ES:DI - start address
        push DX
        shr EDX, 16
        call phexw
        pop DX
        call phexw
    phexdw endp


    ; interrupt handlers

    M = 0                           
    irpc N, 0123456789ABCDEF
    exception_0&N label word                              ;Обработчики исключений 00h..0Fh
        cli                                         ;Запрет прерываний
        jmp exception_handler
    endm
    M = 010H
    irpc N, 0123456789ABCDEF                        
    exception_1&N label word                              ;Обработчики исключений 10h..1Fh
        cli                                         ;Запрет прерываний
        jmp exception_handler
    endm

    exception_handler proc near                           ;Процедура вывода обработки исключений
        mov  AX, TEXT_SEG                           ;Поместить в ax дескриптор текста
        mov  ES, AX

        mov AL, "E"
        stosw
        mov AL, "I"
        stosw
        mov AL, "P"
        stosw
        mov AL, ":"
        stosw
        pop EAX
        mov EAX, EDX
        call phexdw

        mov AL, "C"
        stosw
        mov AL, "S"
        stosw
        mov AL, ":"
        stosw
        pop EAX
        mov EAX, EDX
        call phexdw

        mov AL, "F"
        stosw
        mov AL, "s"
        stosw
        mov AL, ":"
        stosw
        pop EAX
        mov EAX, EDX
        call phexdw

        sti
        jmp exit_rmode
        fj16 PCODE_SEG exit_rmode
    exception_handler endp

    kb_handler proc near
        push EAX

        in AL, 60h  ; read key scancode
        shl AL, 8

        mov AL, 20h
        out 20h, AL

        inc DX
        cmp AH, 01h
        jne skip_exit
        fj16 PCODE_SEG exit_rmode
        skip_exit:

        pop EAX
        iretd
    kb_handler endp

    nop_irq_master proc near                      ;Заглушка для аппаратных прерываний ведущего контроллера
        push EAX

        mov  AL, 20h
        out  20h, AL

        pop  EAX
        iretd
    nop_irq_master endp

    nop_irq_slave proc near                      ;Заглушка для аппаратных прерываний ведомого контроллера
        push EAX
        mov  AL, 20h
        out  20h, AL
        out  0A0h, AL
        pop  EAX
        iretd
    nop_irq_slave endp


pstack db 256 dup (?)            
pstack_end:


pcode ends


end start
