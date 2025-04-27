.386p
.model large


seg_desc struc                                   
    limit_l dw 0FFFFh ; low 16 of limit
    base_l dw 0000h ; |  
           db 00h   ; |_ low 24 of base
    access db 0 ; |  is present (1), privelege level (2), type (1)
                ; |  type flags: is code (1), allow lower priv. access / is stack (1), 
                ; |_ readable / writeable (1), 0
    attrs_limit_h db 11001111b ; |  attrs: limit *= 0x1000 (1), 32 bits memory (1), 0, 0
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
idtr struc        
    limit dw 0                            
    idt_l dw 0 ; Смещение биты (0-15)
    idt_h dw 0 ; Смещение биты (31-16)
idtr ends


data segment para use16

    gdt label
        gdt_null_desc seg_desc <0,0,0,0,0,0>                              
        gdt_code_desc seg_desc <,,,10011010b,,>             
        gdt_data_desc seg_desc  <,,,10010010b,,>      
    GDT_END equ $

    gdtr label
        gdt_size dw GDT_END - gdt - 1
        gdt_addr dd gdt

    msg db "Hello world!"

data ends


farjmp macro cs, lbl
    db  0EAh
    dd  offset lbl 
    dw  cs
endm


rcode segment para use16
RCODE_START equ $

assume CS:rcode, DS:data, ES:data
rstart:
    PCODE_DESC equ gdt_code_desc - gdt
    DATA_DESC equ gdt_data_desc - gdt

    mov AX, data                                 
    mov DS, AX                                   
    mov ES, AX                          

    lgdt fword ptr gdtr
    ; lidt fword ptr idtr

    ; enable p-mode
    mov EAX, CR0
    or  AL, 1b 
    mov CR0, EAX

    farjmp PCODE_DESC pstart

rcode ends


pcode segment para use32

assume CS:pcode, DS:data, ES:data
pstart:
    mov AX, data                                 
    mov DS, AX                                   
    mov ES, AX                          

    mov EBX, 0B8000000h

    indicate:
        mov AH, 0Fh
        mov AL, "A"
        mov word ptr [EBX], AX
        jmp indicate

pcode ends


end
