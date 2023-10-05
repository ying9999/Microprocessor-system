#include "hardware/regs/addressmap.h"
#include "hardware/regs/io_bank0.h"
#include "hardware/regs/timer.h"
#include "hardware/regs/m0plus.h"

.syntax unified                       @ Specify unified assembly syntax
.cpu    cortex-m0plus                 @ Specify CPU type is Cortex M0+
.thumb                                @ Specify thumb assembly for RP2040
.global main_asm                      @ Provide program starting address to the linker
.align 4                              @ Specify code alignment

.equ    DFLT_STATE_STRT, 1            @ Specify the value to start flashing
.equ    DFLT_STATE_STOP, 0            @ Specify the value to stop flashing
.equ    DFLT_ALARM_TIME, 2000000      @ Specify the default alarm timeout

.equ    GPIO_ISR_OFFSET, 0x74         @ GPIO is int #13 (vector table entry 29)
.equ    ALRM_ISR_OFFSET, 0x40         @ ALARM0 is int #0 (vector table entry 16)

.equ    GPIO_BTN_PIN, 21              @ Specify pin for the GP21
.equ    GPIO_BTN_DN, 0x00400000       @ Mask for falling-edge event on GP21
.equ    GPIO_BTN_UP, 0x00800000       @ Mask for rising-edge event on GP21

.equ    GPIO_LED_PIN, 28              @ Specify pin for the built-in LED
.equ    GPIO_DIR_IN,   0              @ Specify input direction for a GPIO pin
.equ    GPIO_DIR_OUT,  1              @ Specify output direction for a GPIO pin

@ Entry point to the ASM portion of the program
main_asm:
    bl    init_leds           // Same as previous labs
    bl    init_btns           // Use asm_gpio_set_irq C function to setup falling-edge interrutps
    bl    install_alrm_isr    // See below
    bl    install_gpio_isr    // See below
    bl    setup



chooseDiff:
    movs r7, #10
    bl    printChooseLevel             @ print choose level message
    b     Input                        @ branch to Morse code input buffer logic portion
    

theLevel1:
    movs r4, #1                        @ record now user is in level1
    movs r7, #10                       @ reset r7
    bl   level1Message                 @ print level 1 message
    movs r0, #1                        
    bl   displayQuestion               @ print question with it's corresponding morse code
    bl   enable_timer                  @ reset Watchdog Timer
    b    Input                         @ branch to Morse code input buffer logic portion


theLevel2:
    movs r4, #2                        @ record now user is in level1
    movs r7, #10                       @ reset r7
    bl   level2Message                 @ print level 2 message
    movs r0, #2
    bl   displayQuestion               @ only print the question
    bl   enable_timer                  @ reset Watchdog Timer
    b    Input                         @ branch to Morse code input buffer logic portion


update:
    movs r0, r7
    bl   checkMessage                  @ print the result (wrong or correct)
    movs r0, r7
    bl   updateInfo                    @ Update the current user lives and correctNumber
    bl   checkCorrectCounter           @ check whether should branch to theLevel2
    CMP  R0, #1
    BEQ  complete                      @ check whether user pass the game
    CMP  R0, #2
    BEQ  levelUp                       @ branch to theLevel2
update_2:    
    bl   checkLives                    @ check the current lives
    CMP  R0, #1
    BNE  complete                      @ check whether user is died
    cmp  r4, #1
    BNE  else
    b    theLevel1                     @ return to level1 and continue the game
    b    end
else:
    b    theLevel2                     @ return to level2 and continue the game
end:

levelUp:                                @ branch to theLevel2
    MOVS R4, #2
    B    update_2                       @ branch to update_2

complete:
    bl   gameComplete                   @ reaches the end since game complete

Input:                                  @ Morse code input buffer logic portion
    wfi
    bl     update_timer                 @ reset Watchdog Timer
    ldr    r3, =(TIMER_BASE + TIMER_TIMELR_OFFSET)
    ldr    r5, [r3]                     @ get the current time

    cmp    r7, #11
    BEQ    chooseDiff                   @ if user doesn't choose correct difficulty level, branch to chooseDiff again
    cmp    r7, #12
    BEQ    theLevel1                    @ if user choose level1, branch to theLevel1
    cmp    r7, #13
    BEQ    theLevel2                    @ if user choose level2, branch to level2
    cmp    r7, #0
    BEQ    update                       @ users' input is wrong, update lives and levelNumbers
    cmp    r7, #1
    BEQ    update                       @ users' input is correct, update lives and levelNumbers
    bl     set_alarm                    @ Set a new alarm
    wfi
    ldr    r6, [r3]                     @ get the current time
    subs   r0, r6, r5                   @ get the time that the button been pressed
    bl     Dash_Dot                     @ transfer user input inot morse code
    b      Input 



init_btns:
    push    {lr}
  
    movs    r0, #GPIO_BTN_PIN           @ This value is the pin that BUTTON connected on the PI PICO board
    bl      asm_gpio_init               @ Call the subroutine to initialise the GPIO pin specified by r0
    movs    r0, #GPIO_BTN_PIN           @ This value is the pin that BUTTON connected on the PI PICO board
    movs    r1, #GPIO_DIR_IN            @ We want this GPIO pin to be setup as an input pin
    bl      asm_gpio_set_dir            @ Call the subroutine to set the GPIO pin specified by r0 to state specified by r1
    
    movs    r0, #GPIO_BTN_PIN           @ setup falling-edge interrutps for GP21
    bl      asm_gpio_set_irqF

    movs    r0, #GPIO_BTN_PIN           @ setup falling-edge interrutps for GP21
    bl      asm_gpio_set_irqR
    pop     {pc}


@ Subroutine used to initialise the PI Pico built-in LED
init_leds:
    push    {lr}
    movs    r0, #GPIO_LED_PIN           @ This value is the GPIO LED pin on the PI PICO board
    bl      asm_gpio_init               @ Call the subroutine to initialise the GPIO pin specified by r0
    movs    r0, #GPIO_LED_PIN           @ This value is the GPIO LED pin on the PI PICO board
    movs    r1, #GPIO_DIR_OUT           @ We want this GPIO pin to be setup as an output pin
    bl      asm_gpio_set_dir            @ Call the subroutine to set the GPIO pin specified by r0 to state specified by r1
    pop     {pc}


//
// Sets up the alrm_isr in the RAM vector table and enables the correct interrupt
//
install_alrm_isr:
    ldr   r1, =(PPB_BASE + M0PLUS_VTOR_OFFSET)      @ Get the address of the RAM vector table using the (PPB_BASE + M0PLUS_VTOR_OFFSET) register
    ldr   r2, [r1]  
    movs  r1, #ALRM_ISR_OFFSET
    add   r1, r1, r2
    ldr   r0, =alrm_isr
    str   r0, [r1]                                  @ Store the address of the alrm_isr handler to the correct offset for ALARM0 in the vector table
    
    ldr   r1, =(PPB_BASE + M0PLUS_NVIC_ICPR_OFFSET)
    ldr   r2, [r1]
    ldr   r1, =#0x1
    orrs  r2, r2, r1                                @ Disable the ALARM0 IRQ by writing the correct value to (PPB_BASE + M0PLUS_NVIC_ICPR_OFFSET)
    ldr   r1, =(PPB_BASE + M0PLUS_NVIC_ICPR_OFFSET)
    str   r2, [r1]

    ldr   r1, =(PPB_BASE + M0PLUS_NVIC_ISER_OFFSET)
    ldr   r2, [r1]
    ldr   r1, =#0x1
    orrs  r2, r2, r1                                @ Enable the ALARM0 IRQ by writing the correct value to (PPB_BASE + M0PLUS_NVIC_ISER_OFFSET)
    ldr   r1, =(PPB_BASE + M0PLUS_NVIC_ISER_OFFSET)
    str   r2, [r1]
    bx    lr                                        @ Exit subroutine


//
// Enable alarm timer interrupts and set an alarm
//
set_alarm:
    push  {lr}
    ldr   r1, =(TIMER_BASE + TIMER_TIMELR_OFFSET) @ Get the current timer count from (TIMER_BASE + TIMER_TIMELR_OFFSET) register
    ldr   r2, [r1]
    ldr   r1, =DFLT_ALARM_TIME
    add   r1, r1, r2                              @ Add the time delay you want to wait for to the current timer count
    ldr   r2, =(TIMER_BASE + TIMER_ALARM0_OFFSET)
    str   r1, [r2]                                @ Push the updated value to (TIMER_BASE + TIMER_ALARM0_OFFSET)
    
    ldr   r1, =(TIMER_BASE + TIMER_INTE_OFFSET)   @ Enable alarm timer interrupts using the (TIMER_BASE + TIMER_INTE_OFFSET) register
    ldr   r2, [r1]
    ldr   r1, =#0x1
    orrs  r2, r2, r1
    ldr   r1, =(TIMER_BASE + TIMER_INTE_OFFSET)
    str   r2, [r1]
    pop   {pc}                                    @ Exit subroutine


//
// Service the pending interrupt from the ALARM0 TIMER
//
.thumb_func 
alrm_isr:
    push    {lr}

    ldr   r1, =(TIMER_BASE + TIMER_INTR_OFFSET)   @ Disable pending interrupt from TIMER by writing correct value to (TIMER_BASE + TIMER_INTR_OFFSET)
    ldr   r2, [r1]
    ldr   r1, =#0x1
    orrs  r2, r2, r1
    ldr   r1, =(TIMER_BASE + TIMER_INTR_OFFSET)
    str   r2, [r1]

    
    bl    check                                   @ input end, check user's input
    mov   r7, r0                                  @ record the result
    pop     {pc}                                  @ Exit ISR


//
// Sets up the gpio_isr in the RAM vector table and enables the correct interrupt
//
install_gpio_isr:
    ldr     r1, =(PPB_BASE + M0PLUS_VTOR_OFFSET)      @ Get the address of the RAM vector table using the (PPB_BASE + M0PLUS_VTOR_OFFSET) register
    ldr     r2, [r1]                                
    movs    r1, #GPIO_ISR_OFFSET                    
    add     r1, r1, r2                              
    ldr     r0, =gpio_isr                           
    str     r0, [r1]                                  @ Store the address of the alrm_isr handler to the correct offset for ALARM0 in the vector table
  
    ldr     r2, =(PPB_BASE + M0PLUS_NVIC_ICPR_OFFSET) @ Disable the GPIO IRQ by writing the correct value to (PPB_BASE + M0PLUS_NVIC_ICPR_OFFSET)
    ldr     r1, =#0x2000   
    str     r1 ,[r2]

    ldr     r2, =(PPB_BASE + M0PLUS_NVIC_ISER_OFFSET) @ Enable the GPIO IRQ by writing the correct value to (PPB_BASE + M0PLUS_NVIC_ISER_OFFSET)
    ldr     r1, =#0x2000    
    str     r1 ,[r2] 
    bx      lr                                        @ Exit subroutine


//
// Service the pending interrupt from the GPIO
//
.thumb_func
gpio_isr:
    push    {lr}
    ldr     r1, =(IO_BANK0_BASE + IO_BANK0_PROC0_INTS2_OFFSET) @ Read the interrupt status event from the (IO_BANK0_BASE + IO_BANK0_PROC0_INTS2_OFFSET) register
    ldr     r2, [r1]

    ldr     r0, =#0x2000
    str     r0, [r1]

    ldr     r3, =GPIO_BTN_DN
    cmp     r2, r3
    BNE     end1
    ldr     r0, =(IO_BANK0_BASE + IO_BANK0_INTR2_OFFSET)       @ Disable pending interrupt from GPIO by writing correct value to (IO_BANK0_BASE + IO_BANK0_INTR2_OFFSET)
    str     r3, [r0]
    end1:

    ldr     r3, =GPIO_BTN_UP
    cmp     r2, r3
    BNE     end2
    ldr     r0, =(IO_BANK0_BASE + IO_BANK0_INTR2_OFFSET)       @ Disable pending interrupt from GPIO by writing correct value to (IO_BANK0_BASE + IO_BANK0_INTR2_OFFSET)
    str     r3, [r0]
    end2:
    pop     {pc}                                               @ Exit ISR





@ Set data alignment
.data
    .align 4
