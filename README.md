# macOS-Tastaturassistent – Anleitung

Mit `mac_tastatur_assistent.sh` kannst du unter macOS (auch Sequoia 15) mehrere Tastaturmodelle **getrennt** konfigurieren. Das Skript verwendet nur macOS-Bordmittel (`hidutil`, `launchctl`, `plutil`) und benötigt keine Administratorrechte und keine Internetverbindung.

## Starten

1. Lade `mac_tastatur_assistent.sh` auf den Mac und speichere die Datei z. B. unter `Downloads`.
2. Öffne **Terminal** und führe aus:

   ```bash
   bash ~/Downloads/mac_tastatur_assistent.sh
   ```

   Wenn du die Datei an einem anderen Ort gespeichert hast, passe den Pfad an. Du kannst die Datei auch nach `bash ` ins Terminal ziehen.

3. Wähle **1 – Tastatur auswählen und Tasten zuordnen**.
4. Wähle die angeschlossene Tastatur aus der Liste. Die angezeigten **VendorID** und **ProductID** dienen dazu, die Regeln nur auf dieses Tastaturmodell anzuwenden. Falls ein Gerät nicht erkannt wird, kannst du die IDs manuell eingeben.
5. Wähle eine Belegung:
   - **Windows-Kürzel:** Ctrl und Windows-Taste tauschen ihre Funktionen; `Ctrl+C` kopiert.
   - **Apple-ähnlich:** Windows- und Alt-Taste tauschen ihre Funktionen; Command liegt neben der Leertaste.
   - **Ctrl/Alt tauschen.**
   - **Caps Lock/Escape tauschen.**
   - **Individuell:** beliebige Zuordnungen zwischen linken/rechten Ctrl-, Windows-/Command-, Alt-/Option-Tasten sowie Caps Lock und Escape definieren.
6. Teste die Tasten. Nur wenn alles stimmt, bestätigst du die **dauerhafte Einrichtung**.

## Was wird dauerhaft gespeichert?

Für jedes ausgewählte Tastaturmodell wird eine eigene `.plist`-Datei in `~/Library/LaunchAgents` angelegt, zum Beispiel:

```
~/Library/LaunchAgents/local.keyboardwizard.v413c.p2003.plist
```

Die Tastenbelegung wird bei jeder Benutzeranmeldung und danach etwa alle 30 Sekunden erneut gesetzt. So wird sie auch nach dem Aus- und Wiedereinstecken der Tastatur normalerweise wiederhergestellt. Andere Tastaturmodelle werden nicht beeinflusst – **zwei Geräte mit identischen VendorID/ProductID werden jedoch gemeinsam konfiguriert**.

## Prüfen und rückgängig machen

Starte das Skript erneut:

```bash
bash ~/Downloads/mac_tastatur_assistent.sh
```

Wähle **2 – Status**, um die erkannten Tastaturen und ihre aktive Belegung zu sehen. Mit **3 – Belegung und eigenen LaunchAgent entfernen** kannst du die Änderung für eine ausgewählte Tastatur rückgängig machen. Das Skript entfernt dabei nur die selbst erstellten LaunchAgents.

## Zu beachten

- Wenn bereits eine ältere `hidutil`-Konfiguration oder ein anderer Tastatur-Remapper läuft, kann diese Einstellung mit dem neuen Agent kollidieren. Deaktiviere zuerst solche konkurrierenden Regeln.
- `hidutil` belegt **einzelne Tasten** um; damit lassen sich keine mehrstufigen Makros, Tastenkombinationen mit Bedingungen oder anwendungsspezifische Regeln erstellen.
- Die macOS-Erkennung **ISO/ANSI/JIS** (Tastaturtyp) bleibt davon unabhängig. Falls nach dem Einstecken ein Tastatur-Assistent erscheint, hat dies mit der Ctrl-/Alt-Zuordnung selbst nichts zu tun.
- Der Assistent nutzt eine Textansicht von `hidutil list` für die Geräteerkennung. Je nach Tastatur oder macOS-Version ist gelegentlich die manuelle Eingabe von VendorID und ProductID nötig.
- Die Erstellung und der Inhalt der `.plist` wurden auf ihre Struktur geprüft; die tatsächliche Wirkung hängt von der jeweiligen macOS-Version und Tastatur ab. Darum zuerst testen, dann dauerhaft speichern.
