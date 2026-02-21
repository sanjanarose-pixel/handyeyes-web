<p align="center">
  <img src="pic.png" alt="HandyEyes Banner" width="100%">
</p>

# HandyEyes 🎯

## Basic Details

### Team Name: Lunar Logic

### Team Members
- Sanjana Sujith - MITS
- Shaen Meryl Saj - MITS

### Hosted Project Link and video link
https://handyeyes-web.vercel.app/ 

https://drive.google.com/file/d/1BUn84T-wslzhdjfNLMOcNQjmZj_pf87Y/view?usp=drivesdk


### Project Description
HandyEyes is a hybrid real-time object detection system that combines on-device machine learning with cloud-based vision AI to provide low-latency, confidence-filtered audio feedback for visually impaired users.

### The Problem Statement
Visually impaired users struggle to navigate dynamic environments safely due to limited real-time environmental awareness.

### The Solution
HandyEyes detects objects in real time using the camera, processes them on-device for immediate feedback, and uses cloud AI for enhanced detection accuracy. It delivers audio alerts to users about obstacles and surroundings.

---

## Technical Details

### Technologies/Components Used

**Software:**
- Languages: Dart (Flutter), JavaScript (for web integration)
- Frameworks: Flutter Web
- Libraries: Google ML Kit, flutter_tts, speech_to_text
- Tools: VS Code, Git, Flutter SDK

**Hardware:**
- No additional hardware required — works with smartphone or laptop camera
- Optional: Headphones for audio output

---

## Features

- Real-time object detection
- Confidence-filtered audio alerts
- Works entirely in the browser (Flutter Web)
- Cloud-based detection fallback for higher accuracy
- Lightweight and low-latency

---

## Implementation

### For Software:

#### Installation
```bash
# Clone the repo
git clone https://github.com/YOUR_USERNAME/handyeyes-web.git
cd handyeyes-web

# Run locally
flutter pub get
flutter run -d chrome
Run
flutter build web
# Then serve locally or deploy to hosting platform
Project Documentation
Screenshots

Live object detection in action


Audio feedback being delivered


Confidence levels displayed

System Architecture

HandyEyes processes camera input on-device, with optional cloud AI integration for improved accuracy.

Application Workflow

User points camera → On-device ML processes → Audio alerts delivered in real-time.

AI Tools Used (Optional)
Tool: ChatGPT

Purpose: Debugging and guidance for Flutter & ML Kit integration

Percentage of AI-generated code: ~5%

Human Contributions: Architecture, Flutter code, ML integration, UI/UX

Team Contributions
Sanjana Sujith: Flutter development, ML Kit integration, web deployment

Shaen Meryl Saj: Cloud AI integration, testing, documentation

License
This project is licensed under the MIT License - see the LICENSE file for details.

Made with ❤️ at TinkerHub
