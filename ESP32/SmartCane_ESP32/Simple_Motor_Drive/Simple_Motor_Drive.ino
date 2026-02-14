const int IN1 = 2;   // forward
const int IN2 = 3;   // reverse

const int SPEED = 255; // (8-bit)

const uint32_t PWM_FREQ = 1000; // 1 kHz
const uint8_t  PWM_BITS = 8;    // 0..255

void setup() {
  pinMode(IN1, OUTPUT);
  pinMode(IN2, OUTPUT);
}

void loop() {
  analogWrite(IN2, 0);
  analogWrite(IN1, SPEED);
  delay(2000);

  analogWrite(IN1, 0);
  analogWrite(IN2, 0);
  delay(2000);

  analogWrite(IN1, 0);
  analogWrite(IN2, SPEED);
  delay(2000);

  analogWrite(IN1, 0);
  analogWrite(IN2, 0);
  delay(2000);
}
