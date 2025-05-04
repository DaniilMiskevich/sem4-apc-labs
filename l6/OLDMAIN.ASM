.386p
.model large


; farjmp macro cs, lbl
;     db  0EAh
;     dd  offset lbl 
;     dw  cs
; endm


write MACRO msg
    push AX
    push DX

    mov AH, 09h
    mov DX, offset msg
    int 21h

    pop DX
    pop AX
ENDM


rcode segment para use16

assume CS:rcode, DS:data, ES:data
rstart:
START:
    ;mov AX, data                                 
    ;mov DS, AX                                   
    ;mov ES, AX                          

    ;sti

    ;lgdt fword ptr gdtr
    ;; lidt fword ptr idtr

    ;; enable p-mode
    ;mov EAX, CR0
    ;or  AL, 1b 
    ;mov CR0, EAX

    ;lea EDI, pstart
    ;mov EAX, CODE_DESC
    ;push EAX
    ;push EDI

    ;farjmp CODE_DESC pstart
        mov ax,DATA                                 
        mov ds,ax                                   
        mov es,ax                          
        mov ds:[TIME], al
        call FILL_CR_0_BUFFER_RM
    PREPARE_RTC:                                    ;Подготовка часов RTC 
        mov al,0Bh
        out 70h,al                                  ;Выбрать регистр состояния 0Bh
        in  al,71h                                  
        or  al,00000100b                            ;Установить бит DM в 1 - формат представления время в двоичном виде
        out 71h,al                                  
    ENABLE_A20:                                     ;Открыть линию A20(to get more address memory)
        in  al,92h                                                                              
        or  al,2                                    ;Установить бит 1 в 1                                                   
        out 92h,al           
    SAVE_MASK:                                      ;Сохранить маски прерываний     
        in      al,21h
        mov     INT_MASK_M,al                  
        in      al,0A1h
        mov     INT_MASK_S,al                 
    DISABLE_INTERRUPTS:                             ;Запрет маскируемых и немаскируемых прерываний        
        cli                                         ;Запрет маскирумых прерываний
        in  al,70h	
        or	al,10000000b                            ;Установить 7 бит в 1 для запрета немаскируемых прерываний
        out	70h,al
        nop	                                        ;skip tackt
    LOAD_GDT:                                       ;Заполнить глобальную таблицу дескрипторов            
        mov ax,DATA
        mov dl,ah
        xor dh,dh
        shl ax,4
        shr dx,4
        mov si,ax
        mov di,dx
    WRITE_GDT:                                      ;Заполнить дескриптор GDT
        lea bx,GDT_GDT
        mov ax,si
        mov dx,di
        add ax,offset GDT
        adc dx,0
        mov [bx][S_DESC.BASE_L],ax
        mov [bx][S_DESC.BASE_M],dl
        mov [bx][S_DESC.BASE_H],dh
    WRITE_CODE_RM:                                  ;Заполнить дескриптор сегмента кода реального режима
        lea bx,GDT_CODE_RM
        mov ax,cs
        xor dh,dh
        mov dl,ah
        shl ax,4
        shr dx,4
        mov [bx][S_DESC.BASE_L],ax
        mov [bx][S_DESC.BASE_M],dl
        mov [bx][S_DESC.BASE_H],dh
    WRITE_DATA:                                     ;Записать дескриптор сегмента данных
        lea bx,GDT_DATA
        mov ax,si
        mov dx,di
        mov [bx][S_DESC.BASE_L],ax
        mov [bx][S_DESC.BASE_M],dl
        mov [bx][S_DESC.BASE_H],dh
    WRITE_STACK:                                    ;Записать дескриптор сегмента стека
        lea bx, GDT_STACK
        mov ax,ss
        xor dh,dh
        mov dl,ah
        shl ax,4
        shr dx,4
        mov [bx][S_DESC.BASE_L],ax
        mov [bx][S_DESC.BASE_M],dl
        mov [bx][S_DESC.BASE_H],dh
    WRITE_CODE_PM:                                  ;Записать дескриптор кода защищенного режима
        lea bx,GDT_CODE_PM
        mov ax,pcode
        xor dh,dh
        mov dl,ah
        shl ax,4
        shr dx,4
        mov [bx][S_DESC.BASE_L],ax
        mov [bx][S_DESC.BASE_M],dl
        mov [bx][S_DESC.BASE_H],dh        
    WRITE_IDT:                                      ;Записать дескриптор IDT
        lea bx,GDT_IDT
        mov ax,si
        mov dx,di
        add ax,OFFSET IDT
        adc dx,0
        mov [bx][S_DESC.BASE_L],ax
        mov [bx][S_DESC.BASE_M],dl
        mov [bx][S_DESC.BASE_H],dh        
        mov IDTR.IDT_L,ax
        mov IDTR.IDT_H,dx
    FILL_IDT:                                       ;Заполнить таблицу дескрипторов векторов прерываний
        irpc    N, 0123456789ABCDEF                 ;Заполнить векторы 00-0F исключениями
            lea eax, EXC_0&N
            mov IDT_0&N.OFFS_L,ax
            shr eax, 16
            mov IDT_0&N.OFFS_H,ax
        endm
        irpc    N, 0123456789ABCDEF                 ;Заполнить векторы 10-1F исключениями
            lea eax, EXC_1&N
            mov IDT_1&N.OFFS_L,ax
            shr eax, 16
            mov IDT_1&N.OFFS_H,ax
        endm

        lea eax, TIMER_HANDLER                      ;Поместить обработчик прерывания таймера на 20 шлюз
        mov IDT_TIMER.OFFS_L,ax
        shr eax, 16
        mov IDT_TIMER.OFFS_H,ax

        lea eax, KEYBOARD_HANDLER                   ;Поместить обработчик прерывания клавиатуры на 21 шлюз
        mov IDT_KEYBOARD.OFFS_L,ax
        shr eax, 16
        mov IDT_KEYBOARD.OFFS_H,ax

        irpc    N, 234567                           ;Заполнить вектора 22-27 заглушками
            lea eax,IDLE_IRQ_MASTER
            mov IDT_2&N.OFFS_L, AX
            shr eax,16
            mov IDT_2&N.OFFS_H, AX
        endm
        
        irpc    N, 89ABCDEF                         ;Заполнить вектора 28-2F заглушками
            lea eax,IDLE_IRQ_SLAVE
            mov IDT_2&N.OFFS_L,ax
            shr eax,16
            mov IDT_2&N.OFFS_H,ax
        endm
        lgdt fword ptr GDT_GDT                      ;Загрузить регистр GDTR
        lidt fword ptr IDTR                         ;Загрузить регистр IDTR
        mov eax,cr0                                 ;Получить управляющий регистр cr0
        or  al,00000001b                            ;Установить бит PE в 1
        mov cr0,eax                                 ;Записать измененный cr0 и тем самым включить защищенный режим
    OVERLOAD_CS:                                    ;Перезагрузить сегмент кода на его дескриптор
        db  0eah                                    ;Искуственно сконструированная команда дальнего перехода
        dw  offset OVERLOAD_SEGMENT_REGISTERS       ;Приведет к смене содержимого IP и CS на селектор дескриптора
        dw  CODE_RM_DESC        
    OVERLOAD_SEGMENT_REGISTERS:                     ;Переинициализировать остальные сегментные регистры на дескрипторы
        mov ax,DATA_DESC                            
        mov ds,ax                                   ;В DS находится селектор дескриптора сегмента данных
        mov es,ax                                   ;Так же как в ES
        mov ax,STACK_DESC                           
        mov ss,ax                                   ;В SS селектор дескриптора сегмента стека
        xor ax,ax
        mov fs,ax                                   ;Обнулить регистр fs
        mov gs,ax                                   ;Обнулить регистр gs
        lldt ax                                     ;Обнулить регистр LDTR - не использовать таблицы локальных дескрипторов
    PREPARE_TO_RETURN:                              ;Подготовится к возврату в реальный режим
        push cs                                     ;Сохраним сегмент кода в стек
        push 24;offset BACK_TO_RM                      ;Сохраним смещение точки возврата
        mov  edi,pcode                           ;Получить точку входа в защищенный режим
        mov  eax,CODE_PM_DESC                       ;Получить дескриптор кода защищенного режима
        push eax                                    ;Занести их в стек
        push edi                                    
    REINITIALIAZE_CONTROLLER_FOR_PM:                ;Переинициализировать контроллер прерываний на вектора 20h, 28h
        mov al,00010001b                            ;ICW1 - переинициализация контроллера прерываний
        out 20h,al                                  ;Переинициализируем ведущий контроллер
        out 0A0h,al                                 ;Переинициализируем ведомый контроллер
        mov al,20h                                  ;ICW2 - номер базового вектора прерываний
        out 21h,al                                  ;ведущего контроллера
        mov al,28h                                  ;ICW2 - номер базового вектора прерываний
        out 0A1h,al                                 ;ведомого контроллера
        mov al,04h                                  ;ICW3 - ведущий контроллер подключен к 3 линии
        out 21h,al       
        mov al,02h                                  ;ICW3 - ведомый контроллер подключен к 3 линии
        out 0A1h,al      
        mov al,11h                                  ;ICW4 - режим специальной полной вложенности для ведущего контроллера
        out 21h,al        
        mov al,01h                                  ;ICW4 - режим обычной полной вложенности для ведомого контроллера
        out 0A1h,al       
        mov al, 0                                   ;Размаскировать прерывания
        out 21h,al                                  ;Ведущего контроллера
        out 0A1h,al                                 ;Ведомого контроллера
    ENABLE_INTERRUPTS_0:                            ;Разрешить маскируемые и немаскируемые прерывания
        in  al,70h	
        and	al,01111111b                            ;Установить 7 бит в 0 для запрета немаскируемых прерываний
        out	70h,al
        nop
        sti                                         ;Разрешить маскируемые прерывания
    GO_TO_CODE_PM:                                  ;Переход к сегменту кода защищенного режима
        db 66h                                      ;next operation is 32bit operation
        retf


    INPUT proc near                                 ;Процедура ввода время-нахождения в защищенном режиме 
        mov ah,0ah
        xor di,di
        mov dx,offset ds:[INPUT_TIME]
        int 21h
        mov dl,0ah
        mov ah,02
        int 21h 
        
        mov si,offset INPUT_TIME+2 
        cmp byte ptr [si],"-" 
        jnz ii1
        mov di,1 
        inc si   
    II1:
        xor ax,ax
        mov bx,10  
    II2:
        mov cl,[si]
        cmp cl,0dh 
        jz ii3
        cmp cl,'0' 
        jl er
        cmp cl,'9' 
        ja er
     
        sub cl,'0' 
        mul bx     
        add ax,cx  
        inc si     
        jmp ii2    
    ER:   
        mov dx, offset MSG_ERROR
        mov ah,09
        int 21h
        int 20h
    II3:
        ret
    INPUT endp

    FILL_CR_0_BUFFER_RM proc near; cr0-rigester 0-bit=enables protected mode
        push eax
        push esi
        push dx

        mov eax, cr0
        xor dx, dx
        mov cx, 32
        lea esi, BUFFER_CR_0_RM
        fill_cr_0_loop_rm:
        mov dl, al
        shl dl, 7
        shr dl, 7
        shr eax, 1
        add dl, 48 
        mov [esi], dl
        inc esi
        xor dl, dl
        loop fill_cr_0_loop_rm

        pop dx
        pop esi
        pop eax
        ret
    FILL_CR_0_BUFFER_RM endp

SIZE_CODE_RM = ($ - rcode)
rcode ends


pcode segment para use32

assume CS:pcode, DS:data, ES:data
pstart:
hlt
        mov  ax,TEXT_DESC                           ;Поместить в ax дескриптор текста
        mov  es,ax
        xor  edi,edi
        mov  ecx,80*25                              ;Количество символов в окне
        mov  ax,700h
        rep  stosw
    hlt
    ;mov AX, DATA_DESC                                 
    ;mov DS, AX                                   
    ;mov AX, VMEM_DESC                                 
    ;mov ES, AX                          

    ;hlt

    ;xor  EDI, EDI
    ;mov  ECX, 80 * 25
    ;mov  AX, 700h
    ;rep  stosw


    ;mov AX, 0FEh 
    ;out 64h, AX


    ;CLRSCR  proc near                               ;Процедура очистки консоли
    ;    push es
    ;    pushad
    ;    mov  ax,TEXT_DESC                           ;Поместить в ax дескриптор текста
    ;    mov  es,ax
    ;    xor  edi,edi
    ;    mov  ecx,80*25                              ;Количество символов в окне
    ;    mov  ax,700h
    ;    rep  stosw
    ;    popad
    ;    pop  es
    ;    ret
    ;CLRSCR  endp


    ;BUFFER_CLEAR  proc near                         ;Процедура очистки буфера
    ;    mov al,' '
    ;    mov [esi+0],al
    ;    mov [esi+1],al
    ;    mov [esi+2],al
    ;    mov [esi+3],al
    ;    mov [esi+4],al
    ;    mov [esi+5],al
    ;    mov [esi+6],al
    ;    mov [esi+7],al
    ;    ret
    ;BUFFER_CLEAR  endp


    ;BUFFER_OUTPUT proc near                         ;Процедура вывода текстового буфера, оканчивающегося 0
    ;    push es
    ;    PUSHAD
    ;    mov  ax,TEXT_DESC                           ;Поместить в es селектор текста
    ;    mov  es,ax
    ;OUTPUT_LOOP:                                    ;Цикл по выводу буфера
    ;    lodsb                                       
    ;    or   al,al
    ;    jz   OUTPUT_EXIT                            ;Если дошло до 0, то конец выхода
    ;    stosb
    ;    inc  edi
    ;    jmp  OUTPUT_LOOP
    ;OUTPUT_EXIT:                                    ;Выход из процедуры вывода
    ;    popad
    ;    pop  es
    ;    ret
    ;BUFFER_OUTPUT ENDP

    IDLE_IRQ_MASTER proc near                      ;Заглушка для аппаратных прерываний ведущего контроллера
        ret
    IDLE_IRQ_MASTER endp
    IDLE_IRQ_SLAVE proc near                      ;Заглушка для аппаратных прерываний ведущего контроллера
        ret
    IDLE_IRQ_SLAVE endp
    TIMER_HANDLER proc near                      ;Заглушка для аппаратных прерываний ведущего контроллера
        ret
    TIMER_HANDLER endp
    KEYBOARD_HANDLER proc near                      ;Заглушка для аппаратных прерываний ведущего контроллера
        ret
    KEYBOARD_HANDLER endp
    M = 0                           
    IRPC N, 0123456789ABCDEF
    EXC_0&N label word                              ;Обработчики исключений 00h..0Fh
        ret
    endm
    M = 010H
    IRPC N, 0123456789ABCDEF                        
    EXC_1&N label word                              ;Обработчики исключений 10h..1Fh
        ret
    endm

SIZE_CODE_PM = ($ - pcode)
pcode ends


;data segment para use16
;
;    seg_desc struc                                   
;        limit_l dw 0FFFFh ; low 16 of limit
;        base_l dw 0000h ; |  
;        base_m db 00h   ; |_ low 24 of base
;        access db 0 ; |  is present (1), privelege level (2), 1
;                    ; |  type flags: is code (1), allow lower priv. access / is stack (1), 
;                    ; |_ readable / writeable (1), 0
;        attrs_limit_h db 00001111b ; |  attrs: limit *= 0x1000 (1), 32 bits memory (1), 0, 0
;                                   ; |_ hight 4 of limit
;        base_h db 00h ; high 8 of base
;    seg_desc ends        
;
;
;    intr_desc struc                                   
;        off_l dw 0 ; Адрес обработчика (0:15)
;        selector dw 0 ; Селектор кода, содержащего код обработчика
;        param_count db 0 ; Параметры
;        access db 0 ; Уровень доступа
;        off_h dw 0 ; Адрес обработчика (31:16)
;    intr_desc ends        
;    idtr struc        
;        limit dw 0                            
;        idt_l dw 0 ; Смещение биты (0-15)
;        idt_h dw 0 ; Смещение биты (31-16)
;    idtr ends
;
;
;    gdt label
;        gdt_null_desc seg_desc <0,0,0,0,0,0>                              
;        gdt_code_desc seg_desc <,,,10011010b,,>             
;        CODE_DESC equ gdt_code_desc - gdt
;        gdt_data_desc seg_desc <,,,10010010b,,>      
;        DATA_DESC equ gdt_data_desc - gdt
;        gdt_vmem_desc seg_desc <4000h,8000h,0Bh,11110010b,0,0> 
;        VMEM_DESC equ gdt_vmem_desc - gdt
;    GDT_END equ $
;
;    gdtr label
;        gdt_size dw GDT_END - gdt - 1
;        gdt_addr dd gdt
;
;    CR equ 0Dh
;    LF equ 0Ah
;    CRLF equ CR, LF
;    EOL equ "$"
;
;    msg_greet db "Hello world!", CRLF
;
;data ends

;stolen_back:
;    cli                                         ;Запрет маскируемых прерываний
;    in  al,70h	                                ;И не маскируемых прерываний
;	or	AL,10000000b                            ;Установить 7 бит в 1 для запрета немаскируемых прерываний
;	out	70h,AL
;	nop
;REINITIALISE_CONTROLLER:                        ;Переиницализация контроллера прерываний               
;    mov al,00010001b                            ;ICW1 - переинициализация контроллера прерываний
;    out 20h,al                                  ;Переинициализируем ведущий контроллер
;    out 0A0h,al                                 ;Переинициализируем ведомый контроллер
;    mov al,8h                                   ;ICW2 - номер базового вектора прерываний
;    out 21h,al                                  ;ведущего контроллера
;    mov al,70h                                  ;ICW2 - номер базового вектора прерываний
;    out 0A1h,al                                 ;ведомого контроллера
;    mov al,04h                                  ;ICW3 - ведущий контроллер подключен к 3 линии
;    out 21h,al       
;    mov al,02h                                  ;ICW3 - ведомый контроллер подключен к 3 линии
;    out 0A1h,al      
;    mov al,11h                                  ;ICW4 - режим специальной полной вложенности для ведущего контроллера
;    out 21h,al        
;    mov al,01h                                  ;ICW4 - режим обычной полной вложенности для ведомого контроллера
;    out 0A1h,al
;PREPARE_SEGMENTS:                               ;Подготовка сегментных регистров для возврата в реальный режим          
;    mov GDT_CODE_RM.LIMIT,0FFFFh                ;Установка лимита сегмента кода в 64KB
;    mov GDT_DATA.LIMIT,0FFFFh                   ;Установка лимита сегмента данных в 64KB
;    mov GDT_STACK.LIMIT,0FFFFh                  ;Установка лимита сегмента стека в 64KB
;    db  0EAH                                    ;Перезагрузить регистр cs
;    dw  offset CONTINUE
;    dw  CODE_RM_DESC                            ;На сегмент кода реального режима
;    CONTINUE:
;    mov ax,DATA_DESC                            ;Загрузим сегментные регистры дескриптором сегмента данных
;    mov ds,ax                                   
;    mov es,ax                                   
;    mov fs,ax                                   
;    mov gs,ax                                   
;    mov ax,STACK_DESC
;    mov ss,ax                                   ;Загрузим регистр стека дескриптором стека
;ENABLE_REAL_MODE:                               ;Включим реальный режим
;    mov eax,cr0
;    and al,11111110b                            ;Обнулим 0 бит регистра cr0
;    mov cr0,eax                        
;    db  0EAH
;    dw  offset CONTINUE2
;    dw  CODE_RM
;    CONTINUE2:                                 ;Перезагрузим регистр кода
;    mov ax,STACK_A
;    mov ss,ax                      
;    mov ax,DATA
;    mov ds,ax                      
;    mov es,ax
;    xor ax,ax
;    mov fs,ax
;    mov gs,ax
;    mov IDTR.LIMIT, 3FFH                
;    mov dword ptr  IDTR+2, 0            
;    lidt fword ptr IDTR                 
;REPEAIR_MASK:                                   ;Восстановить маски прерываний
;    mov al,INT_MASK_M
;    out 21h,al                                  ;Ведущего контроллера
;    mov al,INT_MASK_S
;    out 0A1h,al                                 ;Ведомого контроллера
;ENABLE_INTERRUPTS:                              ;Разрешить маскируемые и немаскируемые прерывания
;    in  al,70h	
;	and	al,01111111b                            ;Установить 7 бит в 0 для разрешения немаскируемых прерываний
;	out	70h,al
;    nop
;    sti                                         ;Разрешить маскируемые прерывания
;DISABLE_A20:                                    ;Закрыть линию A20
;    in  al,92h
;    and al,11111101b                            ;Обнулить 1 бит - запретить линию A20
;    out 92h, al
;EXIT:                                           ;Выход из программы
;    mov ax,3h
;    int 10H                                     ;Очистить видео-режим    
;    lea dx,MSG_EXIT
;    mov ah,9h
;    int 21h                                     ;Вывести сообщение
;
;    call FILL_CR_0_BUFFER_RM                    ;Вывести содержимое рагистра CR0
;    lea dx, BUFFER_CR_0_RM
;    mov ah, 9h
;    int 21h
;    
;    mov ax,4C00h
;    int 21H                                     ;Выход в dos


DATA    segment para use16                      ;Сегмент данных реального/защищенного режима
DATA_BEGIN      = $
    ;Структуры данных
    ;______________________________________________________________________________
    S_DESC  struc                                   ;Структура сегментного дескриптора
        LIMIT       dw 0                            ;Лимит сегмента   
        BASE_L      dw 0                            ;Адрес базы, младшая часть 
        BASE_M      db 0                            ;Адрес базы, средняя часть
        ACCESS      db 0                            ;Байт доступа
        ATTRIBS     db 0                            ;Лимит сегмента и атрибуты
        BASE_H      db 0                            ;Адрес базы, старшая часть
    S_DESC  ends        
    I_DESC  struc                                   ;Структура дескриптора таблицы прерываний
        OFFS_L      dw 0                            ;Адрес обработчика (0:15)
        SEL         dw 0                            ;Селектор кода, содержащего код обработчика
        PARAM_CNT   db 0                            ;Параметры
        ACCESS      db 0                            ;Уровень доступа
        OFFS_H      dw 0                            ;Адрес обработчика (31:16)
    I_DESC  ends        
    R_IDTR  struc                                   ; IDTR structure:
        LIMIT       dw 0                            ; 16-Bit Table Limit 0..15
        IDT_L       dw 0                            ; 32-Bit Linear Base Address (low) 16..31
        IDT_H       dw 0                            ; 32-Bit Linear Base Address (high) 32..47
    R_IDTR  ends
    ;______________________________________________________________________________|

    ;GDT - глобальная таблица дескрипторов
    ;______________________________________________________________________________
    GDT_BEGIN   = $
    GDT label   word                            ;Метка начала GDT
    GDT_0       S_DESC <0,0,0,0,0,0>                                  
    GDT_GDT     S_DESC <GDT_SIZE-1,,,10010010b,0,>                 
    GDT_CODE_RM S_DESC <SIZE_CODE_RM-1,,,10011010b,0,>             
    GDT_DATA    S_DESC <SIZE_DATA-1,,,11110010b,0,>      
    GDT_STACK   S_DESC <1000h-1,,,10010010b,0,>                    
    GDT_TEXT    S_DESC <2000h-1,8000h,0Bh,11110010b,0,0> 
    GDT_CODE_PM S_DESC <SIZE_CODE_PM-1,,,10011010b,01000000b,>    
    GDT_IDT     S_DESC <SIZE_IDT-1,,,10010010b,0,>                  
    GDT_SIZE    = ($ - GDT_BEGIN)               ;Размер GDT
    ;______________________________________________________________________________|

    ;Селлекторы сегментов
    CODE_RM_DESC = (GDT_CODE_RM - GDT_0)
    DATA_DESC    = (GDT_DATA - GDT_0)      
    STACK_DESC   = (GDT_STACK - GDT_0)
    TEXT_DESC    = (GDT_TEXT - GDT_0)  
    CODE_PM_DESC = (GDT_CODE_PM - GDT_0)
    IDT_DESC     = (GDT_IDT - GDT_0)

    ;IDT - таблица дескрипторов прерываний
    ;______________________________________________________________________________
    IDTR    R_IDTR  <SIZE_IDT,0,0>              ;Формат регистра IDTR   
    IDT label   word                            ;Метка начала IDT
    IDT_BEGIN   = $
    IRPC    N, 0123456789ABCDEF
        IDT_0&N I_DESC <0, CODE_PM_DESC,0,10001111b,0>            ; 00...0F
    ENDM
    IRPC    N, 0123456789ABCDEF
        IDT_1&N I_DESC <0, CODE_PM_DESC, 0, 10001111b, 0>         ; 10...1F
    ENDM
    IDT_TIMER    I_DESC <0,CODE_PM_DESC,0,10001110b,0>             ;IRQ 0 - прерывание системного таймера
    IDT_KEYBOARD I_DESC <0,CODE_PM_DESC,0,10001110b,0>             ;IRQ 1 - прерывание клавиатуры
    IRPC    N, 23456789ABCDEF
        IDT_2&N         I_DESC <0, CODE_PM_DESC, 0, 10001110b, 0>  ; 22...2F
    ENDM
    SIZE_IDT        =       ($ - IDT_BEGIN)						; Размер IDT
    ;______________________________________________________________________________|


    MSG_HELLO           db "Press key to change mode to PM",13,10,"$"
    MSG_HELLO_PM        db "We are in PM. Press ESC or wait till timer ends to exit PM",0
    MSG_EXIT            db "We are in RM",13,10,"$"
    MSG_KEYBOARD        db "Scan code:",0
    MSG_TIME            db "Go back to RM in  XXXXXXX seconds",0
    MSG_COUNT           db "Amount of interrupt calls:",0
    MSG_EXC             db "Exception: XX",0
    MSG_ENTER           db "Enter time in protected mode: $"
    MSG_ERROR           db "incorrect error$"
    HEX_TAB             db "0123456789ABCDEF"   ;Таблица номеров исключений
    ESP32               dd  1 dup(?)            ;Указатель на вершину стека
    INT_MASK_M          db  1 dup(?)            ;Значение регистра масок ведущего контроллера
    INT_MASK_S          db  1 dup(?)            ;Значение регистра масок ведомого контроллера
    KEY_SCAN_CODE       db  1 dup(?)            ;Ска-код последней нажатой клавиши
    SECOND              db  1 dup(?)            ;Текущее значение секунд
    TIME                db  1 dup(10)           ;Время нахождения в зазищенном режиме
    COUNT               dw  1 dup(0)            ;Количество вызовов прерывания (диапазон от 0 до 65535)
    BUFFER_COUNT        db  8 dup(' ')          ;Буфер для вывода количества вызовов прерываинй
                        db  1 dup(0)
    BUFFER_SCAN_CODE    db  8 dup(' ')          ;Буфер для вывода скан-кода клавиатуры
                        db  1 dup(0)                
    BUFFER_TIME         db  8 dup(' ')          ;Буфер для вывода оставшегося время в защищенном режиме
                        db  1 dup(0)
    INPUT_TIME          db  6,7 dup(?)          ;Буфер для ввода время   
    BUFFER_CR_0			db 32 dup('?')
    					db 1 dup(0) 
    BUFFER_CR_0_RM			db 32 dup('?'), 13, 10, "$" 					    
SIZE_DATA   = ($ - DATA_BEGIN)                  ;size of data segment
DATA    ends
;Сегмент стека реального/защищенного режима
STACK_A segment para stack
    db  1000h dup(?)
STACK_A  ends

end START
