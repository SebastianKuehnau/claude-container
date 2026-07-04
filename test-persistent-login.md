# Test: Persistente Claude Code Anmeldung

Dieser Test verifiziert, dass die Claude Code Anmeldung über Container-Neustarts hinweg erhalten bleibt.

## Schritt 1: Container erstmalig starten

```bash
# DevContainer in VS Code neu bauen
# Command Palette (Cmd+Shift+P): Dev Containers: Rebuild Container

# ODER mit Docker Compose:
docker-compose up -d claude
docker-compose exec claude zsh
```

## Schritt 2: Anmeldestatus prüfen (sollte NICHT angemeldet sein)

```bash
# Im Container
claude --version

# Versuche einen einfachen Befehl
claude -p "hello"
```

**Erwartetes Ergebnis:** Claude sollte Sie auffordern, sich anzumelden.

## Schritt 3: Bei Claude anmelden

```bash
# Im Container
claude login
```

Folgen Sie dem Authentifizierungs-Flow im Browser.

## Schritt 4: Verifizieren, dass Credentials gespeichert wurden

```bash
# Im Container
ls -la ~/.claude/
# Sollte .credentials.json und andere Dateien zeigen

# Auf dem Host (in einem neuen Terminal AUSSERHALB des Containers)
ls -la ~/.claude-container/claude/
# Sollte DIESELBEN Dateien zeigen
```

**Erwartetes Ergebnis:**
- `~/.claude-container/claude/.credentials.json` existiert auf dem Host
- Die Dateien im Container (`~/.claude/`) sind identisch (Bind-Mount)

## Schritt 5: Testen, dass Claude Code funktioniert

```bash
# Im Container
claude -p "What is 2+2?"
```

**Erwartetes Ergebnis:** Claude antwortet, ohne erneut nach Login zu fragen.

## Schritt 6: Container stoppen und neu starten

```bash
# Container stoppen
docker-compose down

# Container neu starten
docker-compose up -d claude
docker-compose exec claude zsh
```

## Schritt 7: Prüfen, dass Login NOCH BESTEHT

```bash
# Im Container (nach Neustart)
claude -p "What is 3+3?"
```

**Erwartetes Ergebnis:** ✅ Claude antwortet OHNE erneuten Login! Die Session wurde wiederhergestellt.

## Schritt 8: Container komplett neu bauen

```bash
# Container UND Image löschen, dann neu bauen
docker-compose down
docker-compose build --no-cache claude
docker-compose up -d claude
docker-compose exec claude zsh
```

## Schritt 9: Finale Verifikation

```bash
# Im neu gebauten Container
claude -p "What is 5+5?"

# Credentials sollten noch da sein
ls -la ~/.claude/
```

**Erwartetes Ergebnis:** ✅ Auch nach kompletten Rebuild bleibt die Anmeldung bestehen!

## Troubleshooting

### Test schlägt fehl: Login wird nicht persistiert

Prüfen Sie die Mounts:

```bash
# Im Container
mount | grep claude
# Sollte zeigen:
# /home/sebastian/.claude-container/claude on /home/node/.claude type virtiofs
# /home/sebastian/.claude-container/claude.json on /home/node/.claude.json type virtiofs
```

Prüfen Sie die devcontainer.json:

```bash
cat .devcontainer/devcontainer.json | grep -A5 mounts
```

Sollte zeigen:
```json
"mounts": [
  "source=${localEnv:HOME}/.claude-container/claude,target=/home/node/.claude,type=bind,consistency=cached",
  "source=${localEnv:HOME}/.claude-container/claude.json,target=/home/node/.claude.json,type=bind,consistency=cached",
  ...
]
```

### Berechtigungsfehler

```bash
# Auf dem Host
ls -la ~/.claude-container/
# Dateien sollten Ihnen gehören

# Falls nicht:
sudo chown -R $USER:$USER ~/.claude-container/
```

## Erfolg!

Wenn alle Schritte funktionieren, ist die persistente Anmeldung korrekt konfiguriert. Sie müssen sich nur einmal anmelden und können dann beliebig oft Container neu starten/bauen.
