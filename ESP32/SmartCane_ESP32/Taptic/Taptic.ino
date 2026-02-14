void cycle() {
  digitalWrite(1, HIGH);
  delayMicroseconds(3840);
  digitalWrite(1, LOW);
  delayMicroseconds(3840);
}

void setup() {
  pinMode(1, OUTPUT);
}

void loop() {
  for (int i = 0; i < 4; i++) {
    cycle();
  }
  delay(1000);
}
