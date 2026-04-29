# ALVA-TEXT Demo-Video — Storyboard v1

> **Ziel:** In 30 Sekunden zeigen, wie simpel ALVA-TEXT bedient wird und wie hoch der Mehrwert ist. Der Zuschauer soll innerhalb der ersten 5 Sekunden „verstanden" haben, was passiert.
>
> **Format:** 1920×1080 (Landscape), MP4 (H.264, AAC), max. 6 MB. Optional zusätzlich 1080×1080 (Square) für Social.
>
> **Sprecher:** Keine Voice-Over. Tonspur = nur Originalton (Tippen, Aufnahmesignal, Whoosh beim Texteinfügen). Untertitel auf Deutsch eingeblendet.
>
> **Ablage:** Endprodukt nach `/Users/AdPolis/codex-work/alper-scheel/web/adluna/assets/video/alva-text-demo.mp4`. Dann ist es automatisch in `alva-text.html` (`<video>`-Slot) verfügbar.

---

## Storyboard (30 Sekunden, 7 Beats)

### Beat 1 · 0:00–0:03 — Die Frustsituation
**Szene:** Mac-Bildschirm, Mail.app im Vordergrund, leere E-Mail an „kunde@firma.de", Cursor blinkt im Body. Untertitel unten: „Eine Mail. Drei Absätze im Kopf. Keine Lust zu tippen."
**Bewegung:** Statisch, nur der Cursor blinkt.

### Beat 2 · 0:03–0:05 — Hotkey
**Szene:** Tastatur-Closeup (oder Screen-Overlay einer Tastatur). Daumen drückt `⌃` + `⌥`. In der Menüleiste oben: das ALVA-TEXT-Symbol färbt sich rot, ein kleiner Status erscheint: „REC".
**Untertitel:** „⌥ + ⌃ halten."

### Beat 3 · 0:05–0:13 — Sprechen
**Szene:** Splitscreen oder Cut zwischen Sprecher (kann nur Mund/Mikrofon sein) und Bildschirm. Im Bildschirm: über der Mail eine kleine Wellenform-Animation (wie in der Live-Demo auf der Webseite).
**Originalton:** Stimme spricht: *„Sehr geehrte Damen und Herren, anbei der überarbeitete Vertragsentwurf zur Kenntnis. Die Anpassungen aus unserem Telefonat von gestern sind eingearbeitet — insbesondere die geänderte Laufzeit und die neue Klausel zur außerordentlichen Kündigung."*
**Untertitel:** Live-Mitschrift, was gesprochen wird.

### Beat 4 · 0:13–0:14 — Loslassen
**Szene:** Daumen lässt die Tasten los. Status in der Menüleiste wechselt von Rot („REC") auf kurz Gelb („Adaptive-Mode läuft", 0,8 Sek).
**Untertitel:** „Loslassen."

### Beat 5 · 0:14–0:22 — Text erscheint
**Szene:** Zoom auf die Mail. Der diktierte Text erscheint im Mail-Body — aber nicht als Roh-Diktat, sondern in **sauberer geschäftlicher Form** mit Anrede, Absatzbruch, Schluss:

> Sehr geehrte Damen und Herren,
>
> anbei finden Sie den überarbeiteten Vertragsentwurf zur Kenntnis. Die Anpassungen aus unserem Telefonat vom gestrigen Tag sind eingearbeitet — insbesondere die geänderte Laufzeit sowie die neue Klausel zur außerordentlichen Kündigung.
>
> Mit freundlichen Grüßen

**Animation:** Text erscheint nicht typewriter-mäßig, sondern absatzweise (fade-in, 0,3 Sek pro Block). Sound: dezenter „Whoosh".
**Untertitel:** „Sauber formatiert. In der App, in der Sie sind."

### Beat 6 · 0:22–0:27 — Highlight-Frame
**Szene:** Standbild der fertigen Mail. Drei Highlights mit Pfeilen/Markierungen:
1. Pfeil auf „Sehr geehrte Damen und Herren": *„Anrede formell — automatisch erkannt."*
2. Pfeil auf den Absatzbruch: *„Saubere Struktur — niemand mag Bleiwüsten."*
3. Pfeil auf „Mit freundlichen Grüßen": *„Sign-off aus Ihrem Profil — nicht erfunden."*

### Beat 7 · 0:27–0:30 — Logo + Claim
**Szene:** Cut auf weiße Fläche. AdLuna-Logo zentriert. Darunter Claim: **„ALVA-TEXT. Lokal und loyal."** Klein darunter: „Kostenlos in der Beta · adluna.de/alva-text".

---

## Aufnahme-Tipps

- **Bildschirmaufnahme:** macOS QuickTime Player → Datei → Neue Bildschirmaufnahme. Oder ScreenStudio (zoomt automatisch sauber rein).
- **Webcam-Inserts:** Nicht zwingend nötig. Wenn doch, dann nur ein kleiner Ausschnitt im Splitscreen während Beat 3.
- **Mic:** Direktes Headset oder Lavalier; in Beat 3 muss die Stimme klar verständlich sein, weil sie als Untertitel mitläuft.
- **Cursor sichtbar machen:** macOS-Einstellungen → Bedienungshilfen → Zeiger → Cursor-Größe leicht erhöht.
- **Umgebung:** Saubere, leere Mail. Keine privaten Empfänger. Beispiel-Domain ist „kunde@firma.de".

## Schnitt-Tipps

- **Schnittprogramm:** Final Cut Pro, DaVinci Resolve oder iMovie reichen.
- **Untertitel:** Als integrierte Untertitel-Spur, weiß auf halb-transparentem Schwarz (Inter Medium 36px), unten zentriert.
- **Sound-Mix:** Originalton -3 dB, dezente Background-Drone bei -24 dB optional. Ein dezenter „Whoosh" bei Beat 5 (Pixabay/Free-Sound).
- **Export:** H.264, 24 fps, CRF 23, max. 6 MB für die Web-Einbettung.

## Alternativ-Variante (15 Sek, kürzer)

Wenn die 30-Sek-Version zu lang wirkt:
- Beat 1 streichen (direkt mit Hotkey starten).
- Beat 6 streichen (Highlights weg).
- Beat 3 auf 6 Sek kürzen (kürzerer Beispieltext).

## Open-Loop-Hinweis

Bis das Video fertig ist, läuft auf `alva-text.html` die animierte CSS-Inline-Demo (Mac-Fenster mit Wellenform und Typing-Effekt). Sobald `assets/video/alva-text-demo.mp4` existiert und auf Cloudflare Pages deployed ist, taucht der `<video>`-Player automatisch unter dem Disclosure-Toggle auf — kein zusätzlicher HTML-Eingriff nötig.
