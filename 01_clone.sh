#!/usr/bin/env bash
# =============================================================================
# 01_clone.sh
# Naklonuje fork vhyza/elasticsearch-analysis-lemmagen
#
# Pouzitie:
#   ./01_clone.sh <github-username-alebo-org>
#
# Priklad:
#   ./01_clone.sh ableneo
# =============================================================================

set -euo pipefail

UPSTREAM_REPO="vhyza/elasticsearch-analysis-lemmagen"
UPSTREAM_URL="https://github.com/${UPSTREAM_REPO}.git"
LEXICONS_REPO="https://github.com/vhyza/lemmagen-lexicons.git"

# --- Argument check -----------------------------------------------------------

if [[ $# -lt 1 ]]; then
  echo "Chyba: chyba github username."
  echo "Pouzitie: $0 <github-username-alebo-org>"
  exit 1
fi

GITHUB_USER="$1"
FORK_URL="https://github.com/${GITHUB_USER}/elasticsearch-analysis-lemmagen.git"

# --- Prerekvizity -------------------------------------------------------------

echo "==> Kontrola prerekvizit..."

command -v git  >/dev/null 2>&1 || { echo "CHYBA: git nie je nainstalovany"; exit 1; }
command -v java >/dev/null 2>&1 || { echo "CHYBA: java nie je nainstalovana"; exit 1; }
command -v mvn  >/dev/null 2>&1 || { echo "CHYBA: maven nie je nainstalovany"; exit 1; }

JAVA_VER=$(java -version 2>&1 | awk -F '"' '/version/ {print $2}' | cut -d'.' -f1)
if [[ "$JAVA_VER" -lt 21 ]]; then
  echo "CHYBA: Java 21+ vyzadovana, najdena verzia: $JAVA_VER"
  echo "       Nastav JAVA_HOME na JDK 21 a skus znova."
  exit 1
fi

echo "    git:  OK ($(git --version))"
echo "    java: OK (verzia $JAVA_VER)"
echo "    mvn:  OK ($(mvn --version | head -1))"

# --- Fork info ----------------------------------------------------------------

echo ""
echo "==> Krok 1: Fork na GitHub"
echo "    Ak si este neurobil fork, sprav ho rucne:"
echo "    https://github.com/${UPSTREAM_REPO}/fork"
echo ""
echo "    Fork URL ktoru ocakavam: ${FORK_URL}"
echo ""
read -rp "    Pokracovat (fork uz existuje)? [y/N] " CONFIRM
if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
  echo "Prerusene. Spusti znova po vytvoreni forku."
  exit 0
fi

# --- Clone --------------------------------------------------------------------

echo ""
echo "==> Krok 2: Klonovanie forku..."

if [[ -d "elasticsearch-analysis-lemmagen" ]]; then
  echo "    Adresar elasticsearch-analysis-lemmagen uz existuje, preskakujem klonovanie."
else
  git clone "${FORK_URL}" elasticsearch-analysis-lemmagen
  echo "    Klonovanie OK."
fi

cd elasticsearch-analysis-lemmagen

# --- Upstream remote ----------------------------------------------------------

echo ""
echo "==> Krok 3: Pridavanie upstream remote..."

if git remote get-url upstream >/dev/null 2>&1; then
  echo "    upstream remote uz existuje, preskakujem."
else
  git remote add upstream "${UPSTREAM_URL}"
  echo "    upstream remote pridany: ${UPSTREAM_URL}"
fi

git remote -v

# --- Sync s upstream ----------------------------------------------------------

echo ""
echo "==> Krok 4: Sync s upstream/master..."
git fetch upstream
git checkout master
git merge upstream/master --ff-only || {
  echo "VAROVANIE: Fast-forward merge zlyhal, fork moze byt pred upstream."
  echo "           Pokracujem bez merge."
}

# --- Vetva pre ES 8.18 --------------------------------------------------------

echo ""
echo "==> Krok 5: Vytvorenie vetvy es-8.18..."

if git show-ref --verify --quiet refs/heads/es-8.18; then
  echo "    Vetva es-8.18 uz existuje, prepinem na nu."
  git checkout es-8.18
else
  git checkout -b es-8.18
  echo "    Vetva es-8.18 vytvorena."
fi

# --- Lexicons repo ------------------------------------------------------------

echo ""
echo "==> Krok 6: Klonovanie lemmagen-lexicons (Slovak lexikon)..."

cd ..
if [[ -d "lemmagen-lexicons" ]]; then
  echo "    Adresar lemmagen-lexicons uz existuje, preskakujem."
else
  git clone --depth=1 "${LEXICONS_REPO}" lemmagen-lexicons
  echo "    Lexikony stiahunute."
fi

# --- Finish -------------------------------------------------------------------

echo ""
echo "================================================================"
echo " HOTOVO"
echo "================================================================"
echo ""
echo " Struktura:"
echo "   ./elasticsearch-analysis-lemmagen/   <- fork (vetva: es-8.18)"
echo "   ./lemmagen-lexicons/                 <- lexikony"
echo ""
echo " Dalsi krok:"
echo "   ./02_prepare_build.sh"
echo ""
