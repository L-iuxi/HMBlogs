IOY0 EQU 0600H 

DISPLAY_8255_A EQU IOY0+00H*2 ;控制数码管显示
SELECT_8255_B EQU IOY0+01H*2 ;控制数码管选择
SWandLED_8255_C EQU IOY0+02H*2 ;接收开关输入以及亮灯
MODE_8255_IO EQU IOY0+03H*2

REPEAT_DISP_NUM EQU 5	;重复显示次数
DELAY_NUM EQU 1000	;延时次数

DIGITAL_TUBE_FIRST EQU 00001110B	;数码管位置
DIGITAL_TUBE_SECOND EQU 00001101B
DIGITAL_TUBE_FOURTH EQU 00000111B

 
STACK SEGMENT

    DW 32 DUP(?)
    
STACK ENDS

DATA SEGMENT

    NUMS DB 3FH,06H,5BH,4FH,66h,6dh,7dh,07h,7fh,6fh,79H ;
   
DATA ENDS

CODE SEGMENT
    ASSUME CS:CODE,SS:STACK
    
START:   
    MOV AX,DATA;初始化栈，ds，8255
    MOV DS,AX
    MOV AX,STACK
    MOV SS,AX
       
       
    MOV DX, MODE_8255_IO
    MOV AL, 81H ;1000 0001 表示A口C口高四位低四位输出，C口也有开关作为输入
    OUT DX, AL ;控制字送控制寄存器
    MOV BX, 0 ;清零，用于存放当前速度值

CTRL:       ;用于检测C口输入的档位信号，并根据档位调整速度值，并显示在数码管上。
    MOV DX , SWandLED_8255_C
    IN AL, DX ;将C口的值输入到AL寄存器中，用于判断档位。
   
    MOV AH,0 ;用于后续计算速度值
    MOV CX ,00 ;用于后续存放档位值
    
    TEST AL,1H ;AL是否等于1，TEST是进行and操作，影响标志位
    JNZ GEAR1 ;若AL为XXXX XXX1(8255's PC0)，跳GEAR1
    

    JMP JUMP_OR_ACCELERATE
   

GEAR1:       
    TEST AL, 2H
    JNZ GEAR2 ;若AL为XXXX XX1X(8255's PC1)，跳GEAR2
    
    MOV CX,10 ;正计数加到10
    MOV DX , SWandLED_8255_C
    mov AL,00010000B ; 将挡位对应的LED灯点亮
    out DX, AL ;将AL的值给C口
   
    JMP JUMP_OR_ACCELERATE


       
GEAR2:       
    TEST AL, 4H
    JNZ GEAR3 ;若AL为XXXX X1XX(8255's PC2)，跳GEAR3
    
    MOV CX, 20 
    MOV DX , SWandLED_8255_C
    mov AL, 00100000B
    out DX, AL
   
    JMP JUMP_OR_ACCELERATE
       
     
GEAR3:       
    TEST AL,8H
    JNZ GEAR4 ;若AL为XXXX 1XXX(8255's PC3)，跳GEAR4
    
    MOV CX,30
    MOV DX , SWandLED_8255_C
    mov AL,01000000B
    out DX, AL


    JMP JUMP_OR_ACCELERATE
       

GEAR4:  
   
    MOV CX,40 ;CX送40
    MOV DX , SWandLED_8255_C
    mov AL,10000000B
    out DX, AL

   
    JMP JUMP_OR_ACCELERATE
   

       
JUMP_OR_ACCELERATE:    ;increase number   

    CMP CX,BX ;比较设定档位和当前实时档位
    JB SLOW_DOWN ;设定档位小于当前档位
    JZ SPEED_NOT_CHANGED ;相等时显示不用改变
    
    CALL INC_DISP 
    JMP CTRL
    
SLOW_DOWN:	;decrease number
    CALL DEC_DISP
    JMP CTRL

SPEED_NOT_CHANGED:    
    CALL DISP_PRE
    JMP CTRL   



INC_DISP PROC
    MOV DI, REPEAT_DISP_NUM ; 重复显示
    
INC_LOOP: 
    CALL DISP_PRE
    DEC DI
    JNZ INC_LOOP 
    INC BX;加1
    CMP BX,CX 
    JB INC_DISP;如果仍较小，继续增加
    MOV BX,CX;达到目标，更新BX中的当前速度值
    RET
INC_DISP ENDP

DEC_DISP PROC
    MOV DI, REPEAT_DISP_NUM 
    
DEC_LOOP:
    CALL DISP_PRE
    DEC DI
    JNZ DEC_LOOP
    DEC BX
    CMP CX,BX
    JB DEC_DISP
    RET
DEC_DISP ENDP


       
DISP_PRE PROC   ;准备显示

    PUSH CX
    PUSH DX
    PUSH AX
    PUSH BX
           
    MOV AX,BX
    MOV CL,10
    DIV CL ; AL 商 AH 余数  e.g.:36 / 10 = 3 ..... 6 
    MOV CX,0
    
    ;计数高位
    MOV BL,AL ; e.g.:3  
    MOV CX,DIGITAL_TUBE_FIRST
           
    CALL DISPLAY
    CALL DELAY
 
     
      ;计数低位   
    MOV BL,AH ; e.g.:6
    MOV CX,DIGITAL_TUBE_SECOND
    
    CALL DISPLAY
    CALL DELAY
     
      ;档位
    MOV BL, AL ;e.g.:3
    MOV CX,DIGITAL_TUBE_FOURTH
    
    CALL DISPLAY
    CALL DELAY
               
           
    POP BX
    POP AX
    POP DX
    POP CX
    RET
DISP_PRE ENDP

;BUG 显示高位3，显示低位3，显示低位6，显示挡位6，显示挡位3

DISPLAY  PROC
    PUSH BX
    PUSH AX
   
    ;控制第X灯亮
    MOV DX, SELECT_8255_B
    ROL CX,4
    MOV AX,CX
    
    OUT DX,AX ;B口输出CX
   
   
    ;输出值到数码管
    MOV BH,0
    MOV DX,DISPLAY_8255_A
    MOV SI,OFFSET NUMS

    MOV AX,[SI+BX]
    OUT DX,AX ;A口输出BX，也就是NUMS[BX]

    POP AX
    POP BX
    RET
DISPLAY ENDP   

                   
DELAY PROC


    PUSH CX
    MOV CX,DELAY_NUM
    
DELAY_LOOP:
    CALL EXEC_DELAY_ONCE
    DEC CX
    JNZ DELAY_LOOP
    
    POP CX
    RET   
DELAY ENDP


EXEC_DELAY_ONCE PROC
    PUSH CX
    MOV CX,1
    
JUST_WASTE_TIME_LOOP:
    DEC CX
    JNZ JUST_WASTE_TIME_LOOP
   
    POP CX
    RET
EXEC_DELAY_ONCE ENDP


CODE ENDS
END START