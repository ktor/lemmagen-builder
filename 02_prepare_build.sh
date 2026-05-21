#!/usr/bin/env bash
# =============================================================================
# 02_prepare_build.sh
# Pripravi fork na build pre Elasticsearch 8.18.0
#
# Co skript robi:
#   1. Zmeni elasticsearch.version v pom.xml na 8.18.0
#   2. Zmeni verziu projektu v pom.xml na 8.18.0
#   3. Prida Elastic Maven repository do pom.xml
#   4. Updatuje plugin-descriptor.properties
#   5. Prida entitlement-policy.yaml (ES 8.18 security)
#   6. Skopiruje sk.lem lexikon
#   7. Commitne zmeny
#
# Pouzitie:
#   ./02_prepare_build.sh [--es-version 8.18.0]
# =============================================================================

set -euo pipefail

# --- Konfigurácia -------------------------------------------------------------

ES_VERSION="8.18.0"
PLUGIN_DIR="elasticsearch-analysis-lemmagen"
LEXICONS_DIR="lemmagen-lexicons"

# Spracovanie argumentov
while [[ $# -gt 0 ]]; do
  case $1 in
    --es-version)
      ES_VERSION="$2"
      shift 2
      ;;
    *)
      echo "Neznamy argument: $1"
      exit 1
      ;;
  esac
done

# --- Kontrola adresarov -------------------------------------------------------

echo "==> Kontrola adresarov..."

if [[ ! -d "$PLUGIN_DIR" ]]; then
  echo "CHYBA: Adresar '$PLUGIN_DIR' nenajdeny."
  echo "       Spusti najprv 01_clone.sh"
  exit 1
fi

if [[ ! -d "$LEXICONS_DIR" ]]; then
  echo "CHYBA: Adresar '$LEXICONS_DIR' nenajdeny."
  echo "       Spusti najprv 01_clone.sh"
  exit 1
fi

SK_LEM="${LEXICONS_DIR}/free/lexicons/sk.lem"
if [[ ! -f "$SK_LEM" ]]; then
  echo "CHYBA: Slovak lexikon nenajdeny: $SK_LEM"
  exit 1
fi

echo "    Plugin dir: OK"
echo "    Lexikony:   OK"
echo "    sk.lem:     OK"

cd "$PLUGIN_DIR"

# Overi ze sme na spravnej vetvi
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
if [[ "$CURRENT_BRANCH" != "es-8.18" ]]; then
  echo ""
  echo "VAROVANIE: Aktualna vetva je '$CURRENT_BRANCH', nie 'es-8.18'."
  read -rp "           Pokracovat aj tak? [y/N] " CONFIRM
  if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
    exit 1
  fi
fi

# --- Backup povodnych suborov -------------------------------------------------

echo ""
echo "==> Backup povodnych suborov..."
cp pom.xml pom.xml.orig
cp plugin-descriptor.properties plugin-descriptor.properties.orig
echo "    pom.xml.orig                        vytvoreny"
echo "    plugin-descriptor.properties.orig   vytvoreny"

# --- Patch pom.xml: verzia projektu ------------------------------------------

echo ""
echo "==> Patch pom.xml: verzia projektu -> ${ES_VERSION}..."

# Zisti aktualu verziu projektu (prvy <version> tag, nie v <parent> alebo <dependency>)
OLD_PROJECT_VERSION=$(xmllint --xpath "string(/project/version)" pom.xml 2>/dev/null || \
  grep -m1 '<version>' pom.xml | sed 's/.*<version>\(.*\)<\/version>.*/\1/' | xargs)

if [[ -z "$OLD_PROJECT_VERSION" ]]; then
  echo "    VAROVANIE: Nepodarilo sa detekovat staru verziu projektu, pokracujem rucne."
else
  echo "    Stara verzia: ${OLD_PROJECT_VERSION}"
  # Nahrada prveho vyskytu <version>X</version> (projekt, nie dependency)
  sed -i.bak "0,/<version>${OLD_PROJECT_VERSION}<\/version>/s//<version>${ES_VERSION}<\/version>/" pom.xml
  echo "    Nova verzia:  ${ES_VERSION}"
fi

# --- Patch pom.xml: elasticsearch.version property ---------------------------

echo ""
echo "==> Patch pom.xml: elasticsearch.version -> ${ES_VERSION}..."

if grep -q '<elasticsearch.version>' pom.xml; then
  OLD_ES_VER=$(grep '<elasticsearch.version>' pom.xml | sed 's/.*<elasticsearch.version>\(.*\)<\/elasticsearch.version>.*/\1/' | xargs)
  sed -i.bak "s|<elasticsearch.version>${OLD_ES_VER}</elasticsearch.version>|<elasticsearch.version>${ES_VERSION}</elasticsearch.version>|g" pom.xml
  echo "    ${OLD_ES_VER} -> ${ES_VERSION}"
else
  # Prida do <properties> ak neexistuje
  sed -i.bak "s|</properties>|  <elasticsearch.version>${ES_VERSION}</elasticsearch.version>\n  </properties>|" pom.xml
  echo "    Pridana nová property elasticsearch.version=${ES_VERSION}"
fi

# --- Patch pom.xml: Java verzia ----------------------------------------------

echo ""
echo "==> Patch pom.xml: java.version -> 21..."

# maven.compiler.source / target
for PROP in "maven.compiler.source" "maven.compiler.target" "maven.compiler.release"; do
  if grep -q "<${PROP}>" pom.xml; then
    sed -i.bak "s|<${PROP}>[^<]*</${PROP}>|<${PROP}>21</${PROP}>|g" pom.xml
    echo "    ${PROP} -> 21"
  fi
done

# --- Patch pom.xml: Elastic Maven repository ---------------------------------

echo ""
echo "==> Kontrola Elastic Maven repository v pom.xml..."

if grep -q "artifacts.elastic.co" pom.xml; then
  echo "    Elastic repository uz existuje, preskakujem."
else
  echo "    Pridavam Elastic Maven repository..."
  # Prida repository pred </repositories> alebo vytvori <repositories> sekciu
  if grep -q '<repositories>' pom.xml; then
    sed -i.bak "s|</repositories>|  <repository>\n      <id>elastic-releases</id>\n      <url>https://artifacts.elastic.co/maven</url>\n    </repository>\n  </repositories>|" pom.xml
  else
    # Prida pred </project>
    sed -i.bak "s|</project>|  <repositories>\n    <repository>\n      <id>elastic-releases</id>\n      <url>https://artifacts.elastic.co/maven</url>\n    </repository>\n  </repositories>\n</project>|" pom.xml
  fi
  echo "    Elastic repository pridany."
fi

# --- Cistenie .bak suborov ---------------------------------------------------

rm -f pom.xml.bak
echo ""
echo "==> Finalna kontrola pom.xml..."
echo "    elasticsearch.version: $(grep '<elasticsearch.version>' pom.xml | sed 's/.*<elasticsearch.version>\(.*\)<\/elasticsearch.version>.*/\1/' | xargs)"
echo "    project version:       $(xmllint --xpath "string(/project/version)" pom.xml 2>/dev/null || grep -m1 '<version>' pom.xml | sed 's/.*<version>\(.*\)<\/version>.*/\1/' | xargs)"

# --- plugin-descriptor.properties --------------------------------------------

echo ""
echo "==> Patch plugin-descriptor.properties..."

# elasticsearch.version
if grep -q "^elasticsearch.version=" plugin-descriptor.properties; then
  OLD_DESC_VER=$(grep "^elasticsearch.version=" plugin-descriptor.properties | cut -d'=' -f2)
  sed -i "s|elasticsearch.version=.*|elasticsearch.version=${ES_VERSION}|" plugin-descriptor.properties
  echo "    elasticsearch.version: ${OLD_DESC_VER} -> ${ES_VERSION}"
else
  echo "elasticsearch.version=${ES_VERSION}" >> plugin-descriptor.properties
  echo "    elasticsearch.version=${ES_VERSION} pridany"
fi

# java.version
if grep -q "^java.version=" plugin-descriptor.properties; then
  OLD_JAVA_VER=$(grep "^java.version=" plugin-descriptor.properties | cut -d'=' -f2)
  sed -i "s|java.version=.*|java.version=21|" plugin-descriptor.properties
  echo "    java.version: ${OLD_JAVA_VER} -> 21"
else
  echo "java.version=21" >> plugin-descriptor.properties
  echo "    java.version=21 pridany"
fi

# version
if grep -q "^version=" plugin-descriptor.properties; then
  OLD_VER=$(grep "^version=" plugin-descriptor.properties | cut -d'=' -f2)
  sed -i "s|^version=.*|version=${ES_VERSION}|" plugin-descriptor.properties
  echo "    version: ${OLD_VER} -> ${ES_VERSION}"
fi

# Odstrán 'type=' ak existuje (sposobuje chybu v ES 8.4+)
if grep -q "^type=" plugin-descriptor.properties; then
  sed -i "/^type=/d" plugin-descriptor.properties
  echo "    type= odstraneny (nekompatibilne s ES 8.4+)"
fi

# --- entitlement-policy.yaml (ES 8.18 security) ------------------------------

echo ""
echo "==> Vytvaranie entitlement-policy.yaml..."

cat > entitlement-policy.yaml << 'EOF'
# Elasticsearch 8.18 Entitlement Policy
# Plugin cita .lem lexikon subory z config/lemmagen/
ALL-UNNAMED:
  - files:
      - path: "${es.config}/lemmagen"
        mode: read
  - files:
      - path: "${es.config}/lemmagen/*"
        mode: read
EOF

echo "    entitlement-policy.yaml vytvoreny."

# --- Kopirovanie Slovak lexikonu ---------------------------------------------

echo ""
echo "==> Kopirovanie Slovak lexikonu..."

mkdir -p config/lemmagen
cp "../${SK_LEM}" config/lemmagen/sk.lem
echo "    sk.lem skopirovany do config/lemmagen/"
echo "    Licencia: CC BY-SA 4.0 (komerčne OK, vyžaduje atribuciu)"

# --- Git commit --------------------------------------------------------------

echo ""
echo "==> Git commit..."

git add pom.xml plugin-descriptor.properties entitlement-policy.yaml config/lemmagen/sk.lem
git status --short

git commit -m "build: update for Elasticsearch ${ES_VERSION}

- elasticsearch.version -> ${ES_VERSION}
- java.version -> 21
- add entitlement-policy.yaml for ES 8.18 security model
- add sk.lem lexicon (CC BY-SA 4.0)
- add Elastic Maven repository"

echo "    Commit vytvoreny."

# --- Instrukcie na build -----------------------------------------------------

echo ""
echo "================================================================"
echo " HOTOVO - Fork pripraveny na build"
echo "================================================================"
echo ""
echo " Dalsi krok - build:"
echo ""
echo "   cd ${PLUGIN_DIR}"
echo "   mvn clean package -DskipTests"
echo ""
echo " Ocakavany vystup:"
echo "   target/releases/elasticsearch-analysis-lemmagen-${ES_VERSION}-plugin.zip"
echo ""
echo " Ak build zlyha na compile erroroch:"
echo "   Skontroluj LemmagenFilterFactory.java - zmeny ES internal API"
echo "   Pozri IMPLEMENTATION_PLAN.md sekcia Troubleshooting"
echo ""
echo " Po uspesnom builde - instalacia:"
echo "   \$ES_HOME/bin/elasticsearch-plugin install \\"
echo "     file://\$(pwd)/target/releases/elasticsearch-analysis-lemmagen-${ES_VERSION}-plugin.zip"
echo "   mkdir -p \$ES_HOME/config/lemmagen"
echo "   cp config/lemmagen/sk.lem \$ES_HOME/config/lemmagen/"
echo ""
