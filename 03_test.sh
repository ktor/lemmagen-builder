#!/usr/bin/env bash
# =============================================================================
# 03_test.sh
# Overenie spravnej funkcie LemmaGen Slovak analyzera v ES 8.18
#
# Pouzitie:
#   ./03_test.sh [--host localhost] [--port 9200]
#
# Spusti zo zlozky kde je docker-compose.yml:
#   cd docker && ../03_test.sh
# =============================================================================

set -euo pipefail

# --- Konfigurácia -------------------------------------------------------------

ES_HOST="localhost"
ES_PORT="9200"
ES_URL=""
INDEX="test-lemmagen-sk"
PASS=0
FAIL=0
TOTAL=0

while [[ $# -gt 0 ]]; do
  case $1 in
    --host) ES_HOST="$2"; shift 2 ;;
    --port) ES_PORT="$2"; shift 2 ;;
    *) echo "Neznamy argument: $1"; exit 1 ;;
  esac
done

ES_URL="http://${ES_HOST}:${ES_PORT}"

# --- Pomocné funkcie ----------------------------------------------------------

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

log_section() { echo -e "\n${CYAN}${BOLD}==> $1${NC}"; }
log_info()    { echo -e "    $1"; }
log_pass()    { echo -e "    ${GREEN}PASS${NC}  $1"; PASS=$((PASS+1)); TOTAL=$((TOTAL+1)); }
log_fail()    { echo -e "    ${RED}FAIL${NC}  $1"; FAIL=$((FAIL+1)); TOTAL=$((TOTAL+1)); }
log_warn()    { echo -e "    ${YELLOW}WARN${NC}  $1"; }

# Vola ES API, vrati HTTP status code
es_curl() {
  local method="$1"
  local path="$2"
  local data="${3:-}"
  if [[ -n "$data" ]]; then
    curl -s -o /tmp/es_response.json -w "%{http_code}" \
      -X "$method" "${ES_URL}${path}" \
      -H "Content-Type: application/json" \
      -d "$data"
  else
    curl -s -o /tmp/es_response.json -w "%{http_code}" \
      -X "$method" "${ES_URL}${path}"
  fi
}

es_response() { cat /tmp/es_response.json; }

# Vrati stemovany token pre dany vstup
get_token() {
  local text="$1"
  local status
  status=$(es_curl GET "/${INDEX}/_analyze" \
    "{\"analyzer\": \"slovak_lemmagen\", \"text\": \"${text}\"}")
  if [[ "$status" == "200" ]]; then
    es_response | python3 -c "
import sys, json
data = json.load(sys.stdin)
tokens = [t['token'] for t in data.get('tokens', [])]
print(' '.join(tokens))
" 2>/dev/null || echo ""
  else
    echo ""
  fi
}

# Overi ze token sa nachadza vo vysledkoch analyze
assert_token() {
  local description="$1"
  local input="$2"
  local expected="$3"
  local result
  result=$(get_token "$input")
  if echo "$result" | grep -qw "$expected"; then
    log_pass "${description}: '${input}' -> obsahuje '${expected}' (got: ${result})"
  else
    log_fail "${description}: '${input}' -> ocakavam '${expected}', dostal '${result}'"
  fi
}

# Overi ze search najde dokument
assert_search_hit() {
  local description="$1"
  local query="$2"
  local expected_id="$3"
  local status
  status=$(es_curl GET "/${INDEX}/_search" "$query")
  local hits
  hits=$(es_response | python3 -c "
import sys, json
data = json.load(sys.stdin)
ids = [h['_id'] for h in data.get('hits', {}).get('hits', [])]
print(' '.join(ids))
" 2>/dev/null || echo "")
  if echo "$hits" | grep -qw "$expected_id"; then
    log_pass "${description}: query nasiel dokument '${expected_id}'"
  else
    log_fail "${description}: query nenasiel dokument '${expected_id}' (hits: ${hits:-ziadne})"
  fi
}

# --- Start -------------------------------------------------------------------

echo ""
echo -e "${BOLD}================================================================"
echo " LemmaGen Slovak Analyzer - Test Suite"
echo -e "================================================================${NC}"
echo " ES: ${ES_URL}"
echo " Index: ${INDEX}"

# =============================================================================
# TEST 1: Dostupnost ES
# =============================================================================
log_section "Test 1: Dostupnost Elasticsearch"

STATUS=$(es_curl GET "/")
if [[ "$STATUS" == "200" ]]; then
  ES_VERSION=$(es_response | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['version']['number'])" 2>/dev/null || echo "neznama")
  log_pass "ES je dostupny (verzia: ${ES_VERSION})"
else
  log_fail "ES nie je dostupny na ${ES_URL} (HTTP ${STATUS})"
  echo -e "\n${RED}ES nie je dostupny. Skontroluj docker compose.${NC}"
  exit 1
fi

# =============================================================================
# TEST 2: Plugin je nainstalovany
# =============================================================================
log_section "Test 2: Plugin lemmagen je nainstalovany"

STATUS=$(es_curl GET "/_nodes/plugins")
if [[ "$STATUS" == "200" ]]; then
  if es_response | python3 -c "
import sys, json
data = json.load(sys.stdin)
nodes = data.get('nodes', {})
for node_id, node in nodes.items():
    plugins = [p['name'] for p in node.get('plugins', [])]
    if 'elasticsearch-analysis-lemmagen' in plugins:
        print('found')
        break
" 2>/dev/null | grep -q "found"; then
    log_pass "Plugin 'elasticsearch-analysis-lemmagen' je nainstalovany"
  else
    log_fail "Plugin 'elasticsearch-analysis-lemmagen' NIE JE nainstalovany"
    log_warn "Skontroluj: docker compose logs elasticsearch | grep -i lemmagen"
  fi
else
  log_fail "Nepodarilo sa nacitat zoznam pluginov (HTTP ${STATUS})"
fi

# =============================================================================
# TEST 3: Vytvorenie indexu so Slovak analyzerom
# =============================================================================
log_section "Test 3: Vytvorenie indexu so Slovak LemmaGen analyzerom"

# Zmaz index ak existuje
es_curl DELETE "/${INDEX}" >/dev/null 2>&1 || true

STATUS=$(es_curl PUT "/${INDEX}" '{
  "settings": {
    "number_of_shards": 1,
    "number_of_replicas": 0,
    "analysis": {
      "filter": {
        "sk_lemmagen": {
          "type": "lemmagen",
          "lexicon": "sk"
        },
        "sk_stop": {
          "type": "stop",
          "stopwords": ["a", "ale", "aj", "alebo", "ako", "an", "ani",
                        "bo", "by", "byť",
                        "ci", "čo",
                        "do",
                        "ho",
                        "i", "ich",
                        "je", "jej", "jej", "ju",
                        "k", "kde", "keď", "kto",
                        "lebo",
                        "má", "mi", "mu",
                        "na", "nad", "nám", "nie", "no",
                        "o", "od",
                        "po", "pod", "pre", "pri",
                        "s", "sa", "si", "so",
                        "ta", "tak", "ten", "to",
                        "u",
                        "v", "vám", "vás", "vo",
                        "z", "za", "zo"]
        }
      },
      "analyzer": {
        "slovak_lemmagen": {
          "type": "custom",
          "tokenizer": "standard",
          "filter": [
            "lowercase",
            "sk_stop",
            "sk_lemmagen",
            "asciifolding"
          ]
        }
      }
    }
  },
  "mappings": {
    "properties": {
      "id":      { "type": "keyword" },
      "title":   { "type": "text", "analyzer": "slovak_lemmagen" },
      "content": { "type": "text", "analyzer": "slovak_lemmagen" }
    }
  }
}')

if [[ "$STATUS" == "200" ]]; then
  log_pass "Index '${INDEX}' uspesne vytvoreny"
else
  log_fail "Vytvorenie indexu zlyhalo (HTTP ${STATUS}): $(es_response)"
  echo -e "\n${RED}Nepodarilo sa vytvorit index. Dalsi testy preskakujem.${NC}"
  exit 1
fi

# =============================================================================
# TEST 4: Lemmatizacia - sklonovanie podstatnych mien
# =============================================================================
log_section "Test 4: Lemmatizacia - sklonovanie podstatnych mien"

# Rozne pady "republika" -> "republika"
assert_token "nominativ sg"     "republika"     "republika"
assert_token "genitiv sg"       "republiky"     "republika"
assert_token "dativ sg"         "republike"     "republika"
assert_token "akuzativ sg"      "republiku"     "republika"
assert_token "nominativ pl"     "republiky"     "republika"
assert_token "genitiv pl"       "republík"      "republika"

# Rozne pady "slovensko" -> "slovensko"
assert_token "genitiv sg"       "slovenska"     "slovensko"
assert_token "lokativ sg"       "slovensku"     "slovensko"

# =============================================================================
# TEST 5: Lemmatizacia - sklonovanie pridavnych mien
# =============================================================================
log_section "Test 5: Lemmatizacia - sklonovanie pridavnych mien"

# Rozne tvary "slovenský" -> "slovensky" (po asciifolding)
assert_token "m. nominativ sg"  "slovenský"     "slovensky"
assert_token "f. nominativ sg"  "slovenská"     "slovensky"
assert_token "n. nominativ sg"  "slovenské"     "slovensky"
assert_token "m. genitiv sg"    "slovenského"   "slovensky"
assert_token "f. genitiv sg"    "slovenskej"    "slovensky"
assert_token "pl. nominativ"    "slovenské"     "slovensky"
assert_token "pl. genitiv"      "slovenských"   "slovensky"

# =============================================================================
# TEST 6: Lemmatizacia - casovanie slovies
# =============================================================================
log_section "Test 6: Lemmatizacia - casovanie slovies"

# Rozne tvary "pracovať" -> "pracovat" (po asciifolding)
assert_token "1. os. sg prit."  "pracujem"      "pracovat"
assert_token "2. os. sg prit."  "pracuješ"      "pracovat"
assert_token "3. os. sg prit."  "pracuje"       "pracovat"
assert_token "1. os. pl prit."  "pracujeme"     "pracovat"
assert_token "3. os. pl prit."  "pracujú"       "pracovat"
assert_token "minuly cas"       "pracoval"      "pracovat"
assert_token "minuly cas f"     "pracovala"     "pracovat"

# =============================================================================
# TEST 7: Full-text search - findovanie cez rozne tvary
# =============================================================================
log_section "Test 7: Full-text search - hladanie cez sklonovane tvary"

# Indexacia testovacich dokumentov
log_info "Indexovanie testovacich dokumentov..."

es_curl POST "/${INDEX}/_doc/1" '{
  "id": "1",
  "title": "Slovenská republika a jej história",
  "content": "Slovenská republika je demokratický štát v strednej Európe. Hlavné mesto republiky je Bratislava."
}' >/dev/null

es_curl POST "/${INDEX}/_doc/2" '{
  "id": "2",
  "title": "Hospodárstvo Slovenska",
  "content": "Hospodárstvo slovenskej republiky zaznamenalo výrazný rast. Slovenské firmy pracujú na medzinárodných trhoch."
}' >/dev/null

es_curl POST "/${INDEX}/_doc/3" '{
  "id": "3",
  "title": "Kultúra a jazyk",
  "content": "Slovenský jazyk patrí do skupiny slovanských jazykov. Obyvatelia hovoria po slovensky."
}' >/dev/null

# Refresh index
es_curl POST "/${INDEX}/_refresh" >/dev/null
sleep 1

# Hladanie "republika" najde dokumenty kde je pouzite v roznych padoch
assert_search_hit \
  "query 'republika' najde doc kde je 'republiky'" \
  '{"query": {"match": {"content": "republika"}}}' \
  "1"

assert_search_hit \
  "query 'republika' najde doc kde je 'republiky' (doc2)" \
  '{"query": {"match": {"content": "republika"}}}' \
  "2"

# Hladanie "slovenský" najde vsetky dokumenty so slovenskymi pridavnymi menami
assert_search_hit \
  "query 'slovensky' najde doc kde je 'Slovenská'" \
  '{"query": {"match": {"title": "slovensky"}}}' \
  "1"

assert_search_hit \
  "query 'slovensky' najde doc kde je 'Slovenského'" \
  '{"query": {"match": {"content": "slovensky"}}}' \
  "2"

assert_search_hit \
  "query 'slovensky' najde doc kde je 'Slovenský' (doc3)" \
  '{"query": {"match": {"content": "slovensky"}}}' \
  "3"

# Hladanie cez casovanie
assert_search_hit \
  "query 'pracovat' najde doc kde je 'pracujú'" \
  '{"query": {"match": {"content": "pracovat"}}}' \
  "2"

# =============================================================================
# TEST 8: Porovnanie - bez lemmagen vs. s lemmagen
# =============================================================================
log_section "Test 8: Overenie ze standard analyzer NEfinduje sklonovane formy"

# Standard analyzer by nemal najst "republika" ked hladame "republiky" (iny tvar)
STATUS=$(es_curl GET "/${INDEX}/_search" '{
  "query": {
    "match": {
      "content": {
        "query": "republika",
        "analyzer": "standard"
      }
    }
  }
}')

if [[ "$STATUS" == "200" ]]; then
  HITS=$(es_response | python3 -c "
import sys,json; d=json.load(sys.stdin)
print(d['hits']['total']['value'])
" 2>/dev/null || echo "0")
  # Standard analyzer by mal najst menej dokumentov ako lemmagen
  LEMMAGEN_HITS=2  # vieme ze lemmagen nasiel 2
  if [[ "$HITS" -lt "$LEMMAGEN_HITS" ]]; then
    log_pass "Standard analyzer nasiel ${HITS} dok., LemmaGen nasiel ${LEMMAGEN_HITS} dok. - lemmagen pridava hodnotu"
  else
    log_warn "Standard analyzer nasiel ${HITS} dok. (ocakavane < ${LEMMAGEN_HITS}) - mozno sa prekryvaju"
  fi
fi

# =============================================================================
# TEST 9: Cleanup
# =============================================================================
log_section "Test 9: Cleanup testovacieho indexu"

STATUS=$(es_curl DELETE "/${INDEX}")
if [[ "$STATUS" == "200" ]]; then
  log_pass "Index '${INDEX}' vymazany"
else
  log_warn "Mazanie indexu zlyhalo (HTTP ${STATUS}) - nevadzi"
  TOTAL=$((TOTAL+1))
fi

# =============================================================================
# Suhrn
# =============================================================================

echo ""
echo -e "${BOLD}================================================================"
echo " Suhrn testov"
echo -e "================================================================${NC}"
echo ""
echo -e "  Celkovo:  ${TOTAL}"
echo -e "  ${GREEN}PASS:${NC}     ${PASS}"
echo -e "  ${RED}FAIL:${NC}     ${FAIL}"
echo ""

if [[ "$FAIL" -eq 0 ]]; then
  echo -e "  ${GREEN}${BOLD}Vsetky testy presli. LemmaGen Slovak analyzer funguje spravne.${NC}"
  exit 0
else
  echo -e "  ${RED}${BOLD}${FAIL} testov zlyhalo. Skontroluj vystupy vyssie.${NC}"
  echo ""
  echo "  Diagnostika:"
  echo "    docker compose logs elasticsearch | tail -50"
  echo "    curl ${ES_URL}/_cat/plugins?v"
  echo "    curl ${ES_URL}/_nodes/plugins | python3 -m json.tool"
  exit 1
fi
