#include <Arduino.h>
#include <Wire.h>
#include <SPI.h>
#include <SD.h>
#include <Adafruit_GFX.h>
#include <Adafruit_SSD1306.h>
#include <VL53L0X.h>

#define SCREEN_WIDTH  128
#define SCREEN_HEIGHT 64
#define OLED_ADDRESS  0x3C

#define SD_CS    5
#define SD_SCK   18
#define SD_MISO  19
#define SD_MOSI  23

#define BTN_PWR   25
#define BTN_SEL   27
#define BTN_DOWN  33
#define BTN_MEAS  32
#define BUZZER    26
#define LASER_PIN 4

Adafruit_SSD1306 display(SCREEN_WIDTH, SCREEN_HEIGHT, &Wire, -1);
VL53L0X sensor;

bool sdReady     = false;
int  recordCount = 0;
float lastMm     = 0;

// ── History scroll data ────────────────────────────────────
int historyOffset = 0;  // which record to start showing from
int historyTotal  = 0;  // total records on SD
String historyLines[100]; // store all records

// ── Button struct ──────────────────────────────────────────
struct Button {
  int pin;
  bool lastReading;
  bool stable;
  unsigned long lastChangeTime;
  bool triggered;
};

Button btnPwr  = {BTN_PWR,  true, true, 0, false};
Button btnSel  = {BTN_SEL,  true, true, 0, false};
Button btnDown = {BTN_DOWN, true, true, 0, false};
Button btnMeas = {BTN_MEAS, true, true, 0, false};

void updateButton(Button &btn) {
  btn.triggered = false;
  bool reading = digitalRead(btn.pin);
  if (reading != btn.lastReading) {
    btn.lastChangeTime = millis();
    btn.lastReading = reading;
  }
  if ((millis() - btn.lastChangeTime) > 50) {
    if (btn.stable == true && reading == false) btn.triggered = true;
    btn.stable = reading;
  }
}

// ── Buzzer ─────────────────────────────────────────────────
void beep(int times, bool longBeep = false) {
  if (longBeep) {
    digitalWrite(BUZZER, HIGH); delay(600);
    digitalWrite(BUZZER, LOW);  return;
  }
  for (int i = 0; i < times; i++) {
    digitalWrite(BUZZER, HIGH); delay(80);
    digitalWrite(BUZZER, LOW);  delay(100);
  }
}

// ── Screens ────────────────────────────────────────────────
enum Screen { OFF, MODE_SELECT, NORMAL, BLE };
Screen currentScreen = OFF;
int selectedMode = 0;

// ── Normal mode states ─────────────────────────────────────
enum NormalState { IDLE, LASER_ON, MEASURED, HISTORY };
NormalState normalState = IDLE;

// ── Display functions ──────────────────────────────────────
void drawHeader(String mode) {
  display.setTextColor(SSD1306_WHITE);
  display.setTextSize(1);
  display.setCursor(0, 0);
  display.println("SmartMeasure Pro");
  display.drawLine(0, 10, 128, 10, SSD1306_WHITE);
  display.setCursor(98, 0);
  display.print(mode);
}

void showModeSelect() {
  display.clearDisplay();
  display.setTextColor(SSD1306_WHITE);
  display.setTextSize(1);
  display.setCursor(18, 0);
  display.println("SmartMeasure Pro");
  display.drawLine(0, 10, 128, 10, SSD1306_WHITE);
  display.setCursor(0, 14); display.println("Select Mode:");
  display.setCursor(0, 28);
  display.print(selectedMode == 0 ? "> " : "  ");
  display.println("Normal Mode");
  display.setCursor(0, 40);
  display.print(selectedMode == 1 ? "> " : "  ");
  display.println("Bluetooth Mode");
  display.setCursor(0, 54); display.println("SEL=ok  DWN=move");
  display.display();
}

void showIdle() {
  display.clearDisplay();
  drawHeader("NRM");
  display.setTextSize(1);
  display.setCursor(0, 14); display.println("Press MEASURE");
  display.setCursor(0, 24); display.println("to start");
  display.setCursor(0, 36);
  display.print("Records: "); display.print(recordCount);
  display.setCursor(0, 52); display.println("SEL=history PWR=off");
  display.display();
}

void showLaserOn() {
  display.clearDisplay();
  drawHeader("NRM");
  display.setTextSize(1);
  display.setCursor(0, 14); display.println("** LASER ON **");
  display.setCursor(0, 26); display.println("Aim at target");
  display.setCursor(0, 38); display.println("Press MEASURE again");
  display.setCursor(0, 52); display.println("PWR=cancel");
  display.display();
}

void showMeasuring() {
  display.clearDisplay();
  drawHeader("NRM");
  display.setTextSize(1);
  display.setCursor(20, 28); display.println("Measuring...");
  display.display();
}

void showResult(float mm) {
  display.clearDisplay();
  drawHeader("NRM");
  display.setTextSize(1);
  display.setCursor(0, 14); display.println("Result:");
  display.setTextSize(2);
  display.setCursor(0, 28);
  if (mm >= 1000) { display.print(mm/1000.0, 2); display.println(" m"); }
  else            { display.print((int)mm);       display.println(" mm"); }
  display.setTextSize(1);
  display.setCursor(0, 52); display.println("MEAS=save PWR=cancel");
  display.display();
}

void showSaved(float mm) {
  display.clearDisplay();
  drawHeader("NRM");
  display.setCursor(28, 14); display.println(">> SAVED! <<");
  display.setTextSize(2);
  display.setCursor(0, 28);
  if (mm >= 1000) { display.print(mm/1000.0, 2); display.println(" m"); }
  else            { display.print((int)mm);       display.println(" mm"); }
  display.setTextSize(1);
  display.setCursor(0, 52);
  display.print("Total: "); display.print(recordCount);
  display.display();
}

void loadHistory() {
  historyTotal = 0;
  if (!sdReady) return;
  File f = SD.open("/readings.csv");
  if (!f) return;
  while (f.available()) {
    String line = f.readStringUntil('\n');
    line.trim();
    if (line.startsWith("count") || line.length() < 3) continue;
    historyLines[historyTotal] = line;
    historyTotal++;
    if (historyTotal >= 100) break;
  }
  f.close();
  // start from last record
  historyOffset = max(0, historyTotal - 3);
}

void showHistory() {
  display.clearDisplay();
  drawHeader("NRM");
  display.setTextSize(1);

  // header — no mode indicator, no last measurement
  display.setCursor(0, 0);
  display.println("-- History --");
  display.drawLine(0, 10, 128, 10, SSD1306_WHITE);

  if (!sdReady) {
    display.setCursor(0, 20); display.println("SD not available");
    display.setCursor(0, 54); display.println("PWR=back");
    display.display(); return;
  }

  if (historyTotal == 0) {
    display.setCursor(0, 20); display.println("No records yet");
    display.setCursor(0, 54); display.println("PWR=back");
    display.display(); return;
  }

  // show 3 records starting from historyOffset
  for (int i = 0; i < 3; i++) {
    int idx = historyOffset + i;
    if (idx >= historyTotal) break;

    String l  = historyLines[idx];
    int c1    = l.indexOf(',');
    int c2    = l.indexOf(',', c1 + 1);
    String num = l.substring(0, c1);
    String mm  = l.substring(c1 + 1, c2);

    display.setCursor(0, 14 + i * 14);
    display.print("#"); display.print(num);
    display.print("  "); display.print(mm); display.print(" mm");
  }

  // scroll indicator bottom right
  display.setCursor(80, 54);
  display.print(historyOffset + 1);
  display.print("-");
  display.print(min(historyOffset + 3, historyTotal));
  display.print("/");
  display.print(historyTotal);

  // navigation hint
  display.setCursor(0, 54);
  display.print("PWR=back DWN/SEL=scroll");

  display.display();
}

// ── SD save ────────────────────────────────────────────────
bool saveToSD(float mm) {
  if (!sdReady) return false;
  File f = SD.open("/readings.csv", FILE_APPEND);
  if (!f) return false;
  recordCount++;
  f.print(recordCount); f.print(",");
  f.print(mm, 1);       f.print(",");
  f.println(millis());
  f.close();
  return true;
}

// ── Measure ────────────────────────────────────────────────
float doMeasure() {
  for (int i = 0; i < 3; i++) {
    digitalWrite(LASER_PIN, LOW);  delay(150);
    digitalWrite(LASER_PIN, HIGH); delay(150);
  }
  digitalWrite(LASER_PIN, LOW);
  showMeasuring();
  delay(100);
  uint16_t mm = sensor.readRangeContinuousMillimeters();
  if (sensor.timeoutOccurred() || mm >= 2000) return -1;
  return (float)mm;
}

// ── Setup ──────────────────────────────────────────────────
void setup() {
  Serial.begin(115200);
  Wire.begin(21, 22);

  pinMode(BTN_PWR,   INPUT_PULLUP);
  pinMode(BTN_SEL,   INPUT_PULLUP);
  pinMode(BTN_DOWN,  INPUT_PULLUP);
  pinMode(BTN_MEAS,  INPUT_PULLUP);
  pinMode(BUZZER,    OUTPUT);
  pinMode(LASER_PIN, OUTPUT);
  digitalWrite(BUZZER,    LOW);
  digitalWrite(LASER_PIN, LOW);

  // OLED
  display.begin(SSD1306_SWITCHCAPVCC, OLED_ADDRESS);
  display.clearDisplay();
  display.display();

  // Sensor
  sensor.setTimeout(500);
  sensor.init();
  sensor.startContinuous();

  // SD
  SPI.begin(SD_SCK, SD_MISO, SD_MOSI, SD_CS);
  delay(200);
  if (SD.begin(SD_CS, SPI, 4000000)) {
    sdReady = true;
    if (!SD.exists("/readings.csv")) {
      File f = SD.open("/readings.csv", FILE_WRITE);
      if (f) { f.println("count,mm,millis"); f.close(); }
    }
  }

  Serial.println("Ready - press PWR to start");
}

// ── Loop ───────────────────────────────────────────────────
void loop() {
  updateButton(btnPwr);
  updateButton(btnSel);
  updateButton(btnDown);
  updateButton(btnMeas);

  // ── OFF ─────────────────────────────────────────────────
  if (currentScreen == OFF) {
    if (btnPwr.triggered) {
      currentScreen = MODE_SELECT;
      selectedMode  = 0;
      beep(1);
      showModeSelect();
    }
  }

  // ── MODE SELECT ─────────────────────────────────────────
  else if (currentScreen == MODE_SELECT) {
    if (btnDown.triggered) {
      selectedMode = (selectedMode + 1) % 2;
      beep(1);
      showModeSelect();
    }
    if (btnSel.triggered) {
      beep(2);
      if (selectedMode == 0) {
        currentScreen = NORMAL;
        normalState   = IDLE;
        showIdle();
        Serial.println("Normal mode");
      } else {
        currentScreen = BLE;
        display.clearDisplay();
        display.setTextColor(SSD1306_WHITE);
        display.setTextSize(1);
        display.setCursor(18, 0); display.println("SmartMeasure Pro");
        display.drawLine(0, 10, 128, 10, SSD1306_WHITE);
        display.setCursor(0, 20); display.println("BLE Mode");
        display.setCursor(0, 32); display.println("Waiting for app...");
        display.display();
        Serial.println("BLE mode");
      }
    }
    if (btnPwr.triggered) {
      currentScreen = OFF;
      display.clearDisplay(); display.display();
      beep(2);
    }
  }

  // ── NORMAL MODE ─────────────────────────────────────────
  else if (currentScreen == NORMAL) {

    // IDLE
    if (normalState == IDLE) {
      if (btnMeas.triggered) {
        digitalWrite(LASER_PIN, HIGH);
        beep(1);
        showLaserOn();
        normalState = LASER_ON;
        Serial.println("Laser ON");
      }
      if (btnSel.triggered) {
        loadHistory();       // load all records first
        historyOffset = max(0, historyTotal - 3);  // start from latest
        showHistory();
        normalState = HISTORY;
      }
      if (btnPwr.triggered) {
        currentScreen = OFF;
        display.clearDisplay(); display.display();
        beep(2);
      }
    }

    // LASER ON
    else if (normalState == LASER_ON) {
      if (btnMeas.triggered) {
        float mm = doMeasure();
        if (mm < 0) {
          beep(1, true);
          display.clearDisplay();
          drawHeader("NRM");
          display.setTextSize(1);
          display.setCursor(0, 20); display.println("Out of range!");
          display.setCursor(0, 32); display.println("Move closer");
          display.setCursor(0, 44); display.println("Press MEAS again");
          display.display();
          delay(1500);
          digitalWrite(LASER_PIN, HIGH);
          showLaserOn();
        } else {
          lastMm = mm;
          beep(1);
          showResult(lastMm);
          normalState = MEASURED;
          Serial.print("Measured: "); Serial.print(mm); Serial.println(" mm");
        }
      }
      if (btnPwr.triggered) {
        digitalWrite(LASER_PIN, LOW);
        beep(1);
        showIdle();
        normalState = IDLE;
      }
    }

    // MEASURED
    else if (normalState == MEASURED) {
      if (btnMeas.triggered) {
        bool ok = saveToSD(lastMm);
        if (ok) {
          beep(3);
          showSaved(lastMm);
          delay(1500);
          Serial.print("Saved: "); Serial.print(lastMm); Serial.println(" mm");
        } else {
          beep(1, true);
          display.clearDisplay();
          drawHeader("NRM");
          display.setCursor(0, 28); display.println("Save FAILED!");
          display.display();
          delay(1000);
        }
        showIdle();
        normalState = IDLE;
      }
      if (btnPwr.triggered) {
        beep(1);
        showIdle();
        normalState = IDLE;
      }
    }

    // HISTORY
    else if (normalState == HISTORY) {

      // scroll down
      if (btnDown.triggered) {
        if (historyOffset + 3 < historyTotal) {
          historyOffset++;
          beep(1);
          showHistory();
        }
      }

      // scroll up
      if (btnSel.triggered) {
        if (historyOffset > 0) {
          historyOffset--;
          beep(1);
          showHistory();
        }
      }

      // back to idle
      if (btnPwr.triggered) {
        beep(1);
        showIdle();
        normalState = IDLE;
      }
    }
  }

  // ── BLE MODE ────────────────────────────────────────────
  else if (currentScreen == BLE) {
    if (btnPwr.triggered) {
      currentScreen = OFF;
      display.clearDisplay(); display.display();
      beep(2);
    }
  }

  delay(10);
}