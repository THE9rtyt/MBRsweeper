[org 0x7c00]
VIDEO_MEM equ 0xb800

HIDDEN equ 0x00
UNCOVERED equ 0x61
COVERED equ 0x77
SELECTOR_UNCOVERED equ 0x2f
SELECTOR_COVERED equ 0x44

[bits 16]
main:
    mov ax, VIDEO_MEM
    mov es, ax      ;extra segment used for video memory access
    xor ax, ax      ;clear ax
    mov ds, ax      ;set Data Segment to 0
    mov ss, ax      ;set Stack Segment to 0
    mov bp, 0xb000  ;setup stack well above us
    mov sp, bp
    mov al, 0x03    ;set display mode(ah=00) to 3(al) to 80x25 color
    int 0x10

    mov ah, 0x02    ;mov cursor
    mov bh, 0       ;screen 0
    mov dx, 0x0122  ;row 0x01, col 0x22
    int 0x10

    mov si, title
    call print

    mov ah, 0x02    ;read realtime clock
    int 0x1a        ;read, ch=hrs, cl=min, dh=sec
    mov ch, dh      ;move seconds over hours to get more randoms seed
    mov [seed], cx
    mov bx, [cursor_offset] ;bx is the cursor register, it must always be maintained
    call clear_field
    call generate
    
    call draw_cursor
loop:
    call get_input          ;sets key to ax
    call key_to_direction   ;converts key to direction in al
    cmp al, 4
    jl handle_direction     ;<4
    je handle_click         ;==4
    jmp loop                ;else
    handle_direction:
        call move_selector
        jmp loop
    handle_click:
        call click
        call draw_cursor
        jmp loop

print:
    mov ah, 0x0e    ;BIOS tele-type output
print_loop:
    lodsb       ;move the byte at si, based on the data segment, into al
    cmp al, 0       ;compare al to 0
    je print_end    ;if equal to 0, string is done
    int 0x10        ;print character in al
    jmp print_loop

print_end:
    ret

clear_field:
    push bx
    sub bx, 164
    mov ah, HIDDEN
    mov al, 0x00
    clear_field_loop:
        mov [es:bx], ax
        cmp bx, 0x0f9e
        jge clear_field_end
        add bx, 2
        jmp clear_field_loop

    clear_field_end:
    pop bx
    ret

generate:
    generate_col_loop:
        generate_row_loop:
            call random ;get random num in (e)dx
            cmp edx, 0x2fff ;difficulty set here, increase for more difficulty
            jg not_mine
            mine:
                call put_num
                add byte [es:bx], 0x20
            not_mine:
            add byte [es:bx], 0x50
            inc bx
            mov byte [es:bx], COVERED
            inc bx
            call divmod
            cmp dx, 154
            jle generate_row_loop

        add bx, 8
        cmp cx, 23
        jl generate_col_loop

    sub bx, 0x696   ;return to center of minefield
    ret

random: ;linear congruential generator(LCG)
    push ax
    xor edx, edx
    mov eax, [seed]
    mul dword [a]       ;a
    add eax, [c]        ;c
    div dword [m]       ;m
    mov [seed], edx
    jmp math_ret ;pop ax ret

put_num:    ;adds 1 to all the adjecent squares of location es:bx
    pusha
    sub bx, 162     ;move bx to first position
    xor ax, ax
    mov si, places
    put_num_loop:
        inc byte [es:bx]
        lodsb       ;move the byte at si, based on the data segment, into al
        cmp al, 0
        je return ;popa ret
        add bx, ax
        jmp put_num_loop

divmod:     ;does bx/160, leaves qoutient(/) in cx and remainder(%) in dx
    push ax
    xor dx,dx
    mov ax, bx
    div word [MAX_COL]
    mov cx, ax

math_ret:
    pop ax
    ret

draw_cursor:    ;postion in bx
    mov ch, SELECTOR_COVERED
    mov cl, SELECTOR_UNCOVERED

    jmp draw

undraw_cursor:  ;position in bx
    mov ch, COVERED
    mov cl, UNCOVERED

draw:   ;position in bx, uncovered in cl and covered in ch
    pusha
    mov al,[es:bx]
    add bx, 1
    cmp al, 0x40
    jg covered
    uncovered:
        mov [es:bx], cl
        jmp return
    covered:
        mov [es:bx], ch

return: ;general return used by many functions
    popa
    ret

get_input:      ;waits for keyboard input and leaves it in ax
    mov ah, 0
    int 0x16    ;wait for keyboard input
    ret

key_to_direction: ;compares ah to arrow key scan codes
    ;sets al to correspoding direction, 4(enter), 5(bad key)
    mov al, 0
    cmp ah, 0x48
    je key_up
    cmp ah, 0x50
    je key_down
    cmp ah, 0x4b
    je key_left
    cmp ah, 0x4d
    je key_right
    cmp ah, 0x1c
    je key_ent

        inc al
    key_ent:
        inc al
    key_up:
        inc al
    key_down:
        inc al
    key_left:
        inc al
    key_right:
        ret

move_selector: ;moves selector based on direction al
    call undraw_cursor
    call divmod ;sets row(bx/160) in cx, col(bx%160) in dx
    cmp al, 2
    jl ltrt ;<2, left/right
    updn:
        je move_down
        move_up:
            cmp cx, 3
            jle move_selector_end
            sub bx, 160
            jmp move_selector_end
        move_down:
            cmp cx, 23
            jge move_selector_end
            add bx, 160
            jmp move_selector_end
    ltrt:
        cmp al, 0
        je move_right
        move_left:
            cmp dx, 4
            jle move_selector_end
            sub bx, 2
            jmp move_selector_end
        move_right:
            cmp dx, 154
            jge move_selector_end
            add bx, 2

move_selector_end:
    call draw_cursor
    ret


click:
    cmp byte [es:bx], '`'
    jg mine_hit
    cmp byte [es:bx], 'P'
    jl click_end
    jg set_num
    sub byte [es:bx],0x10
    call clear_space
    set_num:
        sub byte [es:bx],0x20
        call undraw_cursor
    click_end:
        ret

mine_hit:
    mov si, hit_message
    call print
    call get_input ;wait for a key to be pressed
    jmp main ;restart

clear_space:
    pusha
    sub bx, 162     ;move bx to first position
    xor ax, ax
    mov si, places
    clear_space_loop:
        call click  ;recursive functions my beloved
        lodsb       ;move the byte at si, based on the data segment, into al
        cmp al, 0
        je return ;popa ret
        add bx, ax
        jmp clear_space_loop


;constants
MAX_COL:
    dw 160
cursor_offset:
    dw 0x01e4
;PRNG constants
a:
    dd 0x41c64e6d
c:
    dd 0x3039
m:
    dd 0x10000
;loop constants
places:
    db 2,2,156,4,156,2,2,0
;strings
title:
    db 0x01,'MBRsweeper',0
hit_message:
    db ' F',0x07,0 ;pay respects, beeeep
;memory storage
seed:
    dd 0x09


; Fill with 510 zeros minus the size of the previous code
times 510-($-$$) db 0
; Magic number
dw 0xAA55