#!/bin/bash
# ═══════════════════════════════════════════════════════
#  VECTORISEUR PRO — Installation
# ═══════════════════════════════════════════════════════

set -e

echo "═══════════════════════════════════════════════════════"
echo "  VECTORISEUR PRO — Installation des dépendances"
echo "═══════════════════════════════════════════════════════"
echo ""

# Check Python version
PYTHON_CMD=""
if command -v python3 &> /dev/null; then
    PYTHON_CMD="python3"
elif command -v python &> /dev/null; then
    PYTHON_CMD="python"
else
    echo "❌ Python 3 n'est pas installé."
    echo "   Installe-le via: brew install python3"
    exit 1
fi

PYTHON_VERSION=$($PYTHON_CMD --version 2>&1)
echo "  Python: $PYTHON_VERSION"

# Create virtual environment
VENV_DIR="$(dirname "$0")/.venv"

if [ ! -d "$VENV_DIR" ]; then
    echo ""
    echo "  Création de l'environnement virtuel..."
    $PYTHON_CMD -m venv "$VENV_DIR"
fi

# Activate venv
source "$VENV_DIR/bin/activate"
echo "  Environnement: $VENV_DIR"
echo ""

# Upgrade pip
pip install --upgrade pip -q

# Install dependencies
echo "  Installation des dépendances..."
pip install -r "$(dirname "$0")/requirements.txt" -q

echo ""
echo "═══════════════════════════════════════════════════════"
echo "  ✓ Installation terminée !"
echo ""
echo "  Pour lancer le serveur :"
echo "    cd $(dirname "$0")"
echo "    source .venv/bin/activate"
echo "    python server.py"
echo ""
echo "  Puis ouvrir : http://localhost:5555"
echo "═══════════════════════════════════════════════════════"
