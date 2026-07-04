#!/bin/bash
# Skript zur Überprüfung der persistenten Claude Code Authentifizierung

set -e

echo "=== Claude Code Persistent Login Verification ==="
echo

# Farben für bessere Lesbarkeit
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 1. Prüfen ob Host-Verzeichnisse existieren
echo "1. Prüfe Host-Verzeichnisse..."
CLAUDE_DIR="$HOME/.claude-container/claude"
CLAUDE_FILE="$HOME/.claude-container/claude.json"

if [ -d "$CLAUDE_DIR" ]; then
    echo -e "${GREEN}✓${NC} Verzeichnis existiert: $CLAUDE_DIR"
else
    echo -e "${RED}✗${NC} Verzeichnis fehlt: $CLAUDE_DIR"
    echo "  Erstelle Verzeichnis..."
    mkdir -p "$CLAUDE_DIR"
    echo -e "${GREEN}✓${NC} Verzeichnis erstellt"
fi

if [ -f "$CLAUDE_FILE" ]; then
    echo -e "${GREEN}✓${NC} Datei existiert: $CLAUDE_FILE"
else
    echo -e "${YELLOW}⚠${NC} Datei fehlt: $CLAUDE_FILE"
    echo "  Erstelle Datei..."
    touch "$CLAUDE_FILE"
    echo -e "${GREEN}✓${NC} Datei erstellt"
fi

# 2. Prüfen der Berechtigungen
echo
echo "2. Prüfe Berechtigungen..."
ls -la "$HOME/.claude-container/" | grep -E "(claude$|claude.json)"

# 3. Prüfen ob Session-Daten vorhanden sind
echo
echo "3. Prüfe Session-Daten..."
if [ -d "$CLAUDE_DIR" ] && [ "$(ls -A "$CLAUDE_DIR" 2>/dev/null)" ]; then
    echo -e "${GREEN}✓${NC} Session-Daten gefunden in $CLAUDE_DIR"
    echo "  Dateien:"
    ls -lh "$CLAUDE_DIR"
else
    echo -e "${YELLOW}⚠${NC} Keine Session-Daten in $CLAUDE_DIR"
    echo "  Dies ist normal wenn Sie sich noch nie angemeldet haben."
fi

# 4. Prüfen der .devcontainer/devcontainer.json Konfiguration
echo
echo "4. Prüfe devcontainer.json Konfiguration..."
if grep -q ".claude-container/claude" .devcontainer/devcontainer.json; then
    echo -e "${GREEN}✓${NC} Volume-Mounts für persistente Anmeldung konfiguriert"
else
    echo -e "${RED}✗${NC} Volume-Mounts NICHT konfiguriert!"
    echo "  Sie müssen möglicherweise die neuesten Änderungen pullen."
fi

# 5. Zusammenfassung und nächste Schritte
echo
echo "=== Zusammenfassung ==="
echo
echo "Um persistente Anmeldung zu nutzen:"
echo "1. Stellen Sie sicher, dass die Host-Verzeichnisse existieren (siehe oben)"
echo "2. Bauen Sie den DevContainer neu:"
echo "   ${YELLOW}\"Dev Containers: Rebuild Container\"${NC} in VS Code"
echo "   oder"
echo "   ${YELLOW}docker-compose build claude${NC}"
echo "3. Melden Sie sich bei Claude Code an"
echo "4. Die Session bleibt erhalten, auch wenn Sie den Container neu erstellen"
echo
echo "Verifikation nach Anmeldung:"
echo "  Im Container: ${YELLOW}ls -la ~/.claude/${NC}"
echo "  Auf Host: ${YELLOW}ls -la $CLAUDE_DIR${NC}"
echo
echo "Beide sollten identische Dateien zeigen (via Bind-Mount)."
