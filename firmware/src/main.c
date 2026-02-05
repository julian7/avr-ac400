#include <avr/interrupt.h>
#include <avr/io.h>
#include <stdbool.h>
#include <stdint.h>

#include "config.h"
#include "gpio.h"
#include "ir.h"

/*
 * AC400 firmware:
 * - Relays: active-high
 * - Buttons: active-low with internal pullups
 */

#define BUZZER_SHORT_MS 80
#define BUZZER_LONG_MS 400
#define BUZZER_GAP_MS 120

/* Timer0: 1ms system tick */
#define TIMER0_PRESCALE 64UL
#define TIMER0_OCR ((F_CPU / TIMER0_PRESCALE / 1000UL) - 1U)

#define IR_CMD_ON 0x30
#define IR_CMD_OFF 0x90
#define IR_CMD_TIME 0xA0

typedef enum { SPEED_OFF = 0, SPEED_LOW, SPEED_MID, SPEED_HIGH } speed_t;

typedef struct {
  uint8_t integrator;
  bool pressed;
} debounce_t;

static volatile uint32_t g_ms = 0;

static speed_t g_speed = SPEED_OFF;
static uint8_t g_timer_sel_hours = 0; /* 0,1,2,4 */
static uint32_t g_timer_seconds_remaining = 0;

static uint32_t g_buzzer_next_ms = 0;
static uint8_t g_buzzer_state = 0;
static uint8_t g_buzzer_beeps_remaining = 0;
static uint16_t g_buzzer_on_ms = 0;
static uint16_t g_buzzer_off_ms = 0;
static uint8_t g_buzzer_followup_shorts = 0;

static void buzzer_set(uint8_t on) { gpio_write(BUZZER_PIN, on ? 1 : 0); }

static void buzzer_start(uint8_t beeps, uint16_t on_ms, uint16_t off_ms) {
  if (beeps == 0)
    return;
  uint32_t now_ms;
  uint8_t sreg = SREG;
  cli();
  now_ms = g_ms;
  SREG = sreg;

  g_buzzer_followup_shorts = 0;
  g_buzzer_beeps_remaining = beeps;
  g_buzzer_on_ms = on_ms;
  g_buzzer_off_ms = off_ms;
  g_buzzer_state = 1;
  buzzer_set(1);
  g_buzzer_next_ms = now_ms + on_ms;
}

static void buzzer_start_timer(uint8_t shorts) {
  if (shorts == 0)
    return;
  buzzer_start(1, BUZZER_LONG_MS, BUZZER_GAP_MS);
  g_buzzer_followup_shorts = shorts;
}

static void buzzer_update(uint32_t now_ms) {
  if (g_buzzer_state == 0)
    return;
  if ((int32_t)(now_ms - g_buzzer_next_ms) < 0)
    return;

  if (g_buzzer_state == 1) {
    buzzer_set(0);
    g_buzzer_state = 2;
    g_buzzer_next_ms = now_ms + g_buzzer_off_ms;
  } else {
    if (g_buzzer_beeps_remaining > 1) {
      g_buzzer_beeps_remaining--;
      g_buzzer_state = 1;
      buzzer_set(1);
      g_buzzer_next_ms = now_ms + g_buzzer_on_ms;
    } else {
      g_buzzer_state = 0;
      g_buzzer_beeps_remaining = 0;
      if (g_buzzer_followup_shorts > 0) {
        uint8_t shorts = g_buzzer_followup_shorts;
        g_buzzer_followup_shorts = 0;
        buzzer_start(shorts, BUZZER_SHORT_MS, BUZZER_GAP_MS);
      }
    }
  }
}

static void update_leds(void) {
  gpio_write(LED1_PIN, g_timer_sel_hours == 1);
  gpio_write(LED2_PIN, g_timer_sel_hours == 2);
  gpio_write(LED3_PIN, g_timer_sel_hours == 4);

  gpio_write(LED4_PIN, g_speed == SPEED_HIGH);
  gpio_write(LED5_PIN, g_speed == SPEED_MID);
  gpio_write(LED6_PIN, g_speed == SPEED_LOW);
}

static void relays_all_off(void) {
  gpio_write(RELAY_LOW_PIN, 0);
  gpio_write(RELAY_MID_PIN, 0);
  gpio_write(RELAY_HIGH_PIN, 0);
}

static void set_speed(speed_t speed) {
  relays_all_off();
  g_speed = speed;
  if (speed == SPEED_LOW) {
    gpio_write(RELAY_LOW_PIN, 1);
  } else if (speed == SPEED_MID) {
    gpio_write(RELAY_MID_PIN, 1);
  } else if (speed == SPEED_HIGH) {
    gpio_write(RELAY_HIGH_PIN, 1);
  }
  update_leds();
}

static speed_t next_speed(speed_t s) {
  switch (s) {
  case SPEED_OFF:
    return SPEED_LOW;
  case SPEED_LOW:
    return SPEED_MID;
  case SPEED_MID:
    return SPEED_HIGH;
  default:
    return SPEED_LOW;
  }
}

static uint8_t next_timer_sel_hours(uint8_t h) {
  switch (h) {
  case 0:
    return 1;
  case 1:
    return 2;
  case 2:
    return 4;
  default:
    return 0;
  }
}

static void timer_rotate_from_ir(void) {
  g_timer_sel_hours = next_timer_sel_hours(g_timer_sel_hours);

  if (g_timer_sel_hours == 0) {
    g_timer_seconds_remaining = 0;
  } else {
    g_timer_seconds_remaining = (uint32_t)g_timer_sel_hours * 3600UL;
  }

  if (g_timer_sel_hours > 0) {
    buzzer_start_timer(g_timer_sel_hours);
  }

  update_leds();
}

static bool debounce_update(debounce_t *db, bool raw_pressed) {
  const uint8_t max = 3;
  if (raw_pressed) {
    if (db->integrator < max)
      db->integrator++;
  } else {
    if (db->integrator > 0)
      db->integrator--;
  }

  bool new_pressed = (db->integrator >= max);
  bool pressed_event = (!db->pressed && new_pressed);
  db->pressed = new_pressed;
  return pressed_event;
}

static void io_init(void) {
  gpio_set_output(RELAY_LOW_PIN);
  gpio_set_output(RELAY_MID_PIN);
  gpio_set_output(RELAY_HIGH_PIN);
  relays_all_off();

  gpio_set_output(BUZZER_PIN);
  buzzer_set(0);

  gpio_set_input(ON_KEY_PIN, 1);
  gpio_set_input(OFF_KEY_PIN, 1);

  gpio_set_output(LED1_PIN);
  gpio_set_output(LED2_PIN);
  gpio_set_output(LED3_PIN);
  gpio_set_output(LED4_PIN);
  gpio_set_output(LED5_PIN);
  gpio_set_output(LED6_PIN);
  update_leds();
}

static void timer0_init(void) {
  TCCR0A = (1 << WGM01);
  TCCR0B = (1 << CS01) | (1 << CS00);
  OCR0A = (uint8_t)TIMER0_OCR;
  TIMSK0 = (1 << OCIE0A);
}

static void handle_command(uint8_t cmd) {
  switch (cmd) {
  case IR_CMD_ON:
    buzzer_start(1, BUZZER_SHORT_MS, BUZZER_GAP_MS);
    if (g_speed == SPEED_OFF) {
      set_speed(SPEED_LOW);
    } else {
      set_speed(next_speed(g_speed));
    }
    break;
  case IR_CMD_OFF:
    buzzer_start(1, BUZZER_SHORT_MS, BUZZER_GAP_MS);
    set_speed(SPEED_OFF);
    g_timer_sel_hours = 0;
    g_timer_seconds_remaining = 0;
    update_leds();
    break;
  case IR_CMD_TIME:
    timer_rotate_from_ir();
  }
}

ISR(TIMER0_COMPA_vect) { g_ms++; }

int main(void) {
  io_init();
  timer0_init();
  ir_init();
  sei();

  debounce_t on_db = {0, false};
  debounce_t off_db = {0, false};

  uint32_t last_debounce_ms = 0;
  uint32_t last_second_ms = 0;

  for (;;) {
    uint32_t now_ms;
    cli();
    now_ms = g_ms;
    sei();

    buzzer_update(now_ms);

    if ((uint32_t)(now_ms - last_debounce_ms) >= 10) {
      last_debounce_ms += 10;

      bool on_raw = (gpio_read(ON_KEY_PIN) == 0);
      bool off_raw = (gpio_read(OFF_KEY_PIN) == 0);

      if (debounce_update(&on_db, on_raw)) {
        buzzer_start(1, BUZZER_SHORT_MS, BUZZER_GAP_MS);
        if (g_speed == SPEED_OFF) {
          set_speed(SPEED_LOW);
        } else {
          set_speed(next_speed(g_speed));
        }
      }

      if (debounce_update(&off_db, off_raw)) {
        buzzer_start(1, BUZZER_SHORT_MS, BUZZER_GAP_MS);
        set_speed(SPEED_OFF);
        g_timer_sel_hours = 0;
        g_timer_seconds_remaining = 0;
        update_leds();
      }
    }

    if ((uint32_t)(now_ms - last_second_ms) >= 1000) {
      last_second_ms += 1000;
      if (g_timer_seconds_remaining > 0 && g_speed != SPEED_OFF) {
        g_timer_seconds_remaining--;
        if (g_timer_seconds_remaining == 0) {
          g_timer_sel_hours = 0;
          set_speed(SPEED_OFF);
          buzzer_start(1, BUZZER_LONG_MS, BUZZER_GAP_MS);
        }
        update_leds();
      }
    }

    uint8_t cmd;
    if (ir_take_command(&cmd)) {
      handle_command(cmd);
    }
  }
  return 0;
}
