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
    off_l dw 0 ; Адрес обработчика (0:15)
    selector dw 0 ; Селектор кода, содержащего код обработчика
    param_count db 0 ; Параметры
    access db 0 ; Уровень доступа
    off_h dw 0 ; Адрес обработчика (31:16)
intr_desc ends        


; needs to be at the start
gdt seg_desc <0,0,0,0,0,0>                              
gdt_pcode seg_desc <,      ,    , 10011110b, 11001111b, >
gdt_pdata seg_desc <,      ,    , 10010010b, 11001111b, >       
gdt_rcode seg_desc <,      ,    , 10011010b, 10001111b, >             
gdt_rdata seg_desc <,      ,    , 10010010b, 10001111b, >       
gdt_text seg_desc  <, 8000h, 0Bh, 10010010b, 11001111b, > 
;gdt_idt seg_desc   <,      ,    ,          ,          , >                  
gdt_limit dw (offset gdt_limit) - (offset gdt) - 1
gdt_addr dd (offset gdt)


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
    xor EAX, EAX 
    mov AX, CS          
    shl EAX, 4          

    add [gdt_addr], EAX 

    ; write physical addresses for rmode into gdt
    mov word ptr [gdt_rcode+2], AX  
    mov word ptr [gdt_rdata+2], AX 
    shr EAX, 16
    mov byte ptr [gdt_rcode+4], AL
    mov byte ptr [gdt_rcode+7], AH
    mov byte ptr [gdt_rdata+4], AL
    mov byte ptr [gdt_rdata+7], AH

    ; calculate physical addr of protected segment
    xor EAX, EAX 
    mov AX, pcode                
    shl EAX, 4                  

    ; write physical addresses for pmode into gdt
    mov word ptr [gdt_pcode+2], AX   
    mov word ptr [gdt_pdata+2], AX
    shr EAX, 16
    mov byte ptr [gdt_pcode+4], AL
    mov byte ptr [gdt_pcode+7], AH
    mov byte ptr [gdt_pdata+4], AL
    mov byte ptr [gdt_pdata+7], AH

    ; disable interrupts
    cli
    in AL, 70h       ; | 
    or AL, 10000000b ; |
    out 70h, AL      ; |_ set bit 7 in CMOS register to disable nmi 

    in AL, 92h  ; |
    or AL, 10b  ; |
    out 92h, AL ; |_ set bit 1 in PS/2 to enable A20 line

    ; enter pmode

    lgdt qword ptr [gdt_limit]

    mov EAX, CR0 
    or EAX, 1b  
    mov CR0, EAX 

    fj32 gdt_pcode, pstart

continue:
    ; setup segments
    mov AX, CS ; | 
    mov DS, AX ; | 
    mov SS, AX ; |_ DS = SS = CS, single segment
    mov SP, (offset rstack_end) ; setup stack 

    ; enable interrupts
    in AL, 70h        ; |
    and AL, 01111111b ; |
    out 70h, AL       ; |_ clear bit 7 in CMOS register to enable nmi 
    sti               

    ; exit
    mov AL, 00h
    mov AH, 4Ch               
    int 21h                  


return_to_rmode:
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
    mov AX, (offset gdt_pdata) ; |
    mov DS, AX                 ; |
    mov SS, AX                 ; |_ DS = SS = PDATA, single segment
    mov ESP, (offset pstack_end) ; setup stack
    mov AX, (offset gdt_text)  ; |
    mov ES, AX                 ; |_ ES = TEXT

    xor  EDI, EDI
    mov  ECX, 80*25 
    mov  AX, 0141h
    rep  stosw

    wait_esc:
        in AL, 60h  ; |
        cmp AL, 01h ; |_ check if scancode is ESC 
        jne wait_esc

    mov AX, (offset gdt_rcode)
    mov DS, AX                   

    fj16 gdt_rcode, return_to_rmode


pstack db 256 dup (?)            
pstack_end:


pcode ends


end start
