#!/bin/bash
# macOS-Tastaturassistent – interaktive, geraetespezifische Tastenbelegung
# macOS 12+; benoetigt nur macOS-Bordmittel (hidutil, launchctl, plutil, awk).
# Kompatibel mit dem auf macOS vorinstallierten Bash 3.2.
# Erstellt pro VendorID/ProductID einen eigenen LaunchAgent (30-Sekunden-Pruefung).

set -u

AGENTS_DIR="$HOME/Library/LaunchAgents"
PERIOD=30
PREFIX="local.keyboardwizard"

if [ "$(uname -s)" != "Darwin" ]; then
  echo "Fehler: Dieses Skript funktioniert ausschliesslich unter macOS."
  exit 1
fi
if ! command -v hidutil >/dev/null 2>&1; then
  echo "Fehler: Das macOS-Programm 'hidutil' wurde nicht gefunden."
  exit 1
fi

# Verwendete HID Usage IDs (Usage Page 0x07 / Tastatur).
# Links: Ctrl=E0, Win/Cmd=E3, Alt/Option=E2
# Rechts: Ctrl=E4, Win/Cmd=E7, Alt/Option=E6
NAMES=("Ctrl links" "Windows/Command links" "Alt/Option links" \
       "Ctrl rechts" "Windows/Command rechts" "Alt/Option rechts" \
       "Feststelltaste (Caps Lock)" "Escape")
CODES=("0x7000000E0" "0x7000000E3" "0x7000000E2" \
       "0x7000000E4" "0x7000000E7" "0x7000000E6" \
       "0x700000039" "0x700000029")

SRC=()
DST=()
VENDOR=""
PRODUCT=""
DEVICENAME=""
MATCH=""
LABEL=""
PLIST=""

line() { printf '\n%s\n' '------------------------------------------------------------'; }
ask() {
  # ask "Fragetext" -> REPLY
  printf '%s' "$1"
  IFS= read -r REPLY || { printf '\nEingabe beendet.\n'; exit 0; }
}
answer_yes() {
  case "$1" in [jJyY]|[jJyY][aA]|[yY][eE][sS]) return 0 ;; *) return 1 ;; esac
}

# Ergebnis per globaler Variable NUMBER, um Subshell-Nebenwirkungen zu vermeiden.
number_from_user() {
  local v="$1"
  NUMBER=""
  if [[ "$v" =~ ^0[xX][0-9a-fA-F]+$ ]]; then
    NUMBER=$((v))
  elif [[ "$v" =~ ^[0-9]+$ ]]; then
    NUMBER=$((10#$v))
  else
    return 1
  fi
  if [ "$NUMBER" -lt 0 ] || [ "$NUMBER" -gt 65535 ]; then
    return 1
  fi
  return 0
}

set_target() {
  local i k
  VENDOR="$1"; PRODUCT="$2"; DEVICENAME="$3"
  MATCH="{\"VendorID\":$VENDOR,\"ProductID\":$PRODUCT}"
  # IDs statt Tastaturname: eindeutiger und pfadsicher fuer den Agent.
  printf -v LABEL '%s.v%04x.p%04x' "$PREFIX" "$VENDOR" "$PRODUCT"
  PLIST="$AGENTS_DIR/$LABEL.plist"
}

# macOS hidutil list hat eine Texttabelle. Nur echte Keyboard-Usages
# (UsagePage=1, Usage=6) nehmen; doppelte Services pro Hardwaretyp entfernen.
# Der Produktname wird aus dem Teil nach den ersten acht Spalten gelesen.
scan_devices() {
  DEV_V=(); DEV_P=(); DEV_N=(); DEV_T=()
  local v p n t number
  while IFS='|' read -r v p n t; do
    [ -n "$v" ] || continue
    number_from_user "$v" || continue
    v="$NUMBER"
    number_from_user "$p" || continue
    p="$NUMBER"
    DEV_V+=("$v")
    DEV_P+=("$p")
    DEV_N+=("$n")
    DEV_T+=("$t")
  done < <(hidutil list 2>/dev/null | awk '
      $1 ~ /^0x[0-9a-fA-F]+$/ && $2 ~ /^0x[0-9a-fA-F]+$/ && $4 == 1 && $5 == 6 {
        key=tolower($1) ":" tolower($2)
        if (seen[key]++) next
        transport=$7
        rest=$0
        for (i=1; i<=8; i++) sub(/^[[:space:]]*[^[:space:]]+[[:space:]]*/, "", rest)
        # Produktnamen koennen Leerzeichen enthalten; Spalten sind mehrfach getrennt.
        split(rest, fields, /[[:space:]][[:space:]]+/)
        name=fields[1]
        sub(/[[:space:]]+$/, "", name)
        if (name == "") name="Unbekannte Tastatur"
        gsub(/\|/, "/", name)
        row=sprintf("%s|%s|%s|%s", $1, $2, name, transport)
        if (name ~ /Apple Internal/ || transport == "SPI") {
          internal[++n_internal]=row
        } else {
          print row
        }
      }
      END { for (j=1; j<=n_internal; j++) print internal[j] }
    ')
}

show_devices() {
  local i
  scan_devices
  echo
  echo "Erkannte Tastaturen (VendorID + ProductID):"
  if [ "${#DEV_V[@]}" -eq 0 ]; then
    echo "  Keine Tastatur automatisch gefunden."
  else
    for ((i=0; i<${#DEV_V[@]}; i++)); do
      printf '  %2d) %-32s %-10s VID 0x%04X / PID 0x%04X\n' \
        "$((i+1))" "${DEV_N[$i]}" "${DEV_T[$i]}" "${DEV_V[$i]}" "${DEV_P[$i]}"
    done
  fi
  echo "   m) VendorID/ProductID manuell eingeben"
  echo "   0) Zurueck"
}

choose_device() {
  local choice v p n idx
  while :; do
    show_devices
    ask "Tastatur auswaehlen: "
    choice="$REPLY"
    case "$choice" in
      0) return 1 ;;
      m|M)
        ask "VendorID (z. B. 0x413c oder 16700): "
        number_from_user "$REPLY" || { echo "Ungueltige VendorID."; continue; }
        v="$NUMBER"
        ask "ProductID (z. B. 0x2003 oder 8195): "
        number_from_user "$REPLY" || { echo "Ungueltige ProductID."; continue; }
        p="$NUMBER"
        n="Manuell gewaehlte Tastatur"
        set_target "$v" "$p" "$n"
        break ;;
      *)
        if ! [[ "$choice" =~ ^[0-9]+$ ]]; then
          echo "Bitte eine Nummer eingeben."; continue
        fi
        idx=$((10#$choice-1))
        if [ "$idx" -lt 0 ] || [ "$idx" -ge "${#DEV_V[@]}" ]; then
          echo "Diese Auswahl gibt es nicht."; continue
        fi
        set_target "${DEV_V[$idx]}" "${DEV_P[$idx]}" "${DEV_N[$idx]}"
        break ;;
    esac
  done
  line
  printf 'Ausgewaehlt: %s (VID 0x%04X / PID 0x%04X)\n' \
    "$DEVICENAME" "$VENDOR" "$PRODUCT"
  echo "Hinweis: Zwei Tastaturen mit *denselben* IDs werden gemeinsam beeinflusst."
  if [ "$VENDOR" -eq 1452 ]; then
    echo "ACHTUNG: Das koennte eine interne Apple-Tastatur sein."
    ask "Trotzdem fortfahren? [j/N]: "
    answer_yes "$REPLY" || return 1
  fi
  return 0
}

add_mapping() {
  local source="$1" destination="$2" i
  [ "$source" = "$destination" ] && return 0
  for ((i=0; i<${#SRC[@]}; i++)); do
    if [ "${SRC[$i]}" = "$source" ]; then
      DST[$i]="$destination"
      return 0
    fi
  done
  SRC+=("$source")
  DST+=("$destination")
}

make_preset() {
  local preset="$1" both="$2"
  SRC=(); DST=()
  case "$preset" in
    1) # Windows-Shortcuts: Ctrl -> Cmd, Win -> Ctrl
      add_mapping "${CODES[0]}" "${CODES[1]}"
      add_mapping "${CODES[1]}" "${CODES[0]}"
      if [ "$both" = "1" ]; then
        add_mapping "${CODES[3]}" "${CODES[4]}"
        add_mapping "${CODES[4]}" "${CODES[3]}"
      fi ;;
    2) # Mac-aehnliche Position: Win <-> Alt
      add_mapping "${CODES[1]}" "${CODES[2]}"
      add_mapping "${CODES[2]}" "${CODES[1]}"
      if [ "$both" = "1" ]; then
        add_mapping "${CODES[4]}" "${CODES[5]}"
        add_mapping "${CODES[5]}" "${CODES[4]}"
      fi ;;
    3) # Ctrl <-> Alt
      add_mapping "${CODES[0]}" "${CODES[2]}"
      add_mapping "${CODES[2]}" "${CODES[0]}"
      if [ "$both" = "1" ]; then
        add_mapping "${CODES[3]}" "${CODES[5]}"
        add_mapping "${CODES[5]}" "${CODES[3]}"
      fi ;;
    4) # Caps -> Esc; Esc -> Caps
      add_mapping "${CODES[6]}" "${CODES[7]}"
      add_mapping "${CODES[7]}" "${CODES[6]}" ;;
  esac
}

custom_mapping() {
  local i s d
  SRC=(); DST=()
  echo
  echo "Individuelle Tastenbelegung (alle nicht genannten Tasten bleiben unveraendert)."
  echo "Du kannst mehrere Zuordnungen nacheinander eingeben."
  while :; do
    echo
    for ((i=0; i<${#NAMES[@]}; i++)); do
      printf '  %d) %s\n' "$((i+1))" "${NAMES[$i]}"
    done
    echo "  0) Eingabe abschliessen"
    ask "Welche physische Taste soll geaendert werden? "
    s="$REPLY"
    if [ "$s" = "0" ]; then break; fi
    if ! [[ "$s" =~ ^[1-8]$ ]]; then
      echo "Bitte 1 bis 8 waehlen."; continue
    fi
    ask "Welche Funktion soll '${NAMES[$((s-1))]}' ausloesen? [1-8]: "
    d="$REPLY"
    if ! [[ "$d" =~ ^[1-8]$ ]]; then
      echo "Bitte 1 bis 8 waehlen."; continue
    fi
    if [ "$s" = "$d" ]; then
      echo "Quelle und Ziel sind identisch; keine Aenderung hinzugefuegt."
    else
      add_mapping "${CODES[$((s-1))]}" "${CODES[$((d-1))]}"
      echo "Hinzugefuegt: ${NAMES[$((s-1))]} -> ${NAMES[$((d-1))]}"
    fi
  done
}

choose_mapping() {
  local c two
  while :; do
    line
    echo "Gewuenschte Belegung:"
    echo "  1) Windows-Kuerzel: Ctrl=Command (Ctrl+C kopiert), Win=Ctrl"
    echo "  2) Apple-aehnlich: Alt=Command, Win=Option"
    echo "  3) Ctrl und Alt vertauschen"
    echo "  4) Caps Lock und Escape vertauschen"
    echo "  5) Individuell: mehrere Tasten selbst zuordnen"
    echo "  0) Zurueck"
    ask "Bitte waehlen [0-5]: "
    c="$REPLY"
    case "$c" in
      0) return 1 ;;
      1|2|3)
        ask "Auch die RECHTEN Ctrl-/Win-/Alt-Tasten umbelegen? [j/N]: "
        two=0
        answer_yes "$REPLY" && two=1
        make_preset "$c" "$two"
        break ;;
      4) make_preset 4 0; break ;;
      5) custom_mapping; break ;;
      *) echo "Ungueltige Auswahl." ;;
    esac
  done
  if [ "${#SRC[@]}" -eq 0 ]; then
    echo "Keine Tasten zugeordnet."
    return 1
  fi
  return 0
}

key_name() {
  local i
  KEYNAME="$1"
  for ((i=0; i<${#CODES[@]}; i++)); do
    if [ "${CODES[$i]}" = "$1" ]; then KEYNAME="${NAMES[$i]}"; return; fi
  done
}

show_mapping() {
  local i src dst
  echo
  echo "Gewaehlte Zuordnungen:"
  for ((i=0; i<${#SRC[@]}; i++)); do
    key_name "${SRC[$i]}"; src="$KEYNAME"
    key_name "${DST[$i]}"; dst="$KEYNAME"
    printf '  %-29s -> %s\n' "$src" "$dst"
  done
}

build_json() {
  local i entry
  MAP_JSON='{"UserKeyMapping":['
  for ((i=0; i<${#SRC[@]}; i++)); do
    [ "$i" -eq 0 ] || MAP_JSON+=','
    printf -v entry '{"HIDKeyboardModifierMappingSrc":%s,"HIDKeyboardModifierMappingDst":%s}' \
      "${SRC[$i]}" "${DST[$i]}"
    MAP_JSON+="$entry"
  done
  MAP_JSON+=']}'
}

show_current() {
  hidutil property --matching "$MATCH" --get UserKeyMapping 2>&1
}

apply_now() {
  echo
  echo "Tastenbelegung wird testweise angewendet ..."
  if ! hidutil property --matching "$MATCH" --set "$MAP_JSON"; then
    echo "FEHLER: hidutil konnte die Belegung nicht uebernehmen."
    echo "Pruefe, ob die Tastatur angeschlossen ist."
    return 1
  fi
  echo
  echo "Aktueller Status laut hidutil:"
  local current
  current=$(show_current)
  echo "$current"
  if printf '%s\n' "$current" | grep -q '(null)'; then
    echo "WARNUNG: hidutil zeigt weiterhin (null) an."
    echo "Die Tastatur wurde moeglicherweise nicht mit dem Filter erreicht."
    return 1
  fi
  return 0
}

agent_loaded() {
  launchctl print "gui/$(id -u)/$LABEL" >/dev/null 2>&1
}

install_agent() {
  local tempfile lintout
  mkdir -p "$AGENTS_DIR" || return 1
  tempfile=$(mktemp "$AGENTS_DIR/.keyboardwizard.XXXXXX") || return 1
  # XML-sicher, da LABEL/IDs aus Zahlen gebildet und MAP_JSON nur bekannte HID-Codes enthaelt.
  cat > "$tempfile" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>/usr/bin/hidutil</string>
    <string>property</string>
    <string>--matching</string>
    <string>$MATCH</string>
    <string>--set</string>
    <string>$MAP_JSON</string>
  </array>
  <key>RunAtLoad</key><true/>
  <key>StartInterval</key><integer>$PERIOD</integer>
</dict>
</plist>
EOF
  if ! lintout=$(plutil -lint "$tempfile" 2>&1); then
    echo "FEHLER: plist ist ungueltig: $lintout"
    rm -f "$tempfile"
    return 1
  fi
  # Vorhandenen *eigenen* Agent zuerst entladen, dann die neue Konfiguration aktivieren.
  if agent_loaded; then
    launchctl bootout "gui/$(id -u)/$LABEL" >/dev/null 2>&1 || {
      echo "Fehler beim Entladen des bisherigen Agents. Keine Datei ersetzt."
      rm -f "$tempfile"
      return 1
    }
  fi
  if ! mv -f "$tempfile" "$PLIST"; then
    echo "FEHLER: Konnte Agent-Datei nicht speichern."
    return 1
  fi
  if ! launchctl bootstrap "gui/$(id -u)" "$PLIST"; then
    echo "Agent konnte nicht gestartet werden; die Datei wurde jedoch erstellt:"
    echo "  $PLIST"
    echo "Du kannst spaeter erneut versuchen:"
    echo "  launchctl bootstrap gui/\$(id -u) '$PLIST'"
    return 1
  fi
  echo
  echo "Dauerhafte Einrichtung abgeschlossen."
  echo "  Agent: $PLIST"
  echo "  Beim Anmelden und alle $PERIOD Sekunden wird die Belegung gesetzt."
  echo "  Auch nach Ab- und Wiederanstecken (normalerweise innerhalb eines Intervalls)."
  echo "  Fuer eine weitere Tastatur einfach das Skript nochmals starten."
  return 0
}

configure() {
  choose_device || return
  choose_mapping || return
  show_mapping
  echo
  echo "WICHTIG: Eine vorhandene hidutil-Belegung dieser Tastatur wird ersetzt."
  echo "Andere Remapping-Dienste (z. B. aeltere LaunchAgents) koennen dagegen arbeiten."
  ask "Jetzt testweise anwenden? [j/N]: "
  answer_yes "$REPLY" || return
  build_json
  apply_now || return
  echo
  echo "Probiere nun das Verhalten aus, etwa Ctrl+C / Ctrl+V in einem Textfeld."
  ask "Funktioniert die Belegung wie gewuenscht? [j/N]: "
  if ! answer_yes "$REPLY"; then
    ask "Test-Belegung fuer diese Tastatur zuruecksetzen? [J/n]: "
    case "$REPLY" in n|N|nein|Nein) echo "Temporäre Zuordnung bleibt vorerst aktiv." ;;
      *) hidutil property --matching "$MATCH" --set '{"UserKeyMapping":[]}' ;;
    esac
    return
  fi
  echo
  ask "Dauerhaft bei Anmeldung und nach erneutem Anschluss aktivieren? [j/N]: "
  if answer_yes "$REPLY"; then
    install_agent
  else
    if [ -f "$PLIST" ]; then
      echo "ACHTUNG: Ein bereits eingerichteter Agent fuer diese Tastatur existiert."
      echo "Er kann deine temporaere Belegung in ca. $PERIOD Sekunden ueberschreiben."
    else
      echo "Nur temporaer aktiv: Nach einem Neustart/Neuanschluss kann die Belegung verschwinden."
    fi
  fi
}

status() {
  local i f found=0 any=0
  line
  echo "Erkannte Tastaturen und aktuelle hidutil-Zuordnung:"
  scan_devices
  for ((i=0; i<${#DEV_V[@]}; i++)); do
    set_target "${DEV_V[$i]}" "${DEV_P[$i]}" "${DEV_N[$i]}"
    printf '\n%s (VID 0x%04X / PID 0x%04X):\n' "$DEVICENAME" "$VENDOR" "$PRODUCT"
    show_current
    if [ -f "$PLIST" ]; then
      if agent_loaded; then echo "Eigener LaunchAgent: installiert und geladen";
      else echo "Eigener LaunchAgent: installiert, aber nicht geladen"; fi
    else echo "Eigener LaunchAgent: nicht vorhanden"; fi
    any=1
  done
  [ "$any" -eq 1 ] || echo "Keine HID-Tastatur gefunden."
  echo
  echo "Vom Assistenten verwaltete LaunchAgents:"
  for f in "$AGENTS_DIR/$PREFIX".*.plist; do
    [ -f "$f" ] || continue
    found=1
    printf '  %s\n' "${f##*/}"
  done
  [ "$found" -eq 1 ] || echo "  Keine vorhanden."
}

remove_mapping() {
  choose_device || return
  echo
  echo "Diese Aktion stoppt und entfernt nur den LaunchAgent des Assistenten"
  echo "fuer die gewaehlte Tastatur und setzt ihre hidutil-Belegung zurueck."
  if [ -f "$PLIST" ]; then echo "Agent-Datei: $PLIST";
  else echo "Es ist kein eigener Agent fuer diese Tastatur gespeichert."; fi
  ask "Wirklich zuruecksetzen? [j/N]: "
  answer_yes "$REPLY" || return
  if agent_loaded; then
    if ! launchctl bootout "gui/$(id -u)/$LABEL"; then
      echo "FEHLER: Agent konnte nicht entladen werden. Bitte zuerst Ursache klaeren."
      return
    fi
  fi
  if [ -f "$PLIST" ]; then
    if ! rm -f "$PLIST"; then echo "FEHLER: Agent-Datei konnte nicht geloescht werden."; return; fi
  fi
  echo "Aktive hidutil-Zuordnung wird entfernt ..."
  hidutil property --matching "$MATCH" --set '{"UserKeyMapping":[]}'
  echo "Fertig. Andere (nicht von diesem Skript verwaltete) LaunchAgents wurden nicht veraendert."
}

main() {
  echo "============================================================"
  echo " macOS-Tastaturassistent (hidutil)"
  echo " Tastaturspezifische Zuordnung ohne Zusatzsoftware"
  echo "============================================================"
  echo "Hinweis: Kein Tastaturtreiber, keine Administratorrechte noetig."
  echo "Bei Apple-Tastaturen (auch internen) bitte besonders vorsichtig sein."
  while :; do
    line
    echo "  1) Tastatur auswaehlen und Tasten zuordnen"
    echo "  2) Status aller erkannten Tastaturen anzeigen"
    echo "  3) Belegung und eigenen LaunchAgent entfernen"
    echo "  0) Beenden"
    ask "Auswahl: "
    case "$REPLY" in
      1) configure ;;
      2) status ;;
      3) remove_mapping ;;
      0) echo "Auf Wiedersehen."; return 0 ;;
      *) echo "Bitte 0, 1, 2 oder 3 eingeben." ;;
    esac
  done
}

main
